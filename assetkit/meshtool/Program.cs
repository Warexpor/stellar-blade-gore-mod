// meshtool: read Stellar Blade skeletal meshes from legacy files (retoc to-legacy output).
//   dump <legacy_root> <usmap> <package> <out.json>   raw render LODs: sections, indices, positions, skin weights, bones
//   gltf <legacy_root> <usmap> <package> <out_dir>    glTF 2.0 (binary) for Blender
//   bones <legacy_root> <usmap> - <out_dir>           reference skeletons only, package paths on stdin, <out_dir>/<package>.json
// <package> is the path under <legacy_root> without extension, e.g. SB/Content/Art/Character/PC/CH_P_EVE_30/CH_P_EVE_30
using System.Text.Json;
using CUE4Parse.FileProvider;
using CUE4Parse.MappingsProvider.Usmap;
using CUE4Parse.UE4.Assets.Exports.SkeletalMesh;
using CUE4Parse.UE4.Versions;
using CUE4Parse_Conversion;
using CUE4Parse_Conversion.Options;

if (args.Length != 5) { Console.Error.WriteLine("usage: meshtool dump|gltf <legacy_root> <usmap> <package> <out>"); return 2; }
var (cmd, root, usmap, pkg, outp) = (args[0], args[1], args[2], args[3], args[4]);

var provider = new DefaultFileProvider(root, SearchOption.AllDirectories, true, new VersionContainer(EGame.GAME_StellarBlade));
provider.MappingsContainer = new FileUsmapTypeMappingsProvider(usmap);
provider.Initialize();
provider.Mount();
if (cmd == "ls") { foreach (var k in provider.Files.Keys.Take(20)) Console.WriteLine(k); return 0; }
if (cmd == "bones")
{
    string? p;
    while ((p = Console.ReadLine()) != null)
    {
        p = p.Trim(); if (p.Length == 0) continue;
        var m = provider.LoadPackageObject<USkeletalMesh>($"{p}.{Path.GetFileName(p)}");
        var o = Path.Combine(outp, p + ".json");
        Directory.CreateDirectory(Path.GetDirectoryName(o)!);
        await File.WriteAllTextAsync(o, JsonSerializer.Serialize(new { package = p, bones = Bones(m.ReferenceSkeleton) }));
    }
    return 0;
}

var mesh = provider.LoadPackageObject<USkeletalMesh>($"{pkg}.{Path.GetFileName(pkg)}");
if (cmd == "gltf")
{
    var session = new ExportSession();
    session.Add(mesh);
    var res = await session.RunAsync(outp, new ExportOptions(meshFormat: EMeshFormat.Gltf2, exportMaterials: false, exportMorphTargets: false));
    foreach (var r in res) Console.WriteLine(r.Success ? string.Join("\n", r.DiskFilePaths) : r.ToString());
    return res.All(r => r.Success) ? 0 : 1;
}

static string B64<T>(T[] a) where T : unmanaged => Convert.ToBase64String(System.Runtime.InteropServices.MemoryMarshal.AsBytes(a.AsSpan()));

static object[] Bones(CUE4Parse.UE4.Assets.Exports.Animation.FReferenceSkeleton skel) => skel.FinalRefBoneInfo.Select((b, i) =>
{
    var t = skel.FinalRefBonePose[i];
    return (object)new { name = b.Name.Text, parent = b.ParentIndex, rot = new[] { t.Rotation.X, t.Rotation.Y, t.Rotation.Z, t.Rotation.W }, loc = new[] { t.Translation.X, t.Translation.Y, t.Translation.Z } };
}).ToArray();
var bones = Bones(mesh.ReferenceSkeleton);
var lods = new List<object>();
foreach (var lod in mesh.LODModels ?? [])
{
    if (lod.SkipLod) { lods.Add(new { skipped = true }); continue; }
    var vb = lod.VertexBufferGPUSkin;
    var n = vb.GetVertexCount();
    var pos = new float[n * 3];
    FSkelMeshVertexBase V(int i) => vb.VertsFloat.Length > 0 ? vb.VertsFloat[i] : vb.VertsHalf.Length > 0 ? vb.VertsHalf[i]
        : vb.VertsFloatPacked.Length > 0 ? vb.VertsFloatPacked[i] : vb.VertsHalfPacked[i];
    // skin weights: bone indices are section-local (BoneMap), resolve to reference-skeleton indices
    var infBone = new short[n * 8];
    var infW = new byte[n * 8];
    Array.Fill(infBone, (short)-1);
    var secOf = new int[n];
    for (var s = 0; s < lod.Sections.Length; s++)
    {
        var sec = lod.Sections[s];
        for (var v = (int)sec.BaseVertexIndex; v < sec.BaseVertexIndex + sec.NumVertices && v < n; v++) secOf[v] = s;
    }
    for (var i = 0; i < n; i++)
    {
        var vx = V(i);
        pos[i * 3] = vx.Pos.X; pos[i * 3 + 1] = vx.Pos.Y; pos[i * 3 + 2] = vx.Pos.Z;
        var inf = vx.Infs;
        if (inf == null) continue;
        var map = lod.Sections[secOf[i]].BoneMap;
        for (var k = 0; k < Math.Min(8, inf.BoneIndex.Length); k++)
        {
            var w = inf.BoneWeight[k];
            if (w == 0) continue;
            infBone[i * 8 + k] = (short)map[inf.BoneIndex[k]];
            infW[i * 8 + k] = (byte)Math.Min(255, inf.bUse16BitBoneWeight ? w >> 8 : w);
        }
    }
    lods.Add(new
    {
        numVertices = n,
        sections = lod.Sections.Select(s => new { material = s.MaterialIndex, baseIndex = s.BaseIndex, numTriangles = s.NumTriangles, baseVertex = s.BaseVertexIndex, numVertices = s.NumVertices, boneMap = s.BoneMap, cloth = s.HasClothData, disabled = s.bDisabled }).ToArray(),
        indices = B64(lod.Indices!.Buffer!),
        positions = B64(pos),
        infBones = B64(infBone),
        infWeights = Convert.ToBase64String(infW),
    });
}
var mats = mesh.SkeletalMaterials.Select(m => m.MaterialInterface?.Name ?? m.MaterialSlotName.Text).ToArray();
await File.WriteAllTextAsync(outp, JsonSerializer.Serialize(new { package = pkg, bones, materials = mats, lods }));
Console.WriteLine($"{pkg}: {bones.Length} bones, {lods.Count} LODs -> {outp}");
return 0;
