using UAssetAPI;
using UAssetAPI.ExportTypes;
using UAssetAPI.Unversioned;
using UAssetAPI.UnrealTypes;
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
switch (args[0]) {
  case "dump": File.WriteAllText(args[2], Load(args[1]).SerializeJson(true)); break;
  case "fromjson": {
    var a = UAsset.DeserializeJson(File.ReadAllText(args[1]));
    a.Mappings = map; a.Write(args[2]); Console.WriteLine("wrote " + args[2]); break;
  }
  case "dumpall": { // dumpall <legacy_content_root> <json_root> [class], package paths (no extension) on stdin
    // Dumps each package (only those whose main export is [class]) and checks that JSON -> asset writes the same
    // export data (.uexp) and an equally long header; the header may differ in name hashes, which retoc writes
    // as 0 and UAssetAPI recomputes. Prints "ok|bad|skip <rel> [why]".
    string? rel;
    while ((rel = Console.ReadLine()) != null) {
      rel = rel.Trim(); if (rel.Length == 0) continue;
      try {
        var f = Path.Combine(args[1], rel + ".uasset");
        if (!File.Exists(f)) { Console.WriteLine($"missing {rel}"); continue; }
        var a = Load(f);
        var main = a.Exports.FirstOrDefault(e => e.OuterIndex.Index == 0);
        if (args.Length > 3 && main?.GetExportClassType().ToString() != args[3]) { Console.WriteLine($"skip {rel} {main?.GetExportClassType()}"); continue; }
        var json = a.SerializeJson(true);
        var back = UAsset.DeserializeJson(json); back.Mappings = map;
        var hdr = (int)new FileInfo(f).Length;
        var orig = File.ReadAllBytes(f).Concat(File.ReadAllBytes(Path.ChangeExtension(f, ".uexp"))).ToArray();
        var rt = back.WriteData().ToArray();
        if (rt.Length != orig.Length || !rt.AsSpan(hdr).SequenceEqual(orig.AsSpan(hdr))) { Console.WriteLine($"bad {rel} round-trip differs"); continue; }
        var o = Path.Combine(args[2], rel + ".json");
        Directory.CreateDirectory(Path.GetDirectoryName(o)!);
        File.WriteAllText(o, json);
        Console.WriteLine($"ok {rel}");
      } catch (Exception ex) { Console.WriteLine($"bad {rel} {ex.Message.Split('\n')[0]}"); }
      GC.Collect();
    }
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
