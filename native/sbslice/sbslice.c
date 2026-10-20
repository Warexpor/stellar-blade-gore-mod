// sbslice.dll: dismemberment for Eve, through the engine's own skinning (see "skin cut" below).
//
// Nothing in Lua can reach the skin weights, so this DLL repoints one debug cheat that gameplay never calls,
// USBCheatManager::SBRewardGroupDropFormationPathLocation, to its own handler (exec_slice). The cheat's
// FString parameter carries the command, its LocX/Y/Z and DirX/Y/Z floats a point and a direction.
// Handshake (paths relative to the game's Win64 dir, like the Lua log):
//   Lua writes the UFunction's address (hex) to ue4ss/Mods/EveRagdollProbe/sbslice.req
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

static const u16 UNPIN[] = u"ue4ss\\Mods\\EveRagdollProbe\\sbslice.unpin";

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
#define MAX_SINKS 64

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
static struct { u64 mesh; int bone, down; float m[16]; } sinks[MAX_SINKS];
static int nsinks;

static const u16 CUTRES[] = u"ue4ss\\Mods\\EveRagdollProbe\\sbslice.cut";

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

// pw = plane point, nw = plane normal pointing into the limb (world)
static void skin_cut(u64 comp, int lod, int b, const float *pw, const float *nw)
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

    // one block: per bone flags, per section bone maps, per vertex weights / section / side / seam / rim
    u64 nbsec = (u64)c.nsec * nb;
    u64 bytes = 5 * (u64)nb + nbsec + 16 + 4 * (u64)nb + 8 * (u64)c.nsec + 2 * (u64)nv + 3 * (u64)nv;
    bytes = (bytes + 15) & ~15ull;
    u64 at_out = bytes;
    bytes += (u64)nv * sizeof(skin_info) + (u64)nv * 3 * sizeof(float);
    unsigned char *mem = VirtualAlloc(0, bytes, 0x3000 /*COMMIT|RESERVE*/, 0x04 /*READWRITE*/);
    if (!mem) { skin_result("err out of memory"); return; }
    unsigned char *limb = mem, *haschild = limb + nb, *drop_l = haschild + nb, *drop_b = drop_l + nb, *stable = drop_b + nb;
    unsigned char *inmap = stable + nb;
    int *usage = (int *)(((u64)(inmap + nbsec) + 3) & ~3ull);     // vertices weighted to each bone
    int *secsink = usage + nb;                                      // [section * 2 + side]
    u16 *vsec = (u16 *)(secsink + 2 * c.nsec);
    unsigned char *side = (unsigned char *)(vsec + nv), *seam = side + nv, *rim = seam + nv;
    skin_info *out = (skin_info *)(mem + at_out);
    float *rimpos = (float *)(out + nv);
    c.inmap = inmap; c.vsec = vsec;

    for (int i = 0; i < nb; i++) {
        int par = parent_of(&c, i);
        limb[i] = i == b || (par >= 0 && par < i && limb[par]);
        if (par >= 0 && par < nb) haschild[par] = 1;
    }
    int parent_b = parent_of(&c, b);
    for (int s = 0; s < c.nsec; s++) {
        u64 sec = secs + (u64)s * 0xe8;
        unsigned short *bmap = *(unsigned short **)(sec + SEC_BONE_MAP);
        int nbmap = *(int *)(sec + SEC_BONE_MAP + 8);
        for (int k = 0; k < nbmap; k++) if (bmap[k] < nb) inmap[(u64)s * nb + bmap[k]] = 1;
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

    // pass 1: original weights (mesh bone indices), skinned position, side
    unsigned char *data = *(unsigned char **)(sw + SW_DATA);
    u32 *lookup = *(u32 **)(sw + SW_LOOKUP);
    int variable = *(unsigned char *)(sw + SW_VARIABLE) && lookup;
    u32 maxinf = *(u32 *)(sw + SW_MAX_INFLUENCES);
    int wide = *(unsigned char *)(sw + SW_16BIT_INDEX) != 0;
    int nlimb = 0, nseam = 0, moved = 0, stuck = 0, unsunk = 0;
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
            float sub = 0, x[3];
            for (u32 i = 0; i < cn; i++) {
                u32 li = wide ? ((unsigned short *)(data + off))[i] : data[off + i];
                unsigned char w = data[off + (wide ? 2 : 1) * cn + i];
                int mb = li < (u32)nbmap ? bmap[li] : 0;
                o->bones[i] = mb;
                o->weights[i] = w;
                if (w && mb < nb) { usage[mb]++; if (limb[mb]) sub += w; }
            }
            skin_point(&c, o, (const float *)(pos + (u64)v * pstride), x);
            float d[3] = { x[0] - p[0], x[1] - p[1], x[2] - p[2] };
            side[v] = sub > 0 && d[0] * n[0] + d[1] * n[1] + d[2] * n[2] > 0;
            nlimb += side[v];
        }
    }

    // pass 2: triangles across the cut
    for (int i = 0; i + 2 < ni; i += 3) {
        u32 a = index_get(ib, i), e = index_get(ib, i + 1), f = index_get(ib, i + 2);
        if (a >= (u32)nv || e >= (u32)nv || f >= (u32)nv) continue;
        if (side[a] != side[e] || side[a] != side[f]) seam[a] = seam[e] = seam[f] = 1;
    }

    // sinks, per section and side: a bone of that side in the section's BoneMap close to the joint that costs
    // little to give up: stable, a leaf, few vertices of its own (a helper, not a main deformer like the
    // pelvis). An earlier cut's sink is free. Never B or its parent (they carry the limb and the stump), never
    // the root.
    float joint[3] = { p[0], p[1], p[2] };
    { const float *t = pose_of(&c, b); if (t) { joint[0] = t[4]; joint[1] = t[5]; joint[2] = t[6]; } }
    float far = 0;
    for (int v = 0; v < nv; v++) {
        if (!seam[v] || vsec[v] == 0xffff) continue;
        int s = vsec[v], sd = side[v];
        if (secsink[s * 2 + sd] != -1) continue;
        int best = -2; float bd = 1e30f;
        for (int i = 1; i < nb; i++) {
            if (!inmap[(u64)s * nb + i] || limb[i] != sd || i == b || i == parent_b) continue;
            const float *t = pose_of(&c, i);
            if (!t) continue;
            float d0 = t[4] - joint[0], d1 = t[5] - joint[1], d2 = t[6] - joint[2], d = d0 * d0 + d1 * d1 + d2 * d2;
            // squared distance, so a factor 4 is twice as far
            float score = is_sink(&c, i) ? d * 0.5f
                : d * (stable[i] ? 1.0f : 16.0f) * (haschild[i] ? 4.0f : 1.0f) * (1.0f + usage[i] / 200.0f);
            if (score < bd) { bd = score; best = i; }
        }
        secsink[s * 2 + sd] = best;
        if (best >= 0) { const float *t = pose_of(&c, best); float d0 = t[4] - joint[0], d1 = t[5] - joint[1], d2 = t[6] - joint[2], d = __builtin_sqrtf(d0 * d0 + d1 * d1 + d2 * d2); if (d > far) far = d; }
    }
    // every sink gives up its weights everywhere, on both sides
    for (int i = 0; i < nb; i++) { drop_l[i] = !limb[i]; drop_b[i] = limb[i]; }
    for (int i = 0; i < 2 * c.nsec; i++) if (secsink[i] >= 0) drop_l[secsink[i]] = drop_b[secsink[i]] = 1;
    for (int i = 0; i < nsinks; i++) if (sinks[i].mesh == c.sm) drop_l[sinks[i].bone] = drop_b[sinks[i].bone] = 1;

    // pass 3: new weights
    for (int v = 0; v < nv; v++) {
        skin_info *o = &out[v];
        int s = vsec[v];
        if (s == 0xffff) continue;
        if (seam[v]) {
            int sink = secsink[s * 2 + side[v]];
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
        int r = keep_only(o, drop, nb, fallback_bone(&c, s, side[v] ? b : parent_b, drop));
        if (r > 0) moved++;
        else if (r < 0) stuck++;
    }

    // rims: the vertices next to the seam on each side, posed with their new weights; the caps go there
    for (int i = 0; i + 2 < ni; i += 3) {
        u32 t[3] = { index_get(ib, i), index_get(ib, i + 1), index_get(ib, i + 2) };
        if (t[0] >= (u32)nv || t[1] >= (u32)nv || t[2] >= (u32)nv) continue;
        if (!seam[t[0]] && !seam[t[1]] && !seam[t[2]]) continue;
        for (int k = 0; k < 3; k++) if (!seam[t[k]]) rim[t[k]] = 1;
    }
    int nrim[2] = { 0, 0 };
    for (int pass = 0; pass < 2; pass++) {
        int k = 0;
        for (int v = 0; v < nv; v++) {
            if (!rim[v] || side[v] != pass) continue;
            skin_point(&c, &out[v], (const float *)(pos + (u64)v * pstride), rimpos + (u64)(pass ? nrim[0] : 0) * 3 + (u64)k * 3);
            k++;
        }
        nrim[pass] = k;
    }

    tarray arr = { out, nv, nv };
    ((set_override_fn)(exe + RVA_SET_SKIN_WEIGHT_OVERRIDE))(comp, lod, &arr);

    // the new sinks, kept for skin_restore; "k" collapses them (zero scale at their own origin)
    int nnew = 0, full = 0;
    for (int i = 0; i < 2 * c.nsec; i++) {
        int bone = secsink[i];
        if (bone < 0 || is_sink(&c, bone)) continue;
        if (nsinks >= MAX_SINKS) { full = 1; continue; }
        float *m = c.refinv + (u64)bone * 16;
        sinks[nsinks].mesh = c.sm; sinks[nsinks].bone = bone; sinks[nsinks].down = 0;
        for (int k = 0; k < 16; k++) sinks[nsinks].m[k] = m[k];
        nsinks++; nnew++;
    }

    char *msg = VirtualAlloc(0, 8192, 0x3000, 0x04);
    if (!msg) { VirtualFree(mem, 0, 0x8000); skin_result("err out of memory"); return; }
    char *o = msg;
    o = put(o, "ok verts="); o = put_int(o, nv);
    o = put(o, " limb="); o = put_int(o, nlimb);
    o = put(o, " seam="); o = put_int(o, nseam);
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
    float nb_dir[3] = { n[0], n[1], n[2] }, nl_dir[3] = { -n[0], -n[1], -n[2] };
    o = put_fit(o, "b", rimpos, nrim[0], p, nb_dir, tm);   // body opening, facing the limb
    o = put_fit(o, "l", rimpos + (u64)nrim[0] * 3, nrim[1], p, nl_dir, tm); // limb opening, facing the body
    *o = 0;
    VirtualFree(mem, 0, 0x8000 /*RELEASE*/);
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
    return put_back;
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
        for (int k = 0; k < 16; k++) m[k] = 0;
        m[15] = 1;
        sinks[i].down = 1;
        n++;
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
    ((comp_fn)(exe + RVA_MARK_RENDER_STATE_DIRTY))(comp);
    skin_result(msg);
}

