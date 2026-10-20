"""Build a .usmap (ExplicitEnumValues) from a UE4SS UHT-style header dump."""
import re, struct, sys, pathlib

root = pathlib.Path(sys.argv[1]); out = sys.argv[2]
hdrs = list(root.rglob("*.h"))

enums = {}      # name -> [(val,name)]
schemas = {}    # name -> (super, [(name, arraydim, typestr)])
enum_class = set()  # enums usable directly as EnumProperty

re_enum_ns = re.compile(r"namespace\s+(\w+)\s*\{\s*enum\s+Type\s*(?::\s*\w+)?\s*\{(.*?)\};", re.S)
re_enum = re.compile(r"enum\s+(class\s+)?(\w+)\s*(?::\s*(\w+))?\s*\{(.*?)\};", re.S)
re_type = re.compile(r"(?:class|struct)\s+(?:\w+_API\s+)?([UAF]\w+)\s*(?::\s*public\s+([UAFI]\w+))?[^;{]*\{")

def parse_entries(body, prefix):
    res, v = [], 0
    for ent in body.split(","):
        ent = re.sub(r"//.*", "", ent).strip()
        if not ent: continue
        if "=" in ent:
            n, e = [x.strip() for x in ent.split("=", 1)]
            try: v = int(e, 0)
            except ValueError: pass
        else: n = ent
        res.append((v, f"{prefix}::{n}"))
        v += 1
    return res

for h in hdrs:
    t = h.read_text(errors="replace")
    if "UENUM" in t:
        for m in re_enum_ns.finditer(t):
            enums[m.group(1)] = parse_entries(m.group(2), m.group(1))
        tt = re_enum_ns.sub("", t)
        for m in re_enum.finditer(tt):
            enums[m.group(2)] = parse_entries(m.group(4), m.group(2))
            if m.group(1) or m.group(3): enum_class.add(m.group(2))
    for m in re_type.finditer(t):
        if not re.search(r"U(CLASS|STRUCT|INTERFACE)\([^)]*\)\s*$", t[:m.start()].rstrip()[-200:] + "\n" if False else t[max(0,m.start()-200):m.start()]):
            continue
        name, sup = m.group(1), m.group(2)
        # body: find matching brace
        i, depth = m.end(), 1
        while depth and i < len(t):
            depth += {"{": 1, "}": -1}.get(t[i], 0); i += 1
        body = t[m.end():i]
        props = []
        for pm in re.finditer(r"UPROPERTY\((?:[^()]|\([^)]*\))*\)\s*\n\s*([^;]+?)\s+(\w+)(?:\[(\w+)\])?\s*;", body):
            ty, pn, dim = pm.group(1).strip(), pm.group(2), pm.group(3)
            try: dim = int(dim) if dim else 1
            except ValueError: dim = 1
            props.append((pn, dim, ty))
        schemas[name[1:]] = (sup[1:] if sup else None, props)

# hand-written engine types needed by show assets
ENGINE = {
    "Object": (None, []), "DataAsset": ("Object", []), "PrimaryDataAsset": ("DataAsset", []),
    "IndexedCurve": (None, []),
    "RealCurve": ("IndexedCurve", [("DefaultValue",1,"float"),("PreInfinityExtrap",1,"TEnumAsByte<ERichCurveExtrapolation>"),("PostInfinityExtrap",1,"TEnumAsByte<ERichCurveExtrapolation>")]),
    "RichCurve": ("RealCurve", [("Keys",1,"TArray<FRichCurveKey>")]),
    "SimpleCurve": ("RealCurve", [("InterpMode",1,"TEnumAsByte<ERichCurveInterpMode>"),("Keys",1,"TArray<FSimpleCurveKey>")]),
    "RuntimeFloatCurve": (None, [("EditorCurveData",1,"FRichCurve"),("ExternalCurve",1,"UCurveFloat*")]),
    "RuntimeVectorCurve": (None, [("VectorCurves",3,"FRichCurve"),("ExternalCurve",1,"UCurveVector*")]),
    "Transform": (None, [("Rotation",1,"FQuat"),("Translation",1,"FVector"),("Scale3D",1,"FVector")]),
    "SlateColor": (None, [("SpecifiedColor",1,"FLinearColor"),("ColorUseRule",1,"TEnumAsByte<ESlateColorStylingMode::Type>")]),
    "FloatRange": (None, []), "Int32Interval": (None, [("Min",1,"int32"),("Max",1,"int32")]),
    "FloatInterval": (None, [("Min",1,"float"),("Max",1,"float")]),
    "Vector4": (None, []),
    "TableRowBase": (None, []),
    "DataTable": ("Object", [("RowStruct",1,"UScriptStruct*"),("bStripFromClientBuilds",1,"bool"),("bIgnoreExtraFields",1,"bool"),("bIgnoreMissingFields",1,"bool"),("ImportKeyField",1,"FString")]),
}
for k, v in ENGINE.items(): schemas.setdefault(k, v)

names, nidx = [], {}
def N(s):
    if s is None: return -1
    if s not in nidx: nidx[s] = len(names); names.append(s)
    return nidx[s]

