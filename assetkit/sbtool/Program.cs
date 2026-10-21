using UAssetAPI;
using UAssetAPI.ExportTypes;
using UAssetAPI.Unversioned;
using UAssetAPI.UnrealTypes;
using UAssetAPI.PropertyTypes.Objects;
using UAssetAPI.PropertyTypes.Structs;
var ver = EngineVersion.VER_UE4_27;
var map = new Usmap(Environment.GetEnvironmentVariable("SB_USMAP"));
// UAssetAPI writes ClothingAssetCommon back shorter than it read it (cloth LOD data is lost), so exports of these
// classes stay raw bytes. Nothing here edits them.
string[] rawClasses = (Environment.GetEnvironmentVariable("SB_RAW_CLASSES") ?? "ClothingAssetCommon").Split(',');
UAsset Load(string p) {
  var head = new UAsset(p, false, ver, map);
  var skip = head.Exports.Select((e, i) => (e, i)).Where(t => rawClasses.Contains(t.e.GetExportClassType().ToString())).Select(t => t.i).ToArray();
  if (skip.Length == 0) return new UAsset(p, ver, map);
  var a = new UAsset(ver, map) { FilePath = p };
  a.Read(a.PathToReader(p), skip);
  return a;
}
// batch commands take package paths (SB/Content-relative, no extension) on stdin and run SB_JOBS at a time
// (default: half the cores; a mesh package holds a few hundred MB while it is being processed)
int jobs = int.TryParse(Environment.GetEnvironmentVariable("SB_JOBS"), out var j) && j > 0 ? j : Math.Max(1, Environment.ProcessorCount / 2);
void Batch(Action<string> each) {
  var rels = new List<string>();
  string? line;
  while ((line = Console.ReadLine()) != null) if (line.Trim().Length > 0) rels.Add(line.Trim());
  Parallel.ForEach(rels, new ParallelOptions { MaxDegreeOfParallelism = jobs }, rel => {
    try { each(rel); } catch (Exception ex) { Console.WriteLine($"bad {rel} {ex.Message.Split('\n')[0]}"); }
  });
}
// the bAllowCPUAccess flags of a skeletal mesh's LODInfo entries
IEnumerable<(int lod, BoolPropertyData flag)> CpuFlags(UAsset a) {
  var main = a.Exports.OfType<NormalExport>().First(e => e.OuterIndex.Index == 0);
  var info = main.Data.OfType<ArrayPropertyData>().First(p => p.Name.ToString() == "LODInfo");
  for (int i = 0; i < info.Value.Length; i++) {
    var flag = ((StructPropertyData)info.Value[i]).Value.OfType<BoolPropertyData>().FirstOrDefault(p => p.Name.ToString() == "bAllowCPUAccess")
      ?? throw new Exception($"LOD{i} has no bAllowCPUAccess");
    yield return (i, flag);
  }
}
void SetCpu(UAsset a, int[] lods) {
  foreach (var (lod, flag) in CpuFlags(a)) if (lods.Contains(lod)) { flag.Value = true; flag.IsZero = false; }
}
// a package's bytes as UAssetAPI writes them, and whether that is the file it came from (header length and export
// data; the header may differ in name hashes, which retoc writes as 0 and UAssetAPI recomputes)
(byte[] bytes, bool same) RoundTrip(UAsset a, string f) {
  var rt = a.WriteData().ToArray();
  var hdr = (int)new FileInfo(f).Length;
  var orig = File.ReadAllBytes(f).Concat(File.ReadAllBytes(Path.ChangeExtension(f, ".uexp"))).ToArray();
  return (rt, rt.Length == orig.Length && rt.AsSpan(hdr).SequenceEqual(orig.AsSpan(hdr)));
}
string Import(UAsset a, FPackageIndex i) {
  var imp = i.ToImport(a);
  return imp.ObjectName.ToString();
}
string ImportPackage(UAsset a, FPackageIndex i) {
  var imp = i.ToImport(a);
  while (imp.OuterIndex.Index != 0) imp = imp.OuterIndex.ToImport(a);
  return imp.ObjectName.ToString();
}
switch (args[0]) {
  case "dump": File.WriteAllText(args[2], Load(args[1]).SerializeJson(true)); break;
  case "fromjson": {
    var a = UAsset.DeserializeJson(File.ReadAllText(args[1]));
    a.Mappings = map; a.Write(args[2]); Console.WriteLine("wrote " + args[2]); break;
  }
  case "dumpall": { // dumpall <legacy_content_root> <json_root> [class], package paths (no extension) on stdin
    // Dumps each package (only those whose main export is [class]) and checks that JSON -> asset writes the same
    // export data (.uexp) and an equally long header (see RoundTrip). Prints "ok|bad|skip|missing <rel> [why]".
    Batch(rel => {
      var f = Path.Combine(args[1], rel + ".uasset");
      if (!File.Exists(f)) { Console.WriteLine($"missing {rel}"); return; }
      var a = Load(f);
      var main = a.Exports.FirstOrDefault(e => e.OuterIndex.Index == 0);
      if (args.Length > 3 && main?.GetExportClassType().ToString() != args[3]) { Console.WriteLine($"skip {rel} {main?.GetExportClassType()}"); return; }
      var json = a.SerializeJson(true);
      var back = UAsset.DeserializeJson(json); back.Mappings = map;
      if (!RoundTrip(back, f).same) { Console.WriteLine($"bad {rel} round-trip differs"); return; }
      var o = Path.Combine(args[2], rel + ".json");
      Directory.CreateDirectory(Path.GetDirectoryName(o)!);
      File.WriteAllText(o, json);
      Console.WriteLine($"ok {rel}");
    });
    break;
  }
  case "dumplist": { // dumplist <legacy_content_root> <json_root>: plain dumps, no checks
    Batch(rel => {
      var o = Path.Combine(args[2], rel + ".json");
      Directory.CreateDirectory(Path.GetDirectoryName(o)!);
      File.WriteAllText(o, Load(Path.Combine(args[1], rel + ".uasset")).SerializeJson(true));
    });
    break;
  }
  case "fromjsonall": { // fromjsonall <json_root> <legacy_content_root>
    Batch(rel => {
      var a = UAsset.DeserializeJson(File.ReadAllText(Path.Combine(args[1], rel + ".json")));
      a.Mappings = map;
      var o = Path.Combine(args[2], rel + ".uasset");
      Directory.CreateDirectory(Path.GetDirectoryName(o)!);
      a.Write(o);
    });
    break;
  }
  case "meshinfo": { // meshinfo <legacy_content_root>: "ok <rel> <skeleton> <physics asset package>" per skeletal mesh
    // that round-trips byte-exactly (no JSON: meshes are only ever patched in place, see cpuaccess)
    Batch(rel => {
      var f = Path.Combine(args[1], rel + ".uasset");
      if (!File.Exists(f)) { Console.WriteLine($"missing {rel}"); return; }
      var a = Load(f);
      var main = a.Exports.OfType<NormalExport>().FirstOrDefault(e => e.OuterIndex.Index == 0);
      if (main?.GetExportClassType().ToString() != "SkeletalMesh") { Console.WriteLine($"skip {rel} {main?.GetExportClassType()}"); return; }
      if (!RoundTrip(a, f).same) { Console.WriteLine($"bad {rel} round-trip differs"); return; }
      CpuFlags(a).ToList();
      var obj = (string n) => main.Data.OfType<ObjectPropertyData>().FirstOrDefault(p => p.Name.ToString() == n)?.Value;
      var sk = obj("Skeleton"); var pa = obj("PhysicsAsset");
      // and every object it imports, as "imp <rel> <package> <path>" (lowercase, '/'-joined like retoc), for
      // patch_shows.fix_public
      var lines = new List<string> { $"ok {rel} {(sk != null && sk.IsImport() ? Import(a, sk) : "-")} {(pa != null && pa.IsImport() ? ImportPackage(a, pa) : "-")}" };
      for (int i = 0; i < a.Imports.Count; i++) {
        var imp = a.Imports[i];
        if (imp.OuterIndex.Index == 0) continue;
        var parts = new List<string> { imp.ObjectName.ToString() };
        var outer = imp.OuterIndex.ToImport(a);
        while (outer.OuterIndex.Index != 0) { parts.Insert(0, outer.ObjectName.ToString()); outer = outer.OuterIndex.ToImport(a); }
        parts.Insert(0, outer.ObjectName.ToString());
        lines.Add($"imp {rel} {outer.ObjectName.ToString().ToLowerInvariant()} {string.Join("/", parts).ToLowerInvariant()}");
      }
      Console.Write(string.Join("\n", lines) + "\n");
    });
    break;
  }
  case "cpuaccess": { // cpuaccess <legacy_content_root> <out_content_root> <lods, comma separated>
    var lods = args[3].Split(',').Select(int.Parse).ToArray();
    Batch(rel => {
      var a = Load(Path.Combine(args[1], rel + ".uasset"));
      SetCpu(a, lods);
      var o = Path.Combine(args[2], rel + ".uasset");
      Directory.CreateDirectory(Path.GetDirectoryName(o)!);
      a.Write(o);
      Console.WriteLine($"ok {rel}");
    });
    break;
  }
  case "checkcpu": { // checkcpu <vanilla_content_root> <repacked_content_root> <lods>: the repacked mesh is the vanilla
    // one with exactly those flags set. Compared per export (data and raw extras, as JSON so names are strings):
    // the read-back header differs anyway, since retoc can't resolve the game's imports from the mod container alone.
    var lods = args[3].Split(',').Select(int.Parse).ToArray();
    Batch(rel => {
      var v = Load(Path.Combine(args[1], rel + ".uasset"));
      SetCpu(v, lods);
      var o = Load(Path.Combine(args[2], rel + ".uasset"));
      var off = CpuFlags(o).Where(t => lods.Contains(t.lod) && !t.flag.Value).Select(t => t.lod).ToList();
      if (off.Count > 0) { Console.WriteLine($"bad {rel} LOD{string.Join(",", off)} without CPU access"); return; }
      var exports = (UAsset a) => ((Newtonsoft.Json.Linq.JArray)Newtonsoft.Json.Linq.JObject.Parse(a.SerializeJson(false))["Exports"]!)
        .ToDictionary(e => (string)e["ObjectName"]!, e => new Newtonsoft.Json.Linq.JArray(e["Data"] ?? "", e["Extras"] ?? ""));
      var ve = exports(v); var oe = exports(o);
      var diff = ve.Keys.Union(oe.Keys).Where(k => !ve.ContainsKey(k) || !oe.ContainsKey(k) || !Newtonsoft.Json.Linq.JToken.DeepEquals(ve[k], oe[k])).ToList();
      Console.WriteLine(diff.Count == 0 ? $"ok {rel}" : $"bad {rel} changed beyond bAllowCPUAccess: {string.Join(",", diff)}");
    });
    break;
  }
  case "validate": {
    int ok = 0, bad = 0;
    foreach (var f in Directory.EnumerateFiles(args[1], "*.uasset", SearchOption.AllDirectories)) {
      try {
        var a = Load(f);
        var raw = a.Exports.Where(e => e is RawExport || (e is NormalExport n && e.Extras != null && e.Extras.Length > 4)).ToList();
        var orig = File.ReadAllBytes(f).Concat(File.ReadAllBytes(Path.ChangeExtension(f, ".uexp"))).ToArray();
        var ms = a.WriteData(); var rt = ms.ToArray();
        bool same = rt.SequenceEqual(orig);
        if (raw.Count == 0 && same) ok++; else { bad++; if (bad <= 40) Console.WriteLine($"BAD {Path.GetFileName(f)} raw={raw.Count} same={same} {string.Join(",", raw.Select(r => r.GetExportClassType().ToString()).Distinct())}"); }
      } catch (Exception ex) { bad++; if (bad <= 40) Console.WriteLine($"ERR {Path.GetFileName(f)} {ex.Message.Split('\n')[0]}"); }
    }
    Console.WriteLine($"ok={ok} bad={bad}"); break;
  }
}