// "c<comp>,<lod>,<bone>" / "x<comp>,<lod>" / "r", fields in hex
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
//   c<comp>,<lod>,<bone> skin cut, plane point LocX/Y/Z, normal DirX/Y/Z; answer in sbslice.cut
//   k                    collapse the sinks the last cuts recorded (call once their weights are in use)
//   x<comp>,<lod>        undo the cut on that component
//   r                    put back every collapsed sink (a mesh asset outlives the component)
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
    if (txt[0] != 'c' && txt[0] != 'x') { skin_result("err unknown command"); return; }
    u64 f[3] = { 0, 0, 0 };
    int k = parse_fields(txt + 1, len - 1, f, 3);
    if (f[0] < 0x10000) { skin_result("err bad component"); return; }
    if (txt[0] == 'x') { skin_clear(f[0], (int)f[1]); return; }
    if (k < 3) { skin_result("err want c<comp>,<lod>,<bone>"); return; }
    float l2 = dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2];
    if (l2 < 1e-8f) { skin_result("err no plane normal"); return; }
    float kk = rsqrt(l2), nrm[3] = { dir[0] * kk, dir[1] * kk, dir[2] * kk };
    skin_cut(f[0], (int)f[1], (int)f[2], loc, nrm);
}

static const u16 REQ[] = u"ue4ss\\Mods\\EveRagdollProbe\\sbslice.req";
static const u16 OK[] = u"ue4ss\\Mods\\EveRagdollProbe\\sbslice.ok";
static const u16 ERR[] = u"ue4ss\\Mods\\EveRagdollProbe\\sbslice.err";

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
