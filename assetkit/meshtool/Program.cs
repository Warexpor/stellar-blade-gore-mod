// meshtool: read Stellar Blade skeletal meshes from legacy files (retoc to-legacy output).
//   dump <legacy_root> <usmap> <package> <out.json>   raw render LODs: sections, indices, positions, skin weights, bones
//   gltf <legacy_root> <usmap> <package> <out_dir>    glTF 2.0 (binary) for Blender
//   morphs <legacy_root> <usmap> <package> <out.json>  morph target deltas (LOD0)
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

if (cmd == "anims")
{
    // anims <legacy_root> <usmap> - <out.json>: per animation sequence (package paths on stdin) its length and, in
    // component space, the pelvis and head heights and the root's travel over its frames (is she on the floor at
    // the end?)
    var rows = new List<object>();
    string? p;
    while ((p = Console.ReadLine()) != null)
    {
        p = p.Trim(); if (p.Length == 0) continue;
        CUE4Parse.UE4.Assets.Exports.Animation.UAnimSequence? a = null;
        try
        {
            a = provider.LoadPackageObject<CUE4Parse.UE4.Assets.Exports.Animation.UAnimSequence>($"{p}.{Path.GetFileName(p)}");
            rows.Add(AnimRow(a, p));
        }
        // the game's own codecs aren't all supported: the length and frame count still come from the asset
        catch (Exception e) { rows.Add(new { package = p, length = a?.SequenceLength, frames = a?.NumFrames, error = e.Message }); }
    }
    await File.WriteAllTextAsync(outp, JsonSerializer.Serialize(rows, new JsonSerializerOptions { WriteIndented = true }));
    return 0;
}

var mesh = provider.LoadPackageObject<USkeletalMesh>($"{pkg}.{Path.GetFileName(pkg)}");
if (cmd == "morphs")
{
    // morphs: per morph target, its LOD0 deltas as [vertex, dx, dy, dz] (vertex: the render LOD0 index of dump)
    var morphs = new Dictionary<string, float[][]>();
    foreach (var mi in mesh.MorphTargets)
    {
        if (!mi.TryLoad<CUE4Parse.UE4.Assets.Exports.Animation.UMorphTarget>(out var mt) || mt.MorphLODModels.Length == 0) continue;
        morphs[mt.Name] = mt.MorphLODModels[0].Vertices.Select(v => new[] { (float)v.SourceIdx, v.PositionDelta.X, v.PositionDelta.Y, v.PositionDelta.Z }).ToArray();
    }
    await File.WriteAllTextAsync(outp, JsonSerializer.Serialize(morphs));
    Console.WriteLine($"{pkg}: {morphs.Count} morph targets -> {outp}");
    return 0;
}
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

static object AnimRow(CUE4Parse.UE4.Assets.Exports.Animation.UAnimSequence anim, string pkg)
{
    var set = CUE4Parse_Conversion.Animations.AnimConverter.ConvertAnims(anim);
    var seq = set.Sequences[0];
    var rs = set.Skeleton.ReferenceSkeleton;
    int n = rs.FinalRefBoneInfo.Length;
    int Find(string name) { for (int i = 0; i < n; i++) if (rs.FinalRefBoneInfo[i].Name.Text == name) return i; return -1; }
    int pel = Find("Bip001-Pelvis"), head = Find("Bip001-Head"), rootb = 0;
    var heights = new List<float[]>();
    int frames = Math.Max(seq.NumFrames, 1);
    for (int f = 0; f < frames; f++)
    {
        var wq = new CUE4Parse.UE4.Objects.Core.Math.FQuat[n];
        var wp = new CUE4Parse.UE4.Objects.Core.Math.FVector[n];
        for (int i = 0; i < n; i++)
        {
            var bp = rs.FinalRefBonePose[i];
            var q = bp.Rotation; var t = bp.Translation; var sc = bp.Scale3D;
            if (i < seq.Tracks.Count && seq.Tracks[i] != null && (seq.Tracks[i].KeyQuat.Length > 0 || seq.Tracks[i].KeyPos.Length > 0))
                seq.Tracks[i].GetBoneTransform(f, frames, ref q, ref t, ref sc);
            int par = rs.FinalRefBoneInfo[i].ParentIndex;
            if (par < 0) { wq[i] = q; wp[i] = t; }
            else { wq[i] = wq[par] * q; wp[i] = wp[par] + wq[par].RotateVector(t); }
        }
        heights.Add(new[] { pel >= 0 ? wp[pel].Z : 0, head >= 0 ? wp[head].Z : 0, wp[rootb].X, wp[rootb].Y, wp[rootb].Z });
    }
    var first = heights[0]; var last = heights[^1];
    return new
    {
        package = pkg, length = anim.SequenceLength, frames = seq.NumFrames,
        pelvis = new { first = first[0], last = last[0], min = heights.Min(h => h[0]), max = heights.Max(h => h[0]) },
        head = new { first = first[1], last = last[1], min = heights.Min(h => h[1]) },
        rootTravel = new[] { last[2] - first[2], last[3] - first[3], last[4] - first[4] },
        // the head's height at every tenth of the way, to see when she reaches the floor
        headCurve = Enumerable.Range(0, 11).Select(k => MathF.Round(heights[(int)((heights.Count - 1) * k / 10.0)][1], 1)).ToArray(),
    };
}
