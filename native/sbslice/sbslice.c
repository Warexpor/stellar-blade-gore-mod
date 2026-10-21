// sbslice.dll: dismemberment for Eve, through the engine's own skinning (see "skin cut" below).
//
// Nothing in Lua can reach the skin weights, so this DLL repoints one debug cheat that gameplay never calls,
// USBCheatManager::SBRewardGroupDropFormationPathLocation, to its own handler (exec_slice). The cheat's
// FString parameter carries the command, its LocX/Y/Z and DirX/Y/Z floats a point and a direction.
// Handshake (paths relative to the game's Win64 dir, like the Lua log):
//   Lua writes the UFunction's address (hex) to ue4ss/Mods/StellarBladeGore/sbslice.req
//   the DLL swaps that UFunction's native pointer (data, no code patching) and writes sbslice.ok / sbslice.err
// Loaded by UE4SS as a C++ mod (Mods/SBSlice/dlls/main.dll). It exports no start_mod, so UE4SS logs that it
// can't start it; the DLL pins itself so it stays loaded.
typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef void *HANDLE;
#define WINAPI __stdcall
__declspec(dllimport) HANDLE WINAPI CreateThread(void *, u64, u32(WINAPI *)(void *), void *, u32, u32 *);
__declspec(dllimport) void WINAPI Sleep(u32);
__declspec(dllimport) HANDLE WINAPI CreateFileW(const u16 *, u32, u32, void *, u32, u32, HANDLE);
__declspec(dllimport) int WINAPI ReadFile(HANDLE, void *, u32, u32 *, void *);
__declspec(dllimport) int WINAPI WriteFile(HANDLE, const void *, u32, u32 *, void *);
__declspec(dllimport) int WINAPI CloseHandle(HANDLE);
__declspec(dllimport) int WINAPI DeleteFileW(const u16 *);
__declspec(dllimport) void *WINAPI GetModuleHandleW(const u16 *);
__declspec(dllimport) int WINAPI GetModuleHandleExW(u32, const void *, void **);
__declspec(dllimport) int WINAPI DisableThreadLibraryCalls(void *);
__declspec(dllimport) void *WINAPI VirtualAlloc(void *, u64, u32, u32);
__declspec(dllimport) int WINAPI VirtualFree(void *, u64, u32);

int _fltused = 0;
#ifndef SBSLICE_HOSTED
// no CRT: clang still calls these for struct copies (the sink records)
void *memcpy(void *d, const void *s, u64 n)
{
    unsigned char *o = d;
    const unsigned char *i = s;
    while (n--) *o++ = *i++;
    return d;
}
void *memset(void *d, int c, u64 n)
{
    unsigned char *o = d;
    while (n--) *o++ = (unsigned char)c;
    return d;
}
#endif

// SB-Win64-Shipping.exe (Steam build of 2025-09-10, sha256 in README); RVAs from the image base
#define RVA_EXEC_REWARD_DROP_FORMATION_PATH_LOCATION 0x26a25e0 // its native exec thunk
#define RVA_SET_SKIN_WEIGHT_OVERRIDE 0x4128fd0               // USkinnedMeshComponent::SetSkinWeightOverride
#define RVA_GET_SKIN_WEIGHT_BUFFER 0x4127080                 // USkinnedMeshComponent::GetSkinWeightBuffer
#define RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS 0x41288f0          // FSkelMeshComponentLODInfo::ReleaseOverrideSkinWeights
#define RVA_MARK_RENDER_STATE_DIRTY 0x40888d0                // UActorComponent::MarkRenderStateDirty
#define RVA_WEAK_PTR_GET 0x2ba3ab0                           // FWeakObjectPtr::Get
#define INVALID_HANDLE ((HANDLE)(long long)-1)

static u64 exe;

static void write_file(const u16 *path, const char *s)
{
    HANDLE h = CreateFileW(path, 0x40000000 /*GENERIC_WRITE*/, 1, 0, 2 /*CREATE_ALWAYS*/, 0x80, 0);
    if (h == INVALID_HANDLE) return;
    u32 n = 0, w;
    while (s[n]) n++;
    WriteFile(h, s, n, &w, 0);
    CloseHandle(h);
}