P = dict(ByteProperty=0, BoolProperty=1, IntProperty=2, FloatProperty=3, ObjectProperty=4, NameProperty=5,
         DelegateProperty=6, DoubleProperty=7, ArrayProperty=8, StructProperty=9, StrProperty=10, TextProperty=11,
         InterfaceProperty=12, MulticastDelegateProperty=13, WeakObjectProperty=14, LazyObjectProperty=15,
         SoftObjectProperty=17, UInt64Property=18, UInt32Property=19, UInt16Property=20, Int64Property=21,
         Int16Property=22, Int8Property=23, MapProperty=24, SetProperty=25, EnumProperty=26)
SIMPLE = {"bool":"BoolProperty","int32":"IntProperty","float":"FloatProperty","double":"DoubleProperty","FName":"NameProperty",
          "FString":"StrProperty","FText":"TextProperty","uint8":"ByteProperty","uint32":"UInt32Property","uint64":"UInt64Property",
          "int64":"Int64Property","int16":"Int16Property","uint16":"UInt16Property","int8":"Int8Property"}
unknown = set()

def split_args(s):
    out, d, cur = [], 0, ""
    for c in s:
        if c == "<": d += 1
        if c == ">": d -= 1
        if c == "," and d == 0: out.append(cur.strip()); cur = ""
        else: cur += c
    out.append(cur.strip()); return out

def enc(ty):
    ty = ty.replace("const ", "").strip()
    m = re.match(r"(\w+)<(.*)>$", ty)
    if m:
        tmpl, args = m.group(1), split_args(m.group(2))
        if tmpl == "TArray": return struct.pack("<B", P["ArrayProperty"]) + enc(args[0])
        if tmpl == "TSet": return struct.pack("<B", P["SetProperty"]) + enc(args[0])
        if tmpl == "TMap": return struct.pack("<B", P["MapProperty"]) + enc(args[0]) + enc(args[1])
        if tmpl == "TEnumAsByte": return struct.pack("<B", P["ByteProperty"])
        if tmpl in ("TSubclassOf",): return struct.pack("<B", P["ObjectProperty"])
        if tmpl in ("TSoftObjectPtr", "TSoftClassPtr"): return struct.pack("<B", P["SoftObjectProperty"])
        if tmpl == "TWeakObjectPtr": return struct.pack("<B", P["WeakObjectProperty"])
        if tmpl == "TLazyObjectPtr": return struct.pack("<B", P["LazyObjectProperty"])
        if tmpl == "TScriptInterface": return struct.pack("<B", P["InterfaceProperty"])
        unknown.add(ty); return struct.pack("<B", 0xFF)
    if ty.endswith("*"): return struct.pack("<B", P["ObjectProperty"])
    if ty in SIMPLE: return struct.pack("<B", P[SIMPLE[ty]])
    if ty in enums: return struct.pack("<B", P["EnumProperty"]) + struct.pack("<B", P["ByteProperty"]) + struct.pack("<i", N(ty))
    if ty in ("FSoftObjectPath", "FSoftClassPath"): return struct.pack("<Bi", P["StructProperty"], N(ty[1:]))
    if ty.startswith("F") and ty[1:] in schemas or ty in ("FVector","FVector2D","FRotator","FQuat","FLinearColor","FColor","FGuid","FFrameNumber","FRichCurveKey","FSimpleCurveKey","FIntPoint","FIntVector","FBox","FBox2D","FGameplayTag","FGameplayTagContainer","FDateTime","FTimespan","FPerPlatformFloat","FPerPlatformInt","FVector4","FMatrix","FPlane","FFloatRange","FInt32Range"):
        return struct.pack("<Bi", P["StructProperty"], N(ty[1:]))
    if ty.startswith("F"):  # delegate types or unknown struct
        if re.match(r"F\w*(Delegate|Event|Signature|On\w+)$", ty) or ty.startswith("FOn"):
            return struct.pack("<B", P["MulticastDelegateProperty"])
        unknown.add(ty); return struct.pack("<Bi", P["StructProperty"], N(ty[1:]))
    unknown.add(ty); return struct.pack("<B", 0xFF)

body = bytearray()
# enums
en = b"".join(struct.pack("<iH", N(k), len(v)) + b"".join(struct.pack("<qi", val, N(n)) for val, n in v) for k, v in enums.items())
sc = bytearray()
for k, (sup, props) in schemas.items():
    total = sum(d for _, d, _ in props)
    sc += struct.pack("<iiHH", N(k), N(sup), total, len(props))
    idx = 0
    for pn, dim, ty in props:
        sc += struct.pack("<HBi", idx, dim, N(pn)) + enc(ty)
        idx += dim
nm = struct.pack("<i", len(names)) + b"".join(struct.pack("<H", len(s.encode())) + s.encode() for s in names)
data = nm + struct.pack("<i", len(enums)) + en + struct.pack("<i", len(schemas)) + sc
hdr = struct.pack("<HBi", 0x30C4, 4, 0) + struct.pack("<BII", 0, len(data), len(data))
open(out, "wb").write(hdr + data)
print(f"enums={len(enums)} schemas={len(schemas)} names={len(names)}")
print("unknown types:", sorted(unknown)[:80])
