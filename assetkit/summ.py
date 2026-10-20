import json,sys
d=json.load(open(sys.argv[1]))
imps=d["Imports"]
def ref(i):
    if i is None: return None
    if i<0: return "imp:"+imps[-i-1]["ObjectName"]
    if i>0: return "exp:"+d["Exports"][i-1]["ObjectName"]
    return "null"
def val(p,ind):
    if not isinstance(p,dict) or "$type" not in p:
        print(" "*ind+str(p)[:200]); return
    t=p["$type"].split(",")[0].split(".")[-1]
    n=p.get("Name")
    v=p.get("Value")
    if t in("StructPropertyData","ArrayPropertyData"):
        print(" "*ind+f"{n} [{p.get('StructType') or p.get('ArrayType')}]")
        for c in v or []: val(c,ind+2)
    elif t=="MapPropertyData":
        print(" "*ind+f"{n} MAP")
        for kv in v or []:
            print(" "*(ind+2)+"key:"); 
            for k in (kv if isinstance(kv,list) else [kv]): val(k,ind+4)
    elif t=="ObjectPropertyData": print(" "*ind+f"{n} = {ref(v)}")
    elif t=="SoftObjectPropertyData": print(" "*ind+f"{n} = {v}")
    else: print(" "*ind+f"{n} ({t[:-12]}) = {v if not isinstance(v,(dict,list)) else json.dumps(v)[:200]}")
for i,e in enumerate(d["Exports"],1):
    print(f"EXPORT {i} {e['ObjectName']} class={ref(e['ClassIndex'])} outer={ref(e['OuterIndex'])} tmpl={ref(e['TemplateIndex'])}")
    for p in e.get("Data") or []: val(p,2)