static int hexval(u32 c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static void hex64(char *out, u64 v)
{
    for (int i = 15; i >= 0; i--) { int d = v & 15; out[i] = d < 10 ? '0' + d : 'a' + d - 10; v >>= 4; }
    out[16] = 0;
}

static float rsqrt(float x) { return 1.0f / __builtin_sqrtf(x); }
static float fabsf_(float x) { return x < 0 ? -x : x; }

static u64 parse_hex(const u16 *txt, int len)
{
    u64 v = 0;
    for (int i = 0; txt && i < len; i++) {
        int d = hexval(txt[i]);
        if (d < 0) break;
        v = v << 4 | (u64)d;
    }
    return v;
}

static const u16 UNPIN[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.unpin";

// SB's engine adds a counter to USceneComponent (+0x180, not reflected) that stops the parent from pushing
// its transform down to the component while it is non-zero. A death ragdoll sets it on Eve's mesh and the
// respawn never clears it, so the mesh stays where she died while the capsule respawns elsewhere (zeroing
// it in a live game made the mesh follow again). Writes the old value to sbslice.unpin.
#define SCENE_PARENT_UPDATE_BLOCK 0x180
static void unpin(u64 component)
{
    u32 *c = (u32 *)(component + SCENE_PARENT_UPDATE_BLOCK);
    char msg[24] = "was 0x";
    hex64(msg + 6, *c);
    // a sane counter is small; anything else means a wrong address, so leave the memory alone
    if (*c <= 64) *c = 0;
    else { msg[0] = 'b'; msg[1] = 'a'; msg[2] = 'd'; }
    write_file(UNPIN, msg);
}

// ---- skin cut: dismemberment through a per-component skin weight override --------------------------------
// The game's own slicer can't hide the cut region on Eve (it relies on a material parameter only its gore
// master has), so the cut is made in the skinning instead, on her own mesh with her own materials. For one
// skeletal mesh component and a plane (current pose) every vertex joins one side:
//   limb: weighted to bone B's subtree and in front of the plane -> keeps only limb bone weights
//   body: everything else -> keeps only body bone weights
// so no vertex is shared across the cut any more, and once Lua breaks the ragdoll constraint at B the limb's
// physics bodies carry it away without stretching anything. Triangles that cross the plane would still span
// the gap, so all their vertices ("seam") go 100% to a sink bone of their side, a helper bone close to the
// joint, and that bone's inverse bind matrix becomes a zero scale at its own origin: every seam vertex then
// lands on the sink's live position, whatever drives it (animation, physics), the triangles across the cut
// collapse to lines and the rings next to them close the opening like a drawstring. The sink's own vertices
// move to their strongest other bone first. Lua covers both openings with a cap (fit reported here).
// Why not HideBone: a hidden bone renders at its parent's bind origin, not at itself, and it leaves the
// required bones, so it stops updating (the severed limb then stretched back to where the cut was).
// The weights go to the engine's own USkinnedMeshComponent::SetSkinWeightOverride, which maps mesh bones to
// each section's BoneMap and silently drops a weight on a bone the section doesn't have, so every bone used
// here is checked against the vertex's section. Layouts below are from its skinning code in this build
// (GetTypedSkinnedVertexPosition, CreateSkinWeightsArray, UpdateRefToLocalMatrices):
#define SC_SKELETAL_MESH 0x568       // USkinnedMeshComponent::SkeletalMesh
#define SC_MASTER_POSE 0x570         // TWeakObjectPtr MasterPoseComponent
#define SC_SPACE_BASES 0x5a8         // TArray<FTransform> ComponentSpaceTransformsArray[2]
#define SC_SPACE_READ 0x674          // CurrentReadComponentTransforms
#define SC_MASTER_BONE_MAP 0x690     // TArray<int32> MasterBoneMap
#define SC_LOD_INFO 0x798            // TArray<FSkelMeshComponentLODInfo>, 0x48 each
#define SC_TO_WORLD 0x1f0            // USceneComponent::ComponentToWorld (quat, translation, scale)
#define SM_REF_BONE_INFO 0x1e0       // FinalRefBoneInfo: FName + int32 parent, 0xc each
#define SM_REF_BONE_POSE 0x1f0       // FinalRefBonePose: local FTransforms
#define SM_REF_BASES_INV 0x318       // TArray<FMatrix> RefBasesInvMatrix (read every frame for skinning)
#define SM_RENDER_DATA 0x80          // FSkeletalMeshRenderData* (its LODRenderData array first)
#define SC_MESH_OBJECT 0x7e8         // FSkeletalMeshObject*, render data at +0x40 when set
#define LOD_SECTIONS 0x10            // TArray<FSkelMeshRenderSection>, 0xe8 each
#define LOD_INDICES 0x28             // FRawStaticIndexBuffer16or32Interface*: vtable +0x58 Num, +0x68 Get(i)
#define LOD_POSITIONS 0xc8           // StaticVertexBuffers.PositionVertexBuffer: data +0x28, stride +0x30
#define LOD_NUM_VERTICES 0xfc
#define SEC_BASE_VERTEX 0x10
#define SEC_BONE_MAP 0x28            // TArray<uint16>
#define SEC_NUM_VERTICES 0x38
#define SW_VARIABLE 0x21             // FSkinWeightVertexBuffer: variable influences per vertex
#define SW_MAX_INFLUENCES 0x24
#define SW_16BIT_INDEX 0x28
#define SW_DATA 0x38
#define SW_NUM_VERTICES 0x40
#define SW_LOOKUP 0x78               // per vertex: offset << 8 | influence count (variable buffers)
#define MAX_INF 12                   // FSkelMeshSkinWeightInfo: int32 Bones[12], uint8 Weights[12]
#define STABLE_CM 3.0f               // a sink must sit where the bind pose puts it relative to its parent
#define MAX_SINKS 256

typedef struct { int bones[MAX_INF]; unsigned char weights[MAX_INF]; } skin_info;
typedef struct { void *data; int num, max; } tarray;
typedef void (*set_override_fn)(u64 comp, int lod, const tarray *weights);
typedef u64 (*get_buffer_fn)(u64 comp, int lod);
typedef void (*comp_fn)(u64 comp);
typedef void (*lodinfo_fn)(u64 lodinfo);
typedef u64 (*weak_get_fn)(u64 weak);
typedef int (*index_num_fn)(u64 self);
typedef u32 (*index_get_fn)(u64 self, u32 i);

// inverse bind matrices this DLL collapsed, to put back (the mesh asset is shared, so it must be undone)
// A cut records its sinks first and collapses them on "k" once the new weights are on the GPU: a collapsed bone
// under the old weights would pull every vertex the helper used to move onto its origin for a frame or two.
// A sink either collapses to a point (at, in the bone's frame) or, for a split, flattens onto the cut plane (pm, the
// whole replacement matrix): every vertex on it lands where it is, only pushed onto the plane, so the seam closes
// without a triangle reaching across the body.
static struct { u64 mesh; int bone, down, proj; float m[16], at[3], pm[16]; } sinks[MAX_SINKS];
#define SINK_IN 2.0f // cm a sink's collapse point sits inside its own side of the cut
static int nsinks;

// bones that never become a sink (Lua sends them before a cut, per mesh asset: the main skeleton, hair, capes,
// accessories). A sink gives up its weights everywhere and collapses: on a main deformer (the pelvis, a clavicle, the
// head) that broke the body around it, on a hair or cape bone the seam followed the swinging hair.
#define MAX_BONES 1024
static u64 nosink_mesh;
static unsigned char nosink[MAX_BONES];
// a split half's limbs, decided by Lua from where each limb is (a limb never splits lengthwise): roots of the limbs
// that go with the other half, and of the ones that stay. For the next MODE_SIDE cut on that component
#define MAX_LIMB_ROOTS 8
static u64 limbs_comp;
static int gone_roots[MAX_LIMB_ROOTS], ngone, keep_roots[MAX_LIMB_ROOTS], nkeep;

static const u16 CUTRES[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.cut";

static void quat_rot(const float *q, const float *v, float *o) // o = q * v * q^-1
{
    float tx = 2 * (q[1] * v[2] - q[2] * v[1]), ty = 2 * (q[2] * v[0] - q[0] * v[2]), tz = 2 * (q[0] * v[1] - q[1] * v[0]);
    o[0] = v[0] + q[3] * tx + (q[1] * tz - q[2] * ty);
    o[1] = v[1] + q[3] * ty + (q[2] * tx - q[0] * tz);
    o[2] = v[2] + q[3] * tz + (q[0] * ty - q[1] * tx);
}

static void world_to_comp(const float *tm, const float *p, float *o, int is_dir)
{
    float d[3] = { p[0], p[1], p[2] }, iq[4] = { -tm[0], -tm[1], -tm[2], tm[3] };
    if (!is_dir) { d[0] -= tm[4]; d[1] -= tm[5]; d[2] -= tm[6]; }
    quat_rot(iq, d, o);
    if (!is_dir) for (int i = 0; i < 3; i++) o[i] /= tm[8 + i] != 0 ? tm[8 + i] : 1;
}

static void comp_to_world(const float *tm, const float *p, float *o)
{
    float s[3] = { p[0] * tm[8], p[1] * tm[9], p[2] * tm[10] };
    quat_rot(tm, s, o);
    o[0] += tm[4]; o[1] += tm[5]; o[2] += tm[6];
}

static char *put(char *o, const char *s) { while (*s) *o++ = *s++; return o; }
static char *put_int(char *o, long long v)
{
    char t[24]; int n = 0;
    if (v < 0) { *o++ = '-'; v = -v; }
    do { t[n++] = '0' + v % 10; v /= 10; } while (v);
    while (n) *o++ = t[--n];
    return o;
}
static char *put_f(char *o, float f) // one decimal is plenty for cm
{
    long long t = (long long)(f * 10 + (f < 0 ? -0.5f : 0.5f));
    if (t < 0) { *o++ = '-'; t = -t; }
    o = put_int(o, t / 10); *o++ = '.'; *o++ = '0' + t % 10;
    return o;
}
static char *put_v(char *o, const char *name, const float *v, float k)
{
    o = put(o, name);
    for (int i = 0; i < 3; i++) { if (i) *o++ = ','; o = put_f(o, v[i] * k); }
    return o;
}

static void skin_result(const char *msg) { write_file(CUTRES, msg); }

// what one cut works on
typedef struct {
    u64 comp, sm;
    int nb, nv, nsec;
    unsigned char *binfo;            // FinalRefBoneInfo
    float *refinv;                   // RefBasesInvMatrix, 16 floats per bone
    float *space;                    // component-space pose of the pose source, 12 floats per bone
    int nspace;
    int *mmap;                       // MasterBoneMap or 0
    const unsigned char *inmap;      // [section * nb + bone]: bone is in that section's BoneMap
    const u16 *vsec;                 // section of each vertex
} cut_ctx;

static int parent_of(const cut_ctx *c, int bone) { return *(int *)(c->binfo + bone * 0xc + 8); }
static const float *pose_of(const cut_ctx *c, int bone)
{
    int s = c->mmap ? c->mmap[bone] : bone;
    return s >= 0 && s < c->nspace ? c->space + (u64)s * 12 : 0;
}

// skinned position of bind position vp under weights o (mesh bone indices), current pose
static void skin_point(const cut_ctx *c, const skin_info *o, const float *vp, float *x)
{
    x[0] = x[1] = x[2] = 0;
    for (int i = 0; i < MAX_INF; i++) {
        unsigned char w = o->weights[i];
        int mb = o->bones[i];
        if (!w || mb < 0 || mb >= c->nb) continue;
        const float *t = pose_of(c, mb);
        if (!t) continue;
        // component-space bone transform * inverse ref pose * bind position
        const float *m = c->refinv + (u64)mb * 16;
        float r[3] = { vp[0] * m[0] + vp[1] * m[4] + vp[2] * m[8] + m[12],
                       vp[0] * m[1] + vp[1] * m[5] + vp[2] * m[9] + m[13],
                       vp[0] * m[2] + vp[1] * m[6] + vp[2] * m[10] + m[14] };
        float sr[3] = { r[0] * t[8], r[1] * t[9], r[2] * t[10] }, q[3];
        quat_rot(t, sr, q);
        float k = w / 255.0f;
        x[0] += (q[0] + t[4]) * k; x[1] += (q[1] + t[5]) * k; x[2] += (q[2] + t[6]) * k;
    }
}

// move every weight of o on bones where drop[] says so to the strongest remaining bone, or else to fallback.
// Returns 1 if it changed o, 0 if not, -1 if it had to leave o alone (nothing to put the weight on).
static int keep_only(skin_info *o, const unsigned char *drop, int nb, int fallback)
{
    int target = -1, best = -1, gone = 0;
    for (int i = 0; i < MAX_INF; i++) {
        if (!o->weights[i]) continue;
        int mb = o->bones[i];
        if (mb >= 0 && mb < nb && drop[mb]) gone += o->weights[i];
        else if (o->weights[i] > best) { best = o->weights[i]; target = mb; }
    }
    if (!gone) return 0;
    if (target < 0) target = fallback;
    if (target < 0) return -1;
    for (int i = 0; i < MAX_INF; i++) {
        int mb = o->bones[i];
        if (o->weights[i] && mb >= 0 && mb < nb && drop[mb]) o->weights[i] = 0;
    }
    int slot = -1;
    for (int i = 0; i < MAX_INF; i++) if (o->weights[i] && o->bones[i] == target) slot = i;
    if (slot < 0) for (int i = 0; i < MAX_INF; i++) if (!o->weights[i]) { slot = i; o->bones[i] = target; break; }
    if (slot >= 0) o->weights[slot] += gone;
    return 1;
}

// a bone of the wanted side for a vertex of section s whose own bones all went: start, then its ancestors
static int fallback_bone(const cut_ctx *c, int s, int start, const unsigned char *drop)
{
    for (int f = start; f >= 0 && f < c->nb; f = parent_of(c, f))
        if (!drop[f] && c->inmap[(u64)s * c->nb + f]) return f;
    for (int f = 0; f < c->nb; f++) if (!drop[f] && c->inmap[(u64)s * c->nb + f]) return f;
    return -1;
}

// a sink that flattens (a split's, a dent's) is tied to its own plane: no other cut may reuse it
static int is_proj_sink(const cut_ctx *c, int bone)
{
    for (int i = 0; i < nsinks; i++) if (sinks[i].mesh == c->sm && sinks[i].bone == bone && sinks[i].proj) return 1;
    return 0;
}

static int is_sink(const cut_ctx *c, int bone)
{
    for (int i = 0; i < nsinks; i++) if (sinks[i].mesh == c->sm && sinks[i].bone == bone) return 1;
    return 0;
}

// symmetric 3x3 eigen decomposition (cyclic Jacobi): a becomes diagonal, columns of v the eigenvectors
static void eig3(float a[3][3], float v[3][3])
{
    for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) v[i][j] = i == j;
    static const int P[3] = { 0, 0, 1 }, Q[3] = { 1, 2, 2 };
    for (int sweep = 0; sweep < 24; sweep++) {
        float off = fabsf_(a[0][1]) + fabsf_(a[0][2]) + fabsf_(a[1][2]);
        if (off < 1e-9f) break;
        for (int r = 0; r < 3; r++) {
            int p = P[r], q = Q[r];
            if (fabsf_(a[p][q]) < 1e-12f) continue;
            float th = (a[q][q] - a[p][p]) / (2 * a[p][q]);
            float t = 1.0f / (fabsf_(th) + __builtin_sqrtf(th * th + 1));
            if (th < 0) t = -t;
            float cs = rsqrt(t * t + 1), sn = t * cs;
            for (int k = 0; k < 3; k++) { float x = a[k][p], y = a[k][q]; a[k][p] = cs * x - sn * y; a[k][q] = sn * x + cs * y; }
            for (int k = 0; k < 3; k++) { float x = a[p][k], y = a[q][k]; a[p][k] = cs * x - sn * y; a[q][k] = sn * x + cs * y; }
            for (int k = 0; k < 3; k++) { float x = v[k][p], y = v[k][q]; v[k][p] = cs * x - sn * y; v[k][q] = sn * x + cs * y; }
        }
    }
}

// outline of an opening: the convex hull of its rim points seen along the cut normal, as the rim points
// themselves (so the cap's edge sits on the skin), at most HULL_OUT of them, in order around dir
#define HULL_IN 4096
#define HULL_OUT 40
static float hull_uv[HULL_IN][2];
static int hull_idx[HULL_IN], hull_st[3 * HULL_IN + 2]; // sorted order, then the chain (up to 2x)
static int put_hull_cmp(int a, int b)
{
    return hull_uv[a][0] < hull_uv[b][0] || (hull_uv[a][0] == hull_uv[b][0] && hull_uv[a][1] < hull_uv[b][1]);
}
static float hull_cross(int o, int a, int b)
{
    return (hull_uv[a][0] - hull_uv[o][0]) * (hull_uv[b][1] - hull_uv[o][1]) - (hull_uv[a][1] - hull_uv[o][1]) * (hull_uv[b][0] - hull_uv[o][0]);
}
// pts / keep: rim points and which of them count; maj, mnr: in-plane axes (mnr = dir x maj, so going from maj
// towards mnr turns counter-clockwise seen from the side dir points to)
static char *put_hull(char *o, const char *tag, const float *pts, int n, const unsigned char *use,
                      const float *maj, const float *mnr, const float *tm)
{
    int m = 0;
    for (int i = 0; i < n && m < HULL_IN; i++) {
        if (!use[i]) continue;
        const float *q = pts + i * 3;
        hull_uv[m][0] = q[0] * maj[0] + q[1] * maj[1] + q[2] * maj[2];
        hull_uv[m][1] = q[0] * mnr[0] + q[1] * mnr[1] + q[2] * mnr[2];
        hull_idx[m] = i;
        m++;
    }
    if (m < 3) return o;
    // sort by (u, v): shell sort on an index permutation (hull_st as scratch for the order)
    int *ord = hull_st;
    for (int i = 0; i < m; i++) ord[i] = i;
    for (int gap = m / 2; gap > 0; gap /= 2)
        for (int i = gap; i < m; i++)
            for (int j = i; j >= gap && put_hull_cmp(ord[j], ord[j - gap]); j -= gap) { int t = ord[j]; ord[j] = ord[j - gap]; ord[j - gap] = t; }
    // Andrew's monotone chain, counter-clockwise; the chain goes after the sorted order in the same buffer
    int *h = ord + m, k = 0;
    for (int i = 0; i < m; i++) {
        while (k >= 2 && hull_cross(h[k - 2], h[k - 1], ord[i]) <= 0) k--;
        h[k++] = ord[i];
    }
    for (int i = m - 2, lo = k + 1; i >= 0; i--) {
        while (k >= lo && hull_cross(h[k - 2], h[k - 1], ord[i]) <= 0) k--;
        h[k++] = ord[i];
    }
    k--; // the last point repeats the first
    if (k < 3) return o;
    o = put(o, " "); o = put(o, tag); o = put(o, "p=");
    int count = k < HULL_OUT ? k : HULL_OUT;
    for (int j = 0; j < count; j++) {
        int i = hull_idx[h[(long)j * k / count]];
        float w[3];
        comp_to_world(tm, pts + i * 3, w);
        if (j) *o++ = ';';
        for (int c = 0; c < 3; c++) { if (c) *o++ = ','; o = put_f(o, w[c]); }
    }
    return o;
}

// the opening on one side, from its rim points (component space) around the cut plane (point pp, normal dir
// facing out of the opening): centre, major axis, normal, half extents along major / minor / normal; written to
// the result as world space. A cut near a joint also crosses armour, straps and pads that stand off the skin, so
// points further out than 1.6x the median distance from the cut axis are left out, and the extents are the
// ellipse the rest is spread over (sqrt(2 var) is the radius of a ring), not their extremes.
static char *put_fit(char *o, const char *tag, const float *pts, int n, const float *pp, const float *dir, const float *tm)
{
    o = put(o, " "); o = put(o, tag); o = put(o, "rim="); o = put_int(o, n);
    if (n < 3) return o;
    float rmax = 0;
    for (int i = 0; i < n; i++) {
        float d[3] = { pts[i * 3] - pp[0], pts[i * 3 + 1] - pp[1], pts[i * 3 + 2] - pp[2] };
        float h = d[0] * dir[0] + d[1] * dir[1] + d[2] * dir[2];
        float q[3] = { d[0] - h * dir[0], d[1] - h * dir[1], d[2] - h * dir[2] };
        float r = __builtin_sqrtf(q[0] * q[0] + q[1] * q[1] + q[2] * q[2]);
        if (r > rmax) rmax = r;
    }
    // median distance from the axis, by bisection (no buffer)
    float lo_r = 0, hi_r = rmax;
    for (int it = 0; it < 32; it++) {
        float mid = (lo_r + hi_r) * 0.5f;
        int below = 0;
        for (int i = 0; i < n; i++) {
            float d[3] = { pts[i * 3] - pp[0], pts[i * 3 + 1] - pp[1], pts[i * 3 + 2] - pp[2] };
            float h = d[0] * dir[0] + d[1] * dir[1] + d[2] * dir[2];
            float q[3] = { d[0] - h * dir[0], d[1] - h * dir[1], d[2] - h * dir[2] };
            if (q[0] * q[0] + q[1] * q[1] + q[2] * q[2] <= mid * mid) below++;
        }
        if (below * 2 >= n) hi_r = mid; else lo_r = mid;
    }
    float keep = hi_r * 1.6f;
    float mq[3] = { 0, 0, 0 }, mh = 0;
    int kept = 0;
    for (int i = 0; i < n; i++) {
        float d[3] = { pts[i * 3] - pp[0], pts[i * 3 + 1] - pp[1], pts[i * 3 + 2] - pp[2] };
        float h = d[0] * dir[0] + d[1] * dir[1] + d[2] * dir[2];
        float q[3] = { d[0] - h * dir[0], d[1] - h * dir[1], d[2] - h * dir[2] };
        if (q[0] * q[0] + q[1] * q[1] + q[2] * q[2] > keep * keep) continue;
        for (int k = 0; k < 3; k++) mq[k] += q[k];
        mh += h;
        kept++;
    }
    if (kept >= 3) { for (int k = 0; k < 3; k++) mq[k] /= (float)kept; mh /= (float)kept; }
    o = put(o, " "); o = put(o, tag); o = put(o, "kept="); o = put_int(o, kept);
    if (kept < 3) return o;
    float a[3][3] = { { 0 } }, v[3][3], ec = 0;
    for (int i = 0; i < n; i++) {
        float d[3] = { pts[i * 3] - pp[0], pts[i * 3 + 1] - pp[1], pts[i * 3 + 2] - pp[2] };
        float h = d[0] * dir[0] + d[1] * dir[1] + d[2] * dir[2];
        float q[3] = { d[0] - h * dir[0], d[1] - h * dir[1], d[2] - h * dir[2] };
        if (q[0] * q[0] + q[1] * q[1] + q[2] * q[2] > keep * keep) continue;
        float e[3] = { q[0] - mq[0], q[1] - mq[1], q[2] - mq[2] };
        for (int r = 0; r < 3; r++) for (int k = 0; k < 3; k++) a[r][k] += e[r] * e[k];
        if (fabsf_(h - mh) > ec) ec = fabsf_(h - mh);
    }
    for (int r = 0; r < 3; r++) for (int k = 0; k < 3; k++) a[r][k] /= (float)kept;
    eig3(a, v);
    int hi = 0;
    for (int k = 1; k < 3; k++) if (a[k][k] > a[hi][hi]) hi = k;
    float maj[3] = { v[0][hi], v[1][hi], v[2][hi] };
    float t = maj[0] * dir[0] + maj[1] * dir[1] + maj[2] * dir[2];
    for (int k = 0; k < 3; k++) maj[k] -= t * dir[k];
    float ml = maj[0] * maj[0] + maj[1] * maj[1] + maj[2] * maj[2];
    if (ml < 1e-8f) {
        // round opening: any in-plane axis
        float ax[3] = { fabsf_(dir[0]) < 0.9f ? 1.0f : 0.0f, fabsf_(dir[0]) < 0.9f ? 0.0f : 1.0f, 0 };
        t = ax[0] * dir[0] + ax[1] * dir[1];
        for (int k = 0; k < 3; k++) maj[k] = ax[k] - t * dir[k];
        ml = maj[0] * maj[0] + maj[1] * maj[1] + maj[2] * maj[2];
    }
    ml = rsqrt(ml);
    for (int k = 0; k < 3; k++) maj[k] *= ml;
    float mnr[3] = { dir[1] * maj[2] - dir[2] * maj[1], dir[2] * maj[0] - dir[0] * maj[2], dir[0] * maj[1] - dir[1] * maj[0] };
    // variances along both in-plane axes, from the eigenvalues eig3 left on a's diagonal
    float va = 0, vb = 0;
    for (int e = 0; e < 3; e++) {
        float pa = maj[0] * v[0][e] + maj[1] * v[1][e] + maj[2] * v[2][e];
        float pb = mnr[0] * v[0][e] + mnr[1] * v[1][e] + mnr[2] * v[2][e];
        va += pa * pa * a[e][e];
        vb += pb * pb * a[e][e];
    }
    float ea = __builtin_sqrtf(2 * (va > 0 ? va : 0)), eb = __builtin_sqrtf(2 * (vb > 0 ? vb : 0));
    float cen[3] = { pp[0] + mq[0] + mh * dir[0], pp[1] + mq[1] + mh * dir[1], pp[2] + mq[2] + mh * dir[2] };
    float cw[3], mw[3], nw[3], ext[3] = { ea * tm[8], eb * tm[8], ec * tm[8] };
    comp_to_world(tm, cen, cw);
    quat_rot(tm, maj, mw);
    quat_rot(tm, dir, nw);
    o = put(o, " "); o = put(o, tag); o = put_v(o, "c=", cw, 1);
    o = put(o, " "); o = put(o, tag); o = put_v(o, "x=", mw, 1000);
    o = put(o, " "); o = put(o, tag); o = put_v(o, "z=", nw, 1000);
    o = put(o, " "); o = put(o, tag); o = put_v(o, "e=", ext, 1);
    // the outline, from the same points the fit kept
    static unsigned char use[HULL_IN];
    int nu = n < HULL_IN ? n : HULL_IN;
    for (int i = 0; i < nu; i++) {
        float d[3] = { pts[i * 3] - pp[0], pts[i * 3 + 1] - pp[1], pts[i * 3 + 2] - pp[2] };
        float h = d[0] * dir[0] + d[1] * dir[1] + d[2] * dir[2];
        float q[3] = { d[0] - h * dir[0], d[1] - h * dir[1], d[2] - h * dir[2] };
        use[i] = q[0] * q[0] + q[1] * q[1] + q[2] * q[2] <= keep * keep;
    }
    return put_hull(o, tag, pts, nu, use, maj, mnr, tm);
}

// The flesh cap belongs on the limb itself, not on what is strapped to it: a cut also crosses straps, pads, plates,
// cape and loose sleeves, which come out of the cut as their own material once the seam collapses. Rim points are
// grouped by mesh section; a section whose points go round the cut axis (CORE_BINS of the ANGLE_BINS directions)
// is a layer of the limb, anything else hangs off it. The cap covers the innermost layer and the ones sitting
// tight on it (skin, a body suit), the rest is left out. With no layer at all (a cut through accessories only)
// every point counts, as before. Kept points move to the front of pts / sec; returns their count and writes
// "<tag>sec=section/points/directions/median radius;..." and "<tag>core=sections" to o.
#define ANGLE_BINS 16
#define CORE_BINS 11
#define MAX_RIM_SECTIONS 256
static int popcount16(int b) { int n = 0; for (int i = 0; i < ANGLE_BINS; i++) n += b >> i & 1; return n; }
static int core_count[MAX_RIM_SECTIONS], core_bins[MAX_RIM_SECTIONS];
static float core_med[MAX_RIM_SECTIONS];
static unsigned char core_keep[MAX_RIM_SECTIONS];
// the classification alone: core_keep[s] for every section with points, 0 if a section number is out of range
// (then nothing is filtered)
static int core_classify(const float *pts, const u16 *sec, int m, const float *pp, const float *dir)
{
    int *count = core_count, *bins = core_bins;
    float *med = core_med;
    unsigned char *keep = core_keep;
    float ax[3] = { fabsf_(dir[0]) < 0.9f ? 1.0f : 0.0f, fabsf_(dir[0]) < 0.9f ? 0.0f : 1.0f, 0 };
    float t = ax[0] * dir[0] + ax[1] * dir[1];
    for (int k = 0; k < 3; k++) ax[k] -= t * dir[k];
    float l = rsqrt(ax[0] * ax[0] + ax[1] * ax[1] + ax[2] * ax[2]);
    for (int k = 0; k < 3; k++) ax[k] *= l;
    float ay[3] = { dir[1] * ax[2] - dir[2] * ax[1], dir[2] * ax[0] - dir[0] * ax[2], dir[0] * ax[1] - dir[1] * ax[0] };
    for (int s = 0; s < MAX_RIM_SECTIONS; s++) { count[s] = bins[s] = 0; med[s] = 0; keep[s] = 0; }
    for (int i = 0; i < m; i++) {
        int s = sec[i];
        if (s >= MAX_RIM_SECTIONS) return -1; // more sections than this tracks: no filtering
        float d[3] = { pts[i * 3] - pp[0], pts[i * 3 + 1] - pp[1], pts[i * 3 + 2] - pp[2] };
        float u = d[0] * ax[0] + d[1] * ax[1] + d[2] * ax[2], v = d[0] * ay[0] + d[1] * ay[1] + d[2] * ay[2];
        // direction without atan: a pseudo-angle in [0, 4) that grows with the real one (bins up to ~1.4x apart)
        float p = u / (fabsf_(u) + fabsf_(v) + 1e-9f), pa = v >= 0 ? 1 - p : 3 + p;
        int bin = (int)(pa * (ANGLE_BINS / 4.0f));
        bins[s] |= 1 << (bin < 0 ? 0 : bin >= ANGLE_BINS ? ANGLE_BINS - 1 : bin);
        count[s]++;
    }
    // median distance from the axis per section, by bisection
    for (int s = 0; s < MAX_RIM_SECTIONS; s++) {
        if (!count[s]) continue;
        float lo = 0, hi = 1e4f;
        for (int it = 0; it < 40; it++) {
            float mid = (lo + hi) * 0.5f;
            int below = 0;
            for (int i = 0; i < m; i++) {
                if (sec[i] != s) continue;
                float d[3] = { pts[i * 3] - pp[0], pts[i * 3 + 1] - pp[1], pts[i * 3 + 2] - pp[2] };
                float h = d[0] * dir[0] + d[1] * dir[1] + d[2] * dir[2];
                float q[3] = { d[0] - h * dir[0], d[1] - h * dir[1], d[2] - h * dir[2] };
                if (q[0] * q[0] + q[1] * q[1] + q[2] * q[2] <= mid * mid) below++;
            }
            if (below * 2 >= count[s]) hi = mid; else lo = mid;
        }
        med[s] = hi;
    }
    float inner = 1e30f;
    for (int s = 0; s < MAX_RIM_SECTIONS; s++)
        if (count[s] >= 3 && popcount16(bins[s]) >= CORE_BINS && med[s] < inner) inner = med[s];
    int any = inner < 1e30f;
    for (int s = 0; s < MAX_RIM_SECTIONS; s++)
        if (count[s]) keep[s] = !any || (count[s] >= 3 && popcount16(bins[s]) >= CORE_BINS && med[s] <= inner * 1.35f + 1.0f);
    return any;
}

static char *core_rim(char *o, const char *tag, float *pts, u16 *sec, int *n, const float *pp, const float *dir)
{
    int *count = core_count, *bins = core_bins;
    float *med = core_med;
    unsigned char *keep = core_keep;
    int m = *n;
    if (m < 3) return o;
    if (core_classify(pts, sec, m, pp, dir) < 0) return o;
    o = put(o, " "); o = put(o, tag); o = put(o, "sec=");
    for (int s = 0, listed = 0; s < MAX_RIM_SECTIONS; s++) {
        if (!count[s]) continue;
        if (listed++ >= 32) continue; // the log line only
        if (listed > 1) *o++ = ';';
        o = put_int(o, s); *o++ = '/'; o = put_int(o, count[s]); *o++ = '/'; o = put_int(o, popcount16(bins[s]));
        *o++ = '/'; o = put_f(o, med[s]);
    }
    o = put(o, " "); o = put(o, tag); o = put(o, "core=");
    for (int s = 0, listed = 0; s < MAX_RIM_SECTIONS; s++) {
        if (!count[s] || !keep[s] || listed++ >= 32) continue;
        if (listed > 1) *o++ = ',';
        o = put_int(o, s);
    }
    int k = 0;
    for (int i = 0; i < m; i++) {
        if (!keep[sec[i]]) continue;
        for (int c = 0; c < 3; c++) pts[k * 3 + c] = pts[i * 3 + c];
        sec[k] = sec[i];
        k++;
    }
    *n = k;
    return o;
}

// What decides the limb side:
//   CUT   weighted to B's subtree and in front of the plane (a limb, the torso)
//   WHOLE every vertex: the component goes along whole (Eve's face on a beheading: its neck is weighted to the
//         neck, which stays). No seam; the limb opening is the band of vertices closest to the plane, at most
//         radius from the axis (0 = any).
//   PLANE in front of the plane and within radius of the axis through the plane point, whatever the weights (the
//         neck under the face, weighted to neck / spine / clavicles, none of which leaves with the head)
//   HOLE  no limb: the skin within radius of where a ray (plane point, normal pointing out of the body towards
//         the blow) first meets the mesh collapses onto a sink inside the body, a crater (blunt wound)
//   SIDE  half of a split: what is behind the plane goes, flattened onto it (see "split" below)
//   DENT  no limb, no seam: found like HOLE, the skin within radius of the ray (measured across it) is pressed in up
//         to depth, fully at the ray and fading out to the radius. A sink inside the body flattens onto a plane depth
//         under the surface, and each vertex takes it with a weight from that falloff, so the dent is smooth and the
//         skin stays closed: a wide shallow one for a blunt blow, a narrow deep one for a stab. A HOLE collapsed its
//         ball into a point under a lid, which read as a jagged pit.
// A limb-side vertex in a section that can't follow the limb (no limb bone in its BoneMap), and every limb-side
// vertex of a section with seam vertices on that side but no limb sink, "vanishes": it joins the body side's
// seam and collapses with it, which beats a triangle stretched from the flying limb to the body.
// Only the body is cut. What hangs off it (straps, plates, pads, a cape, a loose sleeve: a section that doesn't go
// round the cut, see core_rim) has no seam: a piece of it crossing the cut (an island of connected triangles) goes
// along whole with the side holding nearly all of its weight, or, tied to both, vanishes whole into a sink. A seam
// through it collapsed onto whatever bone its section had, often far off or swinging, and stretched across the body.
// A hole likewise only goes through the skin and what sits tight on it.
#define MODE_CUT 0
#define MODE_WHOLE 1
#define MODE_PLANE 2
#define MODE_HOLE 3
#define MODE_SIDE 4   // keep what is in front of the plane, the rest vanishes: one half of a vertical split
#define MODE_DENT 5   // a blunt blow or a stab: the skin around where a ray meets it pressed in, smoothly
#define SPLIT_BANDS 4 // a split's opening is fitted in this many bands along its length (head, neck, chest, belly)

// A split's halves are two components on one mesh asset, so they share the collapsed sinks. Sections that have
// nothing to collapse onto (Eve's face: eyes, teeth, brows only know the head bone) borrow a bone no vertex of the
// asset uses: it is added to the section's BoneMap (in place, within the 16 bytes the engine's allocator gives
// even a 1-entry array) and, through the component's MasterBoneMap, made to follow the master's head.
#define MAX_BONEMAP_FIX 64
#define MAX_REMAPS 16
static struct { u64 arr; int num, max; } bmfix[MAX_BONEMAP_FIX];
static int nbmfix;
static struct { u64 comp; int index, old, to, applied; } remaps[MAX_REMAPS]; // applied on "k", with the sinks
static int nremaps;
#define WHOLE_BAND 2.5f // cm above the lowest point near the axis that make up a WHOLE cut's opening
#define ISLAND_MINOR_PCT 15   // a hanging piece goes along whole if its other side holds at most this much weight
#define ISLAND_MAX_VERTS 4000 // bigger pieces (a whole jacket) are cut like the body instead of vanishing
#define ISLAND_MAX_CM 40.0f   // ... and so are pieces reaching further than this from the cut
#define HOLE_LAYER_CM 0.8f    // a layer within this much of the innermost along a hole's ray is the body's (a suit)
// The split: Lua gives the limbs on each side (gone with the other half / staying). What goes is pushed onto the cut
// plane, not into a point: the torso just behind the plane flattens onto it through sinks that project (one per band
// along the opening, so no sink is rigid from the neck to the hips), what lies deeper collapses to a point on the plane
// in its band, the other half's limbs to a point on the plane where they joined. The split works for any plane: a
// slice across the waist or the chest is the same cut as one down the spine. One point sink per section had pulled the whole other half, legs and all, into one spot, and
// every triangle on the midline stretched from the hips or the neck to it.
#define SIDE_TOL 1.0f   // cm: a bone this close to the plane counts as on it
#define SHEET_IN 0.3f   // cm the flattened skin sits inside the kept side, behind the caps
#define SHEET_FAR 5.0f  // cm: what lies further behind the plane collapses to a point in its band instead of
                        // flattening (a slice across the waist would flatten the shoulders out past the opening)

typedef struct {
    const cut_ctx *c;
    const unsigned char *limb, *stable, *haschild;
    const int *usage;
    int b, parent_b, mode;
    float joint[3], pp[3], n[3];
    const unsigned char *nosink;              // or 0
    const unsigned char *gone, *keep;         // MODE_SIDE: limb bones
    unsigned char *btype;                     // MODE_SIDE: 0 free, 1 flattens, 2 + r a point for gone root r,
                                              // 10 + k a point in band k
} sink_args;

static int uf_find(int *par, int v)
{
    while (par[v] != v) { par[v] = par[par[v]]; v = par[v]; }
    return v;
}
static void uf_join(int *par, int a, int b)
{
    a = uf_find(par, a); b = uf_find(par, b);
    if (a != b) par[a < b ? b : a] = a < b ? a : b;
}

// the flattening matrix of a sink: the inverse bind matrix base, then onto the plane (point pp, normal n, component
// space) in the frame of t, the transform the sink rides on as posed now (row vectors, like FMatrix)
static void proj_matrix(const float *base, const float *t, const float *pp, const float *n, float *out)
{
    float iq[4] = { -t[0], -t[1], -t[2], t[3] }, nl[3];
    quat_rot(iq, n, nl);
    float sc = t[8] != 0 ? t[8] : 1;
    float d = ((t[4] - pp[0]) * n[0] + (t[5] - pp[1]) * n[1] + (t[6] - pp[2]) * n[2]) / sc;
    float P[16];
    for (int r = 0; r < 3; r++) {
        for (int k = 0; k < 3; k++) P[r * 4 + k] = (r == k ? 1.0f : 0.0f) - nl[r] * nl[k];
        P[r * 4 + 3] = 0;
    }
    for (int k = 0; k < 3; k++) P[12 + k] = -d * nl[k];
    P[15] = 1;
    for (int r = 0; r < 4; r++)
        for (int k = 0; k < 4; k++) {
            float acc = 0;
            for (int j = 0; j < 4; j++) acc += base[r * 4 + j] * P[j * 4 + k];
            out[r * 4 + k] = acc;
        }
}

// a split half's sink in section s near target, of type want (see btype): a helper of
// the kept side (no limb, nothing past the plane, not another cut's sink) that costs little to give up, preferring
// one this cut already uses the same way
static int side_sink(const sink_args *a, int s, const float *target, int want)
{
    const cut_ctx *c = a->c;
    int nb = c->nb, best = -2;
    float bd = 1e30f;
    for (int i = 1; i < nb; i++) {
        if (!c->inmap[(u64)s * nb + i] || (a->nosink && a->nosink[i]) || a->limb[i] || a->gone[i] || a->keep[i]) continue;
        if (i == a->b || i == a->parent_b) continue;
        if (a->btype[i] ? a->btype[i] != want : is_sink(c, i)) continue;
        const float *t = pose_of(c, i);
        if (!t) continue;
        float d0 = t[4] - target[0], d1 = t[5] - target[1], d2 = t[6] - target[2];
        float score = (d0 * d0 + d1 * d1 + d2 * d2) * (a->stable[i] ? 1.0f : 16.0f) * (a->haschild[i] ? 4.0f : 1.0f)
            * (1.0f + a->usage[i] / 200.0f) * (a->btype[i] ? 0.5f : 1.0f);
        if (score < bd) { bd = score; best = i; }
    }
    if (best >= 0) a->btype[best] = (unsigned char)want;
    return best;
}

// a sink for section s, side sd: a bone of that side in the section's BoneMap close to the joint that costs little
// to give up: stable, a leaf, few vertices of its own (a helper, not a main deformer like the pelvis). An earlier
// cut's sink is free. Never B or its parent (they carry the limb and the stump), never the root. PLANE / HOLE want
// it on its own side of the plane / inside the body (every mode), or the collapsed skin would poke out through the cap.
static int find_sink(const sink_args *a, int s, int sd)
{
    const cut_ctx *c = a->c;
    int nb = c->nb, best = -2;
    float bd = 1e30f;
    for (int i = 1; i < nb; i++) {
        if (!c->inmap[(u64)s * nb + i] || a->limb[i] != sd || i == a->b || i == a->parent_b) continue;
        if (a->nosink && a->nosink[i]) continue;
        // a dent needs a sink of its own (its plane); nothing reuses a flattening one
        if (a->mode == MODE_DENT ? is_sink(c, i) : is_proj_sink(c, i)) continue;
        const float *t = pose_of(c, i);
        if (!t) continue;
        float d0 = t[4] - a->joint[0], d1 = t[5] - a->joint[1], d2 = t[6] - a->joint[2], d = d0 * d0 + d1 * d1 + d2 * d2;
        // squared distance, so a factor 4 is twice as far
        float score = is_sink(c, i) ? d * 0.5f
            : d * (a->stable[i] ? 1.0f : 16.0f) * (a->haschild[i] ? 4.0f : 1.0f) * (1.0f + a->usage[i] / 200.0f);
        // a sink on the wrong side of the plane collapses its seam out past the cut: on the limb, a cone sticking out
        // through the cap (an upper arm's twist bones sit at the shoulder, above a cut 15 % down the bone)
        {
            float h = (t[4] - a->pp[0]) * a->n[0] + (t[5] - a->pp[1]) * a->n[1] + (t[6] - a->pp[2]) * a->n[2];
            int wrong = a->mode == MODE_HOLE || a->mode == MODE_DENT ? h > -0.5f : a->mode == MODE_SIDE ? h < -1.0f : sd ? h < 0 : h > 0;
            if (wrong) score *= 16.0f;
        }
        if (score < bd) { bd = score; best = i; }
    }
    return best;
}

// pw = plane point, nw = plane normal pointing into the limb (HOLE: out of the body), world; radius in cm
// blend a sink into o with weight w (0..1) within its own number of slots: the rest scaled down, the smallest merged
// into the strongest when no slot is free
static void blend_in(skin_info *o, int bone, float w, int slots)
{
    int add = (int)(w * 255 + 0.5f);
    if (add <= 0) return;
    if (add > 255) add = 255;
    if (slots < 1) slots = 1;
    if (slots > MAX_INF) slots = MAX_INF;
    int slot = -1;
    for (int i = 0; i < slots; i++) if (o->weights[i] && o->bones[i] == bone) slot = i;
    for (int i = 0; i < slots && slot < 0; i++) if (!o->weights[i]) slot = i;
    if (slot < 0) {
        int lo = 0, hi = 0;
        for (int i = 1; i < slots; i++) {
            if (o->weights[i] < o->weights[lo]) lo = i;
            if (o->weights[i] > o->weights[hi]) hi = i;
        }
        if (lo == hi) { o->bones[lo] = bone; o->weights[lo] = 255; return; }
        o->weights[hi] = (unsigned char)(o->weights[hi] + o->weights[lo]);
        o->weights[lo] = 0;
        slot = lo;
    }
    int rest = 0;
    for (int i = 0; i < MAX_INF; i++) {
        if (i == slot || !o->weights[i]) continue;
        o->weights[i] = (unsigned char)(o->weights[i] * (255 - add) / 255);
        rest += o->weights[i];
    }
    o->bones[slot] = bone;
    o->weights[slot] = (unsigned char)(255 - rest);
}

// depth: MODE_DENT's, in cm
static void skin_cut(u64 comp, int lod, int b, const float *pw, const float *nw, int mode, float radius, int forced_sink, int remap, float depth)
{
    cut_ctx c = { 0 };
    c.comp = comp;
    c.sm = *(u64 *)(comp + SC_SKELETAL_MESH);
    if (!c.sm) { skin_result("err no mesh"); return; }
    u64 rd = *(u64 *)(comp + SC_MESH_OBJECT) ? *(u64 *)(*(u64 *)(comp + SC_MESH_OBJECT) + 0x40) : *(u64 *)(c.sm + SM_RENDER_DATA);
    if (!rd || lod < 0 || lod >= *(int *)(rd + 8)) { skin_result("err no render data for lod"); return; }
    u64 ld = ((u64 *)*(u64 *)rd)[lod];
    u64 sw = ((get_buffer_fn)(exe + RVA_GET_SKIN_WEIGHT_BUFFER))(comp, lod);
    u64 ib = *(u64 *)(ld + LOD_INDICES);
    c.nv = *(int *)(ld + LOD_NUM_VERTICES);
    unsigned char *pos = *(unsigned char **)(ld + LOD_POSITIONS + 0x28);
    u32 pstride = *(u32 *)(ld + LOD_POSITIONS + 0x30);
    if (!sw || !*(u64 *)(sw + SW_DATA) || !pos || !ib || *(int *)(sw + SW_NUM_VERTICES) != c.nv) {
        skin_result("err no CPU copy of positions / skin weights / indices (cpuaccess LOD?)"); return;
    }
    int ni = ((index_num_fn)(*(u64 *)(*(u64 *)ib + 0x58)))(ib);
    index_get_fn index_get = (index_get_fn)(*(u64 *)(*(u64 *)ib + 0x68));
    c.nb = *(int *)(c.sm + SM_REF_BONE_INFO + 8);
    c.binfo = *(unsigned char **)(c.sm + SM_REF_BONE_INFO);
    c.refinv = *(float **)(c.sm + SM_REF_BASES_INV);
    float *refpose = *(float **)(c.sm + SM_REF_BONE_POSE);
    if (*(int *)(c.sm + SM_REF_BONE_POSE + 8) != c.nb) refpose = 0;
    int nb = c.nb, nv = c.nv;
    if (b <= 0 || b >= nb || !c.refinv || *(int *)(c.sm + SM_REF_BASES_INV + 8) != nb) { skin_result("err bad bone"); return; }
    if (mode < MODE_CUT || mode > MODE_DENT) { skin_result("err bad mode"); return; }
    int holey = mode == MODE_HOLE || mode == MODE_DENT; // a ray to the surface, no limb
    if (forced_sink >= nb || forced_sink < 0) { skin_result("err bad sink"); return; }

    // pose source: the master pose component when there is one (bones mapped through MasterBoneMap)
    u64 master = ((weak_get_fn)(exe + RVA_WEAK_PTR_GET))(comp + SC_MASTER_POSE);
    u64 src = master ? master : comp;
    c.mmap = master ? *(int **)(comp + SC_MASTER_BONE_MAP) : 0;
    c.space = *(float **)(src + SC_SPACE_BASES + (u64)*(int *)(src + SC_SPACE_READ) * 0x10);
    c.nspace = *(int *)(src + SC_SPACE_BASES + (u64)*(int *)(src + SC_SPACE_READ) * 0x10 + 8);
    if (!c.space) { skin_result("err no bone transforms"); return; }
    const float *tm = (float *)(src + SC_TO_WORLD);
    u64 secs = *(u64 *)(ld + LOD_SECTIONS);
    c.nsec = *(int *)(ld + LOD_SECTIONS + 8);
    if (c.nsec <= 0 || c.nsec > 0xfffe) { skin_result("err no sections"); return; }

    float p[3], n[3];
    world_to_comp(tm, pw, p, 0);
    world_to_comp(tm, nw, n, 1);
    float r2 = radius > 0 ? radius * radius / (tm[8] * tm[8]) : 0; // radius in component units, squared

    // one block: per bone flags, per section bone maps / sinks / limb bones, per vertex weights / section / side /
    // seam / rim / posed position
    u64 nbsec = (u64)c.nsec * nb;
    u64 bytes = 5 * (u64)nb + nbsec + 16 + 4 * (u64)nb + 8 * (u64)c.nsec + 2 * (u64)nv + 3 * (u64)nv + (u64)c.nsec;
    bytes = (bytes + 15) & ~15ull;
    u64 at_out = bytes;
    bytes += (u64)nv * sizeof(skin_info) + (u64)nv * 3 * sizeof(float) + (u64)nv * sizeof(u16) + 4;
    bytes = (bytes + 15) & ~15ull;
    u64 at_xs = bytes;
    bytes += (u64)nv * 3 * sizeof(float);
    unsigned char *mem = VirtualAlloc(0, bytes, 0x3000 /*COMMIT|RESERVE*/, 0x04 /*READWRITE*/);
    if (!mem) { skin_result("err out of memory"); return; }
    // a second block for islands (hanging pieces), layers (holes) and the split: per vertex island parent, counts,
    // weights, reach, sink, kind; per bone the split's limb flags, sink types and roots; per section layer flags and
    // the split's band and limb sinks
    u64 bytes2 = (u64)nv * (6 * 4 + 5) + (u64)nb * (3 + 4) + (u64)c.nsec * (1 + 4 * (2 * SPLIT_BANDS + MAX_LIMB_ROOTS)) + 64;
    unsigned char *mem2 = VirtualAlloc(0, bytes2, 0x3000, 0x04);
    if (!mem2) { VirtualFree(mem, 0, 0x8000); skin_result("err out of memory"); return; }
    int *upar = (int *)mem2, *icnt = upar + nv, *iwl = icnt + nv, *iwb = iwl + nv, *vsink = iwb + nv;
    float *iext = (float *)(vsink + nv);
    int *rootof = (int *)(iext + nv), *secband = rootof + nb, *secfar = secband + (u64)c.nsec * SPLIT_BANDS;
    int *secroot = secfar + (u64)c.nsec * SPLIT_BANDS;
    unsigned char *iflag = (unsigned char *)(secroot + (u64)c.nsec * MAX_LIMB_ROOTS), *vkind = iflag + nv, *vroot = vkind + nv;
    unsigned char *vcn = vroot + nv, *idec = vcn + nv, *gonebone = idec + nv, *keepbone = gonebone + nb, *btype = keepbone + nb, *secore = btype + nb;
    const unsigned char *ns = nosink_mesh == c.sm && nb <= MAX_BONES ? nosink : 0;
    unsigned char *limb = mem, *haschild = limb + nb, *drop_l = haschild + nb, *drop_b = drop_l + nb, *stable = drop_b + nb;
    unsigned char *inmap = stable + nb;
    int *usage = (int *)(((u64)(inmap + nbsec) + 3) & ~3ull);     // vertices weighted to each bone
    int *secsink = usage + nb;                                      // [section * 2 + side]: -1 unsearched, -2 none
    u16 *vsec = (u16 *)(secsink + 2 * c.nsec);
    unsigned char *side = (unsigned char *)(vsec + nv), *seam = side + nv, *rim = seam + nv, *seclimb = rim + nv;
    skin_info *out = (skin_info *)(mem + at_out);
    float *rimpos = (float *)(out + nv);
    u16 *rimsec = (u16 *)(rimpos + (u64)nv * 3); // section of each rim point
    float *xs = (float *)(mem + at_xs);          // every vertex, posed with its original weights
    c.inmap = inmap; c.vsec = vsec;

    for (int i = 0; i < nb; i++) {
        int par = parent_of(&c, i);
        limb[i] = !holey && mode != MODE_SIDE && (i == b || (par >= 0 && par < i && limb[par]));
        if (par >= 0 && par < nb) haschild[par] = 1;
    }
    int parent_b = parent_of(&c, b);
    for (int s = 0; s < c.nsec; s++) {
        u64 sec = secs + (u64)s * 0xe8;
        unsigned short *bmap = *(unsigned short **)(sec + SEC_BONE_MAP);
        int nbmap = *(int *)(sec + SEC_BONE_MAP + 8);
        for (int k = 0; k < nbmap; k++) if (bmap[k] < nb) { inmap[(u64)s * nb + bmap[k]] = 1; if (limb[bmap[k]]) seclimb[s] = 1; }
        secsink[s * 2] = secsink[s * 2 + 1] = -1;
    }
    for (int v = 0; v < nv; v++) vsec[v] = 0xffff;

    // a bone is a stable sink candidate if its offset from the parent is still the bind pose's: helper bones
    // that animation slides around (measured 35 cm off) would drag the collapsed seam with them
    for (int i = 1; i < nb; i++) {
        int par = parent_of(&c, i);
        const float *t = pose_of(&c, i), *pt = par >= 0 ? pose_of(&c, par) : 0;
        if (!t || !pt) continue;
        if (!refpose) { stable[i] = 1; continue; }
        float d[3] = { t[4] - pt[4], t[5] - pt[5], t[6] - pt[6] }, iq[4] = { -pt[0], -pt[1], -pt[2], pt[3] }, l[3];
        quat_rot(iq, d, l);
        for (int k = 0; k < 3; k++) l[k] /= pt[8 + k] != 0 ? pt[8 + k] : 1;
        const float *r = refpose + (u64)i * 12 + 4;
        float e[3] = { l[0] - r[0], l[1] - r[1], l[2] - r[2] };
        stable[i] = e[0] * e[0] + e[1] * e[1] + e[2] * e[2] < STABLE_CM * STABLE_CM;
    }

    // a split half: the limbs that go with the other half and the ones that stay (subtrees of Lua's roots), and what
    // kept skin lets go of ("limb" here): those limbs and every helper past the plane (the other half's sinks)
    for (int i = 0; i < nb; i++) { rootof[i] = -1; gonebone[i] = keepbone[i] = btype[i] = 0; }
    if (mode == MODE_SIDE) {
        int lim = limbs_comp == comp;
        for (int i = 0; i < nb; i++) {
            int par = parent_of(&c, i);
            if (lim) for (int r = 0; r < ngone; r++) if (gone_roots[r] == i) rootof[i] = r;
            if (rootof[i] < 0 && par >= 0 && par < i) rootof[i] = rootof[par];
            gonebone[i] = rootof[i] >= 0;
            if (lim) for (int r = 0; r < nkeep; r++) if (keep_roots[r] == i) keepbone[i] = 1;
            if (!keepbone[i] && par >= 0 && par < i) keepbone[i] = keepbone[par];
            const float *t = pose_of(&c, i);
            float h = t ? (t[4] - p[0]) * n[0] + (t[5] - p[1]) * n[1] + (t[6] - p[2]) * n[2] : 0;
            limb[i] = gonebone[i] || (i > 0 && !(ns && ns[i]) && !keepbone[i] && h < -SIDE_TOL / tm[8]);
        }
    }

    // pass 1: original weights (mesh bone indices), skinned position, side
    unsigned char *data = *(unsigned char **)(sw + SW_DATA);
    u32 *lookup = *(u32 **)(sw + SW_LOOKUP);
    int variable = *(unsigned char *)(sw + SW_VARIABLE) && lookup;
    u32 maxinf = *(u32 *)(sw + SW_MAX_INFLUENCES);
    int wide = *(unsigned char *)(sw + SW_16BIT_INDEX) != 0;
    int nlimb = 0, nseam = 0, moved = 0, stuck = 0, unsunk = 0, vanished = 0;
    for (int s = 0; s < c.nsec; s++) {
        u64 sec = secs + (u64)s * 0xe8;
        int base = *(int *)(sec + SEC_BASE_VERTEX), cnt = *(int *)(sec + SEC_NUM_VERTICES);
        unsigned short *bmap = *(unsigned short **)(sec + SEC_BONE_MAP);
        int nbmap = *(int *)(sec + SEC_BONE_MAP + 8);
        for (int v = base; v < base + cnt && v < nv; v++) {
            skin_info *o = &out[v];
            vsec[v] = (u16)s;
            u32 off, cn;
            if (variable) { off = lookup[v] >> 8; cn = lookup[v] & 0xff; }
            else { off = (wide ? 3 : 2) * maxinf * (u32)v; cn = maxinf; }
            if (cn > MAX_INF) cn = MAX_INF;
            vcn[v] = (unsigned char)cn;
            float sub = 0, *x = xs + (u64)v * 3;
            for (u32 i = 0; i < cn; i++) {
                u32 li = wide ? ((unsigned short *)(data + off))[i] : data[off + i];
                unsigned char w = data[off + (wide ? 2 : 1) * cn + i];
                int mb = li < (u32)nbmap ? bmap[li] : 0;
                o->bones[i] = mb;
                o->weights[i] = w;
                if (w && mb < nb) { usage[mb]++; if (limb[mb]) sub += w; }
            }
            skin_point(&c, o, (const float *)(pos + (u64)v * pstride), x);
            float d[3] = { x[0] - p[0], x[1] - p[1], x[2] - p[2] }, h = d[0] * n[0] + d[1] * n[1] + d[2] * n[2];
            float q2 = d[0] * d[0] + d[1] * d[1] + d[2] * d[2] - h * h; // squared distance from the axis
            if (mode == MODE_CUT) side[v] = sub > 0 && h > 0;
            else if (mode == MODE_WHOLE) side[v] = 1;
            else if (mode == MODE_PLANE) side[v] = h > 0 && (sub > 0 || (r2 > 0 && q2 < r2));
            else side[v] = 0;
            if (mode == MODE_SIDE) {
                // the other half's limbs go wherever they are, ours stay wherever they are, the torso by the plane
                int wg = 0, wk = 0, top = -1, topw = 0;
                for (u32 i = 0; i < cn; i++) {
                    int mb = o->bones[i];
                    unsigned char w = o->weights[i];
                    if (!w || mb >= nb) continue;
                    if (gonebone[mb]) { wg += w; if (w > topw) { topw = w; top = rootof[mb]; } }
                    if (keepbone[mb]) wk += w;
                }
                vkind[v] = wg > 127 ? 2 : wk > 127 ? 0 : h <= -SHEET_FAR / tm[8] ? 3 : h <= 0 ? 1 : 0;
                vroot[v] = (unsigned char)(top < 0 ? 0 : top);
                if (vkind[v]) { seam[v] = 1; vanished++; }
            }
            if (side[v] && !seclimb[s]) { side[v] = 0; seam[v] = 1; vanished++; }
        }
    }

    // a hole: where the ray first meets the skin (the vertex furthest out along it, close to it), then a ball there
    // Only the body's layers: of the sections in the ball, the innermost along the ray (by median depth) and those
    // within HOLE_LAYER_CM of it; a plate or pad over the skin stays whole. If the ray came out through one of those,
    // the hole moves in to where it meets the skin.
    float hc[3] = { p[0], p[1], p[2] };
    int layers_dropped = 0;
    if (holey) {
        for (int s = 0; s < c.nsec; s++) secore[s] = 1;
        for (int round = 0; round < 2; round++) {
            float best = -1e30f;
            for (float lane = 3.0f; lane <= 12.0f && best < -1e29f; lane *= 2) {
                float l2 = lane * lane / (tm[8] * tm[8]);
                for (int v = 0; v < nv; v++) {
                    if (vsec[v] == 0xffff || !secore[vsec[v]]) continue;
                    const float *x = xs + (u64)v * 3;
                    float d[3] = { x[0] - p[0], x[1] - p[1], x[2] - p[2] }, h = d[0] * n[0] + d[1] * n[1] + d[2] * n[2];
                    if (d[0] * d[0] + d[1] * d[1] + d[2] * d[2] - h * h < l2 && h > best) { best = h; hc[0] = x[0]; hc[1] = x[1]; hc[2] = x[2]; }
                }
            }
            if (best < -1e29f) { VirtualFree(mem, 0, 0x8000); VirtualFree(mem2, 0, 0x8000); skin_result("err the ray misses the mesh"); return; }
            for (int v = 0; v < nv; v++) {
                seam[v] = 0;
                if (vsec[v] == 0xffff || !secore[vsec[v]]) continue;
                const float *x = xs + (u64)v * 3;
                float d[3] = { x[0] - hc[0], x[1] - hc[1], x[2] - hc[2] };
                if (d[0] * d[0] + d[1] * d[1] + d[2] * d[2] < r2) seam[v] = 1;
            }
            if (round) break;
            // median depth along the ray per section in the ball, by bisection
            static float lmed[MAX_RIM_SECTIONS];
            static int lcnt[MAX_RIM_SECTIONS];
            int too_many = 0;
            for (int k = 0; k < MAX_RIM_SECTIONS; k++) { lcnt[k] = 0; lmed[k] = 0; }
            for (int v = 0; v < nv; v++) if (seam[v]) { if (vsec[v] >= MAX_RIM_SECTIONS) too_many = 1; else lcnt[vsec[v]]++; }
            if (too_many) break;
            float inner = 1e30f;
            for (int k = 0; k < MAX_RIM_SECTIONS; k++) {
                if (!lcnt[k]) continue;
                float lo = -1e4f, hi = 1e4f;
                for (int it = 0; it < 48; it++) {
                    float mid = (lo + hi) * 0.5f;
                    int below = 0;
                    for (int v = 0; v < nv; v++) {
                        if (!seam[v] || vsec[v] != k) continue;
                        const float *x = xs + (u64)v * 3;
                        if ((x[0] - p[0]) * n[0] + (x[1] - p[1]) * n[1] + (x[2] - p[2]) * n[2] <= mid) below++;
                    }
                    if (below * 2 >= lcnt[k]) hi = mid; else lo = mid;
                }
                lmed[k] = hi;
                if (hi < inner) inner = hi;
            }
            if (inner >= 1e30f) break;
            for (int k = 0; k < MAX_RIM_SECTIONS && k < c.nsec; k++)
                if (lcnt[k] && lmed[k] > inner + HOLE_LAYER_CM / tm[8]) { secore[k] = 0; layers_dropped++; }
            if (!layers_dropped) break;
        }
    }

    // pass 2: triangles across the cut
    // a dent: the region across the ray within radius and above the dent's floor, each with its share (in iext)
    float dent_pp[3] = { hc[0] - n[0] * depth / tm[8], hc[1] - n[1] * depth / tm[8], hc[2] - n[2] * depth / tm[8] };
    if (mode == MODE_DENT) {
        float rr = r2 > 0 ? r2 : 1;
        for (int v = 0; v < nv; v++) {
            seam[v] = 0;
            iext[v] = 0;
            if (vsec[v] == 0xffff || !secore[vsec[v]]) continue;
            const float *x = xs + (u64)v * 3;
            float d[3] = { x[0] - hc[0], x[1] - hc[1], x[2] - hc[2] }, h = d[0] * n[0] + d[1] * n[1] + d[2] * n[2];
            float q2 = d[0] * d[0] + d[1] * d[1] + d[2] * d[2] - h * h;
            if (q2 >= rr || h <= -depth / tm[8]) continue;
            float f = 1 - q2 / rr;
            iext[v] = f * f;
            seam[v] = 1;
        }
    }

    if (!holey && mode != MODE_SIDE)
        for (int i = 0; i + 2 < ni; i += 3) {
            u32 a = index_get(ib, i), e = index_get(ib, i + 1), f = index_get(ib, i + 2);
            if (a >= (u32)nv || e >= (u32)nv || f >= (u32)nv) continue;
            if (side[a] != side[e] || side[a] != side[f]) seam[a] = seam[e] = seam[f] = 1;
        }

    // sinks, per section and side, near the joint (PLANE: the plane point, HOLE: where the ray met the skin)
    sink_args sa = { &c, limb, stable, haschild, usage, b, parent_b, mode, { p[0], p[1], p[2] }, { p[0], p[1], p[2] }, { n[0], n[1], n[2] },
                     ns, gonebone, keepbone, btype };
    if (mode == MODE_CUT) { const float *t = pose_of(&c, b); if (t) { sa.joint[0] = t[4]; sa.joint[1] = t[5]; sa.joint[2] = t[6]; } }
    if (holey) for (int k = 0; k < 3; k++) sa.joint[k] = sa.pp[k] = hc[k];

    // hanging pieces (see "Only the body is cut" above): which sections go round the cut, from the seam as it is now
    int islands_moved = 0, islands_gone = 0;
    if (mode == MODE_CUT || mode == MODE_PLANE) {
        int m = 0;
        for (int v = 0; v < nv; v++) {
            if (!seam[v] || vsec[v] == 0xffff) continue;
            for (int k = 0; k < 3; k++) rimpos[(u64)m * 3 + k] = xs[(u64)v * 3 + k];
            rimsec[m++] = vsec[v];
        }
        if (m >= 3 && core_classify(rimpos, rimsec, m, p, n) > 0) {
            int any_off = 0;
            for (int s = 0; s < c.nsec; s++) {
                secore[s] = s >= MAX_RIM_SECTIONS || !core_count[s] || core_keep[s];
                if (!secore[s]) any_off = 1;
            }
            if (any_off) {
                for (int v = 0; v < nv; v++) { upar[v] = v; icnt[v] = iwl[v] = iwb[v] = 0; iext[v] = 0; iflag[v] = idec[v] = 0; }
                for (int i = 0; i + 2 < ni; i += 3) {
                    u32 a = index_get(ib, i), e = index_get(ib, i + 1), f = index_get(ib, i + 2);
                    if (a >= (u32)nv || e >= (u32)nv || f >= (u32)nv) continue;
                    uf_join(upar, (int)a, (int)e);
                    uf_join(upar, (int)a, (int)f);
                }
                // per island (its root): vertices, weight on each side, seam / sides seen, reach from the cut
                for (int v = 0; v < nv; v++) {
                    int s = vsec[v];
                    if (s == 0xffff || secore[s]) continue;
                    int r = uf_find(upar, v);
                    icnt[r]++;
                    for (int i = 0; i < MAX_INF; i++) {
                        int mb = out[v].bones[i];
                        unsigned char w = out[v].weights[i];
                        if (!w || mb < 0 || mb >= nb) continue;
                        if (limb[mb]) iwl[r] += w; else iwb[r] += w;
                    }
                    iflag[r] |= (unsigned char)((seam[v] ? 1 : 0) | (side[v] ? 2 : 4));
                    const float *x = xs + (u64)v * 3;
                    float d2 = (x[0] - p[0]) * (x[0] - p[0]) + (x[1] - p[1]) * (x[1] - p[1]) + (x[2] - p[2]) * (x[2] - p[2]);
                    if (d2 > iext[r]) iext[r] = d2;
                }
                // 1 body side whole, 2 limb side whole, 3 vanishes, 0 cut like the body (too big to vanish)
                float reach = ISLAND_MAX_CM / tm[8];
                for (int r = 0; r < nv; r++) {
                    if (!icnt[r] || !((iflag[r] & 1) || (iflag[r] & 6) == 6)) continue;
                    int tot = iwl[r] + iwb[r], mn = iwl[r] < iwb[r] ? iwl[r] : iwb[r];
                    if ((long long)mn * 100 <= (long long)tot * ISLAND_MINOR_PCT) idec[r] = iwl[r] > iwb[r] ? 2 : 1;
                    else if (icnt[r] <= ISLAND_MAX_VERTS && iext[r] <= reach * reach) idec[r] = 3;
                }
                // a vanishing piece needs a body side sink in its section (any distance: collapsed whole it can't
                // stretch); without one it goes along whole with its majority after all
                for (int v = 0; v < nv; v++) {
                    int s = vsec[v];
                    if (s == 0xffff || secore[s]) continue;
                    int r = uf_find(upar, v);
                    if (idec[r] != 3) continue;
                    if (secsink[s * 2] == -1) secsink[s * 2] = find_sink(&sa, s, 0);
                    if (secsink[s * 2] < 0) idec[r] = iwl[r] > iwb[r] ? 2 : 1;
                }
                for (int r = 0; r < nv; r++) {
                    if (idec[r] == 1 || idec[r] == 2) islands_moved++;
                    else if (idec[r] == 3) islands_gone++;
                }
                for (int v = 0; v < nv; v++) {
                    int s = vsec[v];
                    if (s == 0xffff || secore[s]) continue;
                    int d = idec[uf_find(upar, v)];
                    if (d == 1 || d == 2) { side[v] = (unsigned char)(d == 2); seam[v] = 0; }
                    else if (d == 3) { side[v] = 0; seam[v] = 1; }
                }
            }
        }
    }
    // a forced sink (a split's borrowed bone) for every section with seam vertices, added to its BoneMap if needed
    int borrowed = 0;
    if (forced_sink > 0) {
        for (int v = 0; v < nv; v++) {
            if (!seam[v] || vsec[v] == 0xffff) continue;
            int s = vsec[v];
            if (secsink[s * 2] != -1) continue;
            if (!inmap[(u64)s * nb + forced_sink]) {
                u64 sec = secs + (u64)s * 0xe8;
                u64 arr = sec + SEC_BONE_MAP;
                int num = *(int *)(arr + 8), max = *(int *)(arr + 12);
                unsigned short *bm = *(unsigned short **)arr;
                // the engine's smallest allocation is 16 bytes: room for 8 entries whatever Max says
                if (!bm || num >= 8 || nbmfix >= MAX_BONEMAP_FIX) continue; // left to find_sink
                bmfix[nbmfix].arr = arr; bmfix[nbmfix].num = num; bmfix[nbmfix].max = max; nbmfix++;
                bm[num] = (unsigned short)forced_sink;
                __atomic_thread_fence(__ATOMIC_SEQ_CST);
                *(int *)(arr + 8) = num + 1;
                if (max < num + 1) *(int *)(arr + 12) = num + 1;
                inmap[(u64)s * nb + forced_sink] = 1;
                borrowed++;
            }
            secsink[s * 2] = forced_sink;
        }
        // the borrowed bone is to follow the master's bone "remap" (the head) instead of its own, from "k" on: until
        // then the seam on it stays where it was, rigid on the bone's own transform
        int *map = *(int **)(comp + SC_MASTER_BONE_MAP);
        if (map && remap >= 0 && forced_sink < *(int *)(comp + SC_MASTER_BONE_MAP + 8) && nremaps < MAX_REMAPS) {
            int dup = 0;
            for (int i = 0; i < nremaps; i++) if (remaps[i].comp == comp && remaps[i].index == forced_sink) dup = 1;
            if (!dup) {
                remaps[nremaps].comp = comp; remaps[nremaps].index = forced_sink; remaps[nremaps].to = remap;
                remaps[nremaps].old = map[forced_sink]; remaps[nremaps].applied = 0; nremaps++;
            }
        }
    }
    if (mode != MODE_SIDE)
        for (int v = 0; v < nv; v++) {
            if (!seam[v] || vsec[v] == 0xffff) continue;
            int s = vsec[v], sd = side[v];
            if (secsink[s * 2 + sd] == -1) secsink[s * 2 + sd] = find_sink(&sa, s, sd);
        }
    // a split half's sinks: the torso just behind the plane flattens by bands along the opening (its longest in-plane
    // axis), deeper torso collapses to a point per band, the other half's limbs to a point per root; sections with a
    // borrowed bone (the face) flatten onto that alone
    int nproj = 0, npoint = 0;
    float pin[3] = { p[0] + n[0] * SHEET_IN / tm[8], p[1] + n[1] * SHEET_IN / tm[8], p[2] + n[2] * SHEET_IN / tm[8] };
    float bandc[SPLIT_BANDS][3];
    if (mode == MODE_SIDE) {
        float mc[3] = { 0, 0, 0 }, cov[3][3] = { { 0 } }, ev[3][3], ax[3] = { 0, 0, 0 }, lo_t = 1e30f, hi_t = -1e30f;
        int m = 0;
        for (int v = 0; v < nv; v++) if (vkind[v] == 1) { for (int k = 0; k < 3; k++) mc[k] += xs[(u64)v * 3 + k]; m++; }
        if (!m) for (int v = 0; v < nv; v++) if (vkind[v] == 3) { for (int k = 0; k < 3; k++) mc[k] += xs[(u64)v * 3 + k]; m++; }
        if (m) {
            int kind = 1;
            for (int v = 0; v < nv && kind == 1; v++) if (vkind[v] == 1) kind = 0;
            kind = kind ? 3 : 1; // the near band when there is one
            for (int k = 0; k < 3; k++) mc[k] /= (float)m;
            for (int v = 0; v < nv; v++) {
                if (vkind[v] != kind) continue;
                const float *x = xs + (u64)v * 3;
                float e[3] = { x[0] - mc[0], x[1] - mc[1], x[2] - mc[2] }, h = e[0] * n[0] + e[1] * n[1] + e[2] * n[2];
                for (int k = 0; k < 3; k++) e[k] -= h * n[k];
                for (int r = 0; r < 3; r++) for (int k = 0; k < 3; k++) cov[r][k] += e[r] * e[k];
            }
            eig3(cov, ev);
            int hi = 0;
            for (int k = 1; k < 3; k++) if (cov[k][k] > cov[hi][hi]) hi = k;
            for (int k = 0; k < 3; k++) ax[k] = ev[k][hi];
            for (int v = 0; v < nv; v++) {
                if (vkind[v] != kind) continue;
                const float *x = xs + (u64)v * 3;
                float t = (x[0] - mc[0]) * ax[0] + (x[1] - mc[1]) * ax[1] + (x[2] - mc[2]) * ax[2];
                if (t < lo_t) lo_t = t;
                if (t > hi_t) hi_t = t;
            }
        }
        if (lo_t > hi_t) lo_t = hi_t = 0;
        float span = hi_t > lo_t ? hi_t - lo_t : 1;
        // each band's middle, on the plane
        for (int k = 0; k < SPLIT_BANDS; k++) {
            float tc = lo_t + span * (k + 0.5f) / SPLIT_BANDS;
            for (int j = 0; j < 3; j++) bandc[k][j] = mc[j] + ax[j] * tc;
            float h = (bandc[k][0] - p[0]) * n[0] + (bandc[k][1] - p[1]) * n[1] + (bandc[k][2] - p[2]) * n[2];
            for (int j = 0; j < 3; j++) bandc[k][j] -= h * n[j];
        }
        for (u64 i = 0; i < (u64)c.nsec * SPLIT_BANDS; i++) secband[i] = secfar[i] = -1;
        for (u64 i = 0; i < (u64)c.nsec * MAX_LIMB_ROOTS; i++) secroot[i] = -1;
        // flattening first (the opening matters most), then the limbs' points, then the deep torso's
        static const unsigned char order[3] = { 1, 2, 3 };
        for (int pass = 0; pass < 3; pass++)
            for (int v = 0; v < nv; v++) {
                int s = vsec[v];
                if (vkind[v] != order[pass] || s == 0xffff || (forced_sink > 0 && secsink[s * 2] == forced_sink)) continue;
                const float *x = xs + (u64)v * 3;
                if (vkind[v] != 2) {
                    float t = (x[0] - mc[0]) * ax[0] + (x[1] - mc[1]) * ax[1] + (x[2] - mc[2]) * ax[2];
                    int k = (int)((t - lo_t) / span * SPLIT_BANDS);
                    k = k < 0 ? 0 : k >= SPLIT_BANDS ? SPLIT_BANDS - 1 : k;
                    int *slot = &(vkind[v] == 1 ? secband : secfar)[(u64)s * SPLIT_BANDS + k];
                    if (*slot == -1) *slot = side_sink(&sa, s, bandc[k], vkind[v] == 1 ? 1 : 10 + k);
                } else {
                    int r = vroot[v] < MAX_LIMB_ROOTS ? vroot[v] : 0;
                    int *slot = &secroot[(u64)s * MAX_LIMB_ROOTS + r];
                    if (*slot != -1) continue;
                    // where the limb joined, on the plane
                    const float *t = pose_of(&c, gone_roots[r]);
                    float target[3] = { t ? t[4] : x[0], t ? t[5] : x[1], t ? t[6] : x[2] };
                    float h = (target[0] - p[0]) * n[0] + (target[1] - p[1]) * n[1] + (target[2] - p[2]) * n[2];
                    for (int j = 0; j < 3; j++) target[j] -= h * n[j];
                    *slot = side_sink(&sa, s, target, 2 + r);
                }
            }
        // each vanishing vertex's sink: its own, else the nearest band of its section that flattens (a limb or deep
        // torso with no point of its own flattens rather than stays), else none (it stays: unsunk)
        for (int v = 0; v < nv; v++) {
            vsink[v] = -1;
            int s = vsec[v];
            if (!vkind[v] || s == 0xffff) continue;
            if (forced_sink > 0 && secsink[s * 2] == forced_sink) { vsink[v] = forced_sink; continue; }
            const float *x = xs + (u64)v * 3;
            float t = (x[0] - mc[0]) * ax[0] + (x[1] - mc[1]) * ax[1] + (x[2] - mc[2]) * ax[2];
            int k0 = (int)((t - lo_t) / span * SPLIT_BANDS);
            k0 = k0 < 0 ? 0 : k0 >= SPLIT_BANDS ? SPLIT_BANDS - 1 : k0;
            if (vkind[v] == 2) {
                int r = vroot[v] < MAX_LIMB_ROOTS ? vroot[v] : 0, k = secroot[(u64)s * MAX_LIMB_ROOTS + r];
                if (k >= 0) { vsink[v] = k; continue; }
            }
            if (vkind[v] == 3 && secfar[(u64)s * SPLIT_BANDS + k0] >= 0) { vsink[v] = secfar[(u64)s * SPLIT_BANDS + k0]; continue; }
            for (int dk = 0; dk < SPLIT_BANDS && vsink[v] < 0; dk++)
                for (int sg = -1; sg <= 1 && vsink[v] < 0; sg += 2) {
                    int k = k0 + sg * dk;
                    if (k >= 0 && k < SPLIT_BANDS && secband[(u64)s * SPLIT_BANDS + k] >= 0) vsink[v] = secband[(u64)s * SPLIT_BANDS + k];
                }
        }
    }
    // a section whose limb side has seam vertices but nothing to collapse them onto: that side vanishes
    for (int s = 0; s < c.nsec; s++) {
        if (secsink[s * 2 + 1] != -2) continue;
        for (int v = 0; v < nv; v++) if (vsec[v] == s && side[v]) { side[v] = 0; seam[v] = 1; vanished++; }
        if (secsink[s * 2] == -1) secsink[s * 2] = find_sink(&sa, s, 0);
    }
    for (int v = 0; v < nv; v++) nlimb += side[v];
    float far = 0;
    for (int i = 0; i < 2 * c.nsec; i++) {
        if (secsink[i] < 0) continue;
        const float *t = pose_of(&c, secsink[i]);
        float d0 = t[4] - sa.joint[0], d1 = t[5] - sa.joint[1], d2 = t[6] - sa.joint[2], d = __builtin_sqrtf(d0 * d0 + d1 * d1 + d2 * d2);
        if (d > far) far = d;
    }
    // every sink gives up its weights everywhere, on both sides
    for (int i = 0; i < nb; i++) { drop_l[i] = !limb[i]; drop_b[i] = limb[i]; }
    for (int i = 0; i < 2 * c.nsec; i++) if (secsink[i] >= 0) drop_l[secsink[i]] = drop_b[secsink[i]] = 1;
    for (int i = 0; i < nsinks; i++) if (sinks[i].mesh == c.sm) drop_l[sinks[i].bone] = drop_b[sinks[i].bone] = 1;
    for (int i = 0; i < nb; i++) if (btype[i]) drop_l[i] = drop_b[i] = 1;

    // pass 3: new weights
    for (int v = 0; v < nv; v++) {
        skin_info *o = &out[v];
        int s = vsec[v];
        if (s == 0xffff) continue;
        if (mode == MODE_DENT) {
            // its weights as they were (minus any sink), then the dent's sink blended in
            int r = keep_only(o, drop_b, nb, fallback_bone(&c, s, b, drop_b));
            if (r > 0) moved++;
            else if (r < 0) stuck++;
            if (seam[v]) {
                if (secsink[s * 2] >= 0) { blend_in(o, secsink[s * 2], iext[v], vcn[v]); nseam++; }
                else unsunk++;
            }
            continue;
        }
        if (seam[v]) {
            int sink = mode == MODE_SIDE ? vsink[v] : secsink[s * 2 + side[v]];
            if (sink >= 0) {
                for (int i = 0; i < MAX_INF; i++) { o->bones[i] = 0; o->weights[i] = 0; }
                o->bones[0] = sink;
                o->weights[0] = 255;
                nseam++;
                continue;
            }
            unsunk++;
        }
        // an earlier cut's seam vertex: already all on its sink
        if (o->weights[0] == 255 && is_sink(&c, o->bones[0])) continue;
        const unsigned char *drop = side[v] ? drop_l : drop_b;
        int r = keep_only(o, drop, nb, fallback_bone(&c, s, side[v] || holey || mode == MODE_SIDE ? b : parent_b, drop));
        if (r > 0) moved++;
        else if (r < 0) stuck++;
    }

    // rims: the vertices next to the seam on each side, posed with their new weights; the caps go there. A WHOLE
    // cut has no seam: its opening is the band closest to the plane (the bottom of the neck)
    if (mode == MODE_WHOLE) {
        float lo = 1e30f;
        for (int v = 0; v < nv; v++) {
            if (vsec[v] == 0xffff) continue;
            const float *x = xs + (u64)v * 3;
            float d[3] = { x[0] - p[0], x[1] - p[1], x[2] - p[2] }, h = d[0] * n[0] + d[1] * n[1] + d[2] * n[2];
            if (r2 > 0 && d[0] * d[0] + d[1] * d[1] + d[2] * d[2] - h * h >= r2) continue;
            if (h < lo) lo = h;
        }
        float band = lo + WHOLE_BAND / tm[8];
        for (int v = 0; v < nv; v++) {
            if (vsec[v] == 0xffff) continue;
            const float *x = xs + (u64)v * 3;
            float d[3] = { x[0] - p[0], x[1] - p[1], x[2] - p[2] }, h = d[0] * n[0] + d[1] * n[1] + d[2] * n[2];
            if (r2 > 0 && d[0] * d[0] + d[1] * d[1] + d[2] * d[2] - h * h >= r2) continue;
            if (h < band) rim[v] = 1;
        }
        // the plane moves to the band, so the opening sits where the skin ends
        for (int k = 0; k < 3; k++) p[k] += n[k] * lo;
    } else {
        for (int i = 0; i + 2 < ni; i += 3) {
            u32 t[3] = { index_get(ib, i), index_get(ib, i + 1), index_get(ib, i + 2) };
            if (t[0] >= (u32)nv || t[1] >= (u32)nv || t[2] >= (u32)nv) continue;
            if (!seam[t[0]] && !seam[t[1]] && !seam[t[2]]) continue;
            for (int k = 0; k < 3; k++) if (!seam[t[k]]) rim[t[k]] = 1;
        }
    }
    int nrim[2] = { 0, 0 };
    for (int pass = 0; pass < 2; pass++) {
        int k = 0;
        for (int v = 0; v < nv; v++) {
            if (!rim[v] || side[v] != pass) continue;
            skin_point(&c, &out[v], (const float *)(pos + (u64)v * pstride), rimpos + (u64)(pass ? nrim[0] : 0) * 3 + (u64)k * 3);
            rimsec[(pass ? nrim[0] : 0) + k] = vsec[v];
            k++;
        }
        nrim[pass] = k;
    }
    // the bone a hole's cap rides on: the one carrying most of its rim
    int wound_bone = -1;
    if (holey) {
        for (int i = 0; i < nb; i++) usage[i] = 0;
        for (int v = 0; v < nv; v++) {
            if (!(mode == MODE_DENT ? seam[v] : rim[v])) continue;
            for (int i = 0; i < MAX_INF; i++)
                if (out[v].weights[i] && out[v].bones[i] < nb && !drop_b[out[v].bones[i]]) usage[out[v].bones[i]] += out[v].weights[i];
        }
        int top = 0;
        for (int i = 0; i < nb; i++) if (usage[i] > top) { top = usage[i]; wound_bone = i; }
    }

    tarray arr = { out, nv, nv };
    ((set_override_fn)(exe + RVA_SET_SKIN_WEIGHT_OVERRIDE))(comp, lod, &arr);

    // the new sinks, kept for skin_restore; "k" collapses them (zero scale at their own origin)
    int nnew = 0, full = 0, moved_sinks = 0;
    for (int i = 0; i < 2 * c.nsec; i++) {
        int bone = secsink[i];
        if (bone < 0 || is_sink(&c, bone)) continue;
        if (nsinks >= MAX_SINKS) { full = 1; continue; }
        float *m = c.refinv + (u64)bone * 16;
        sinks[nsinks].mesh = c.sm; sinks[nsinks].bone = bone; sinks[nsinks].down = 0; sinks[nsinks].proj = 0;
        for (int k = 0; k < 16; k++) sinks[nsinks].m[k] = m[k];
        if (mode == MODE_DENT) {
            // the dent's floor, in the sink's frame as posed now
            const float *t = pose_of(&c, bone);
            if (!t) continue;
            proj_matrix(m, t, dent_pp, n, sinks[nsinks].pm);
            sinks[nsinks].proj = 1;
            nsinks++; nnew++;
            continue;
        }
        if (mode == MODE_SIDE) {
            // a borrowed bone (the face) flattens in the frame it will follow from "k" on (the master's head),
            // starting from B's inverse bind matrix (the face rides the head rigidly)
            const float *t = remap >= 0 && remap < c.nspace ? c.space + (u64)remap * 12 : pose_of(&c, bone);
            if (!t) continue;
            proj_matrix(remap >= 0 ? c.refinv + (u64)b * 16 : m, t, pin, n, sinks[nsinks].pm);
            sinks[nsinks].proj = 1;
            nsinks++; nnew++; nproj++;
            continue;
        }
        // where its seam collapses to, in the bone's frame: its origin, unless that is outside its own side of the
        // plane (an upper arm's twist bones sit at the shoulder, above a cut 15 % down the arm, and the arm's seam
        // stuck out through its cap as a cone). Then the origin moved along the normal to SINK_IN inside
        sinks[nsinks].at[0] = sinks[nsinks].at[1] = sinks[nsinks].at[2] = 0;
        const float *t = pose_of(&c, bone);
        if (t && mode != MODE_HOLE && mode != MODE_WHOLE) {
            int sd = i & 1;
            float h = (t[4] - p[0]) * n[0] + (t[5] - p[1]) * n[1] + (t[6] - p[2]) * n[2], want = h;
            if (sd && h < SINK_IN) want = SINK_IN;
            else if (!sd && h > -SINK_IN) want = -SINK_IN;
            if (want != h) {
                float d[3] = { (want - h) * n[0], (want - h) * n[1], (want - h) * n[2] }, iq[4] = { -t[0], -t[1], -t[2], t[3] }, l[3];
                quat_rot(iq, d, l);
                for (int k = 0; k < 3; k++) sinks[nsinks].at[k] = t[8 + k] != 0 ? l[k] / t[8 + k] : 0;
                moved_sinks++;
            }
        }
        nsinks++; nnew++;
    }
    // a split half's own sinks: flattening ones, and points where the other half's limbs joined
    for (int i = 0; i < nb && mode == MODE_SIDE; i++) {
        if (!btype[i] || is_sink(&c, i)) continue;
        if (nsinks >= MAX_SINKS) { full = 1; continue; }
        const float *t = pose_of(&c, i);
        if (!t) continue;
        float *m = c.refinv + (u64)i * 16;
        sinks[nsinks].mesh = c.sm; sinks[nsinks].bone = i; sinks[nsinks].down = 0;
        for (int k = 0; k < 16; k++) sinks[nsinks].m[k] = m[k];
        if (btype[i] == 1) {
            proj_matrix(m, t, pin, n, sinks[nsinks].pm);
            sinks[nsinks].proj = 1;
            nproj++;
        } else {
            sinks[nsinks].proj = 0;
            const float *rt = btype[i] < 10 ? pose_of(&c, gone_roots[btype[i] - 2]) : 0;
            float target[3] = { rt ? rt[4] : t[4], rt ? rt[5] : t[5], rt ? rt[6] : t[6] };
            if (btype[i] >= 10) for (int k = 0; k < 3; k++) target[k] = bandc[btype[i] - 10][k];
            float h = (target[0] - pin[0]) * n[0] + (target[1] - pin[1]) * n[1] + (target[2] - pin[2]) * n[2];
            float d[3] = { target[0] - h * n[0] - t[4], target[1] - h * n[1] - t[5], target[2] - h * n[2] - t[6] };
            float iq[4] = { -t[0], -t[1], -t[2], t[3] }, l[3];
            quat_rot(iq, d, l);
            for (int k = 0; k < 3; k++) sinks[nsinks].at[k] = t[8 + k] != 0 ? l[k] / t[8 + k] : 0;
            npoint++;
        }
        nsinks++; nnew++;
    }

    char *msg = VirtualAlloc(0, 16384, 0x3000, 0x04);
    if (!msg) { VirtualFree(mem, 0, 0x8000); VirtualFree(mem2, 0, 0x8000); skin_result("err out of memory"); return; }
    char *o = msg;
    o = put(o, "ok verts="); o = put_int(o, nv);
    o = put(o, " mode="); o = put_int(o, mode);
    o = put(o, " limb="); o = put_int(o, nlimb);
    o = put(o, " seam="); o = put_int(o, nseam);
    o = put(o, " vanished="); o = put_int(o, vanished);
    o = put(o, " unsunk="); o = put_int(o, unsunk);
    o = put(o, " reweighted="); o = put_int(o, moved);
    o = put(o, " stuck="); o = put_int(o, stuck);
    o = put(o, " far="); o = put_f(o, far * tm[8]);
    o = put(o, full ? " sinks(full)=" : " sinks=");
    int first = 1;
    for (int i = 0; i < nsinks; i++) {
        if (sinks[i].mesh != c.sm) continue;
        if (!first) *o++ = ',';
        o = put_int(o, sinks[i].bone);
        first = 0;
        if (o - msg > 3000) break;
    }
    o = put(o, " new="); o = put_int(o, nnew);
    o = put(o, " sinkmoved="); o = put_int(o, moved_sinks);
    if (forced_sink > 0) { o = put(o, " borrowed="); o = put_int(o, borrowed); }
    if (mode == MODE_SIDE) { o = put(o, " proj="); o = put_int(o, nproj); o = put(o, " point="); o = put_int(o, npoint); }
    if (mode == MODE_CUT || mode == MODE_PLANE) {
        o = put(o, " pieces="); o = put_int(o, islands_moved); *o++ = '/'; o = put_int(o, islands_gone);
    }
    if (holey) { o = put(o, " layersoff="); o = put_int(o, layers_dropped); }
    if (holey) {
        float hw[3];
        comp_to_world(tm, hc, hw);
        o = put_v(o, " hit=", hw, 1);
        o = put(o, " wb="); o = put_int(o, wound_bone);
    }
    if (mode == MODE_DENT) {
        // no opening, nothing to fit
        o = put(o, " dented="); o = put_int(o, nseam);
        *o = 0;
        VirtualFree(mem, 0, 0x8000);
        VirtualFree(mem2, 0, 0x8000);
        skin_result(msg);
        VirtualFree(msg, 0, 0x8000);
        return;
    }
    if (mode == MODE_SIDE) {
        // one long opening down the midline, not convex (head, neck, shoulders, belly): fitted in bands along its
        // longest in-plane axis, each facing the vanished side
        o = put(o, " srim="); o = put_int(o, nrim[0]);
        float out_dir[3] = { -n[0], -n[1], -n[2] }, mc[3] = { 0, 0, 0 };
        int m = nrim[0];
        for (int i = 0; i < m; i++) for (int k = 0; k < 3; k++) mc[k] += rimpos[i * 3 + k] / (float)(m ? m : 1);
        float a[3][3] = { { 0 } }, ev[3][3];
        for (int i = 0; i < m; i++) {
            float e[3] = { rimpos[i * 3] - mc[0], rimpos[i * 3 + 1] - mc[1], rimpos[i * 3 + 2] - mc[2] };
            float h = e[0] * n[0] + e[1] * n[1] + e[2] * n[2];
            for (int k = 0; k < 3; k++) e[k] -= h * n[k];
            for (int r = 0; r < 3; r++) for (int k = 0; k < 3; k++) a[r][k] += e[r] * e[k];
        }
        eig3(a, ev);
        int hi = 0;
        for (int k = 1; k < 3; k++) if (a[k][k] > a[hi][hi]) hi = k;
        float ax[3] = { ev[0][hi], ev[1][hi], ev[2][hi] }, lo_t = 1e30f, hi_t = -1e30f;
        for (int i = 0; i < m; i++) {
            float t = (rimpos[i * 3] - mc[0]) * ax[0] + (rimpos[i * 3 + 1] - mc[1]) * ax[1] + (rimpos[i * 3 + 2] - mc[2]) * ax[2];
            if (t < lo_t) lo_t = t;
            if (t > hi_t) hi_t = t;
        }
        float *band = xs; // free by now: the posed positions were only needed to decide the sides
        for (int k = 0; k < SPLIT_BANDS && m >= 3; k++) {
            float t0 = lo_t + (hi_t - lo_t) * k / SPLIT_BANDS, t1 = lo_t + (hi_t - lo_t) * (k + 1) / SPLIT_BANDS;
            int bn = 0;
            float bc[3] = { 0, 0, 0 };
            for (int i = 0; i < m; i++) {
                const float *q = rimpos + (u64)i * 3;
                float t = (q[0] - mc[0]) * ax[0] + (q[1] - mc[1]) * ax[1] + (q[2] - mc[2]) * ax[2];
                if (t < t0 || t > t1) continue;
                for (int j = 0; j < 3; j++) { band[bn * 3 + j] = q[j]; bc[j] += q[j]; }
                bn++;
            }
            if (bn < 3) continue;
            for (int j = 0; j < 3; j++) bc[j] /= (float)bn;
            // the plane through the band's centre, so the fit measures its spread in the cut plane
            float h = (bc[0] - p[0]) * n[0] + (bc[1] - p[1]) * n[1] + (bc[2] - p[2]) * n[2];
            for (int j = 0; j < 3; j++) bc[j] -= h * n[j];
            char tag[3] = { 's', (char)('0' + k), 0 };
            o = put_fit(o, tag, band, bn, bc, out_dir, tm);
            if (o - msg > 7000) break;
        }
        *o = 0;
        VirtualFree(mem, 0, 0x8000);
        VirtualFree(mem2, 0, 0x8000);
        skin_result(msg);
        VirtualFree(msg, 0, 0x8000);
        return;
    }
    // a cut's body opening faces the limb and the limb's the body; a hole's faces out of the body
    float *pp = mode == MODE_HOLE ? hc : p;
    float nb_dir[3] = { n[0], n[1], n[2] }, nl_dir[3] = { -n[0], -n[1], -n[2] };
    // the limb side's points go after the body side's, so filter the limb side first (it only moves inside its range)
    int nb_core = nrim[0], nl_core = nrim[1];
    char lsec[1024], *lo = core_rim(lsec, "l", rimpos + (u64)nrim[0] * 3, rimsec + nrim[0], &nl_core, pp, nl_dir);
    *lo = 0;
    o = core_rim(o, "b", rimpos, rimsec, &nb_core, pp, nb_dir);
    o = put(o, lsec);
    o = put_fit(o, "b", rimpos, nb_core, pp, nb_dir, tm);   // body opening
    o = put_fit(o, "l", rimpos + (u64)nrim[0] * 3, nl_core, pp, nl_dir, tm); // limb opening
    *o = 0;
    VirtualFree(mem, 0, 0x8000 /*RELEASE*/);
    VirtualFree(mem2, 0, 0x8000);
    skin_result(msg);
    VirtualFree(msg, 0, 0x8000);
}

// put back every collapsed inverse bind matrix (of one mesh, or all with mesh 0)
static int skin_restore(u64 mesh)
{
    int put_back = 0, k = 0;
    for (int i = 0; i < nsinks; i++) {
        u64 sm = sinks[i].mesh;
        if (mesh && sm != mesh) { sinks[k++] = sinks[i]; continue; }
        float *ri = *(float **)(sm + SM_REF_BASES_INV);
        int num = *(int *)(sm + SM_REF_BASES_INV + 8);
        if (ri && sinks[i].bone < num) {
            float *m = ri + (u64)sinks[i].bone * 16;
            for (int j = 0; j < 16; j++) m[j] = sinks[i].m[j];
            put_back++;
        }
    }
    nsinks = k;
    // the borrowed BoneMap entries go with the sinks of a mesh (all of them on "r")
    if (!mesh) {
        for (int i = nbmfix - 1; i >= 0; i--) { *(int *)(bmfix[i].arr + 8) = bmfix[i].num; *(int *)(bmfix[i].arr + 12) = bmfix[i].max; }
        nbmfix = 0;
    }
    return put_back;
}

// give a component's borrowed MasterBoneMap entries back (only on "x": a destroyed clone takes its map with it)
static void unremap(u64 comp)
{
    int k = 0;
    for (int i = 0; i < nremaps; i++) {
        if (remaps[i].comp != comp) { remaps[k++] = remaps[i]; continue; }
        int *map = *(int **)(comp + SC_MASTER_BONE_MAP);
        if (remaps[i].applied && map && remaps[i].index < *(int *)(comp + SC_MASTER_BONE_MAP + 8)) map[remaps[i].index] = remaps[i].old;
    }
    nremaps = k;
}

// copy one component's pose (both component-space buffers) onto another on the same skeleton: a split's clone
// gets its bodies made in the pose the original is in
static void copy_pose(u64 src, u64 dst)
{
    char msg[64] = "ok copied ";
    for (int buf = 0; buf < 2; buf++) {
        u64 sa = src + SC_SPACE_BASES + (u64)buf * 0x10, da = dst + SC_SPACE_BASES + (u64)buf * 0x10;
        float *sp = *(float **)sa, *dp = *(float **)da;
        int sn = *(int *)(sa + 8), dn = *(int *)(da + 8);
        if (!sp || !dp || sn != dn || sn <= 0) { skin_result("err pose buffers differ"); return; }
        for (int i = 0; i < sn * 12; i++) dp[i] = sp[i];
        if (!buf) *put_int(msg + 10, sn) = 0;
    }
    skin_result(msg);
}

// collapse every sink recorded but not yet collapsed
static int skin_collapse(void)
{
    int n = 0;
    for (int i = 0; i < nsinks; i++) {
        if (sinks[i].down) continue;
        float *ri = *(float **)(sinks[i].mesh + SM_REF_BASES_INV);
        int num = *(int *)(sinks[i].mesh + SM_REF_BASES_INV + 8);
        if (!ri || sinks[i].bone >= num) continue;
        float *m = ri + (u64)sinks[i].bone * 16;
        if (sinks[i].proj) {
            for (int k = 0; k < 16; k++) m[k] = sinks[i].pm[k];
        } else {
            for (int k = 0; k < 16; k++) m[k] = 0;
            m[12] = sinks[i].at[0]; m[13] = sinks[i].at[1]; m[14] = sinks[i].at[2];
            m[15] = 1;
        }
        sinks[i].down = 1;
        n++;
    }
    for (int i = 0; i < nremaps; i++) {
        if (remaps[i].applied) continue;
        int *map = *(int **)(remaps[i].comp + SC_MASTER_BONE_MAP);
        if (!map || remaps[i].index >= *(int *)(remaps[i].comp + SC_MASTER_BONE_MAP + 8)) continue;
        map[remaps[i].index] = remaps[i].to;
        remaps[i].applied = 1;
    }
    return n;
}

static void skin_clear(u64 comp, int lod)
{
    char msg[64] = "ok cleared, restored ", *o = msg + 21;
    u64 sm = *(u64 *)(comp + SC_SKELETAL_MESH);
    if (lod >= 0 && lod < *(int *)(comp + SC_LOD_INFO + 8) && *(u64 *)(*(u64 *)(comp + SC_LOD_INFO) + (u64)lod * 0x48 + 0x18))
        ((lodinfo_fn)(exe + RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS))(*(u64 *)(comp + SC_LOD_INFO) + (u64)lod * 0x48);
    o = put_int(o, sm ? skin_restore(sm) : 0);
    *o = 0;
    unremap(comp);
    ((comp_fn)(exe + RVA_MARK_RENDER_STATE_DIRTY))(comp);
    skin_result(msg);
}

// "c<comp>,<lod>,<bone>[,<mode>,<radius>]" / "x<comp>,<lod>" / "r", fields in hex
static int parse_fields(const u16 *txt, int len, u64 *f, int max)
{
    int k = 0;
    u64 v = 0;
    for (int i = 0; i < len && txt[i]; i++) {
        int d = hexval(txt[i]);
        if (d >= 0) { v = v << 4 | (u64)d; continue; }
        if (txt[i] == ',' && k < max) { f[k++] = v; v = 0; continue; }
        break;
    }
    if (k < max) f[k++] = v;
    return k;
}

// UE4.27 FFrame: Locals at +0x28 (checked against the thunk). Params of the cheat function, by UHT offsets:
//   FName RewardGroupAlias @0, float LocX/Y/Z @8/0xc/0x10, FString formationPath @0x18, float DirX/Y/Z @0x28..
// formationPath is the command:
//   u<comp>              unpin a scene component (see unpin), answer in sbslice.unpin
//   c<comp>,<lod>,<bone>[,<mode>[,<radius mm>[,<depth mm>]]]
//                        skin cut (mode: MODE_CUT default, WHOLE, PLANE, HOLE, SIDE, DENT; depth only for DENT),
//                        plane point LocX/Y/Z, normal
//                        DirX/Y/Z; answer in sbslice.cut
//   c...,<sink>,<remap>  MODE_SIDE with a borrowed sink bone that follows the master's bone <remap>
//   p<src>,<dst>         copy src's pose onto dst (same skeleton): a split's clone
//   k                    collapse the sinks the last cuts recorded (call once their weights are in use)
//   x<comp>,<lod>        undo the cut on that component
//   r                    put back every collapsed sink (a mesh asset outlives the component)
//   n<comp>,<bone>,...   bones of comp's mesh asset that may never be a sink (until the next "n")
//   g<comp>,<gone root>,...,0,<kept root>,...
//                        a split half's limbs for the next MODE_SIDE cut on comp (0 = Root, never a limb root)
static void exec_slice(void *context, unsigned char *stack, void *result)
{
    (void)context; (void)result;
    unsigned char *p = *(unsigned char **)(stack + 0x28);
    float *loc = (float *)(p + 8);
    u16 *txt = *(u16 **)(p + 0x18);
    int len = *(int *)(p + 0x20);
    float *dir = (float *)(p + 0x28);
    if (!txt || len < 2) return;
    if (txt[0] == 'u') {
        u64 component = parse_hex(txt + 1, len - 1);
        if (component >= 0x10000) unpin(component);
        return;
    }
    if (txt[0] == 'k') {
        char msg[32] = "ok collapsed ";
        *put_int(msg + 13, skin_collapse()) = 0;
        skin_result(msg);
        return;
    }
    if (txt[0] == 'r') {
        char msg[32] = "ok restored ";
        *put_int(msg + 12, skin_restore(0)) = 0;
        skin_result(msg);
        return;
    }
    if (txt[0] == 'n' || txt[0] == 'g') {
        static u64 lf[MAX_BONES + 2];
        int k = parse_fields(txt + 1, len - 1, lf, MAX_BONES + 2);
        if (k < 1 || lf[0] < 0x10000) { skin_result("err bad component"); return; }
        int cnt = 0;
        if (txt[0] == 'n') {
            for (int i = 0; i < MAX_BONES; i++) nosink[i] = 0;
            nosink_mesh = *(u64 *)(lf[0] + SC_SKELETAL_MESH);
            for (int i = 1; i < k; i++) if (lf[i] < MAX_BONES) { nosink[lf[i]] = 1; cnt++; }
        } else {
            limbs_comp = lf[0]; ngone = nkeep = 0;
            int keep = 0;
            for (int i = 1; i < k; i++) {
                if (lf[i] == 0) { keep = 1; continue; }
                if (keep) { if (nkeep < MAX_LIMB_ROOTS) keep_roots[nkeep++] = (int)lf[i]; }
                else if (ngone < MAX_LIMB_ROOTS) gone_roots[ngone++] = (int)lf[i];
            }
            cnt = ngone * 100 + nkeep;
        }
        char msg[32] = "ok ";
        *put_int(msg + 3, cnt) = 0;
        skin_result(msg);
        return;
    }
    if (txt[0] == 'p') {
        u64 pf[2] = { 0, 0 };
        parse_fields(txt + 1, len - 1, pf, 2);
        if (pf[0] < 0x10000 || pf[1] < 0x10000) { skin_result("err bad component"); return; }
        copy_pose(pf[0], pf[1]);
        return;
    }
    if (txt[0] != 'c' && txt[0] != 'x') { skin_result("err unknown command"); return; }
    u64 f[7] = { 0, 0, 0, 0, 0, 0, 0 };
    int k = parse_fields(txt + 1, len - 1, f, 7);
    if (f[0] < 0x10000) { skin_result("err bad component"); return; }
    if (txt[0] == 'x') { skin_clear(f[0], (int)f[1]); return; }
    if (k < 3) { skin_result("err want c<comp>,<lod>,<bone>"); return; }
    float l2 = dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2];
    if (l2 < 1e-8f) { skin_result("err no plane normal"); return; }
    float kk = rsqrt(l2), nrm[3] = { dir[0] * kk, dir[1] * kk, dir[2] * kk };
    // MODE_DENT: the sixth field is the depth in mm, not a sink
    int dent = (int)f[3] == MODE_DENT;
    skin_cut(f[0], (int)f[1], (int)f[2], loc, nrm, (int)f[3], (float)f[4] * 0.1f, dent ? 0 : (int)f[5],
             k > 6 && !dent ? (int)f[6] : -1, dent ? (float)f[5] * 0.1f : 0);
}

static const u16 REQ[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.req";
static const u16 OK[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.ok";
static const u16 ERR[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.err";

static u32 WINAPI worker(void *arg)
{
    (void)arg;
    const u64 thunk = exe + RVA_EXEC_REWARD_DROP_FORMATION_PATH_LOCATION;
    for (;;) {
        Sleep(250);
        HANDLE h = CreateFileW(REQ, 0x80000000 /*GENERIC_READ*/, 1, 0, 3 /*OPEN_EXISTING*/, 0x80, 0);
        if (h == INVALID_HANDLE) continue;
        char buf[64];
        u32 got = 0;
        ReadFile(h, buf, sizeof buf - 1, &got, 0);
        CloseHandle(h);
        DeleteFileW(REQ);
        u64 ufunc = 0;
        for (u32 i = 0; i < got; i++) {
            int v = hexval((unsigned char)buf[i]);
            if (v < 0) break;
            ufunc = ufunc << 4 | (u64)v;
        }
        // UFunction::Func holds the thunk address; find that field instead of trusting a layout offset
        char msg[96] = "no thunk pointer in UFunction ";
        if (ufunc >= 0x10000) {
            u64 *f = (u64 *)ufunc;
            for (int i = 0; i < 0x40; i++) {
                if (f[i] == thunk || f[i] == (u64)exec_slice) {
                    f[i] = (u64)exec_slice;
                    char ok[40] = "patched +0x";
                    hex64(ok + 11, (u64)i * 8);
                    write_file(OK, ok);
                    goto next;
                }
            }
        }
        hex64(msg + 30, ufunc);
        write_file(ERR, msg);
    next:;
    }
    return 0;
}

int WINAPI DllMain(void *inst, u32 reason, void *reserved)
{
    (void)reserved;
    if (reason == 1) {
        void *self;
        DisableThreadLibraryCalls(inst);
        GetModuleHandleExW(0x4 /*FROM_ADDRESS*/ | 0x1 /*PIN*/, (const void *)DllMain, &self);
        exe = (u64)GetModuleHandleW(0);
        CreateThread(0, 0, worker, 0, 0, 0);
    }
    return 1;
}
