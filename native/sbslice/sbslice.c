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
__declspec(dllimport) u32 WINAPI GetModuleFileNameW(void *, u16 *, u32);
__declspec(dllimport) int WINAPI DisableThreadLibraryCalls(void *);
__declspec(dllimport) HANDLE WINAPI GetProcessHeap(void);
__declspec(dllimport) void *WINAPI HeapAlloc(HANDLE, u32, u64);
__declspec(dllimport) int WINAPI HeapFree(HANDLE, u32, void *);
__declspec(dllimport) int WINAPI VirtualProtect(void *, u64, u32, u32 *);
__declspec(dllimport) int WINAPI FlushInstructionCache(HANDLE, const void *, u64);
__declspec(dllimport) HANDLE WINAPI GetCurrentProcess(void);
__declspec(dllimport) u64 WINAPI GetTickCount64(void);
__declspec(dllimport) u32 WINAPI GetCurrentThreadId(void);
__declspec(dllimport) void *WINAPI AddVectoredExceptionHandler(u32, long(WINAPI *)(void *));

int _fltused = 0;

// zeroed memory off the process heap (VirtualAlloc next to VirtualProtect and CreateThread reads as a loader to
// antivirus machine learning)
static void *mem_alloc(u64 n) { return HeapAlloc(GetProcessHeap(), 0x8 /*HEAP_ZERO_MEMORY*/, n); }
static void mem_free(void *p) { HeapFree(GetProcessHeap(), 0, p); }
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

// SB-Win64-Shipping.exe (Steam build of 2025-09-10, sha256 in README); RVAs from the image base. Another build: found
// by their code at the start (resolve_addresses), 0 where it wasn't
static u64 RVA_EXEC_REWARD_DROP_FORMATION_PATH_LOCATION = 0x26a25e0; // its native exec thunk
static u64 RVA_SET_SKIN_WEIGHT_OVERRIDE = 0x4128fd0;              // USkinnedMeshComponent::SetSkinWeightOverride
static u64 RVA_GET_SKIN_WEIGHT_BUFFER = 0x4127080;                // USkinnedMeshComponent::GetSkinWeightBuffer
static u64 RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS = 0x41288f0;         // FSkelMeshComponentLODInfo::ReleaseOverrideSkinWeights
static u64 RVA_MARK_RENDER_STATE_DIRTY = 0x40888d0;               // UActorComponent::MarkRenderStateDirty
static u64 RVA_WEAK_PTR_GET = 0x2ba3ab0;                          // FWeakObjectPtr::Get
static u64 RVA_GUOBJECTARRAY = 0x6dd7230;                         // FUObjectArray GUObjectArray (UE4SS logs it)
static u64 RVA_GMALLOC = 0x706b500;                               // FMalloc *GMalloc (UE4SS logs it); vtable Malloc +0x10, Free +0x30
static u64 RVA_NEED_CPU_DATA = 0x4529a30;                         // USkeletalMesh::NeedCPUData(LOD): LODInfo[LOD].bAllowCPUAccess
static u64 RVA_SB_CONFIG = 0x7032540;                             // the game's named constants (0x698 bytes, made at 0x1a977b0)
static u64 RVA_STRIHASH = 0x117c180;                              // FCrc::Strihash_DEPRECATED(const TCHAR *): their keys
static u64 RVA_PHOTO_MGR = 0x7032598;                             // photo mode's manager (a singleton, its getter called first in RVA_PHOTO_ENTER)
static u64 RVA_PHOTO_ENTER = 0x22a98b0;                           // photo mode entered (see photo_open)
static u64 RVA_PHOTO_GATE = 0x231c400;                            // and its gates
static u64 RVA_UI_STACK = 0x212f940;                              // the open UI list
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
// The LOD's indices copied out once and kept (two meshes: her body and her face): a cut walked the index buffer two
// to four times through the engine's virtual Get, a million calls a cut on CH_P_EVE_09 (part of the 11-23 ms each cut
// held the frame, playtest). A copy is used again while its buffer still answers the same (its count and 16 indices
// spread over it); 0 when there's no memory for it
static struct { u64 ib; int ni; u32 *ix; } ib_slots[2];
static int ib_next;
static const u32 *ib_indices(u64 ib, int ni, index_get_fn get)
{
    if (ni <= 0) return 0;
    for (int k = 0; k < 2; k++) {
        if (ib_slots[k].ib != ib || ib_slots[k].ni != ni || !ib_slots[k].ix) continue;
        int same = 1;
        for (int j = 0; j < 16 && same; j++) {
            u32 i = (u32)((u64)(ni - 1) * (u64)j / 15);
            same = ib_slots[k].ix[i] == get(ib, i);
        }
        if (same) return ib_slots[k].ix;
    }
    int k = ib_next; ib_next ^= 1;
    if (ib_slots[k].ix) mem_free(ib_slots[k].ix);
    ib_slots[k].ib = 0; ib_slots[k].ni = 0;
    ib_slots[k].ix = mem_alloc((u64)ni * 4);
    if (!ib_slots[k].ix) return 0;
    for (int i = 0; i < ni; i++) ib_slots[k].ix[i] = get(ib, (u32)i);
    ib_slots[k].ib = ib; ib_slots[k].ni = ni;
    return ib_slots[k].ix;
}

// inverse bind matrices this DLL collapsed, to put back (the mesh asset is shared, so it must be undone)
// A cut records its sinks first and collapses them on "k" once the new weights are on the GPU: a collapsed bone
// under the old weights would pull every vertex the helper used to move onto its origin for a frame or two.
// A sink either collapses to a point (at, in the bone's frame) or, for a split, flattens onto the cut plane (pm, the
// whole replacement matrix): every vertex on it lands where it is, only pushed onto the plane, so the seam closes
// without a triangle reaching across the body.
// anchor: the bone a stump seam must stay on (the rim's, -1 if this sink's own transform is the point: a cape's
// seam, a split's). ap: that point in the anchor's frame. The weights stay on `bone` (collapsing the anchor would
// take the whole limb or the torso with them); each frame `at` is rewritten so the point still rides the anchor
// also: components that took comp's weights with this sink in them ("y": a split's copy of a body cut before), whose
// cuts count it as their own too
// A split's flattening sink on a bone that doesn't ride its band's spine bone (no free helper rides Spine or Spine1)
// is held on that bone the same way: proj with anchor >= 0, g its flattening in the anchor's frame at the cut, and
// each frame pm = g * anchor now * the sink's own pose now inverted
static struct { u64 mesh, comp, also[2]; int bone, down, proj, carry, anchor; float m[16], at[3], ap[3], pm[16], g[16]; } sinks[MAX_SINKS];
#define SINK_IN 2.0f // cm a sink's collapse point sits inside its own side of the cut
#define SINK_DEEP 6.0f // cm it sits at most past the plane (a sink bone far off: moved in along the normal)
#define SINK_REUSE_CM 8.0f // an earlier cut's sink serves a seam whose joint is this close to where it collapses
static int nsinks;

// bones that never become a sink (Lua sends them before a cut, per mesh asset: the main skeleton, hair, capes,
// accessories). A sink gives up its weights everywhere and collapses: on a main deformer (the pelvis, a clavicle, the
// head) that broke the body around it, on a hair or cape bone the seam followed the swinging hair.
#define MAX_BONES 1024
static u64 nosink_mesh;
static unsigned char nosink[MAX_BONES];
// a cut's stub carriers (see skin_cut): carry[bone] = the bone whose pose it stands in for, -1 none; subb: B's subtree;
// seccarry: each section's carrier
static short carry[MAX_BONES], subb[MAX_BONES];
// bones that may never carry a stub (Lua, after 0xffff in "n": the rig's Dm- drivers, which the animation points at
// limbs: Dm-Spine-bland, blending Spine and Spine1, carried a waist cut's stub half way after the flying upper body)
static unsigned char nocarry[MAX_BONES];
// the bones with a physics body of their own ("n" after fffe), on nosink_mesh: a cut's sinks ride the body its side's
// stump rides, or one next to it. Bones without one follow their nearest ancestor's body in a ragdoll
static unsigned char hasbody[MAX_BONES];
static int nbodies;
// bones a driver moves ("n" after fffd, a cut through the spine: the rig's Dm- drivers and the helpers under them), on
// nosink_mesh: the animation points them across the cut, so they count as moved while she played (below), a sink only
// when a section has nothing else. CH_P_EVE_30's Ab-L-AX2, under Dm-L-AX2 on the pelvis, took a waist cut's lower seam
// and went with the flying upper body: that half's opening stretched 3.5 m after it (playtest)
// 2 (after fffc, a split half, or a limb cut: the limbs gone so far): a driver of a side whose limbs the half lets go (Dm-R-Trape, the hips' Dm-R-Thigh-point,
// the helpers under them): the animation moves it after them as they fall free, so the half's kept skin lets go of it
// as of the limbs. Kept skin near her middle hung partly on them, cones out of the half (playtest)
static unsigned char drivenb[MAX_BONES];
#define CARRY_ROT_COS 0.99863f // cos(3 deg), half the angle: a carrier turned over 6 degrees off its bind pose is driven
#define CARRY_SECTIONS 256
static int seccarry[CARRY_SECTIONS];
// her bones watched while she plays (Lua's "w" every few ticks while she is alive): a carrier must have held still
// against its parent all along, not only at the cut. A corrective the animation drives is still in some poses and
// swings in others: the thigh's parent is the spine on her rig, and the spine's Ab-AX3, still at the cut, swung a
// thigh's stub (5365 vertices) all over the screen as the leg flew (twenty-fifth playtest). watch_dt: the most it
// slid off its bind offset (cm), watch_dc: the least |cos| of half its turn off its bind rotation
#define CARRY_WATCH 30
static u64 watch_sm;
static int watch_n;
static float watch_dt[MAX_BONES], watch_dc[MAX_BONES];
// this cut's bones that moved against their parents while she played (watched, see above): never a sink, as if Lua
// had named them in "n". The split's seam (26000 vertices) collapsed onto the spine's Ab-AX3 family of correctives on
// CH_P_EVE_10, and in a ragdoll death they stood up in sheets as tall as she was (twenty-sixth playtest); a cost on
// them wasn't enough, they were the only helpers of their bands
static unsigned char wmoved[MAX_BONES], nsx[MAX_BONES], nsm[MAX_BONES], nsd[MAX_BONES];
// moved only with a helper above it (see the watch below): it goes where its driver points, never a sink
// (nsd: nsm with the driven bones, for a seam the watch's moved ones are left for)
static unsigned char winh[MAX_BONES];
// a split half's limbs, decided by Lua from where each limb is (a limb never splits lengthwise): roots of the limbs
// that go with the other half, and of the ones that stay. For the next MODE_SIDE cut on that component
#define MAX_LIMB_ROOTS 8
static u64 limbs_comp;
// a split's accessory chains (Lua: a non-Bip001 chain of bodies off the torso or neck): the half on whose side a chain
// hangs keeps it whole (with its kept roots), the other drops it whole (drop_roots), each vertex mostly on it collapsed
// to a point in its band. Halved, a neck chain's swinging half stretched to the flattened sheet (fifteenth playtest)
#define MAX_KEEP_ROOTS 32
static int gone_roots[MAX_LIMB_ROOTS], ngone, keep_roots[MAX_KEEP_ROOTS], nkeep, drop_roots[MAX_KEEP_ROOTS], ndrop;
// and the spine bones its lid pieces ride (each lid triangle on the nearest one): the flattened skin behind the lid
// is banded the same way, each band on sinks that ride that bone, so sheet and lid move together
#define MAX_RIDE 6
static int ride_bones[MAX_RIDE], nride;
// where the split breaks her spine ("g"'s fifth list: the bone, then 1 for the half above it, 2 for the one below):
// each half's ragdoll lets go of the other side of the break (gore.lua's settle_half), free and invisible, so its kept
// skin may hang on none of it. A waist split 9 cm over the pelvis left the skin above the plane on her half's free
// pelvis, and her torso stretched a metre after it (playtest 40). The half above's weight goes to the break bone
// (the pelvis is the spine's parent: its kept ancestor is no body at all), the half below's to the nearest ancestor
static int free_spine = -1, free_upper;
static short keep_to[MAX_BONES]; // keep_only: a dropped bone's weight goes here first, -1 the nearest kept ancestor
static const short *keep_to_on;
// a split's neck plane (point, normal up the neck, world; "h"; gore.lua puts it at the neck's base): her main hair is
// one piece with no bone a cut could collapse, so a split never halves her head. The half that keeps it (HEAD_KEEP)
// keeps the neck and head above the plane whole, the other (HEAD_DROP) lets them go into its neck, which closes like
// a stump. Within NECK_BASE_R of the neck axis up to halfway to the head bone (the neck alone: wider, it kept the
// trapezius past a split leaned beside the neck, stretched to where the dropped arm collapsed), within NECK_R above
// (her collar; the shoulders stay with the split), and whatever the vanilla skin puts mostly on the head bone's
// subtree. With the plane halfway up the neck, a split 2 cm beside it took the far side's lower neck.
// For the next MODE_SIDE cut on that component only
#define HEAD_KEEP 1
#define HEAD_DROP 2
#define NECK_R 10.0f    // cm from the neck axis
#define NECK_BASE_R 7.0f // cm from it, under halfway to the head bone
#define NECK_BAND 2.5f  // cm under the plane where the kept head's other half of the neck closes into a point
#define NECK_IN 0.5f    // cm under the plane that point sits (on the neck axis), under the neck's lid
#define NECK_SINK 30    // btype of a sink that collapses into the neck
// the kept neck's far side (past the split's plane) shaved at a curve: kept no deeper than neck_shave cm at its foot,
// rising to the whole neck neck_shave_h cm up it; the shaved skin closes into the neck like the far side under the
// neck plane. Whole, the neck stood out past the cut edge in a sharp step (playtest). 0: whole
static float neck_shave = 0.0f, neck_shave_h = 8.0f;
static u64 head_comp;
static int head_mode, head_bone;
static float head_pw[3], head_nw[3];

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

// a sink-local point (at, scale included the way the collapsed matrix stores it) to component space and back.
// The same multiply the skinning does: scale, rotate, translate
static void cs_of_local(const float *t, const float *at, float *cs)
{
    float l[3] = { at[0] * t[8], at[1] * t[9], at[2] * t[10] }, r[3];
    quat_rot(t, l, r);
    cs[0] = t[4] + r[0]; cs[1] = t[5] + r[1]; cs[2] = t[6] + r[2];
}
static void local_of_cs(const float *t, const float *cs, float *at)
{
    float d[3] = { cs[0] - t[4], cs[1] - t[5], cs[2] - t[6] }, iq[4] = { -t[0], -t[1], -t[2], t[3] }, l[3];
    quat_rot(iq, d, l);
    for (int k = 0; k < 3; k++) at[k] = t[8 + k] != 0 ? l[k] / t[8 + k] : 0;
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

// a scan run on a thread of its own (async_cmd): its answer kept here for "&?", not written over the game thread's
static volatile u32 async_tid;
static char async_out[24 * 200 + 128];
static void skin_result(const char *msg)
{
    if (async_tid && GetCurrentThreadId() == async_tid) {
        int i = 0;
        for (; msg[i] && i < (int)sizeof async_out - 1; i++) async_out[i] = msg[i];
        async_out[i] = 0;
        return;
    }
    write_file(CUTRES, msg);
}

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
    const short *carry;              // bone -> the bone whose cut-time pose it stands in for (a stub's carrier), or 0
} cut_ctx;

static int parent_of(const cut_ctx *c, int bone) { return *(int *)(c->binfo + bone * 0xc + 8); }
static const float *pose_of(const cut_ctx *c, int bone)
{
    int s = c->mmap ? c->mmap[bone] : bone;
    return s >= 0 && s < c->nspace ? c->space + (u64)s * 12 : 0;
}

// bone i against its parent as posed, off the bind pose (refpose): dt how far it slid (cm, in the parent's scale),
// dc the |cos| of half its turn
static int off_bind(const cut_ctx *c, const float *refpose, int i, float *dt, float *dc)
{
    int par = parent_of(c, i);
    const float *t = pose_of(c, i), *pt = par >= 0 ? pose_of(c, par) : 0;
    if (!t || !pt) return 0;
    float d[3] = { t[4] - pt[4], t[5] - pt[5], t[6] - pt[6] }, iq[4] = { -pt[0], -pt[1], -pt[2], pt[3] }, l[3];
    quat_rot(iq, d, l);
    for (int k = 0; k < 3; k++) l[k] /= pt[8 + k] != 0 ? pt[8 + k] : 1;
    const float *r = refpose + (u64)i * 12;
    float e[3] = { l[0] - r[4], l[1] - r[5], l[2] - r[6] };
    *dt = __builtin_sqrtf(e[0] * e[0] + e[1] * e[1] + e[2] * e[2]);
    const float *a = pt, *q = t;
    float lq[4] = { a[3] * q[0] - a[0] * q[3] - a[1] * q[2] + a[2] * q[1],
                    a[3] * q[1] - a[1] * q[3] - a[2] * q[0] + a[0] * q[2],
                    a[3] * q[2] - a[2] * q[3] - a[0] * q[1] + a[1] * q[0],
                    a[3] * q[3] + a[0] * q[0] + a[1] * q[1] + a[2] * q[2] }; // conj(a) * q
    float dd = lq[0] * r[0] + lq[1] * r[1] + lq[2] * r[2] + lq[3] * r[3];
    *dc = dd < 0 ? -dd : dd;
    return 1;
}

static int watched_still(const cut_ctx *c, int i)
{
    return watch_sm == c->sm && watch_n >= CARRY_WATCH && watch_dt[i] < STABLE_CM && watch_dc[i] >= CARRY_ROT_COS;
}

// skinned position of bind position vp under weights o (mesh bone indices), current pose
static void skin_point(const cut_ctx *c, const skin_info *o, const float *vp, float *x)
{
    x[0] = x[1] = x[2] = 0;
    for (int i = 0; i < MAX_INF; i++) {
        unsigned char w = o->weights[i];
        int mb = o->bones[i];
        if (!w || mb < 0 || mb >= c->nb) continue;
        // a carrier's matrix isn't in yet (on "k"): it puts the vertex where its source bone has it now
        if (c->carry && c->carry[mb] >= 0) mb = c->carry[mb];
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

// move every weight of o on bones where drop[] says so to that bone's nearest ancestor that stays (and is in section
// s's BoneMap), else to the strongest remaining bone, else to fallback. A helper rides its parent at a fixed offset
// in a ragdoll (no body of its own), so its parent skins the vertex where the helper did; the strongest bone put a
// split's shoulder skin on the chest, and it tore off the clavicle by up to 23 cm once she moved.
// Returns 1 if it changed o, 0 if not, -1 if it had to leave o alone (nothing to put the weight on).
static int keep_only(const cut_ctx *c, int s, skin_info *o, const unsigned char *drop, int fallback)
{
    int nb = c->nb, target = -1, best = -1, gone = 0, rest = 0;
    int up[MAX_INF];
    for (int i = 0; i < MAX_INF; i++) {
        up[i] = -1;
        if (!o->weights[i]) continue;
        int mb = o->bones[i];
        if (mb >= 0 && mb < nb && drop[mb]) {
            gone += o->weights[i];
            int to = keep_to_on ? keep_to_on[mb] : -1;
            if (to >= 0 && to < nb && !drop[to] && (!c->inmap || c->inmap[(u64)s * nb + to])) { up[i] = to; continue; }
            if (to >= 0) { rest += o->weights[i]; continue; }
            for (int a = parent_of(c, mb); a >= 0 && a < nb; a = parent_of(c, a))
                if (!drop[a] && (!c->inmap || c->inmap[(u64)s * nb + a])) { up[i] = a; break; }
            if (up[i] < 0) rest += o->weights[i];
        } else if (o->weights[i] > best) { best = o->weights[i]; target = mb; }
    }
    if (!gone) return 0;
    if (target < 0) target = fallback;
    if (rest && target < 0) return -1;
    unsigned char w[MAX_INF];
    for (int i = 0; i < MAX_INF; i++) {
        w[i] = 0;
        int mb = o->bones[i];
        if (o->weights[i] && mb >= 0 && mb < nb && drop[mb]) { w[i] = o->weights[i]; o->weights[i] = 0; }
    }
    for (int i = 0; i <= MAX_INF; i++) {
        int to = i < MAX_INF ? up[i] : target;
        int add = i < MAX_INF ? (up[i] >= 0 ? w[i] : 0) : rest;
        if (!add || to < 0) continue;
        int slot = -1;
        for (int k = 0; k < MAX_INF; k++) if (o->weights[k] && o->bones[k] == to) slot = k;
        if (slot < 0) for (int k = 0; k < MAX_INF; k++) if (!o->weights[k]) { slot = k; o->bones[k] = to; break; }
        if (slot >= 0) o->weights[slot] += (unsigned char)add;
    }
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

// a stub's carrier (recorded with the sinks, but its skin shows: it isn't collapsed, only held)
static int is_carrier(const cut_ctx *c, int bone)
{
    for (int i = 0; i < nsinks; i++) if (sinks[i].mesh == c->sm && sinks[i].bone == bone && sinks[i].carry) return 1;
    return 0;
}

// a sink an earlier cut on this very component made (its seam vertices are already on it)
static int own_sink(const cut_ctx *c, int bone)
{
    for (int i = 0; i < nsinks; i++)
        if (sinks[i].mesh == c->sm && sinks[i].bone == bone
            && (sinks[i].comp == c->comp || sinks[i].also[0] == c->comp || sinks[i].also[1] == c->comp)) return 1;
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
// hull: write the convex outline too (a split's opening traces its own, see put_outline)
static char *put_fit(char *o, const char *tag, const float *pts, int n, const float *pp, const float *dir, const float *tm,
                     int hull)
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
    if (!hull) return o;
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

// A split's opening isn't convex (her waist and the small of her back curve in, the neck narrows above the shoulders),
// so its outline is traced instead of hulled: the rim points, seen along the normal, are drawn into a grid as discs of
// OUTLINE_GAP, which closes the spaces between them; the outside is flooded in from the border, the rest filled, shrunk
// back by OUTLINE_GAP (so the outline sits on the skin again), and the border of its biggest piece is followed round,
// counter-clockwise seen from the side dir points to, thinned (Douglas-Peucker) to at most OUTLINE_MAX points. Lua cuts
// the polygon into triangles: one lid over the whole opening. Four convex lids a half (one per band) left gaps you could
// see into, and stuck out past the waist.
#define OG_N 320
#define OUTLINE_CELL 0.8f // cm
#define OUTLINE_GAP 1.5f  // cm, doubled while the outside gets in
#define OUTLINE_SEGS 16384
static float ol_segs[OUTLINE_SEGS * 6];
#define OUTLINE_TOL 0.4f  // cm a thinned outline may stray from the traced one, at first
#define OUTLINE_MAX 200
#define OUTLINE_STEPS 16384
static unsigned char og[OG_N * OG_N];
static int og_stack[OG_N * OG_N], og_lab[OG_N * OG_N], og_next[(OG_N + 1) * (OG_N + 1)];
static float ol_uv[OUTLINE_STEPS][2];
static unsigned char ol_keep[OUTLINE_STEPS];
static float ol_area; // cm2 of the last outline put_outline wrote, -1 if it wrote none
static int ol_seg[2 * OUTLINE_STEPS];
// keep the point of a..b (indices into ol_uv, b may wrap past n) furthest from the chord when it is off by more than tol
static void outline_thin(int n, int a, int b, float tol)
{
    int top = 0;
    ol_seg[top++] = a; ol_seg[top++] = b;
    while (top >= 2) {
        int e = ol_seg[--top], s = ol_seg[--top];
        if (e - s < 2) continue;
        const float *p0 = ol_uv[s % n], *p1 = ol_uv[e % n];
        float du = p1[0] - p0[0], dv = p1[1] - p0[1], l = __builtin_sqrtf(du * du + dv * dv);
        float best = -1;
        int bi = -1;
        for (int i = s + 1; i < e; i++) {
            const float *q = ol_uv[i % n];
            float d = l > 1e-6f ? fabsf_((q[0] - p0[0]) * dv - (q[1] - p0[1]) * du) / l
                                : __builtin_sqrtf((q[0] - p0[0]) * (q[0] - p0[0]) + (q[1] - p0[1]) * (q[1] - p0[1]));
            if (d > best) { best = d; bi = i; }
        }
        if (best <= tol || bi < 0 || top + 4 > 2 * OUTLINE_STEPS) continue;
        ol_keep[bi % n] = 1;
        ol_seg[top++] = s; ol_seg[top++] = bi; ol_seg[top++] = bi; ol_seg[top++] = e;
    }
}
// stamp a disc of radius rg (cells) into og at cell (ci, cj)
static void og_disc(int ci, int cj, int rg, int W, int H)
{
    for (int dj = -rg; dj <= rg; dj++)
        for (int di = -rg; di <= rg; di++) {
            int i = ci + di, j = cj + dj;
            if (di * di + dj * dj <= rg * rg && i > 0 && j > 0 && i < W - 1 && j < H - 1) og[j * W + i] = 1;
        }
}
// pts: rim points, segs: where the mesh crosses the plane (pairs of points), all component space; pp: a point on the
// plane; maj, mnr: in-plane axes, mnr = dir x maj. The rim alone had gaps of up to 8 cm (a smooth belly's big
// triangles), and the outside flooded in through them: the cross-section is drawn too
// pts2: more points that close the outline but aren't the opening's (a split's neck, along its top)
static char *put_outline(char *o, const char *tag, const float *pts, int n, const float *pts2, int n2, const float *segs,
                         int ns, const float *pp, const float *dir, const float *maj, const float *mnr, const float *tm,
                         float gapcm)
{
    ol_area = -1;
    if (n < 3) return o;
    float u0 = 1e30f, u1 = -1e30f, v0 = 1e30f, v1 = -1e30f;
    for (int i = 0; i < n; i++) {
        const float *q = pts + (u64)i * 3;
        float u = q[0] * maj[0] + q[1] * maj[1] + q[2] * maj[2], v = q[0] * mnr[0] + q[1] * mnr[1] + q[2] * mnr[2];
        if (u < u0) u0 = u;
        if (u > u1) u1 = u;
        if (v < v0) v0 = v;
        if (v > v1) v1 = v;
    }
    float cell = OUTLINE_CELL / tm[8], gap = gapcm / tm[8];
    float span = (u1 - u0 > v1 - v0 ? u1 - u0 : v1 - v0) + 2 * gap;
    if (span / cell > OG_N - 8) cell = span / (OG_N - 8);
    int rg = (int)(gap / cell + 0.5f);
    if (rg < 1) rg = 1;
    int W = (int)((u1 - u0 + 2 * gap) / cell) + 6, H = (int)((v1 - v0 + 2 * gap) / cell) + 6;
    if (W > OG_N) W = OG_N;
    if (H > OG_N) H = OG_N;
    float ou = u0 - gap - 2 * cell, ov = v0 - gap - 2 * cell; // cell (0, 0)'s lower left corner
    for (int i = 0; i < W * H; i++) og[i] = 0;
    for (int k = 0; k < n; k++) {
        const float *q = pts + (u64)k * 3;
        og_disc((int)((q[0] * maj[0] + q[1] * maj[1] + q[2] * maj[2] - ou) / cell),
                (int)((q[0] * mnr[0] + q[1] * mnr[1] + q[2] * mnr[2] - ov) / cell), rg, W, H);
    }
    for (int k = 0; k < n2; k++) {
        const float *q = pts2 + (u64)k * 3;
        og_disc((int)((q[0] * maj[0] + q[1] * maj[1] + q[2] * maj[2] - ou) / cell),
                (int)((q[0] * mnr[0] + q[1] * mnr[1] + q[2] * mnr[2] - ov) / cell), rg, W, H);
    }
    for (int k = 0; k < ns; k++) {
        const float *a = segs + (u64)k * 6, *b = a + 3;
        float ua = (a[0] * maj[0] + a[1] * maj[1] + a[2] * maj[2] - ou) / cell, va = (a[0] * mnr[0] + a[1] * mnr[1] + a[2] * mnr[2] - ov) / cell;
        float ub = (b[0] * maj[0] + b[1] * maj[1] + b[2] * maj[2] - ou) / cell, vb = (b[0] * mnr[0] + b[1] * mnr[1] + b[2] * mnr[2] - ov) / cell;
        // well outside the rim's box: an accessory crossing the plane far off
        if (ua < 0 || va < 0 || ub < 0 || vb < 0 || ua >= W || va >= H || ub >= W || vb >= H) continue;
        float du = ub - ua, dv = vb - va, l = __builtin_sqrtf(du * du + dv * dv);
        int steps = (int)(l * 2) + 1;
        for (int t = 0; t <= steps; t++) og_disc((int)(ua + du * t / steps), (int)(va + dv * t / steps), rg, W, H);
    }
    // the outside, from the corner (the border is never drawn on)
    int top = 0;
    og[0] = 2; og_stack[top++] = 0;
    while (top) {
        int c = og_stack[--top], i = c % W, j = c / W;
        int nbr[4] = { i > 0 ? c - 1 : -1, i < W - 1 ? c + 1 : -1, j > 0 ? c - W : -1, j < H - 1 ? c + W : -1 };
        for (int k = 0; k < 4; k++) if (nbr[k] >= 0 && !og[nbr[k]]) { og[nbr[k]] = 2; og_stack[top++] = nbr[k]; }
    }
    for (int i = 0; i < W * H; i++) og[i] = og[i] != 2;
    // shrunk back: a cell stays if nothing outside lies within the disc
    for (int j = 0; j < H; j++)
        for (int i = 0; i < W; i++) {
            if (!(og[j * W + i] & 1)) continue;
            int keep = 1;
            for (int dj = -rg; dj <= rg && keep; dj++)
                for (int di = -rg; di <= rg && keep; di++) {
                    int a = i + di, b = j + dj;
                    if (di * di + dj * dj <= rg * rg && (a < 0 || b < 0 || a >= W || b >= H || !(og[b * W + a] & 1))) keep = 0;
                }
            if (keep) og[j * W + i] |= 2;
        }
    for (int i = 0; i < W * H; i++) og[i] = og[i] >> 1 & 1;
    // two cells touching only at a corner join up, so the border never meets itself
    for (int pass = 0; pass < 2; pass++)
        for (int j = 0; j + 1 < H; j++)
            for (int i = 0; i + 1 < W; i++) {
                unsigned char *a = og + j * W + i, *b = a + 1, *c = a + W, *d = c + 1;
                if ((*a && *d && !*b && !*c) || (*b && *c && !*a && !*d)) *a = *b = *c = *d = 1;
            }
    // the biggest piece
    int best = -1, bestn = 0;
    for (int i = 0; i < W * H; i++) og_lab[i] = -1;
    for (int s0 = 0; s0 < W * H; s0++) {
        if (!og[s0] || og_lab[s0] >= 0) continue;
        int cnt = 0;
        top = 0; og_lab[s0] = s0; og_stack[top++] = s0;
        while (top) {
            int c = og_stack[--top], i = c % W, j = c / W;
            cnt++;
            int nbr[4] = { i > 0 ? c - 1 : -1, i < W - 1 ? c + 1 : -1, j > 0 ? c - W : -1, j < H - 1 ? c + W : -1 };
            for (int k = 0; k < 4; k++) if (nbr[k] >= 0 && og[nbr[k]] && og_lab[nbr[k]] < 0) { og_lab[nbr[k]] = s0; og_stack[top++] = nbr[k]; }
        }
        if (cnt > bestn) { bestn = cnt; best = s0; }
    }
    if (best < 0 || bestn < 4) return o;
    // its border, as edges between corners with the piece on their left
    int W1 = W + 1, start = -1;
    for (int i = 0; i < W1 * (H + 1); i++) og_next[i] = -1;
    for (int j = 0; j < H; j++)
        for (int i = 0; i < W; i++) {
            if (og_lab[j * W + i] != best) continue;
            int c00 = j * W1 + i, c10 = c00 + 1, c01 = c00 + W1, c11 = c01 + 1;
            if (j == 0 || og_lab[(j - 1) * W + i] != best) { og_next[c00] = c10; if (start < 0) start = c00; }
            if (i == W - 1 || og_lab[j * W + i + 1] != best) og_next[c10] = c11;
            if (j == H - 1 || og_lab[(j + 1) * W + i] != best) og_next[c11] = c01;
            if (i == 0 || og_lab[j * W + i - 1] != best) og_next[c01] = c00;
        }
    if (start < 0) return o;
    int m = 0, closed = 0;
    for (int c = start; m < OUTLINE_STEPS; ) {
        ol_uv[m][0] = ou + (float)(c % W1) * cell;
        ol_uv[m][1] = ov + (float)(c / W1) * cell;
        ol_keep[m] = 0;
        m++;
        c = og_next[c];
        if (c < 0) break;
        if (c == start) { closed = 1; break; }
    }
    if (!closed || m < 4) return o;
    // a piece with a hole (the outside got in through a gap wider than the closing): its border isn't one loop, and
    // the walk went round the hole too. The caller closes wider gaps
    float sh = 0;
    for (int i = 0; i < m; i++) { int j = (i + 1) % m; sh += ol_uv[i][0] * ol_uv[j][1] - ol_uv[j][0] * ol_uv[i][1]; }
    if ((float)bestn * cell * cell < 0.85f * sh * 0.5f || sh <= 0) return o;
    // thinned: from the first point and the one furthest from it, both ways round
    int far = 0;
    float fd = -1;
    for (int i = 1; i < m; i++) {
        float du = ol_uv[i][0] - ol_uv[0][0], dv = ol_uv[i][1] - ol_uv[0][1];
        if (du * du + dv * dv > fd) { fd = du * du + dv * dv; far = i; }
    }
    int kept = 0;
    for (float tol = OUTLINE_TOL / tm[8]; ; tol *= 1.5f) {
        for (int i = 0; i < m; i++) ol_keep[i] = 0;
        ol_keep[0] = ol_keep[far] = 1;
        outline_thin(m, 0, far, tol);
        outline_thin(m, far, m, tol);
        kept = 0;
        for (int i = 0; i < m; i++) kept += ol_keep[i];
        if (kept <= OUTLINE_MAX) break;
    }
    if (kept < 3) return o;
    ol_area = (float)bestn * cell * cell * tm[8] * tm[8];
    float hd = pp[0] * dir[0] + pp[1] * dir[1] + pp[2] * dir[2];
    o = put(o, " "); o = put(o, tag); o = put(o, "p=");
    int first = 1;
    for (int i = 0; i < m; i++) {
        if (!ol_keep[i]) continue;
        float q[3], w[3];
        for (int k = 0; k < 3; k++) q[k] = maj[k] * ol_uv[i][0] + mnr[k] * ol_uv[i][1] + dir[k] * hd;
        comp_to_world(tm, q, w);
        if (!first) *o++ = ';';
        first = 0;
        for (int k = 0; k < 3; k++) { if (k) *o++ = ','; o = put_f(o, w[k]); }
    }
    return o;
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
#define CORE_FILL_R 1.1f   // a part-way section joins the core within this times the core's radius
#define CORE_FILL_CM 0.5f  // plus this
#define CORE_HOLE 3        // directions in a row the core must miss for that
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
    int covered = 0;
    for (int s = 0; s < MAX_RIM_SECTIONS; s++)
        if (count[s]) {
            keep[s] = !any || (count[s] >= 3 && popcount16(bins[s]) >= CORE_BINS && med[s] <= inner * 1.35f + 1.0f);
            if (keep[s]) covered |= bins[s];
        }
    // the limb's surface split between sections, one of them only part way round (InnerSuit1's thigh: 8 and 11 of
    // the 16 directions at the same radius): a section on the core's own layer that fills directions the core misses
    // is that layer too. Left out, the cap covered only the core's part of the opening and the seam's cones showed
    // through the rest (playtest screenshot). Nearest the core's radius first
    // Only into a real hole, CORE_HOLE directions in a row: a ring of a few points misses single directions anyway,
    // and a strap lying on the skin there isn't skin
    for (int pass = 0; any && pass < MAX_RIM_SECTIONS; pass++) {
        int hole = 0;
        for (int i = 0; i < ANGLE_BINS; i++) {
            int run = 0;
            while (run < ANGLE_BINS && !(covered >> ((i + run) % ANGLE_BINS) & 1)) run++;
            if (run >= CORE_HOLE) for (int k = 0; k < run; k++) hole |= 1 << ((i + k) % ANGLE_BINS);
        }
        if (!hole) break;
        int pick = -1;
        float bd = 1e30f;
        for (int s = 0; s < MAX_RIM_SECTIONS; s++) {
            if (!count[s] || keep[s] || count[s] < 3 || !(bins[s] & hole) || med[s] > inner * CORE_FILL_R + CORE_FILL_CM) continue;
            float d = fabsf_(med[s] - inner);
            if (d < bd) { bd = d; pick = s; }
        }
        if (pick < 0) break;
        keep[pick] = 1;
        covered |= bins[pick];
    }
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
//   CUT   weighted to B's subtree and in front of the plane (a limb, the torso), or mostly to a part of the subtree
//         that hangs free of the plane (FREE_CM): her arms below a waist cut, her hands, the cape on them. By the
//         plane alone they stayed behind with the legs, the gloves floating where she was cut
//   WHOLE every vertex: the component goes along whole (Eve's face on a beheading: its neck is weighted to the
//         neck, which stays). No seam; the limb opening is the band of vertices closest to the plane, at most
//         radius from the axis (0 = any).
//   PLANE in front of the plane and within radius of the axis through the plane point, whatever the weights (the
//         neck under the face, weighted to neck / spine / clavicles, none of which leaves with the head)
//   SIDE  half of a split: what is behind the plane goes, flattened onto it (see "split" below)
// A limb-side vertex in a section that can't follow the limb (no limb bone in its BoneMap), and every limb-side
// vertex of a section with seam vertices on that side but no limb sink, "vanishes": it joins the body side's
// seam and collapses with it, which beats a triangle stretched from the flying limb to the body.
// Only the body is cut. What hangs off it (straps, plates, pads, a cape, a loose sleeve: a section that doesn't go
// round the cut, see core_rim) has no seam: a piece of it crossing the cut (an island of connected triangles) goes
// along whole with the side holding nearly all of its weight, or, tied to both, with the side holding most of its
// vertices. A seam through it collapsed onto whatever bone its section had, often far off or swinging, and stretched
// across the body. A piece reaching well past the plane both ways with a real share on each (a belt strap across a
// waist cut) is cut after all, its seam on the sink nearest that seam, borrowed into its BoneMap if it has none.
#define MODE_CUT 0
#define MODE_WHOLE 1
#define MODE_PLANE 2
#define MODE_SIDE 4   // keep what is in front of the plane, the rest vanishes: one half of a vertical split
// (3, 5 and 6 were the wounds: a hole, a dent and a rupture, gone with them; a living hit's mark is a decal on the
// skin that skin_mark finds)
#define SPLIT_BANDS 6 // most bands a split's flattening sinks are picked in: one per bone the lid rides ("g"), else
#define AXIS_BANDS 4  // this many along the opening (neck, chest, belly)

// A split's halves are two components on one mesh asset, so they share the collapsed sinks. Sections that have
// nothing to collapse onto (Eve's face: eyes, teeth, brows only know the head bone) borrow a bone no vertex of the
// asset uses: it is added to the section's BoneMap (in place, within the 16 bytes the engine's allocator gives
// even a 1-entry array) and, through the component's MasterBoneMap, made to follow the master's head.
#define MAX_BONEMAP_FIX 64
#define MAX_REMAPS 16
static struct { u64 arr; int num, max; unsigned short *old, *data; } bmfix[MAX_BONEMAP_FIX]; // old: data swapped out, or 0; data: the array in use after
static int nbmfix;
static struct { u64 comp; int index, old, to, applied; } remaps[MAX_REMAPS]; // applied on "k", with the sinks
static int nremaps;
#define WHOLE_BAND 2.5f // cm above the lowest point near the axis that make up a WHOLE cut's opening
#define ISLAND_MINOR_PCT 15   // a hanging piece goes along whole if its other side holds at most this much weight
#define ISLAND_MAX_VERTS 4000 // bigger pieces (a whole jacket) are cut like the body, unless nearly all on one side
#define ISLAND_MAX_CM 40.0f   // ... and so are pieces reaching further than this from the cut
#define ISLAND_CROSS_CM 6.0f  // ... and pieces reaching this far past the plane on both sides (a rivet's size)
#define ISLAND_PURE_PCT 3     // ... unless the other side holds at most this much of its weight
#define ISLAND_TIED_REACH 0.75f // ... and pieces with more than ISLAND_MINOR_PCT of their weight on each side reaching
                              //     this share of ISLAND_CROSS_CM past it both ways...
#define ISLAND_TIED_MAX 2.0f    //     ...the side with fewer of its vertices no further than this many ISLAND_CROSS_CM
// The split: Lua gives the limbs on each side (gone with the other half / staying). What goes is pushed onto the cut
// plane, not into a point: the torso just behind the plane flattens onto it through sinks that project (one per band
// along the opening, so no sink is rigid from the neck to the hips), what lies deeper collapses to a point on the plane
// in its band, the other half's limbs to a point on the plane where they joined. The split works for any plane: a
// slice across the waist or the chest is the same cut as one down the spine. One point sink per section had pulled the whole other half, legs and all, into one spot, and
// every triangle on the midline stretched from the hips or the neck to it.
#define SIDE_TOL 1.0f   // cm: a bone this close to the plane counts as on it
#define FREE_CM 3.0f    // cm: a limb bone whose joint and its parent's both lie this far in front of the plane, and
                        // everything under it, hangs free of the cut (CUT goes along with the limb wherever it hangs)
#define SHEET_IN 2.0f   // cm the flattened skin sits inside the kept side, behind the caps. 0.3 put the sheet out in
                        // front of the lid wherever she bent more than the sheet's sinks follow (harness: 2018 of
                        // 42234 sheet vertices on the real mesh); 2 cm hides all but a few
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
    const unsigned char *onplane;             // MODE_SIDE: helpers on the plane (both halves' kept skin drops them)
    u64 secs;                                 // MODE_SIDE: the LOD's sections, to borrow a sink into one
    unsigned char *btype;                     // MODE_SIDE: 0 free, 1 flattens, 2 + r a point for gone root r,
                                              // 10 + k a point in band k
    const unsigned char *headused;            // MODE_SIDE with a neck plane: bones on the head and the skin round
                                              // the neck plane, which one half keeps whole: never a sink
    const signed char *rideof;                // MODE_SIDE with ride bones: the band each bone rides, -1 none
    int band;                                 // the band a sink is wanted for (-1: any)
    signed char *carryb;                      // MODE_SIDE with ride bones: the band each flattening sink carries
    int carryk;                               // the band a flattening sink is wanted to carry now (-1: not tracked)
    const unsigned char *moved;               // MODE_CUT: bones the watch saw moving while she played
    const short *gov;                         // MODE_CUT with bodies sent: each bone's body (itself or an ancestor)
    int refbody[2];                           // the body each side's stump rides: B's parent's, B's
    const unsigned char *nosink_still;        // MODE_SIDE: nosink without the watch, for a half that finds nothing else
    int widen;                                // side_sink tries nosink_still too
} sink_args;

// bodies between two bodies up the hierarchy (0 the same, 1 one is the other's parent body), at most 3
static int body_hops(const cut_ctx *c, const short *gov, int x, int y)
{
    // (a bone under no body at all never moves in a ragdoll: a statue's root, Base, at its feet, took an arm cut's
    // seam as the stump's own body and stretched it 1.9 m to the floor, playtest)
    if (y < 0) return 0;
    if (x < 0) return 3;
    for (int k = 0; k < 2; k++) {
        int a = k ? y : x, to = k ? x : y;
        for (int h = 0; a >= 0 && h < 3; h++) {
            if (a == to) return h;
            int p = parent_of(c, a);
            a = p >= 0 ? gov[p] : -1;
        }
    }
    return 3;
}

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

static void tm_mat(const float *t, float *m);
static void tm_inv_mat(const float *t, float *m);
static void mat_mul(const float *a, const float *b, float *o);
// the flattening matrix of a sink: the inverse bind matrix base, then onto the plane (point pp, normal n, component
// space) in the frame of t, the transform the sink rides on as posed now (row vectors, like FMatrix)
// along: the direction (component space) points slide in onto the plane, 0 straight along n
static void proj_matrix_along(const float *base, const float *t, const float *pp, const float *n, const float *along, float *out)
{
    float iq[4] = { -t[0], -t[1], -t[2], t[3] }, nl[3], al[3];
    quat_rot(iq, n, nl);
    if (along) quat_rot(iq, along, al); else for (int k = 0; k < 3; k++) al[k] = nl[k];
    float an = al[0] * nl[0] + al[1] * nl[1] + al[2] * nl[2];
    if (an < 0) { for (int k = 0; k < 3; k++) al[k] = -al[k]; an = -an; }
    if (an < 1e-3f) { for (int k = 0; k < 3; k++) al[k] = nl[k]; an = 1; }
    for (int k = 0; k < 3; k++) al[k] /= an;
    float sc = t[8] != 0 ? t[8] : 1;
    float d = ((t[4] - pp[0]) * n[0] + (t[5] - pp[1]) * n[1] + (t[6] - pp[2]) * n[2]) / sc;
    float P[16];
    for (int r = 0; r < 3; r++) {
        for (int k = 0; k < 3; k++) P[r * 4 + k] = (r == k ? 1.0f : 0.0f) - nl[r] * al[k];
        P[r * 4 + 3] = 0;
    }
    for (int k = 0; k < 3; k++) P[12 + k] = -d * al[k];
    P[15] = 1;
    for (int r = 0; r < 4; r++)
        for (int k = 0; k < 4; k++) {
            float acc = 0;
            for (int j = 0; j < 4; j++) acc += base[r * 4 + j] * P[j * 4 + k];
            out[r * 4 + k] = acc;
        }
}
static void proj_matrix(const float *base, const float *t, const float *pp, const float *n, float *out)
{
    proj_matrix_along(base, t, pp, n, 0, out);
}

#define BONEMAP_ROOM 512   // entries in an array of ours swapped in for the engine's (tarray_push16)
int mem_readable(u64 p, u64 n); // stats.c
// the engine's own allocator: an array swapped into the engine's hands must be one it can free. Ours came from
// the process heap, and when she was quit with a cut on (the stub carrier is borrowed into sections on every limb cut),
// the engine freed it on the way out: "MallocBinned2 Corruption Canary was 0x3941, should be 0x17ea", a fatal error
// on every Alt+F4 since stub carriers came in
typedef void *(*gmalloc_fn)(u64 self, u64 n, u32 align);
typedef void (*gfree_fn)(u64 self, void *p);
static void *ue_malloc(u64 n)
{
    if (!RVA_GMALLOC) return 0;
    u64 g = *(u64 *)(exe + RVA_GMALLOC);
    if (!g || !*(u64 *)g) return 0;
    return ((gmalloc_fn)(*(u64 **)g)[2])(g, n, 0);
}
static void ue_free(void *p)
{
    if (!RVA_GMALLOC) return;
    u64 g = *(u64 *)(exe + RVA_GMALLOC);
    if (g && *(u64 *)g && p) ((gfree_fn)(*(u64 **)g)[6])(g, p);
}
// ours, once the engine's array is back: freed on a later command, not at once (the render thread may still be
// reading it for a frame)
static unsigned short *bm_dead[MAX_BONEMAP_FIX];
static int nbm_dead;
static void bm_bury(void)
{
    for (int i = 0; i < nbm_dead; i++) ue_free(bm_dead[i]);
    nbm_dead = 0;
}
// add v to a TArray<uint16> of the engine's (a section's BoneMap, the LOD's ActiveBoneIndices), undone by "r" like
// the face's borrowed sink. In place while it has fewer than 8 entries (the engine's smallest allocation is 16 bytes,
// whatever Max says); a fuller one is swapped for a copy of ours with room (BONEMAP_ROOM entries), the engine's array
// kept to be put back. 0 if there is no room
static int tarray_push16(u64 arr, unsigned short v, int limit)
{
    int num = *(int *)(arr + 8), max = *(int *)(arr + 12);
    unsigned short *bm = *(unsigned short **)arr;
    if (!bm || nbmfix >= MAX_BONEMAP_FIX || num >= limit || num >= BONEMAP_ROOM - 1) return 0;
    int ours = 0;
    for (int i = 0; i < nbmfix; i++) if (bmfix[i].arr == arr && bmfix[i].old) ours = 1;
    if (num >= 8 && !ours) {
        // a new array of ours from the engine's allocator, which frees it if the mesh goes with it still in (the game
        // quit with a cut on); skin_restore buries it once the engine's is back
        unsigned short *nb2 = ue_malloc(BONEMAP_ROOM * sizeof(unsigned short));
        if (!nb2) return 0;
        for (int i = 0; i < num; i++) nb2[i] = bm[i];
        nb2[num] = v;
        bmfix[nbmfix].arr = arr; bmfix[nbmfix].num = num; bmfix[nbmfix].max = max; bmfix[nbmfix].old = bm; bmfix[nbmfix].data = nb2; nbmfix++;
        // the pointer first: a reader that still sees the old count reads the same entries
        *(unsigned short **)arr = nb2;
        __atomic_thread_fence(__ATOMIC_SEQ_CST);
        *(int *)(arr + 12) = BONEMAP_ROOM;
        *(int *)(arr + 8) = num + 1;
    } else {
        if (!ours && num >= 8) return 0;
        bmfix[nbmfix].arr = arr; bmfix[nbmfix].num = num; bmfix[nbmfix].max = max; bmfix[nbmfix].old = 0; bmfix[nbmfix].data = bm; nbmfix++;
        bm[num] = v;
        __atomic_thread_fence(__ATOMIC_SEQ_CST);
        *(int *)(arr + 8) = num + 1;
        if (max < num + 1) *(int *)(arr + 12) = num + 1;
    }
    return 1;
}

// the LOD's active bones (ActiveBoneIndices: the mesh's own BoneMaps and their ancestors): the GPU skin builds a
// matrix for those alone each frame (UpdateRefToLocalMatrices), the rest of its bone buffer is whatever the pooled
// buffer held. A helper with no skin of its own on the LOD, borrowed in as a sink or a stub carrier (CH_P_EVE_10's
// Dm-R-Thigh-point, Ab-AX3), threw its vertices across the screen somewhere else every frame, on every cut. So a
// borrowed bone joins ActiveBoneIndices too, found in the LOD's render data by its contents (act_off, once: the
// struct's layout isn't in the exe's symbols); where it isn't found, no inactive bone is borrowed at all
static unsigned char bactive[MAX_BONES];
static int act_off = -1;   // ActiveBoneIndices' offset in FSkeletalMeshLODRenderData: -1 not found yet
static u64 act_arr;        // this cut's, or 0
static int act_miss;       // why the last look found none: 1 no array of that length, 2 one of that length but other bones
#define ACT_SCAN 0x800
// is the array at ld + o this LOD's active bones (nact of them, each in bactive once)? grown: where the offset is
// known already, an earlier cut's borrows changed both sides (bones pushed into it, their ancestors into bactive
// through the BoneMaps), so only distinct bones of the mesh
static int act_at(u64 ld, int o, int nb, int nact, int grown)
{
    if (!mem_readable(ld + o, 16)) return 0;
    u64 p = *(u64 *)(ld + o);
    int num = *(int *)(ld + o + 8), max = *(int *)(ld + o + 12);
    if ((grown ? num <= 0 || num > nb : num != nact) || max < num || max > 4096 || !p || (p & 1) || !mem_readable(p, (u64)num * 2)) return 0;
    const unsigned short *a = (const unsigned short *)p;
    static unsigned char seen[MAX_BONES];
    int ok = 1;
    for (int i = 0; i < nb; i++) seen[i] = 0;
    for (int i = 0; i < num && ok; i++) ok = a[i] < nb && (grown || bactive[a[i]]) && !seen[a[i]]++;
    if (!ok && act_miss < 2) act_miss = 2;
    return ok;
}
// Looked for slot by slot: the whole scan read at once ran into an unreadable page now and then (where the LOD data
// happened to lie), and one miss turned borrowing off for the session (active=0 on half the playtests, stump cones).
// A miss is looked for again on the next cut
static void find_active(u64 ld, int nb, int nact)
{
    act_arr = 0;
    act_miss = 0;
    if (act_off > 0 && act_at(ld, act_off, nb, nact, 1)) act_arr = ld + act_off;
    else {
        act_miss = 1;
        for (int o = LOD_NUM_VERTICES + 4; o + 16 <= ACT_SCAN && !act_arr; o += 8)
            if (act_at(ld, o, nb, nact, 0)) { act_off = o; act_arr = ld + o; act_miss = 0; }
    }
    // the bones the GPU really poses, from the array itself: after a borrow the BoneMaps' ancestors also name bones
    // never pushed into it (the borrowed helper's parents), and a later borrow of one skipped the push
    if (act_arr) {
        const unsigned short *a = *(const unsigned short **)act_arr;
        int num = *(int *)(act_arr + 8);
        for (int i = 0; i < MAX_BONES; i++) bactive[i] = 0;
        for (int i = 0; i < num; i++) if (a[i] < nb) bactive[a[i]] = 1;
    }
}
static int act_pushed;
// add bone to section s's BoneMap (and to the active bones). A waist cut's lower half had no helper of its own in
// CH_P_EVE_09's metal, skin and lace sections (18-79 bones each), and 30000 vertices of her upper body stayed on her
// legs. The GPU skin's bone buffer is sized for the engine's maximum, so a longer map is fine
static int borrow_bone(u64 secs, int s, int bone, unsigned char *inmap, int nb)
{
    if (bone < 0 || bone >= MAX_BONES) return 0;
    if (!bactive[bone]) {
        if (!act_arr || !tarray_push16(act_arr, (unsigned short)bone, BONEMAP_ROOM)) return 0;
        bactive[bone] = 1; act_pushed++;
    }
    if (!tarray_push16(secs + (u64)s * 0xe8 + SEC_BONE_MAP, (unsigned short)bone, 255)) return 0;
    inmap[(u64)s * nb + bone] = 1;
    return 1;
}

// a split half's sink in section s near target, of type want (see btype): a helper of
// the kept side (no limb, nothing past the plane, not another cut's sink) that costs little to give up, preferring
// one this cut already uses the same way. A helper on the plane will do: both halves' kept skin lets go of those
// band: the ride bone's band a sink must ride, -1 any bone, ANY_BAND any band but one (not a bone riding a clavicle
// or a breast on its own: the AX correctives the animation turns)
#define ANY_BAND -2
// (driven_ok 0: none a driver moves, see drivenb: the split's point sinks on them followed the limbs it lets go, cones
// sticking out of both halves, playtest)
static int side_sink_pass(const sink_args *a, int s, const float *target, int want, int driven_ok)
{
    const cut_ctx *c = a->c;
    int nb = c->nb, best = -2;
    float bd = 1e30f;
    for (int i = 1; i < nb; i++) {
        if (!c->inmap[(u64)s * nb + i] || (a->nosink && a->nosink[i]) || (a->limb[i] && !(a->onplane && a->onplane[i])) || a->gone[i] || a->keep[i]) continue;
        if (i == a->b || i == a->parent_b || (a->headused && a->headused[i])) continue;
        if (!driven_ok && nosink_mesh == c->sm && drivenb[i]) continue;
        if (a->rideof && (a->band >= 0 ? a->rideof[i] != a->band : a->band == ANY_BAND && a->rideof[i] < 0)) continue;
        if (a->btype[i] ? a->btype[i] != want : is_sink(c, i)) continue;
        if (want == 1 && a->carryb && a->carryk >= 0 && a->btype[i] && a->carryb[i] != a->carryk) continue; // (another band's)
        const float *t = pose_of(c, i);
        if (!t) continue;
        float d0 = t[4] - target[0], d1 = t[5] - target[1], d2 = t[6] - target[2];
        float score = (d0 * d0 + d1 * d1 + d2 * d2) * (a->stable[i] ? 1.0f : 16.0f) * (a->haschild[i] ? 4.0f : 1.0f)
            * (1.0f + a->usage[i] / 200.0f) * (a->btype[i] ? 0.5f : 1.0f);
        if (score < bd) { bd = score; best = i; }
    }
    // none in the section (CH_P_EVE_09's neck lace only knows the neck and the spine): borrow the best helper of
    // the half into its BoneMap, or the other half's piece of it stays where it was
    if (best < 0 && a->secs) {
        for (int i = 1; i < nb; i++) {
            if (c->inmap[(u64)s * nb + i] || (a->nosink && a->nosink[i]) || (a->limb[i] && !(a->onplane && a->onplane[i]))
                || a->gone[i] || a->keep[i] || i == a->b || i == a->parent_b) continue;
            if ((a->headused && a->headused[i]) || (!driven_ok && nosink_mesh == c->sm && drivenb[i])) continue;
            if (a->rideof && (a->band >= 0 ? a->rideof[i] != a->band : a->band == ANY_BAND && a->rideof[i] < 0)) continue;
            if (a->btype[i] ? a->btype[i] != want : is_sink(c, i)) continue;
            if (want == 1 && a->carryb && a->carryk >= 0 && a->btype[i] && a->carryb[i] != a->carryk) continue;
            const float *t = pose_of(c, i);
            if (!t) continue;
            float d0 = t[4] - target[0], d1 = t[5] - target[1], d2 = t[6] - target[2];
            float score = (d0 * d0 + d1 * d1 + d2 * d2) * (a->stable[i] ? 1.0f : 16.0f) * (a->haschild[i] ? 4.0f : 1.0f);
            if (score < bd) { bd = score; best = i; }
        }
        if (best >= 0 && !borrow_bone(a->secs, s, best, (unsigned char *)c->inmap, nb)) best = -2;
    }
    if (best >= 0) a->btype[best] = (unsigned char)want;
    if (best >= 0 && want == 1 && a->carryb && a->carryk >= 0) a->carryb[best] = (signed char)a->carryk;
    return best;
}
// in its band, else (wider: ANY_BAND or -1, 0 none) any, with none a driver moves first, then with them
static int side_sink(sink_args *a, int s, const float *target, int want, int wider)
{
    int band = a->band, best = -2;
    // widen: then with the helpers the watch saw move allowed, a last resort (a section with nothing else): it watches
    // the whole session, and after a few deaths every
    // helper of her right side had moved once. The copy found no point for her left leg, which flattened onto the
    // plane, a third leg (playtest, a split after an arm cut); with all of them seen, no split at all (harness)
    const unsigned char *ns = a->nosink;
    for (int w = 0; w < 2 && best < 0; w++) {
        if (w && (!a->widen || !a->nosink_still || a->nosink_still == ns)) break;
        a->nosink = w ? a->nosink_still : ns;
        for (int dr = 0; dr < 2 && best < 0; dr++) {
            a->band = band;
            best = side_sink_pass(a, s, target, want, dr);
            if (best < 0 && wider) { a->band = wider; best = side_sink_pass(a, s, target, want, dr); }
        }
    }
    a->nosink = ns;
    a->band = band;
    return best;
}

// a sink for section s, side sd: a bone of that side in the section's BoneMap close to the joint that costs little
// to give up: stable, a leaf, few vertices of its own (a helper, not a main deformer like the pelvis). An earlier
// cut's sink is free. Never B or its parent (they carry the limb and the stump), never the root. PLANE / HOLE want
// it on its own side of the plane / inside the body (every mode), or the collapsed skin would poke out through the cap.
// where an earlier cut's sink collapses its skin now (world): its bone's pose applied to its collapse point. 0 for a
// carrier (its skin isn't collapsed) or no pose
static int sink_point(const cut_ctx *c, int bone, float *o)
{
    const float *t = pose_of(c, bone);
    if (!t) return 0;
    for (int i = 0; i < nsinks; i++) {
        if (sinks[i].mesh != c->sm || sinks[i].bone != bone || sinks[i].carry) continue;
        float l[3] = { sinks[i].at[0] * t[8], sinks[i].at[1] * t[9], sinks[i].at[2] * t[10] }, r[3];
        quat_rot(t, l, r);
        for (int k = 0; k < 3; k++) o[k] = t[4 + k] + r[k];
        return 1;
    }
    return 0;
}

static int find_sink(const sink_args *a, int s, int sd)
{
    const cut_ctx *c = a->c;
    int nb = c->nb, best = -2;
    float bd = 1e30f;
    for (int i = 1; i < nb; i++) {
        if (!c->inmap[(u64)s * nb + i] || a->limb[i] != sd || i == a->b || i == a->parent_b) continue;
        if (a->nosink && a->nosink[i]) continue;
        // nor any bone B hangs from: a statue's root (Base, at its feet, never simulated) took a waist cut's and an
        // arm cut's seam, stretched 1.3 m down to the floor in its ragdoll (playtest)
        {
            int up = 0;
            for (int x = parent_of(c, a->b), g = 0; x >= 0 && x < nb && g < MAX_BONES && !up; x = parent_of(c, x), g++) up = x == i;
            if (up) continue;
        }
        // nothing reuses a flattening sink
        if (is_proj_sink(c, i)) continue;
        // an earlier cut's sink pulls its skin to that cut's opening: free only for a seam right there. The second
        // thigh's seam collapsed into the first thigh's stump (its hip helper, Dm-R-Thigh-point) and stretched across
        // the crotch (twenty-ninth playtest). A carrier's skin shows: never anyone's sink
        if (is_sink(c, i)) {
            float q[3];
            if (!sink_point(c, i, q)) continue;
            float e0 = q[0] - a->joint[0], e1 = q[1] - a->joint[1], e2 = q[2] - a->joint[2];
            if (e0 * e0 + e1 * e1 + e2 * e2 > SINK_REUSE_CM * SINK_REUSE_CM) continue;
        }
        const float *t = pose_of(c, i);
        if (!t) continue;
        float d0 = t[4] - a->joint[0], d1 = t[5] - a->joint[1], d2 = t[6] - a->joint[2], d = d0 * d0 + d1 * d1 + d2 * d2;
        // squared distance, so a factor 4 is twice as far
        float score = is_sink(c, i) ? d * 0.5f
            : d * (a->stable[i] ? 1.0f : 16.0f) * (a->haschild[i] ? 4.0f : 1.0f) * (1.0f + a->usage[i] / 200.0f);
        // on another body than the one its side's stump rides: the seam's point moves against the opening as she
        // bends there. The hip's seam on a chest helper (its own helpers moved while she played, so not sinks)
        // stretched the whole thigh's opening up to the chest (twenty-seventh playtest)
        if (a->gov) { int h = body_hops(c, a->gov, a->gov[i], a->refbody[sd]); score *= h == 0 ? 1.0f : h == 1 ? 4.0f : 64.0f; }
        // a sink on the wrong side of the plane collapses its seam out past the cut: on the limb, a cone sticking out
        // through the cap (an upper arm's twist bones sit at the shoulder, above a cut 15 % down the bone)
        {
            float h = (t[4] - a->pp[0]) * a->n[0] + (t[5] - a->pp[1]) * a->n[1] + (t[6] - a->pp[2]) * a->n[2];
            int wrong = a->mode == MODE_SIDE ? h < -1.0f : sd ? h < 0 : h > 0;
            if (wrong) score *= 16.0f;
        }
        if (score < bd) { bd = score; best = i; }
    }
    return best;
}

// the stump seam on sinks[idx] stays at its present point, but in the anchor's frame (the rim's bone). Collapsing the
// anchor itself would pull every vertex on it into the point: the whole thigh, or the spine
static void sink_anchor(const cut_ctx *c, int idx, int anchor)
{
    if (anchor < 0 || sinks[idx].proj || anchor == sinks[idx].bone) return;
    const float *ts = pose_of(c, sinks[idx].bone), *ta = pose_of(c, anchor);
    if (!ts || !ta) return;
    float cs[3];
    cs_of_local(ts, sinks[idx].at, cs);
    local_of_cs(ta, cs, sinks[idx].ap);
    sinks[idx].anchor = anchor;
}

// pw = plane point, nw = plane normal pointing into the limb, world; radius in cm
// the cut's two work blocks (about 10 MB on CH_P_EVE_09), kept from one cut to the next and zeroed for each: fresh
// pages every cut were thousands of page faults in the cut's frame
static unsigned char *scratch_mem[2];
static u64 scratch_len[2];
static unsigned char *cut_scratch(int k, u64 bytes)
{
    if (scratch_mem[k] && scratch_len[k] >= bytes) {
        u64 *q = (u64 *)scratch_mem[k];
        for (u64 i = 0, n = (bytes + 7) / 8; i < n; i++) q[i] = 0;
        return scratch_mem[k];
    }
    if (scratch_mem[k]) mem_free(scratch_mem[k]);
    scratch_len[k] = 0;
    // (room to grow: the next mesh may be a little bigger)
    u64 len = bytes + bytes / 4;
    scratch_mem[k] = mem_alloc(len);
    if (scratch_mem[k]) scratch_len[k] = len;
    return scratch_mem[k];
}
static void skin_cut(u64 comp, int lod, int b, const float *pw, const float *nw, int mode, float radius, int forced_sink, int remap)
{
    // the cut's cost in CPU cycles (rdtsc, no import): the weights worked out, the engine's override built from them,
    // the rest. In game each cut held the frame 11-23 ms, a stutter at every cut (playtest); "cyc=" says where
    const u64 tc0 = __builtin_ia32_rdtsc();
    u64 tc1 = tc0, tc2 = tc0;
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
    const u32 *ix = ib_indices(ib, ni, index_get);
    if (!ix) { skin_result("err no memory for the indices"); return; }
    c.nb = *(int *)(c.sm + SM_REF_BONE_INFO + 8);
    c.binfo = *(unsigned char **)(c.sm + SM_REF_BONE_INFO);
    c.refinv = *(float **)(c.sm + SM_REF_BASES_INV);
    float *refpose = *(float **)(c.sm + SM_REF_BONE_POSE);
    if (*(int *)(c.sm + SM_REF_BONE_POSE + 8) != c.nb) refpose = 0;
    int nb = c.nb, nv = c.nv;
    if (b <= 0 || b >= nb || !c.refinv || *(int *)(c.sm + SM_REF_BASES_INV + 8) != nb) { skin_result("err bad bone"); return; }
    if (mode < MODE_CUT || mode > MODE_SIDE || mode == 3) { skin_result("err bad mode"); return; }
    if (forced_sink >= nb || forced_sink < 0) { skin_result("err bad sink"); return; }

    // pose source: the master pose component when there is one, its bones matched by name (the engine's
    // MasterBoneMap of a clone made this tick can still be empty or short, and was read unchecked: a split's face and
    // hair copies once came out cut against the wrong bones)
    u64 master = ((weak_get_fn)(exe + RVA_WEAK_PTR_GET))(comp + SC_MASTER_POSE);
    u64 src = master ? master : comp;
    c.mmap = 0;
    if (master) {
        static int namemap[MAX_BONES];
        u64 msm = *(u64 *)(master + SC_SKELETAL_MESH);
        const unsigned char *mbi = msm ? *(unsigned char **)(msm + SM_REF_BONE_INFO) : 0;
        int mnb = msm ? *(int *)(msm + SM_REF_BONE_INFO + 8) : 0;
        if (!mbi || mnb <= 0 || c.nb > MAX_BONES) { skin_result("err no master skeleton"); return; }
        int found = 0;
        for (int i = 0; i < c.nb; i++) {
            u64 nm = *(const u64 *)(c.binfo + (u64)i * 0xc);
            namemap[i] = -1;
            for (int j = 0; j < mnb; j++) if (*(const u64 *)(mbi + (u64)j * 0xc) == nm) { namemap[i] = j; found++; break; }
        }
        if (!found) { skin_result("err no bone shared with the master"); return; }
        c.mmap = namemap;
    }
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
    unsigned char *mem = cut_scratch(0, bytes);
    if (!mem) { skin_result("err out of memory"); return; }
    // a second block for islands (hanging pieces), layers (holes) and the split: per vertex island parent, counts,
    // weights, reach, sink, kind; per bone the split's limb flags, sink types and roots; per section layer flags and
    // the split's band and limb sinks
    u64 bytes2 = (u64)nv * (11 * 4 + 6) + (u64)nb * (4 + 4) + (u64)c.nsec * (1 + 4 * (2 * SPLIT_BANDS + MAX_LIMB_ROOTS + 1)) + 64;
    unsigned char *mem2 = cut_scratch(1, bytes2);
    if (!mem2) { skin_result("err out of memory"); return; }
    int *upar = (int *)mem2, *icnt = upar + nv, *iwl = icnt + nv, *iwb = iwl + nv, *vsink = iwb + nv;
    float *iext = (float *)(vsink + nv), *iup = iext + nv, *idn = iup + nv; // reach, and how far past the plane each way
    int *iown = (int *)(idn + nv), *iownb = iown + nv; // vertices mostly on their own side's bones: limb side, body side
    int *ikw = iownb + nv;                              // weight on the chains a limb cut keeps on the body (the cape)
    int *rootof = ikw + nv, *secband = rootof + nb, *secfar = secband + (u64)c.nsec * SPLIT_BANDS;
    int *secroot = secfar + (u64)c.nsec * SPLIT_BANDS, *secneck = secroot + (u64)c.nsec * MAX_LIMB_ROOTS;
    unsigned char *iflag = (unsigned char *)(secneck + c.nsec), *vkind = iflag + nv, *vroot = vkind + nv;
    unsigned char *vcn = vroot + nv, *idec = vcn + nv, *gonebone = idec + nv, *keepbone = gonebone + nb, *btype = keepbone + nb, *secore = btype + nb;
    unsigned char *vband = secore + c.nsec;          // a split's vanishing vertex: its band
    signed char *rideof = (signed char *)(vband + nv); // per bone: the band (ride bone) it rides, -1 none
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
        limb[i] = mode != MODE_SIDE && (i == b || (par >= 0 && par < i && limb[par]));
        if (par >= 0 && par < nb) haschild[par] = 1;
    }
    // a limb cut: the accessory chains Lua names ("g" with no gone roots, its kept roots) hang off the limb but stay
    // on the body, their skin on their own bones (Lua hangs their bodies on the limb's parent). CH_P_EVE_09's cape
    // hangs off the upper arm's twist bone and went off with the arm. Used by this cut only
    static unsigned char keepcut[MAX_BONES];
    int anykeep = mode == MODE_CUT && limbs_comp == comp && nkeep > 0 && nb <= MAX_BONES;
    if (anykeep) {
        for (int i = 0; i < nb; i++) {
            int par = parent_of(&c, i);
            keepcut[i] = 0;
            for (int r = 0; r < nkeep; r++) if (keep_roots[r] == i) keepcut[i] = 1;
            if (!keepcut[i] && par >= 0 && par < i) keepcut[i] = keepcut[par];
            if (keepcut[i]) limb[i] = 0;
        }
    }
    // or they go whole with the limb (the 4th group, drop roots): every vertex mostly on them is the limb's wherever it
    // lies. Kept on the body, the arm's 80 cm cape hung straight down from the shoulder where the arm had held it
    // (sixteenth playtest)
    static unsigned char withcut[MAX_BONES];
    int anywith = mode == MODE_CUT && limbs_comp == comp && ndrop > 0 && nb <= MAX_BONES;
    if (anywith) {
        for (int i = 0; i < nb; i++) {
            int par = parent_of(&c, i);
            withcut[i] = 0;
            for (int r = 0; r < ndrop; r++) if (drop_roots[r] == i) withcut[i] = 1;
            if (!withcut[i] && par >= 0 && par < i) withcut[i] = withcut[par];
            if (withcut[i]) limb[i] = 1;
        }
    }
    if (mode == MODE_CUT && limbs_comp == comp) limbs_comp = 0;
    int parent_b = parent_of(&c, b);
    for (int s = 0; s < c.nsec; s++) {
        u64 sec = secs + (u64)s * 0xe8;
        unsigned short *bmap = *(unsigned short **)(sec + SEC_BONE_MAP);
        int nbmap = *(int *)(sec + SEC_BONE_MAP + 8);
        for (int k = 0; k < nbmap; k++) if (bmap[k] < nb) { inmap[(u64)s * nb + bmap[k]] = 1; if (limb[bmap[k]]) seclimb[s] = 1; }
        secsink[s * 2] = secsink[s * 2 + 1] = -1;
    }
    for (int v = 0; v < nv; v++) vsec[v] = 0xffff;
    // the active bones: each section's BoneMap as the mesh had it (before any borrow of ours), and their ancestors
    for (int i = 0; i < MAX_BONES; i++) bactive[i] = 0;
    for (int s = 0; s < c.nsec; s++) {
        u64 arr = secs + (u64)s * 0xe8 + SEC_BONE_MAP;
        unsigned short *bmap = *(unsigned short **)arr;
        int n0 = *(int *)(arr + 8);
        for (int i = 0; i < nbmfix; i++) if (bmfix[i].arr == arr && bmfix[i].num < n0) n0 = bmfix[i].num;
        for (int k = 0; k < n0; k++) for (int j = bmap[k]; j >= 0 && j < nb && !bactive[j]; j = parent_of(&c, j)) bactive[j] = 1;
    }
    int nact = 0;
    for (int i = 0; i < nb; i++) nact += bactive[i];
    act_pushed = 0;
    find_active(ld, nb, nact);

    // a bone is a stable sink candidate if its offset from the parent is still the bind pose's: helper bones
    // that animation slides around (measured 35 cm off) would drag the collapsed seam with them
    for (int i = 1; i < nb; i++) {
        int par = parent_of(&c, i);
        if (!pose_of(&c, i) || par < 0 || !pose_of(&c, par)) continue;
        if (!refpose) { stable[i] = 1; continue; }
        float dt, dc;
        stable[i] = off_bind(&c, refpose, i, &dt, &dc) && dt < STABLE_CM;
    }
    // (only her mesh is watched: an enemy's bones, or hers before 30 looks, count as still)
    int nmoved = 0;
    for (int i = 0; i < nb; i++) {
        wmoved[i] = i > 0 && watch_sm == c.sm && watch_n >= CARRY_WATCH && !(watch_dt[i] < STABLE_CM && watch_dc[i] >= CARRY_ROT_COS);
        // a helper under one that moved moves with it, still as it is against its own parent: Ab-R-Side, under the aim
        // helper Dm-R-Side-Point the animation points at the arm, took the shoulder's seam and in an animated death
        // chased the flying arm, a sheet from her shoulder to it (playtest, CH_P_EVE_29). Not past the bones Lua names
        // (Bip001, ...) or a body's: those move as she does
        int par = parent_of(&c, i);
        winh[i] = !wmoved[i] && par > 0 && par < i && wmoved[par] && !(ns && ns[par]) && !(nosink_mesh == c.sm && hasbody[par]);
        if (mode != MODE_SIDE && nosink_mesh == c.sm && drivenb[i]) winh[i] = 1; // (a split's: side_sink)
        if (winh[i]) wmoved[i] = 1;
        nmoved += wmoved[i];
    }
    // (a limb cut whose only other choice rides a body two away takes one after all, see below)
    // and a bone the GPU doesn't skin (not active) is never a sink nor a carrier, unless it can be made active
    // (nsm: the same without the watch, for a seam that finds nothing else)
    for (int i = 0; i < nb; i++) {
        nsm[i] = (ns && ns[i]) || (!act_arr && !bactive[i]);
        nsd[i] = nsm[i] || (nosink_mesh == c.sm && drivenb[i]);
        nsx[i] = nsm[i] || wmoved[i];
    }
    ns = nsx;

    // a split half: the limbs that go with the other half and the ones that stay (subtrees of Lua's roots), and what
    // kept skin lets go of ("limb" here): those limbs and every helper past the plane (the other half's sinks)
    static unsigned char onplane[MAX_BONES], dropbone[MAX_BONES];
    if (nb > MAX_BONES) { skin_result("err too many bones"); return; }
    static unsigned char spsub[MAX_BONES], spfree[MAX_BONES];
    for (int i = 0; i < nb; i++) { rootof[i] = -1; gonebone[i] = keepbone[i] = btype[i] = onplane[i] = dropbone[i] = 0; keep_to[i] = -1; spfree[i] = 0; }
    keep_to_on = 0;
    if (mode == MODE_SIDE) {
        int lim = limbs_comp == comp, brk = lim && free_spine > 0 && free_spine < nb ? free_spine : -1;
        for (int i = 0; i < nb; i++) {
            int par = parent_of(&c, i);
            if (lim) for (int r = 0; r < ngone; r++) if (gone_roots[r] == i) rootof[i] = r;
            if (rootof[i] < 0 && par >= 0 && par < i) rootof[i] = rootof[par];
            gonebone[i] = rootof[i] >= 0;
            if (lim) for (int r = 0; r < nkeep; r++) if (keep_roots[r] == i) keepbone[i] = 1;
            if (!keepbone[i] && par >= 0 && par < i) keepbone[i] = keepbone[par];
            if (lim) for (int r = 0; r < ndrop; r++) if (drop_roots[r] == i) dropbone[i] = 1;
            if (!dropbone[i] && par >= 0 && par < i) dropbone[i] = dropbone[par];
            const float *t = pose_of(&c, i);
            float h = t ? (t[4] - p[0]) * n[0] + (t[5] - p[1]) * n[1] + (t[6] - p[2]) * n[2] : 0;
            // helpers on the plane too: the other half's kept skin keeps whatever lies in front of its plane, so a
            // sink on the plane is safe only if both halves let go of it
            int helper = i > 0 && !(ns && ns[i]) && !keepbone[i];
            onplane[i] = helper && !gonebone[i] && h >= -SIDE_TOL / tm[8] && h <= SIDE_TOL / tm[8];
            if (lim && nosink_mesh == c.sm && drivenb[i] == 2 && !keepbone[i]) onplane[i] = 0, limb[i] = 1;
            else limb[i] = gonebone[i] || (helper && h < -SIDE_TOL / tm[8]) || onplane[i];
            // the other side of a broken spine: free, so kept skin lets go of it (a chain the half keeps stays)
            spsub[i] = i == brk || (par >= 0 && par < i && spsub[par]);
            if (brk > 0 && i > 0 && !keepbone[i] && (free_upper ? !spsub[i] : spsub[i])) {
                limb[i] = spfree[i] = 1;
                onplane[i] = 0;
                if (free_upper) keep_to[i] = (short)brk;
            }
        }
        if (brk > 0) keep_to_on = keep_to;
    }

    // the neck plane, for this cut only (see "h")
    int hmode = mode == MODE_SIDE && head_comp == comp ? head_mode : 0;
    float p2[3] = { 0, 0, 0 }, n2[3] = { 0, 0, 1 }, neckr2 = NECK_R * NECK_R / (tm[8] * tm[8]);
    float baser2 = NECK_BASE_R * NECK_BASE_R / (tm[8] * tm[8]), neckmid = 0;
    static unsigned char headsub[MAX_BONES], headused[MAX_BONES];
    if (hmode) {
        memset(headused, 0, sizeof headused);
        world_to_comp(tm, head_pw, p2, 0);
        world_to_comp(tm, head_nw, n2, 1);
        const float *ht = pose_of(&c, head_bone);
        if (ht) neckmid = ((ht[4] - p2[0]) * n2[0] + (ht[5] - p2[1]) * n2[1] + (ht[6] - p2[2]) * n2[2]) * 0.5f;
        for (int i = 0; i < nb; i++) {
            int par = parent_of(&c, i);
            headsub[i] = i == head_bone || (par >= 0 && par < i && headsub[par]);
        }
    }
    if (mode == MODE_SIDE && head_comp == comp) head_comp = 0;

    // a cut's limb bones that hang free of the plane (see FREE_CM): their skin goes with the limb on either side of it
    static unsigned char freeb[MAX_BONES];
    for (int i = 0; i < nb; i++) {
        freeb[i] = 0;
        if (mode != MODE_CUT || !limb[i] || i == b) continue;
        int par = parent_of(&c, i);
        if (par >= 0 && par < i && freeb[par]) { freeb[i] = 1; continue; }
        const float *t = pose_of(&c, i), *pt = par >= 0 ? pose_of(&c, par) : 0;
        if (!t || !pt) continue;
        float h = (t[4] - p[0]) * n[0] + (t[5] - p[1]) * n[1] + (t[6] - p[2]) * n[2];
        float hp = (pt[4] - p[0]) * n[0] + (pt[5] - p[1]) * n[1] + (pt[6] - p[2]) * n[2];
        freeb[i] = h > FREE_CM / tm[8] && hp > FREE_CM / tm[8];
    }

    // pass 1: original weights (mesh bone indices), skinned position, side
    unsigned char *data = *(unsigned char **)(sw + SW_DATA);
    u32 *lookup = *(u32 **)(sw + SW_LOOKUP);
    int variable = *(unsigned char *)(sw + SW_VARIABLE) && lookup;
    u32 maxinf = *(u32 *)(sw + SW_MAX_INFLUENCES);
    int wide = *(unsigned char *)(sw + SW_16BIT_INDEX) != 0;
    int nlimb = 0, nseam = 0, moved = 0, stuck = 0, unsunk = 0, vanished = 0, carried = 0, unbanded = 0, widened = 0;
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
            float sub = 0, hang = 0, kept = 0, with = 0, *x = xs + (u64)v * 3;
            for (u32 i = 0; i < cn; i++) {
                u32 li = wide ? ((unsigned short *)(data + off))[i] : data[off + i];
                unsigned char w = data[off + (wide ? 2 : 1) * cn + i];
                int mb = li < (u32)nbmap ? bmap[li] : 0;
                o->bones[i] = mb;
                o->weights[i] = w;
                if (w && mb < nb) { usage[mb]++; if (limb[mb]) sub += w; if (freeb[mb]) hang += w; if (anykeep && keepcut[mb]) kept += w; if (anywith && withcut[mb]) with += w; }
            }
            skin_point(&c, o, (const float *)(pos + (u64)v * pstride), x);
            float d[3] = { x[0] - p[0], x[1] - p[1], x[2] - p[2] }, h = d[0] * n[0] + d[1] * n[1] + d[2] * n[2];
            float q2 = d[0] * d[0] + d[1] * d[1] + d[2] * d[2] - h * h; // squared distance from the axis
            // mostly on a kept accessory chain: on the body, wherever it lies (its edge on the arm too)
            if (mode == MODE_CUT) side[v] = (sub > 0 && (h > 0 || hang > 127) && kept <= 127) || with > 127;
            // wholly on an earlier cut's sink: collapsed already, a triangle of only such vertices starts no seam of
            // this cut (vkind 9, MODE_CUT only). A statue's thigh seam lay on a lump helper of its upper body; the
            // waist cut after it took the collapsed thigh's triangles for its own seam and drew the cut-off leg's
            // opening 72 cm up to its plane. (One with skin still showing does: a cape's edge by the arm's seam)
            if (mode == MODE_CUT) {
                int all = o->weights[0] > 0;
                for (u32 i = 0; i < cn && all; i++) if (o->weights[i] && !own_sink(&c, o->bones[i])) all = 0;
                if (all) vkind[v] = 9;
            }
            else if (mode == MODE_WHOLE) side[v] = 1;
            else if (mode == MODE_PLANE) side[v] = h > 0 && (sub > 0 || (r2 > 0 && q2 < r2));
            else side[v] = 0;
            if (mode == MODE_SIDE) {
                // the other half's limbs go wherever they are, ours stay wherever they are, the torso by the plane
                int wg = 0, wk = 0, wh = 0, wd = 0, top = -1, topw = 0;
                for (u32 i = 0; i < cn; i++) {
                    int mb = o->bones[i];
                    unsigned char w = o->weights[i];
                    if (!w || mb >= nb) continue;
                    if (gonebone[mb]) { wg += w; if (w > topw) { topw = w; top = rootof[mb]; } }
                    if (keepbone[mb]) wk += w;
                    if (dropbone[mb]) wd += w;
                    if (hmode && headsub[mb]) wh += w;
                }
                vkind[v] = wg > 127 ? 2 : wk > 127 ? 0 : wd > 127 || h <= -SHEET_FAR / tm[8] ? 3 : h <= 0 ? 1 : 0;
                if (hmode && wg <= 127 && wk <= 127 && wd <= 127) {
                    float e[3] = { x[0] - p2[0], x[1] - p2[1], x[2] - p2[2] }, h2 = e[0] * n2[0] + e[1] * n2[1] + e[2] * n2[2];
                    float rad2 = e[0] * e[0] + e[1] * e[1] + e[2] * e[2] - h2 * h2;
                    int inr = rad2 < (h2 > neckmid ? neckr2 : baser2);
                    int head = (inr && h2 > 0) || wh > 127;
                    // the shave (neck_shave): how deep past the plane the neck is kept this far up it (smoothstep)
                    int shaved = 0;
                    if (hmode == HEAD_KEEP && head && wh <= 127 && h <= 0 && h2 > 0 && neck_shave_h > 0) {
                        float u = h2 * tm[8] / neck_shave_h;
                        if (u < 1) {
                            float k = u * u * (3 - 2 * u);
                            shaved = -h * tm[8] > neck_shave + (NECK_R - neck_shave) * k;
                        }
                    }
                    if (shaved) head = 0;
                    if (head || (inr && h <= 0 && h2 > -NECK_BAND / tm[8]))
                        for (u32 i = 0; i < cn; i++) if (o->weights[i] && o->bones[i] < nb) headused[o->bones[i]] = 1;
                    if (hmode == HEAD_KEEP) {
                        if (head) vkind[v] = 0;
                        else if (shaved || (inr && h <= 0 && h2 > -NECK_BAND / tm[8])) vkind[v] = 4;
                    } else if (head) vkind[v] = 4;
                }
                vroot[v] = (unsigned char)(top < 0 ? 0 : top);
                if (vkind[v]) { seam[v] = 1; vanished++; }
            }
            if (side[v] && !seclimb[s]) { side[v] = 0; seam[v] = 1; vanished++; }
        }
    }
    // a helper the head's skin hangs on is the head's, wherever it lies (CH_P_EVE_09's Ab-NeckSub swings past the plane
    // when she is posed): the kept head lets go of nothing
    // (but not one the broken spine lets go of: it is free)
    if (hmode) for (int i = 0; i < nb; i++) if (headused[i] && !gonebone[i] && !spfree[i]) limb[i] = onplane[i] = 0;

    // pass 2: triangles across the cut
    if (mode != MODE_SIDE)
        for (int i = 0; i + 2 < ni; i += 3) {
            u32 a = ix[i], e = ix[i + 1], f = ix[i + 2];
            if (a >= (u32)nv || e >= (u32)nv || f >= (u32)nv) continue;
            if (vkind[a] == 9 && vkind[e] == 9 && vkind[f] == 9) continue;
            if (side[a] != side[e] || side[a] != side[f]) seam[a] = seam[e] = seam[f] = 1;
        }

    // sinks, per section and side, near the joint (PLANE: the plane point)
    sink_args sa = { &c, limb, stable, haschild, usage, b, parent_b, mode, { p[0], p[1], p[2] }, { p[0], p[1], p[2] }, { n[0], n[1], n[2] },
                     ns, gonebone, keepbone, mode == MODE_SIDE ? onplane : 0, mode == MODE_SIDE ? secs : 0, btype, 0, 0, -1, 0, -1, 0, 0, { -1, -1 }, 0, 0 };
    if (mode == MODE_CUT) { const float *t = pose_of(&c, b); if (t) { sa.joint[0] = t[4]; sa.joint[1] = t[5]; sa.joint[2] = t[6]; } }
    if (mode == MODE_CUT && nmoved) sa.moved = wmoved;
    // (never a driven bone: physics throws it about, and the skin sunk on it stretched with it)
    if (mode == MODE_SIDE) sa.nosink_still = nsd;
    static short gov[MAX_BONES];
    if (mode == MODE_CUT && nosink_mesh == c.sm && nbodies) {
        for (int i = 0; i < nb; i++) { int pa = parent_of(&c, i); gov[i] = hasbody[i] ? (short)i : pa >= 0 && pa < i ? gov[pa] : -1; }
        sa.gov = gov; sa.refbody[0] = parent_b >= 0 ? gov[parent_b] : -1; sa.refbody[1] = gov[b];
    }

    // hanging pieces (see "Only the body is cut" above): which sections go round the cut, from the seam as it is now
    int islands_moved = 0, classified = 0;
    if (mode == MODE_CUT || mode == MODE_PLANE) {
        int m = 0;
        for (int v = 0; v < nv; v++) {
            if (!seam[v] || vsec[v] == 0xffff) continue;
            for (int k = 0; k < 3; k++) rimpos[(u64)m * 3 + k] = xs[(u64)v * 3 + k];
            rimsec[m++] = vsec[v];
        }
        if (m >= 3 && core_classify(rimpos, rimsec, m, p, n) > 0) {
            int any_off = 0;
            classified = 1;
            for (int s = 0; s < c.nsec; s++) {
                secore[s] = s >= MAX_RIM_SECTIONS || !core_count[s] || core_keep[s];
                if (!secore[s]) any_off = 1;
            }
            if (any_off) {
                int *iside = vsink; // limb side vertices per island (vsink is the split's, later)
                for (int v = 0; v < nv; v++) { upar[v] = v; icnt[v] = iwl[v] = iwb[v] = iside[v] = 0; iext[v] = iup[v] = idn[v] = 0; iown[v] = iownb[v] = ikw[v] = 0; iflag[v] = idec[v] = 0; }
                for (int i = 0; i + 2 < ni; i += 3) {
                    u32 a = ix[i], e = ix[i + 1], f = ix[i + 2];
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
                    iside[r] += side[v] != 0;
                    int wl = 0, wb = 0;
                    for (int i = 0; i < MAX_INF; i++) {
                        int mb = out[v].bones[i];
                        unsigned char w = out[v].weights[i];
                        if (!w || mb < 0 || mb >= nb) continue;
                        if (limb[mb]) wl += w; else wb += w;
                        if (anykeep && keepcut[mb]) ikw[r] += w;
                    }
                    iwl[r] += wl; iwb[r] += wb;
                    if (side[v] ? wl > wb : wb > wl) { if (side[v]) iown[r]++; else iownb[r]++; }
                    iflag[r] |= (unsigned char)((seam[v] ? 1 : 0) | (side[v] ? 2 : 4));
                    const float *x = xs + (u64)v * 3;
                    float d2 = (x[0] - p[0]) * (x[0] - p[0]) + (x[1] - p[1]) * (x[1] - p[1]) + (x[2] - p[2]) * (x[2] - p[2]);
                    if (d2 > iext[r]) iext[r] = d2;
                    float dp = (x[0] - p[0]) * n[0] + (x[1] - p[1]) * n[1] + (x[2] - p[2]) * n[2];
                    if (dp > iup[r]) iup[r] = dp;
                    if (-dp > idn[r]) idn[r] = -dp;
                }
                // 1 body side whole, 2 limb side whole, 0 cut like the body. Nearly all of its weight on one side: that
                // side. Else nearly all of its vertices on one side, or small: the side holding most of them (a strap
                // over the shoulder weighted 2:1 to the arm but lying on the chest stays on the chest). It vanished
                // whole into a sink before, which read as the cut taking a piece of her outfit (fifteenth playtest);
                // a big one with little on the other side (the cape, 9% of it past an arm cut) got a seam that tore
                // it across the body
                float reach = ISLAND_MAX_CM / tm[8], cross = ISLAND_CROSS_CM / tm[8];
                for (int r = 0; r < nv; r++) {
                    if (!icnt[r] || !((iflag[r] & 1) || (iflag[r] & 6) == 6)) continue;
                    int tot = iwl[r] + iwb[r], mn = iwl[r] < iwb[r] ? iwl[r] : iwb[r];
                    int vl = iside[r], vb = icnt[r] - vl, vmn = vl < vb ? vl : vb;
                    // reaching well past the plane both ways, with a real share of it on each: cut like the body. Sent
                    // whole, a waist cut's belt straps stood up off her hips like horns where her back had been and a
                    // harness piece 16 cm down her hips went with the upper body, leaving a gap (seventeenth playtest).
                    // The cape past an arm cut (9% of its vertices on the arm) still goes whole, and so does a piece
                    // on one side's bones alone wherever it lies
                    if ((long long)mn * 100 > (long long)tot * ISLAND_PURE_PCT && iup[r] > cross && idn[r] > cross
                        && vmn * 100 > icnt[r] * ISLAND_MINOR_PCT) continue;
                    // the same for a piece tied to both by weight, however few of its vertices lie past the plane (4.5
                    // cm both ways: an arm cut's sleeve edges, 3.4 cm over, cut that way left a stump half open):
                    // CH_P_EVE_29's side panels (22-30% of their weight on the upper body, 8-12% of their vertices over
                    // a waist cut) went whole with the legs, their tops standing 6-8 cm up off her hips where her
                    // torso had been, stretched and open (thirty-seventh playtest). Only when its few vertices over there
                    // stay close to the plane: the cape past an arm cut (18% of its weight on the arm, its 9% of vertices
                    // there hanging 67 cm down the arm) still goes whole
                    float mreach = vl < vb ? iup[r] : idn[r];
                    if ((long long)mn * 100 > (long long)tot * ISLAND_MINOR_PCT && iup[r] > cross * ISLAND_TIED_REACH
                        && idn[r] > cross * ISLAND_TIED_REACH && mreach <= cross * ISLAND_TIED_MAX) continue;
                    if ((long long)mn * 100 <= (long long)tot * ISLAND_MINOR_PCT) idec[r] = iwl[r] > iwb[r] ? 2 : 1;
                    // its few vertices past the plane reaching far down the other side, most of them on that side's
                    // bones: cut like the body. Sent whole, they lost those weights to the other side's: CH_P_EVE_14's
                    // leg laces (14% of their vertices 62 cm down the thigh, on the leg's bones) went with her body,
                    // the knee's skin glued to her spine, a sheet from the severed leg to her (playtest screenshot). The
                    // cape past an arm cut, on its own chain's bones kept on the body, still goes whole
                    else if (mreach > cross * ISLAND_TIED_MAX && (vl < vb ? iown[r] : iownb[r]) * 2 > vmn && !ikw[r]) continue;
                    else if (vmn * 100 <= icnt[r] * ISLAND_MINOR_PCT || (icnt[r] <= ISLAND_MAX_VERTS && iext[r] <= reach * reach))
                        idec[r] = vl > vb ? 2 : 1;
                }
                for (int r = 0; r < nv; r++) islands_moved += idec[r] == 1 || idec[r] == 2;
#ifdef SBSLICE_HOSTED
                if (getenv("ISLANDS")) for (int r = 0; r < nv; r++) if (icnt[r] > 20 && ((iflag[r] & 1) || (iflag[r] & 6) == 6))
                    fprintf(stderr, "island %d sec %d: %d verts (%d limb side, %d / %d on their side's bones), weight limb %d body %d kept chains %d, up %.1f down %.1f reach %.1f -> %d\n",
                        r, vsec[r], icnt[r], iside[r], iown[r], iownb[r], iwl[r], iwb[r], ikw[r], iup[r] * tm[8], idn[r] * tm[8], __builtin_sqrtf(iext[r]) * tm[8], idec[r]);
#endif
                for (int v = 0; v < nv; v++) {
                    int s = vsec[v];
                    if (s == 0xffff || secore[s]) continue;
                    int d = idec[uf_find(upar, v)];
                    if (d == 1 || d == 2) { side[v] = (unsigned char)(d == 2); seam[v] = 0; }
                }
            }
        }
    }
    // a forced sink (a borrowed bone) for every section with seam vertices, added to its BoneMap if needed: a split
    // half's vanishing side, or a cut's limb side (the head's on her face mesh, which knows no bone past the head:
    // made to follow the head, its seam closes there and the face's neck stays on her)
    int borrowed = 0, fsd = mode == MODE_CUT ? 1 : 0;
    if (forced_sink > 0) {
        for (int v = 0; v < nv; v++) {
            if (!seam[v] || vsec[v] == 0xffff || (mode == MODE_CUT && !side[v])) continue;
            int s = vsec[v];
            if (secsink[s * 2 + fsd] != -1) continue;
            if (!inmap[(u64)s * nb + forced_sink]) {
                if (!borrow_bone(secs, s, forced_sink, inmap, nb)) continue; // left to find_sink
                borrowed++;
            }
            secsink[s * 2 + fsd] = forced_sink;
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
            if (secsink[s * 2 + sd] != -1) continue;
            // a piece cut like the body that doesn't go round the cut (a cape torn off a shoulder piece): its seam
            // lies wherever the piece crosses, not at the joint, so its sink is the one nearest that seam. Picked
            // by the joint, the cape's seam on the shoulder collapsed onto a biceps helper 15 cm down the arm and
            // stretched the cape's edge to it (sixteenth playtest)
            float j0[3] = { sa.joint[0], sa.joint[1], sa.joint[2] };
            if (mode == MODE_CUT && classified && s < MAX_RIM_SECTIONS && !secore[s]) {
                float cen[3] = { 0, 0, 0 };
                int cn = 0;
                for (int u = 0; u < nv; u++) {
                    if (!seam[u] || vsec[u] != s || side[u] != sd) continue;
                    for (int k = 0; k < 3; k++) cen[k] += xs[(u64)u * 3 + k];
                    cn++;
                }
                for (int k = 0; k < 3; k++) sa.joint[k] = cen[k] / (float)cn;
                secsink[s * 2 + sd] = find_sink(&sa, s, sd);
            } else secsink[s * 2 + sd] = find_sink(&sa, s, sd);
            {
                // none of that side in its BoneMap (a waist cut's harness piece knows only Spine, the cut's parent,
                // on the hips; a skull's body section knows only the head bone past a beheading's plane): the nearest
                // helper of that side is borrowed into it, or its seam stays on Spine and stretches to the upper
                // body's sink as it falls, or that side of the section vanishes (the skull's whole face did)
                // (still none: every helper of that side moved while she played, a long watch saw them all, or a driver
                // moves it. A moving sink drags its seam's point a little; with none the seam kept its old weights and
                // stretched between the halves of a waist cut, playtest 30, after an arm or the head had come off, or
                // the limb side vanished whole. So again with those the watch saw allowed, then the driven ones too:
                // one in its BoneMap, else one borrowed)
                for (int pass = 0; pass < 3 && secsink[s * 2 + sd] < 0 && mode == MODE_CUT; pass++) {
                    const unsigned char *bns = pass == 2 ? nsm : pass ? nsd : ns;
                    if (pass && !nmoved) break;
                    if (pass) {
                        sink_args sm = sa;
                        sm.nosink = bns;
                        if ((secsink[s * 2 + sd] = find_sink(&sm, s, sd)) >= 0) break;
                    }
                    int best = -1;
                    float bd = 1e30f;
                    for (int i = 1; i < nb; i++) {
                        if (inmap[(u64)s * nb + i] || limb[i] != sd || i == b || i == parent_b || (bns && bns[i]) || is_sink(&c, i)) continue;
                        const float *t = pose_of(&c, i);
                        if (!t) continue;
                        float d0 = t[4] - sa.joint[0], d1 = t[5] - sa.joint[1], d2 = t[6] - sa.joint[2];
                        float h = (t[4] - p[0]) * n[0] + (t[5] - p[1]) * n[1] + (t[6] - p[2]) * n[2];
                        float score = (d0 * d0 + d1 * d1 + d2 * d2) * (stable[i] ? 1.0f : 16.0f) * (haschild[i] ? 4.0f : 1.0f)
                            * ((sd ? h < 0 : h > 0) ? 16.0f : 1.0f);
                        if (score < bd) { bd = score; best = i; }
                    }
                    if (best > 0 && borrow_bone(secs, s, best, inmap, nb)) secsink[s * 2 + sd] = best;
                }
                // the one it has rides another body than its side's stump, or the animation moves it: the seam's point
                // would move against the opening and stretch it. A helper that held still on the stump's own body is
                // borrowed in instead (the spine's Ab-AX3T for a thigh on CH_P_EVE_10; the hip's correctives moved
                // while she played and a chest helper took the seam, twenty-seventh playtest). The carrier's candidates
                // (the parent's own children) come last, the carrier needs one
                int cur = secsink[s * 2 + sd];
                if (cur >= 0 && sa.gov && !is_sink(&c, cur) && body_hops(&c, gov, gov[cur], sa.refbody[sd]) > 0) {
                    // (one body over, still, when the stump's own body has none: CH_P_EVE_09's spine has no helper.
                    // With neither and the one it has two bodies off, a moved one of the next body: it moves the
                    // point a few cm, the chest helper took it the whole thigh's length)
                    int best = -1, curh = body_hops(&c, gov, gov[cur], sa.refbody[sd]);
                    float bd = 1e30f;
                    for (int pass = 0; pass < 2 && best < 0; pass++) for (int i = 1; i < nb; i++) {
                        if (limb[i] != sd || i == b || i == parent_b || is_sink(&c, i) || is_proj_sink(&c, i)) continue;
                        int mv = sa.moved && sa.moved[i];
                        // (not one that moves with a driver above it, nor a driver: Dm-R-Side-Point aims at the arm,
                        // and its Ab-R-Side took the shoulder's seam off with the flying arm, CH_P_EVE_29 playtest)
                        if (pass ? !mv || curh < 2 || (!act_arr && !bactive[i]) || (nosink_mesh == c.sm && (nosink[i] || nocarry[i])) || winh[i]
                                 : (ns && ns[i])) continue;
                        int h = body_hops(&c, gov, gov[i], sa.refbody[sd]);
                        if (!stable[i] || h > 1 || h >= curh) continue;
                        const float *t = pose_of(&c, i);
                        if (!t) continue;
                        float d0 = t[4] - sa.joint[0], d1 = t[5] - sa.joint[1], d2 = t[6] - sa.joint[2];
                        float score = (d0 * d0 + d1 * d1 + d2 * d2) * (parent_of(&c, i) == parent_b ? 4.0f : 1.0f) * (h ? 16.0f : 1.0f);
                        if (score < bd) { bd = score; best = i; }
                    }
                    if (best > 0 && (inmap[(u64)s * nb + best] || borrow_bone(secs, s, best, inmap, nb))) secsink[s * 2 + sd] = best;
                }
            }
            for (int k = 0; k < 3; k++) sa.joint[k] = j0[k];
        }
    // a split half's sinks: the torso just behind the plane flattens by bands along the opening (its longest in-plane
    // axis), deeper torso collapses to a point per band, the other half's limbs to a point per root; sections with a
    // borrowed bone (the face) flatten onto that alone
    int nproj = 0, npoint = 0, nheldband = 0;
    float pin[3] = { p[0] + n[0] * SHEET_IN / tm[8], p[1] + n[1] * SHEET_IN / tm[8], p[2] + n[2] * SHEET_IN / tm[8] };
    float bandc[SPLIT_BANDS][3];
    int nbands = AXIS_BANDS;
    const float *ridet[MAX_RIDE] = { 0 }; // the ride bones that have a band, as posed now
    unsigned char bandfree[MAX_RIDE] = { 0 }; // a free helper rides it (else its sheet's sinks are held on it)
    static signed char carryb[MAX_BONES];  // the band each flattening sink carries, -1 none
    // where the neck closes: on its axis, NECK_IN under the plane
    float neckc[3] = { p2[0] - n2[0] * NECK_IN / tm[8], p2[1] - n2[1] * NECK_IN / tm[8], p2[2] - n2[2] * NECK_IN / tm[8] };
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
        // the bands: with ride bones, the one each vanishing vertex (where it lands on the plane) is nearest to, as
        // the lid's triangles pick theirs, and only sinks riding that bone serve it: a sink on the pelvis had carried
        // 43 cm of the sheet up to the ribs, sinks under a clavicle swung with it, and once she bent the sheet tore
        // between them and stuck out through the lid. Else AXIS_BANDS along the opening
        int byride = limbs_comp == comp && nride > 0;
        nbands = byride ? nride : AXIS_BANDS;
        if (byride) {
            for (int k = 0; k < nride; k++) ridet[k] = pose_of(&c, ride_bones[k]);
            for (int i = 0; i < nb; i++) {
                rideof[i] = -1;
                for (int j = parent_of(&c, i), g = 0; j >= 0 && j < nb && g < nb; j = parent_of(&c, j), g++) {
                    int k = -1;
                    for (int r = 0; r < nride; r++) if (ride_bones[r] == j) k = r;
                    if (k >= 0) { rideof[i] = (signed char)k; break; }
                    if (ns && ns[j]) break; // rides a body of its own (a clavicle, a breast)
                }
            }
            // a bone no free helper rides (Spine and Spine1 carry none) still gets its band: its sheet goes on a
            // helper riding another band (else any free bone), held on the band's bone every frame (sink_hold).
            // Given to the nearest bone that had a helper, the sheet of a whole side lay on one bone (bands=1),
            // stiff while the lid bent with her spine, and came out through it in flickering patches (playtest)
            for (int k = 0; k < nride; k++) {
                int any = 0;
                for (int i = 1; i < nb && !any; i++)
                    any = rideof[i] == k && !(ns && ns[i]) && !(limb[i] && !onplane[i]) && !gonebone[i] && !keepbone[i]
                        && !(hmode && headused[i]);
                bandfree[k] = (unsigned char)any;
            }
            for (int i = 0; i < nb && i < MAX_BONES; i++) carryb[i] = -1;
            sa.rideof = rideof;
            sa.carryb = carryb;
        }
        float bsum[SPLIT_BANDS][3] = { { 0 } };
        int bcnt[SPLIT_BANDS] = { 0 };
        for (int v = 0; v < nv; v++) {
            vband[v] = 0;
            if (vkind[v] != 1 && vkind[v] != 3) continue;
            const float *x = xs + (u64)v * 3;
            float h = (x[0] - p[0]) * n[0] + (x[1] - p[1]) * n[1] + (x[2] - p[2]) * n[2], q[3];
            for (int j = 0; j < 3; j++) q[j] = x[j] - h * n[j];
            int k = 0;
            if (sa.rideof) {
                float bd = 1e30f;
                for (int r = 0; r < nride; r++) {
                    if (!ridet[r]) continue;
                    float d0 = q[0] - ridet[r][4], d1 = q[1] - ridet[r][5], d2 = q[2] - ridet[r][6], d = d0 * d0 + d1 * d1 + d2 * d2;
                    if (d < bd) { bd = d; k = r; }
                }
            } else {
                float t = (x[0] - mc[0]) * ax[0] + (x[1] - mc[1]) * ax[1] + (x[2] - mc[2]) * ax[2];
                k = (int)((t - lo_t) / span * AXIS_BANDS);
                k = k < 0 ? 0 : k >= AXIS_BANDS ? AXIS_BANDS - 1 : k;
            }
            vband[v] = (unsigned char)k;
            for (int j = 0; j < 3; j++) bsum[k][j] += q[j];
            bcnt[k]++;
        }
        // each band's middle, on the plane: where its vertices land, else (axis bands) the middle of its stretch
        for (int k = 0; k < nbands; k++) {
            if (bcnt[k]) { for (int j = 0; j < 3; j++) bandc[k][j] = bsum[k][j] / (float)bcnt[k]; continue; }
            float tc = lo_t + span * (k + 0.5f) / nbands;
            for (int j = 0; j < 3; j++) bandc[k][j] = mc[j] + ax[j] * tc;
            if (sa.rideof && ridet[k]) for (int j = 0; j < 3; j++) bandc[k][j] = ridet[k][4 + j];
            float h = (bandc[k][0] - p[0]) * n[0] + (bandc[k][1] - p[1]) * n[1] + (bandc[k][2] - p[2]) * n[2];
            for (int j = 0; j < 3; j++) bandc[k][j] -= h * n[j];
        }
        for (u64 i = 0; i < (u64)c.nsec * SPLIT_BANDS; i++) secband[i] = secfar[i] = -1;
        for (u64 i = 0; i < (u64)c.nsec * MAX_LIMB_ROOTS; i++) secroot[i] = -1;
        for (int s = 0; s < c.nsec; s++) secneck[s] = -1;
        // the whole head stays on one half: a sink weighted there (a sink is the mesh's, every half lets go of it)
        // would drag the head's skin off its bones
        if (hmode) sa.headused = headused;
        // flattening first (the opening matters most), then the limbs' points, the neck's, the deep torso's
        static const unsigned char order[4] = { 1, 2, 4, 3 };
        for (int pass = 0; pass < 4; pass++)
            for (int v = 0; v < nv; v++) {
                int s = vsec[v];
                if (vkind[v] != order[pass] || s == 0xffff || (forced_sink > 0 && secsink[s * 2] == forced_sink)) continue;
                const float *x = xs + (u64)v * 3;
                if (vkind[v] == 4) {
                    sa.band = -1;
                    if (secneck[s] == -1) secneck[s] = side_sink(&sa, s, neckc, NECK_SINK, 0);
                } else if (vkind[v] != 2) {
                    int k = vband[v];
                    int *slot = &(vkind[v] == 1 ? secband : secfar)[(u64)s * SPLIT_BANDS + k];
                    sa.band = k;
                    // deep torso or a dropped chain with no point riding its band: a point riding any band. A point
                    // shows nothing, whatever it rides; flattened, CH_P_EVE_09's neck lace stood on the copy where
                    // her neck had been, and the dropped hair chains lay pressed on the plane past the lid
                    if (*slot == -1 && vkind[v] == 1 && sa.rideof) {
                        // the sheet: a helper riding the band's bone, else (held on it) one riding another band
                        // (not just any free bone: the other half's limbs' points need some)
                        sa.carryk = k;
                        if (bandfree[k]) *slot = side_sink(&sa, s, bandc[k], 1, 0);
                        if (*slot < 0) { sa.band = ANY_BAND; *slot = side_sink(&sa, s, bandc[k], 1, 0); }
                        sa.carryk = -1;
                        if (*slot < 0) *slot = -2;
                    }
                    if (*slot == -1) *slot = side_sink(&sa, s, bandc[k], vkind[v] == 1 ? 1 : 10 + k, vkind[v] == 3 ? ANY_BAND : 0);
                } else {
                    int r = vroot[v] < MAX_LIMB_ROOTS ? vroot[v] : 0;
                    int *slot = &secroot[(u64)s * MAX_LIMB_ROOTS + r];
                    if (*slot != -1) continue;
                    // where the limb joined, on the plane, on a sink riding the spine bone nearest to it (one under
                    // the clavicle flapped the point about)
                    const float *t = pose_of(&c, gone_roots[r]);
                    float target[3] = { t ? t[4] : x[0], t ? t[5] : x[1], t ? t[6] : x[2] };
                    float h = (target[0] - p[0]) * n[0] + (target[1] - p[1]) * n[1] + (target[2] - p[2]) * n[2];
                    for (int j = 0; j < 3; j++) target[j] -= h * n[j];
                    sa.band = -1;
                    if (sa.rideof) {
                        float bd = 1e30f;
                        for (int k = 0; k < nride; k++) {
                            const float *rt = pose_of(&c, ride_bones[k]);
                            if (!rt) continue;
                            float d0 = target[0] - rt[4], d1 = target[1] - rt[5], d2 = target[2] - rt[6], d = d0 * d0 + d1 * d1 + d2 * d2;
                            if (d < bd) { bd = d; sa.band = k; }
                        }
                    }
                    // none riding that bone (the arms' nearest is the neck, the kept head's): any point will do, it
                    // shows nothing. Flattened instead, the dropped arm lay pressed on the plane, a flat hand
                    *slot = side_sink(&sa, s, target, 2 + r, sa.band >= 0 ? ANY_BAND : 0);
                }
            }
        // a section none of whose bands found a flattening sink (no free helper riding any of them): one with no band
        // to ride, else the whole half stayed (a split's copy vanished 54000 vertices, none sunk, and the split fell
        // back to a waist cut, playtest)
        for (int s = 0; s < c.nsec; s++) {
            int has = 0, v0 = -1;
            for (int k = 0; k < nbands && !has; k++) has = secband[(u64)s * SPLIT_BANDS + k] >= 0;
            if (has) continue;
            for (int v = 0; v < nv && v0 < 0; v++) if (vsec[v] == s && vkind[v] == 1) v0 = v;
            if (v0 < 0) continue;
            sa.band = -1;
            int k = vband[v0];
            sa.carryk = sa.rideof ? k : -1;
            int got = side_sink(&sa, s, bandc[k], 1, 0);
            if (got < 0) { sa.widen = 1; got = side_sink(&sa, s, bandc[k], 1, 0); sa.widen = 0; }
            sa.carryk = -1;
            if (got >= 0) { secband[(u64)s * SPLIT_BANDS + k] = got; unbanded++; }
        }
        // each vanishing vertex's sink: its own, else the nearest band of its section that flattens (a limb or deep
        // torso with no point of its own flattens rather than stays), else none (it stays: unsunk)
        for (int v = 0; v < nv; v++) {
            vsink[v] = -1;
            int s = vsec[v];
            if (!vkind[v] || s == 0xffff) continue;
            if (forced_sink > 0 && secsink[s * 2] == forced_sink) { vsink[v] = forced_sink; continue; }
            int k0 = vband[v];
            if (vkind[v] == 2) {
                int r = vroot[v] < MAX_LIMB_ROOTS ? vroot[v] : 0, k = secroot[(u64)s * MAX_LIMB_ROOTS + r];
                if (k >= 0) { vsink[v] = k; continue; }
                // no point of its own (the sheet's bands took the section's helpers): another point of the section,
                // which shows nothing either. Flattened, the dropped limb lay pressed on the plane
                for (int j = 0; j < MAX_LIMB_ROOTS && k < 0; j++) k = secroot[(u64)s * MAX_LIMB_ROOTS + j];
                for (int j = 0; j < nbands && k < 0; j++) k = secfar[(u64)s * SPLIT_BANDS + j];
                if (k < 0) k = secneck[s];
                // still none: one the watch saw move. Flattened, a whole leg lay on the plane, a third leg on the
                // copy (playtest: after a few deaths every helper of her right side had moved once)
                if (k < 0 && secroot[(u64)s * MAX_LIMB_ROOTS + r] != -3) {
                    const float *t = pose_of(&c, gone_roots[r]);
                    float target[3] = { t ? t[4] : 0, t ? t[5] : 0, t ? t[6] : 0 };
                    float h = (target[0] - p[0]) * n[0] + (target[1] - p[1]) * n[1] + (target[2] - p[2]) * n[2];
                    for (int j = 0; j < 3; j++) target[j] -= h * n[j];
                    sa.band = -1; sa.widen = 1;
                    k = t ? side_sink(&sa, s, target, 2 + r, sa.rideof ? ANY_BAND : 0) : -1;
                    sa.widen = 0;
                    secroot[(u64)s * MAX_LIMB_ROOTS + r] = k >= 0 ? k : -3;
                    if (k >= 0) widened++;
                }
                if (k >= 0) { vsink[v] = k; continue; }
            }
            if (vkind[v] == 4 && secneck[s] >= 0) { vsink[v] = secneck[s]; continue; }
            if (vkind[v] == 3 && secfar[(u64)s * SPLIT_BANDS + k0] >= 0) { vsink[v] = secfar[(u64)s * SPLIT_BANDS + k0]; continue; }
            // deep skin of a section with no point in its band nor a sheet anywhere (CH_P_EVE_29's section 4, 519
            // vertices, stood on both halves of every split, harness): any other point of the section (it shows
            // nothing), else one the watch saw move
            if (vkind[v] == 3) {
                int k = -1, has_band = 0;
                for (int j = 0; j < nbands; j++) has_band |= secband[(u64)s * SPLIT_BANDS + j] >= 0;
                if (!has_band) {
                    for (int j = 0; j < nbands && k < 0; j++) k = secfar[(u64)s * SPLIT_BANDS + j];
                    for (int j = 0; j < MAX_LIMB_ROOTS && k < 0; j++) k = secroot[(u64)s * MAX_LIMB_ROOTS + j];
                    if (k < 0) k = secneck[s];
                    if (k < 0 && secfar[(u64)s * SPLIT_BANDS + k0] != -3) {
                        sa.band = -1; sa.widen = 1;
                        k = side_sink(&sa, s, bandc[k0], 10 + k0, sa.rideof ? ANY_BAND : 0);
                        sa.widen = 0;
                        secfar[(u64)s * SPLIT_BANDS + k0] = k >= 0 ? k : -3;
                        if (k >= 0) widened++;
                    }
                    if (k >= 0) { vsink[v] = k; continue; }
                }
            }
            for (int dk = 0; dk < nbands && vsink[v] < 0; dk++)
                for (int sg = -1; sg <= 1 && vsink[v] < 0; sg += 2) {
                    int k = k0 + sg * dk;
                    if (k >= 0 && k < nbands && secband[(u64)s * SPLIT_BANDS + k] >= 0) vsink[v] = secband[(u64)s * SPLIT_BANDS + k];
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
    for (int i = 0; i < nsinks; i++) if (sinks[i].mesh == c.sm && !sinks[i].carry) drop_l[sinks[i].bone] = drop_b[sinks[i].bone] = 1;
    // a limb cut: the drivers of the limbs gone so far (fffc, as a split half's: Dm-L-Thigh-point and the hip helpers
    // under it, Ab-L-AX2) are what the animation points after the flying limb, and the body's skin that hung partly on
    // them went with it, a spike out of her hips with both legs off (playtest; 310 hip vertices on CH_P_EVE_09). The
    // body lets go of them as of the limb, onto the bone above them
    if (mode == MODE_CUT && nosink_mesh == c.sm) for (int i = 0; i < nb; i++) if (drivenb[i] == 2 && !limb[i]) drop_b[i] = 1;
    // the stub's carrier: kept skin on B's subtree (between the joint and the plane) can't stay on B, which leaves with
    // the limb, and its parent holds it where the bind pose has it: an upper arm hanging 50 degrees off the bind pose
    // left a stub swung back out towards the bind pose, its opening a 3-of-16-direction sliver 4 cm off the cut that
    // the lid and bone stub were fitted to, and she was hollow there (twenty-second playtest). The carrier is a spare
    // helper on B's parent whose matrix becomes B's as posed now, seen from the helper: that skin stays as it is and
    // moves with the parent. Borrowed into the sections that lack it. Only on the parent itself: a helper on Spine2
    // carried the shoulder's stub stiffly against the clavicle and tore it 12 cm once she bent, and a calf's stub on
    // the spine's Ab-AX3 (no free helper on the thigh) stayed behind as the thigh swung (twenty-fourth playtest);
    // with none, the stub stays on the parent as before
    int ncarry = 0, cbone = -1;
    if (mode == MODE_CUT) {
        for (int i = 0; i < nb; i++) {
            int par = parent_of(&c, i);
            carry[i] = -1;
            subb[i] = i == b || (par >= 0 && par < i && subb[par] && limb[i]);
        }
        for (int anc = parent_b; anc >= 0 && anc == parent_b; anc = -1) {
            float bd = 1e30f;
            for (int i = 1; i < nb; i++) {
                if (parent_of(&c, i) != anc || limb[i] || subb[i] || (ns && ns[i]) || (nosink_mesh == c.sm && nocarry[i]) || is_sink(&c, i) || btype[i] || !stable[i]) continue;
                int taken = 0;
                for (int k = 0; k < 2 * c.nsec && !taken; k++) taken = secsink[k] == i;
                if (taken) continue;
                const float *t = pose_of(&c, i), *pt = pose_of(&c, anc);
                if (!t || !pt || !refpose) continue;
                // turned off its bind pose against its parent, now or while she played: something drives it, and
                // would drive the stub
                float dt, dc;
                if (!off_bind(&c, refpose, i, &dt, &dc) || dc < CARRY_ROT_COS || !watched_still(&c, i) || wmoved[i]) continue;
                float d0 = t[4] - sa.joint[0], d1 = t[5] - sa.joint[1], d2 = t[6] - sa.joint[2];
                float score = (d0 * d0 + d1 * d1 + d2 * d2) * (haschild[i] ? 4.0f : 1.0f) * (1.0f + usage[i] / 200.0f);
                if (score < bd) { bd = score; cbone = i; }
            }
        }
        for (int s = 0; s < c.nsec && s < CARRY_SECTIONS; s++) {
            seccarry[s] = -1;
            if (cbone < 0) continue;
            int need = 0;
            for (int v = 0; v < nv && !need; v++) {
                if (vsec[v] != s || side[v] || seam[v]) continue;
                for (int i = 0; i < MAX_INF; i++) if (out[v].weights[i] && out[v].bones[i] < nb && subb[out[v].bones[i]]) need = 1;
            }
            if (!need || (!inmap[(u64)s * nb + cbone] && !borrow_bone(secs, s, cbone, inmap, nb))) continue;
            seccarry[s] = cbone;
            ncarry = 1;
        }
        if (ncarry) { carry[cbone] = (short)b; drop_l[cbone] = drop_b[cbone] = 1; }
    }
    for (int i = 0; i < nb; i++) if (btype[i]) drop_l[i] = drop_b[i] = 1;
    // the half that lets the head go keeps none of its skin on it: the free head spins off once she falls, and the neck
    // skin the vanilla weights still hang partly on it (CH_P_EVE_10: 557 vertices, Neck 204 / Head 51) stretched after
    // it. That weight goes to the head's nearest kept ancestor (the neck), as a gone limb's does
    if (hmode == HEAD_DROP) for (int i = 0; i < nb; i++) if (headsub[i]) drop_b[i] = 1;

    // pass 3: new weights
    for (int v = 0; v < nv; v++) {
        skin_info *o = &out[v];
        int s = vsec[v];
        if (s == 0xffff) continue;
        if (seam[v]) {
            int sink = mode == MODE_SIDE ? vsink[v] : secsink[s * 2 + side[v]];
            if (sink >= 0) {
                for (int i = 0; i < MAX_INF; i++) { o->bones[i] = 0; o->weights[i] = 0; }
                o->bones[0] = sink;
                o->weights[0] = 255;
                // the flattened sheet bends like skin: between the two bands of its section it lies between, weighted
                // by where along the spine (both put it on the same spot of the plane now). On one band's sink, the
                // sheet tore where two bands met and came out through the lid once she bent
                if (mode == MODE_SIDE && vkind[v] == 1 && sa.rideof) {
                    const float *x = xs + (u64)v * 3;
                    int ka = -1, kb = -1, prev = -1;
                    float bd = 1e30f, bt = 0;
                    for (int k = 0; k < nride; k++) {
                        if (!ridet[k] || secband[(u64)s * SPLIT_BANDS + k] < 0) continue;
                        if (prev >= 0) {
                            const float *a0 = ridet[prev] + 4, *b0 = ridet[k] + 4;
                            float ab[3] = { b0[0] - a0[0], b0[1] - a0[1], b0[2] - a0[2] }, ax2[3] = { x[0] - a0[0], x[1] - a0[1], x[2] - a0[2] };
                            float l2 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
                            float t = l2 > 0 ? (ax2[0] * ab[0] + ax2[1] * ab[1] + ax2[2] * ab[2]) / l2 : 0;
                            t = t < 0 ? 0 : t > 1 ? 1 : t;
                            float d[3] = { ax2[0] - ab[0] * t, ax2[1] - ab[1] * t, ax2[2] - ab[2] * t }, dd = d[0] * d[0] + d[1] * d[1] + d[2] * d[2];
                            if (dd < bd) { bd = dd; ka = prev; kb = k; bt = t; }
                        }
                        prev = k;
                    }
                    if (ka >= 0) {
                        int wb = (int)(bt * 255.0f + 0.5f);
                        int sa0 = secband[(u64)s * SPLIT_BANDS + ka], sb0 = secband[(u64)s * SPLIT_BANDS + kb];
                        if (wb >= 255) { o->bones[0] = sb0; }
                        else if (wb > 0) { o->bones[0] = sa0; o->weights[0] = (unsigned char)(255 - wb); o->bones[1] = sb0; o->weights[1] = (unsigned char)wb; }
                        else o->bones[0] = sa0;
                    }
                }
                nseam++;
                continue;
            }
#ifdef SBSLICE_HOSTED
            if (getenv("UNSUNK") && mode == MODE_SIDE) {
                static int shown;
                if (shown++ < 6) fprintf(stderr, "unsunk v%d sec %d kind %d band %d root %d secband %d secfar %d secneck %d\n", v, s, vkind[v], vband[v], vroot[v],
                    secband[(u64)s * SPLIT_BANDS + vband[v]], secfar[(u64)s * SPLIT_BANDS + vband[v]], secneck[s]);
            }
#endif
            unsunk++;
        }
        // an earlier cut's seam vertex: already all on its sink. Only this component's: a split's copy shares the
        // mesh asset, and a vertex of its kept half that the vanilla skin puts wholly on a helper the other half had
        // just made its sink (CH_P_EVE_09's Ab-NeckSub) stayed on it and was flattened with the other half
        {
            int all = o->weights[0] > 0;   // a split's sheet may lie between two of them
            for (int i = 0; i < MAX_INF && all; i++) if (o->weights[i] && !own_sink(&c, o->bones[i])) all = 0;
            if (all) continue;
        }
        const unsigned char *drop = side[v] ? drop_l : drop_b;
        // the stub's skin on B's subtree goes to the section's carrier whole
        int cw = 0, cb = ncarry && !side[v] && s < CARRY_SECTIONS ? seccarry[s] : -1;
        if (cb >= 0)
            for (int i = 0; i < MAX_INF; i++)
                if (o->weights[i] && o->bones[i] < nb && subb[o->bones[i]]) { cw += o->weights[i]; o->weights[i] = 0; }
        int r = cw == 255 ? 1 : keep_only(&c, s, o, drop, fallback_bone(&c, s, side[v] || mode == MODE_SIDE ? b : parent_b, drop));
        if (cw) {
            int slot = -1;
            for (int k = 0; k < MAX_INF; k++) if (o->weights[k] && o->bones[k] == cb) slot = k;
            if (slot < 0) for (int k = 0; k < MAX_INF; k++) if (!o->weights[k]) { slot = k; o->bones[k] = cb; break; }
            if (slot >= 0) o->weights[slot] = (unsigned char)(o->weights[slot] + cw);
            r = 1;
            carried++;
        }
        if (r > 0) moved++;
        else if (r < 0) stuck++;
    }
    c.carry = ncarry ? carry : 0;

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
            u32 t[3] = { ix[i], ix[i + 1], ix[i + 2] };
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
    // the bone each side's opening rides: the one carrying most of that side's rim (sinks collapse, so not those).
    // A thigh's body side rides the hip's twist helpers, which follow the leg, not the pelvis the stump hangs off
    // (the stub on the pelvis slid to the edge of the stump as she moved, fifteenth playtest)
    int ride_bone[2] = { -1, -1 };
    if (mode == MODE_CUT || mode == MODE_PLANE) {
        for (int pass = 0; pass < 2; pass++) {
            for (int i = 0; i < nb; i++) usage[i] = 0;
            for (int v = 0; v < nv; v++) {
                if (!rim[v] || side[v] != pass) continue;
                for (int i = 0; i < MAX_INF; i++) {
                    int bb = out[v].bones[i];
                    if (out[v].weights[i] && bb < nb && !is_sink(&c, bb)) usage[bb] += out[v].weights[i];
                }
            }
            int top = 0;
            for (int i = 0; i < nb; i++) if (usage[i] > top) { top = usage[i]; ride_bone[pass] = i; }
        }
    }

    tarray arr = { out, nv, nv };
    tc1 = __builtin_ia32_rdtsc();
    ((set_override_fn)(exe + RVA_SET_SKIN_WEIGHT_OVERRIDE))(comp, lod, &arr);
    tc2 = __builtin_ia32_rdtsc();

    // does the opening go round the plane point? A chain cut off on its own (a cape off her shoulder: its plane through
    // the chain's parent bone, inside her) crosses the plane off to one side of that point, and its seam drawn to the
    // point stretched the cloth's cut edge in towards her as a band past the cut (playtest). Then each section's seam
    // goes to the middle of its own rim on the plane instead. The rim's directions round the point, in 36 bins
    int round_p = 1;
    if (mode == MODE_CUT && nrim[0] + nrim[1] >= 3) {
        float ax[3] = { 1, 0, 0 };
        if (n[0] * n[0] > 0.5f) { ax[0] = 0; ax[1] = 1; }
        float d0 = ax[0] * n[0] + ax[1] * n[1] + ax[2] * n[2], ua[3], ub[3];
        for (int k = 0; k < 3; k++) ua[k] = ax[k] - d0 * n[k];
        float ul = __builtin_sqrtf(ua[0] * ua[0] + ua[1] * ua[1] + ua[2] * ua[2]);
        for (int k = 0; k < 3; k++) ua[k] /= ul;
        ub[0] = n[1] * ua[2] - n[2] * ua[1]; ub[1] = n[2] * ua[0] - n[0] * ua[2]; ub[2] = n[0] * ua[1] - n[1] * ua[0];
        unsigned char bins[36] = { 0 };
        for (int r = 0; r < nrim[0] + nrim[1]; r++) {
            const float *q = rimpos + (u64)r * 3;
            float d[3] = { q[0] - p[0], q[1] - p[1], q[2] - p[2] };
            float x = d[0] * ua[0] + d[1] * ua[1] + d[2] * ua[2], y = d[0] * ub[0] + d[1] * ub[1] + d[2] * ub[2];
            if (x * x + y * y < 0.25f) continue;
            // (a diamond angle, 0..4 round the circle: no atan2 without the CRT)
            float da = y >= 0 ? (x >= 0 ? y / (x + y) : 1 - x / (-x + y)) : (x < 0 ? 2 - y / (-x - y) : 3 + x / (x - y));
            int bi = (int)(da * 9.0f);
            bins[bi < 0 ? 0 : bi > 35 ? 35 : bi] = 1;
        }
        int filled = 0;
        for (int k = 0; k < 36; k++) filled += bins[k];
        round_p = filled >= 27;
    }
    // the new sinks, kept for skin_restore; "k" collapses them (zero scale at their own origin)
    int nnew = 0, full = 0, moved_sinks = 0, own_mid = 0;
    for (int i = 0; i < 2 * c.nsec; i++) {
        int bone = secsink[i];
        if (bone < 0) continue;
        // a stump's seam (a section round the cut, not a cape or a strap that crosses somewhere else) is held on the
        // bone its rim rides. The helper the weights sit on — a thigh twist, the spine's Ab-AX3T, a knee driver —
        // keeps being animated after the cut, and the seam point left the opening as a cone (the cut face's black
        // cavity). A piece that doesn't go round the cut keeps the sink it was given, out where that piece crosses
        int sd = i & 1, sec = i >> 1;
        int stump = mode == MODE_CUT && !(classified && sec < MAX_RIM_SECTIONS && !secore[sec]);
        int anch = -1;
        if (stump && !(bone == forced_sink && remap >= 0)) {
            anch = ride_bone[sd] >= 0 ? ride_bone[sd] : sd ? b : parent_b;
            if (anch == bone || anch < 0 || anch >= nb) anch = -1;
        }
        if (is_sink(&c, bone)) {
            if (anch >= 0)
                for (int k = 0; k < nsinks; k++)
                    if (sinks[k].mesh == c.sm && sinks[k].bone == bone && !sinks[k].carry && !sinks[k].proj && sinks[k].anchor < 0)
                        sink_anchor(&c, k, anch);
            continue;
        }
        if (nsinks >= MAX_SINKS) { full = 1; continue; }
        float *m = c.refinv + (u64)bone * 16;
        sinks[nsinks].mesh = c.sm; sinks[nsinks].comp = comp; sinks[nsinks].bone = bone; sinks[nsinks].down = 0; sinks[nsinks].proj = 0; sinks[nsinks].carry = 0; sinks[nsinks].anchor = -1; sinks[nsinks].also[0] = sinks[nsinks].also[1] = 0;
        for (int k = 0; k < 16; k++) sinks[nsinks].m[k] = m[k];
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
        // stuck out through its cap as a cone). Then the origin moved along the normal to SINK_IN inside. A limb cut's
        // seam goes to the opening's centre, SINK_IN inside: from a sink off to the side (a groin helper for a cut
        // near the knee) the skin round the opening was drawn out to the sink as a sheet. Only with her bodies sent
        // (a limb or the head: a waist cut's upper body flies off, and its seam drawn to the middle of the opening
        // took the legs' skin along)
        sinks[nsinks].at[0] = sinks[nsinks].at[1] = sinks[nsinks].at[2] = 0;
        // (a borrowed bone that will follow the master's bone "remap": its point in that bone's frame)
        const float *t = bone == forced_sink && remap >= 0 && remap < c.nspace ? c.space + (u64)remap * 12 : pose_of(&c, bone);
        if (t && mode == MODE_CUT && sa.gov) {
            float in = (i & 1) ? SINK_IN : -SINK_IN;
            // (the rim's own middle on this side, all its sections, not the plane point: on a thigh the suit's big
            // triangles left its rim 3.4 cm in from the plane and the bone 6 cm off its middle, so the seam's point,
            // SINK_IN in from the plane at the bone, lay outside the cap and drew half the suit over it, playtest)
            float at[3] = { p[0], p[1], p[2] };
            if (round_p) {
                float mc[3] = { 0, 0, 0 };
                int m = 0, r0 = sd ? nrim[0] : 0;
                for (int r = 0; r < nrim[sd]; r++) { for (int k = 0; k < 3; k++) mc[k] += rimpos[(u64)(r0 + r) * 3 + k]; m++; }
                if (m) for (int k = 0; k < 3; k++) at[k] = mc[k] / m;
            } else {
                // (this section's rim on this side, its middle put on the plane)
                float mc[3] = { 0, 0, 0 };
                int m = 0, r0 = sd ? nrim[0] : 0;
                for (int r = 0; r < nrim[sd]; r++)
                    if (rimsec[r0 + r] == sec) { for (int k = 0; k < 3; k++) mc[k] += rimpos[(u64)(r0 + r) * 3 + k]; m++; }
                if (m) {
                    for (int k = 0; k < 3; k++) mc[k] /= m;
                    // (only a rim near the plane, else the plane point: a statue's arm seam follows its weights at the shoulder, 30 cm up
                    // from a cut down the arm, and a tilted plane put its point 20 cm down the stump, a cone of skin)
                    float h = (mc[0] - p[0]) * n[0] + (mc[1] - p[1]) * n[1] + (mc[2] - p[2]) * n[2];
                    if (h <= SINK_DEEP && h >= -SINK_DEEP) {
                        for (int k = 0; k < 3; k++) at[k] = mc[k] - h * n[k];
                        own_mid++;
                    }
                }
            }
            float d[3] = { at[0] + n[0] * in - t[4], at[1] + n[1] * in - t[5], at[2] + n[2] * in - t[6] }, iq[4] = { -t[0], -t[1], -t[2], t[3] }, l[3];
            quat_rot(iq, d, l);
            for (int k = 0; k < 3; k++) sinks[nsinks].at[k] = t[8 + k] != 0 ? l[k] / t[8 + k] : 0;
            moved_sinks++;
        } else if (t && mode != MODE_WHOLE) {
            int sd = i & 1;
            float h = (t[4] - p[0]) * n[0] + (t[5] - p[1]) * n[1] + (t[6] - p[2]) * n[2], want = h;
            if (sd && h < SINK_IN) want = SINK_IN;
            else if (!sd && h > -SINK_IN) want = -SINK_IN;
            // nor deeper than SINK_DEEP: a statue's waist seam on its root (Base, 1.3 m down at its feet) drew the
            // opening into a cone out between its legs (playtest: stretched faces on enemies)
            else if (sd && h > SINK_DEEP) want = SINK_DEEP;
            else if (!sd && h < -SINK_DEEP) want = -SINK_DEEP;
            // nor outside the opening's rim: put in its middle (a lurker's waist seam on a fur tentacle's helper 60 cm
            // off to its side drew the opening out to it, playtest). A point inside the rim stays where it was
            float side_d[3] = { 0, 0, 0 };
            if (mode == MODE_CUT) {
                float mc[3] = { 0, 0, 0 }, rr = 0;
                int m = 0, r0 = sd ? nrim[0] : 0;
                for (int r = 0; r < nrim[sd]; r++)
                    if (round_p || rimsec[r0 + r] == sec) { for (int k = 0; k < 3; k++) mc[k] += rimpos[(u64)(r0 + r) * 3 + k]; m++; }
                if (m) {
                    for (int k = 0; k < 3; k++) mc[k] /= m;
                    for (int r = 0; r < nrim[sd]; r++) {
                        if (!(round_p || rimsec[r0 + r] == sec)) continue;
                        const float *x = rimpos + (u64)(r0 + r) * 3;
                        float e[3] = { x[0] - mc[0], x[1] - mc[1], x[2] - mc[2] }, eh = e[0] * n[0] + e[1] * n[1] + e[2] * n[2];
                        float e2 = 0; for (int k = 0; k < 3; k++) { float q = e[k] - eh * n[k]; e2 += q * q; }
                        if (e2 > rr) rr = e2;
                    }
                    float o[3] = { t[4] - mc[0], t[5] - mc[1], t[6] - mc[2] }, oh = o[0] * n[0] + o[1] * n[1] + o[2] * n[2], ol = 0;
                    for (int k = 0; k < 3; k++) { side_d[k] = o[k] - oh * n[k]; ol += side_d[k] * side_d[k]; }
                    if (ol > rr) { for (int k = 0; k < 3; k++) side_d[k] = -side_d[k]; if (want == h) want = h + 1e-4f; }
                    else for (int k = 0; k < 3; k++) side_d[k] = 0;
                }
            }
            if (want != h) {
                float d[3] = { (want - h) * n[0] + side_d[0], (want - h) * n[1] + side_d[1], (want - h) * n[2] + side_d[2] }, iq[4] = { -t[0], -t[1], -t[2], t[3] }, l[3];
                quat_rot(iq, d, l);
                for (int k = 0; k < 3; k++) sinks[nsinks].at[k] = t[8 + k] != 0 ? l[k] / t[8 + k] : 0;
                moved_sinks++;
            }
        }
        sink_anchor(&c, nsinks, anch);
        nsinks++; nnew++;
    }
    // a split half's own sinks: flattening ones, and points where the other half's limbs joined
    for (int i = 0; i < nb && mode == MODE_SIDE; i++) {
        if (!btype[i] || is_sink(&c, i)) continue;
        if (nsinks >= MAX_SINKS) { full = 1; continue; }
        const float *t = pose_of(&c, i);
        if (!t) continue;
        float *m = c.refinv + (u64)i * 16;
        sinks[nsinks].mesh = c.sm; sinks[nsinks].comp = comp; sinks[nsinks].bone = i; sinks[nsinks].down = 0; sinks[nsinks].carry = 0; sinks[nsinks].anchor = -1; sinks[nsinks].also[0] = sinks[nsinks].also[1] = 0;
        for (int k = 0; k < 16; k++) sinks[nsinks].m[k] = m[k];
        if (btype[i] == 1) {
            proj_matrix(m, t, pin, n, sinks[nsinks].pm);
            sinks[nsinks].proj = 1;
            nproj++;
            // a sheet on a bone that doesn't ride its band's: held on the band's bone (g: the flattening in its frame)
            int k = sa.carryb ? carryb[i] : -1;
            const float *ta = k >= 0 && k < nride && rideof[i] != k ? pose_of(&c, ride_bones[k]) : 0;
            if (ta) {
                float ms[16], ia[16], t1[16];
                tm_mat(t, ms);
                tm_inv_mat(ta, ia);
                mat_mul(sinks[nsinks].pm, ms, t1);
                mat_mul(t1, ia, sinks[nsinks].g);
                sinks[nsinks].anchor = ride_bones[k];
                nheldband++;
            }
        } else {
            sinks[nsinks].proj = 0;
            const float *rt = btype[i] < 10 ? pose_of(&c, gone_roots[btype[i] - 2]) : 0;
            float target[3] = { rt ? rt[4] : t[4], rt ? rt[5] : t[5], rt ? rt[6] : t[6] };
            if (btype[i] >= 10 && btype[i] < 10 + SPLIT_BANDS) for (int k = 0; k < 3; k++) target[k] = bandc[btype[i] - 10][k];
            // on the plane, except the neck's point (on the neck axis, wherever the plane runs)
            float h = btype[i] == NECK_SINK ? 0 : (target[0] - pin[0]) * n[0] + (target[1] - pin[1]) * n[1] + (target[2] - pin[2]) * n[2];
            if (btype[i] == NECK_SINK) for (int k = 0; k < 3; k++) target[k] = neckc[k];
            float d[3] = { target[0] - h * n[0] - t[4], target[1] - h * n[1] - t[5], target[2] - h * n[2] - t[6] };
            float iq[4] = { -t[0], -t[1], -t[2], t[3] }, l[3];
            quat_rot(iq, d, l);
            for (int k = 0; k < 3; k++) sinks[nsinks].at[k] = t[8 + k] != 0 ? l[k] / t[8 + k] : 0;
            npoint++;
        }
        nsinks++; nnew++;
    }
    // the carriers: B as posed now, in the carrier's frame (row vectors: bind -> B's frame -> component -> carrier)
    for (int i = 0; i < nb && ncarry; i++) {
        if (carry[i] < 0) continue;
        if (nsinks >= MAX_SINKS) { full = 1; continue; }
        const float *tb = pose_of(&c, carry[i]), *tc = pose_of(&c, i), *mb = c.refinv + (u64)carry[i] * 16;
        if (!tb || !tc) continue;
        float *m = c.refinv + (u64)i * 16, f[4][3];
        sinks[nsinks].mesh = c.sm; sinks[nsinks].comp = comp; sinks[nsinks].bone = i; sinks[nsinks].down = 0;
        sinks[nsinks].proj = 1; sinks[nsinks].carry = 1; sinks[nsinks].anchor = -1; sinks[nsinks].also[0] = sinks[nsinks].also[1] = 0;
        for (int k = 0; k < 16; k++) sinks[nsinks].m[k] = m[k];
        for (int e = 0; e < 4; e++) {
            float vp[3] = { e == 0, e == 1, e == 2 }, r[3], x[3];
            if (e == 3) vp[0] = vp[1] = vp[2] = 0;
            for (int k = 0; k < 3; k++) r[k] = vp[0] * mb[k] + vp[1] * mb[4 + k] + vp[2] * mb[8 + k] + mb[12 + k];
            comp_to_world(tb, r, x);
            world_to_comp(tc, x, f[e], 0);
        }
        float *pm = sinks[nsinks].pm;
        for (int e = 0; e < 3; e++) { for (int k = 0; k < 3; k++) pm[e * 4 + k] = f[e][k] - f[3][k]; pm[e * 4 + 3] = 0; }
        for (int k = 0; k < 3; k++) pm[12 + k] = f[3][k];
        pm[15] = 1;
        nsinks++; nnew++;
    }

    char *msg = mem_alloc(16384);
    if (!msg) { skin_result("err out of memory"); return; }
    char *o = msg;
    o = put(o, "ok verts="); o = put_int(o, nv);
    o = put(o, " mode="); o = put_int(o, mode);
    o = put(o, " limb="); o = put_int(o, nlimb);
    o = put(o, " seam="); o = put_int(o, nseam);
    o = put(o, " vanished="); o = put_int(o, vanished);
    o = put(o, " unsunk="); o = put_int(o, unsunk);
    if (unbanded) { o = put(o, " unbanded="); o = put_int(o, unbanded); }
    if (widened) { o = put(o, " widened="); o = put_int(o, widened); }
    o = put(o, " reweighted="); o = put_int(o, moved);
    o = put(o, " stuck="); o = put_int(o, stuck);
    if (ncarry) { o = put(o, " carried="); o = put_int(o, carried); o = put(o, " carrier="); o = put_int(o, cbone); }
    if (mode == MODE_CUT) { o = put(o, " watched="); o = put_int(o, watch_sm == c.sm ? watch_n : 0); }
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
    if (own_mid) { o = put(o, " ownmid="); o = put_int(o, own_mid); }
    int nheld = 0;
    for (int i = 0; i < nsinks; i++) if (sinks[i].mesh == c.sm && sinks[i].anchor >= 0) nheld++;
    if (nheld) { o = put(o, " held="); o = put_int(o, nheld); }
    // the active bones: where ActiveBoneIndices was found (0 not), how many bones joined it
    o = put(o, " active="); o = put_int(o, act_arr ? act_off : 0); o = put(o, "/"); o = put_int(o, act_pushed);
    if (!act_arr) { o = put(o, act_miss == 2 ? "/other" : "/none"); }
    // (hundreds of thousands of cycles: weights / override / rest, up to here)
    {
        u64 tc3 = __builtin_ia32_rdtsc();
        o = put(o, " cyc="); o = put_int(o, (long long)((tc1 - tc0) / 100000)); o = put(o, "/");
        o = put_int(o, (long long)((tc2 - tc1) / 100000)); o = put(o, "/"); o = put_int(o, (long long)((tc3 - tc2) / 100000));
    }
    if (forced_sink > 0) { o = put(o, " borrowed="); o = put_int(o, borrowed); }
    if (mode == MODE_SIDE) {
        o = put(o, " proj="); o = put_int(o, nproj); o = put(o, " point="); o = put_int(o, npoint);
        int nr = 0;
        for (int k = 0; k < MAX_RIDE; k++) nr += ridet[k] != 0;
        o = put(o, " bands="); o = put_int(o, nr ? nr : nbands); if (nr) o = put(o, "/ride");
        if (nheldband) { o = put(o, " bandheld="); o = put_int(o, nheldband); }
    }
    if (mode == MODE_CUT || mode == MODE_PLANE) {
        o = put(o, " pieces="); o = put_int(o, islands_moved);
    }
    if (mode == MODE_SIDE) {
        // the opening on the plane, one outline (see put_outline), and with a neck plane the neck's: rim points within
        // NECK_R of the neck axis that lie nearer the neck plane than the split's go to the neck
        o = put(o, " srim="); o = put_int(o, nrim[0]);
        float out_dir[3] = { -n[0], -n[1], -n[2] }, mc[3] = { 0, 0, 0 };
        int m = 0, mn = 0;
        // the neck's points after all the rim's (the split's own are packed to the front; xs is still needed)
        float *neck = nrim[0] * 2 <= nv ? rimpos + (u64)nrim[0] * 3 : 0;
        for (int i = 0; i < nrim[0]; i++) {
            float *q = rimpos + (u64)i * 3;
            if (hmode && neck) {
                float e[3] = { q[0] - p2[0], q[1] - p2[1], q[2] - p2[2] }, h2 = e[0] * n2[0] + e[1] * n2[1] + e[2] * n2[2];
                float h = (q[0] - p[0]) * n[0] + (q[1] - p[1]) * n[1] + (q[2] - p[2]) * n[2];
                if (e[0] * e[0] + e[1] * e[1] + e[2] * e[2] - h2 * h2 < (h2 > neckmid ? neckr2 : baser2) && fabsf_(h2) < fabsf_(h)) {
                    for (int k = 0; k < 3; k++) neck[(u64)mn * 3 + k] = q[k];
                    mn++;
                    continue;
                }
            }
            for (int k = 0; k < 3; k++) { rimpos[(u64)m * 3 + k] = q[k]; mc[k] += q[k]; }
            m++;
        }
        for (int k = 0; k < 3; k++) mc[k] /= (float)(m ? m : 1);
        // its longest in-plane axis, for the fit and the outline's grid
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
        float ax[3] = { ev[0][hi], ev[1][hi], ev[2][hi] }, t0 = ax[0] * out_dir[0] + ax[1] * out_dir[1] + ax[2] * out_dir[2];
        for (int k = 0; k < 3; k++) ax[k] -= t0 * out_dir[k];
        float al = ax[0] * ax[0] + ax[1] * ax[1] + ax[2] * ax[2];
        if (m >= 3 && al > 1e-8f) {
            al = rsqrt(al);
            for (int k = 0; k < 3; k++) ax[k] *= al;
            float bx[3] = { out_dir[1] * ax[2] - out_dir[2] * ax[1], out_dir[2] * ax[0] - out_dir[0] * ax[2], out_dir[0] * ax[1] - out_dir[1] * ax[0] };
            float h = (mc[0] - p[0]) * n[0] + (mc[1] - p[1]) * n[1] + (mc[2] - p[2]) * n[2];
            float pc[3] = { mc[0] - h * n[0], mc[1] - h * n[1], mc[2] - h * n[2] };
            o = put_fit(o, "s0", rimpos, m, pc, out_dir, tm, 0);
            // where the skin crosses the plane: triangles between kept and vanished vertices (above a kept head
            // everything is kept, so its section isn't part of the opening), from the posed positions
            int ns = 0;
            for (int i = 0; i + 2 < ni && ns < OUTLINE_SEGS; i += 3) {
                u32 t[3] = { ix[i], ix[i + 1], ix[i + 2] };
                if (t[0] >= (u32)nv || t[1] >= (u32)nv || t[2] >= (u32)nv) continue;
                int g = seam[t[0]] + seam[t[1]] + seam[t[2]];
                if (!g || g == 3) continue;
                float hh[3], *e = ol_segs + (u64)ns * 6;
                for (int k = 0; k < 3; k++) {
                    const float *x = xs + (u64)t[k] * 3;
                    hh[k] = (x[0] - p[0]) * n[0] + (x[1] - p[1]) * n[1] + (x[2] - p[2]) * n[2];
                }
                int got = 0;
                for (int k = 0; k < 3 && got < 2; k++) {
                    int j = (k + 1) % 3;
                    if ((hh[k] > 0) == (hh[j] > 0)) continue;
                    const float *xa = xs + (u64)t[k] * 3, *xb = xs + (u64)t[j] * 3;
                    float f = hh[k] / (hh[k] - hh[j]);
                    for (int c2 = 0; c2 < 3; c2++) e[got * 3 + c2] = xa[c2] + (xb[c2] - xa[c2]) * f;
                    got++;
                }
                if (got == 2) ns++;
            }
            o = put(o, " s0segs="); o = put_int(o, ns);
            ol_area = -1;
            for (float gap = OUTLINE_GAP; gap < 8.0f && ol_area < 0; gap *= 2)
                o = put_outline(o, "s0", rimpos, m, neck, mn, ol_segs, ns, pc, out_dir, ax, bx, tm, gap);
        }
        if (mn >= 3) {
            // the neck's opening faces the side that let go: down from the kept head, up out of the dropped one's stump
            float nd[3] = { hmode == HEAD_KEEP ? -n2[0] : n2[0], hmode == HEAD_KEEP ? -n2[1] : n2[1], hmode == HEAD_KEEP ? -n2[2] : n2[2] };
            o = put(o, " nrim="); o = put_int(o, mn);
            o = put_fit(o, "n", neck, mn, p2, nd, tm, 1);
        }
        *o = 0;
        skin_result(msg);
        mem_free(msg);
        return;
    }
    // a cut's body opening faces the limb and the limb's the body
    float *pp = p;
    float nb_dir[3] = { n[0], n[1], n[2] }, nl_dir[3] = { -n[0], -n[1], -n[2] };
    // the limb side's points go after the body side's, so filter the limb side first (it only moves inside its range)
    int nb_core = nrim[0], nl_core = nrim[1];
    char lsec[1024], *lo = core_rim(lsec, "l", rimpos + (u64)nrim[0] * 3, rimsec + nrim[0], &nl_core, pp, nl_dir);
    *lo = 0;
    o = core_rim(o, "b", rimpos, rimsec, &nb_core, pp, nb_dir);
    o = put(o, lsec);
    if (ride_bone[0] >= 0) { o = put(o, " bb="); o = put_int(o, ride_bone[0]); }
    if (ride_bone[1] >= 0) { o = put(o, " lb="); o = put_int(o, ride_bone[1]); }
    o = put_fit(o, "b", rimpos, nb_core, pp, nb_dir, tm, 1);   // body opening
    o = put_fit(o, "l", rimpos + (u64)nrim[0] * 3, nl_core, pp, nl_dir, tm, 1); // limb opening
    *o = 0;
    skin_result(msg);
    mem_free(msg);
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
        // newest first; a swapped array gets its count back before the engine's data pointer, so no reader sees our
        // count on the engine's shorter array (ours is freed on a later restore: the render thread may still be
        // reading it now)
        bm_bury();
        for (int i = nbmfix - 1; i >= 0; i--) {
            // not the array we left there: the mesh is gone (and the engine freed ours with it), leave it alone
            if (*(unsigned short **)bmfix[i].arr != bmfix[i].data) continue;
            *(int *)(bmfix[i].arr + 8) = bmfix[i].num;
            __atomic_thread_fence(__ATOMIC_SEQ_CST);
            if (bmfix[i].old) {
                *(unsigned short **)bmfix[i].arr = bmfix[i].old;
                if (nbm_dead < MAX_BONEMAP_FIX) bm_dead[nbm_dead++] = bmfix[i].data;
            }
            *(int *)(bmfix[i].arr + 12) = bmfix[i].max;
        }
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

// one look at her bones for the carriers (see watch_sm): each one's furthest slide and turn off its bind offset from
// its parent so far. A new mesh asset (another outfit) starts over
static void skin_watch(u64 comp)
{
    cut_ctx c = { 0 };
    c.sm = *(u64 *)(comp + SC_SKELETAL_MESH);
    if (!c.sm) { skin_result("err no mesh"); return; }
    c.nb = *(int *)(c.sm + SM_REF_BONE_INFO + 8);
    c.binfo = *(unsigned char **)(c.sm + SM_REF_BONE_INFO);
    float *refpose = *(float **)(c.sm + SM_REF_BONE_POSE);
    if (!c.binfo || c.nb <= 0 || c.nb > MAX_BONES || !refpose || *(int *)(c.sm + SM_REF_BONE_POSE + 8) != c.nb) {
        skin_result("err no bones"); return;
    }
    // the pose source: the master pose component when there is one, its bones matched by name
    u64 master = ((weak_get_fn)(exe + RVA_WEAK_PTR_GET))(comp + SC_MASTER_POSE);
    u64 src = master ? master : comp;
    if (master) {
        static int namemap[MAX_BONES];
        u64 msm = *(u64 *)(master + SC_SKELETAL_MESH);
        const unsigned char *mbi = msm ? *(unsigned char **)(msm + SM_REF_BONE_INFO) : 0;
        int mnb = msm ? *(int *)(msm + SM_REF_BONE_INFO + 8) : 0;
        if (!mbi || mnb <= 0) { skin_result("err no master skeleton"); return; }
        for (int i = 0; i < c.nb; i++) {
            u64 nm = *(const u64 *)(c.binfo + (u64)i * 0xc);
            namemap[i] = -1;
            for (int j = 0; j < mnb; j++) if (*(const u64 *)(mbi + (u64)j * 0xc) == nm) { namemap[i] = j; break; }
        }
        c.mmap = namemap;
    }
    c.space = *(float **)(src + SC_SPACE_BASES + (u64)*(int *)(src + SC_SPACE_READ) * 0x10);
    c.nspace = *(int *)(src + SC_SPACE_BASES + (u64)*(int *)(src + SC_SPACE_READ) * 0x10 + 8);
    if (!c.space) { skin_result("err no bone transforms"); return; }
    if (watch_sm != c.sm) {
        watch_sm = c.sm; watch_n = 0;
        for (int i = 0; i < MAX_BONES; i++) { watch_dt[i] = 0; watch_dc[i] = 1; }
    }
    for (int i = 1; i < c.nb; i++) {
        float dt, dc;
        if (!off_bind(&c, refpose, i, &dt, &dc)) { watch_dt[i] = 1e30f; continue; } // unposed: never a carrier
        if (dt > watch_dt[i]) watch_dt[i] = dt;
        if (dc < watch_dc[i]) watch_dc[i] = dc;
    }
    watch_n++;
    char msg[32] = "ok watched ";
    *put_int(msg + 11, watch_n) = 0;
    skin_result(msg);
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

// rewrite every held seam's collapse point so it sits where the anchor (the rim's bone) puts it now. The sink bone
// keeps being posed on its own — a twist, a corrective, a driver — and one inverse-bind matrix can't cancel that
// unless it is recomputed from the pose about to be skinned. comps lists the components still alive (n 0: all)
static void sink_hold(const u64 *comps, int n)
{
    static int namemap[MAX_BONES];
    u64 seen = 0;
    cut_ctx c = { 0 };
    int ok = 0;
    for (int i = 0; i < nsinks; i++) {
        if (sinks[i].anchor < 0 || sinks[i].carry) continue;
        u64 comp = sinks[i].comp;
        if (comp < 0x10000) continue;
        if (n) {
            int listed = 0;
            for (int k = 0; k < n && !listed; k++) listed = comps[k] == comp;
            if (!listed) continue;
        }
#ifndef SBSLICE_HOSTED
        if (!mem_readable(comp, SC_SPACE_READ + 8)) continue;
#endif
        if (comp != seen) {
            ok = 0; seen = comp; c = (cut_ctx){ 0 };
            c.sm = *(u64 *)(comp + SC_SKELETAL_MESH);
            if (!c.sm || c.sm != sinks[i].mesh) continue;
            c.nb = *(int *)(c.sm + SM_REF_BONE_INFO + 8);
            c.binfo = *(unsigned char **)(c.sm + SM_REF_BONE_INFO);
            c.refinv = *(float **)(c.sm + SM_REF_BASES_INV);
            if (!c.binfo || !c.refinv || c.nb <= 0 || c.nb > MAX_BONES || *(int *)(c.sm + SM_REF_BASES_INV + 8) != c.nb) continue;
            u64 master = ((weak_get_fn)(exe + RVA_WEAK_PTR_GET))(comp + SC_MASTER_POSE);
            u64 src = master ? master : comp;
            if (master) {
                u64 msm = *(u64 *)(master + SC_SKELETAL_MESH);
                const unsigned char *mbi = msm ? *(unsigned char **)(msm + SM_REF_BONE_INFO) : 0;
                int mnb = msm ? *(int *)(msm + SM_REF_BONE_INFO + 8) : 0;
                if (!mbi || mnb <= 0) continue;
                for (int b = 0; b < c.nb; b++) {
                    u64 nm = *(const u64 *)(c.binfo + (u64)b * 0xc);
                    namemap[b] = -1;
                    for (int j = 0; j < mnb; j++) if (*(const u64 *)(mbi + (u64)j * 0xc) == nm) { namemap[b] = j; break; }
                }
                c.mmap = namemap;
            }
            int rd = *(int *)(src + SC_SPACE_READ);
            if (rd < 0 || rd > 1) continue;
            c.space = *(float **)(src + SC_SPACE_BASES + (u64)rd * 0x10);
            c.nspace = *(int *)(src + SC_SPACE_BASES + (u64)rd * 0x10 + 8);
            if (!c.space || c.nspace <= 0) continue;
            ok = 1;
        }
        if (!ok || sinks[i].mesh != c.sm || sinks[i].bone < 0 || sinks[i].bone >= c.nb || sinks[i].anchor >= c.nb) continue;
        const float *ts = pose_of(&c, sinks[i].bone), *ta = pose_of(&c, sinks[i].anchor);
        if (!ts || !ta) continue;
        if (sinks[i].proj) {
            float ma[16], is[16], t1[16];
            tm_mat(ta, ma);
            tm_inv_mat(ts, is);
            mat_mul(sinks[i].g, ma, t1);
            mat_mul(t1, is, sinks[i].pm);
            if (sinks[i].down) { float *m = c.refinv + (u64)sinks[i].bone * 16; for (int k = 0; k < 16; k++) m[k] = sinks[i].pm[k]; }
            continue;
        }
        float cs[3];
        cs_of_local(ta, sinks[i].ap, cs);
        local_of_cs(ts, cs, sinks[i].at);
        if (!sinks[i].down) continue;
        float *m = c.refinv + (u64)sinks[i].bone * 16;
        m[12] = sinks[i].at[0]; m[13] = sinks[i].at[1]; m[14] = sinks[i].at[2];
    }
}

// collapse every sink recorded but not yet collapsed
static int skin_collapse(void)
{
    sink_hold(0, 0); // the pose may already have moved since the cut was recorded
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

// a component's weights as the GPU skins it (its override, else the mesh's), into out (nv of them; 0: the count only)
static const char *read_weights(u64 src, int lod, skin_info *out, int *pnv)
{
    u64 sm = *(u64 *)(src + SC_SKELETAL_MESH);
    if (!sm) return "err no mesh";
    u64 rd = *(u64 *)(src + SC_MESH_OBJECT) ? *(u64 *)(*(u64 *)(src + SC_MESH_OBJECT) + 0x40) : *(u64 *)(sm + SM_RENDER_DATA);
    if (!rd || lod < 0 || lod >= *(int *)(rd + 8)) return "err no render data for lod";
    u64 ld = ((u64 *)*(u64 *)rd)[lod];
    u64 sw = ((get_buffer_fn)(exe + RVA_GET_SKIN_WEIGHT_BUFFER))(src, lod);
    int nv = *(int *)(ld + LOD_NUM_VERTICES);
    if (!sw || !*(u64 *)(sw + SW_DATA) || *(int *)(sw + SW_NUM_VERTICES) != nv) return "err no CPU copy of skin weights";
    *pnv = nv;
    if (!out) return 0;
    {
        unsigned char *data = *(unsigned char **)(sw + SW_DATA);
        u32 *lookup = *(u32 **)(sw + SW_LOOKUP);
        int variable = *(unsigned char *)(sw + SW_VARIABLE) && lookup;
        u32 maxinf = *(u32 *)(sw + SW_MAX_INFLUENCES);
        int wide = *(unsigned char *)(sw + SW_16BIT_INDEX) != 0;
        u64 secs = *(u64 *)(ld + LOD_SECTIONS);
        int nsec = *(int *)(ld + LOD_SECTIONS + 8);
        for (int s = 0; s < nsec; s++) {
            u64 sec = secs + (u64)s * 0xe8;
            int base = *(int *)(sec + SEC_BASE_VERTEX), cnt = *(int *)(sec + SEC_NUM_VERTICES);
            unsigned short *bmap = *(unsigned short **)(sec + SEC_BONE_MAP);
            int nbmap = *(int *)(sec + SEC_BONE_MAP + 8);
            for (int v = base; v < base + cnt && v < nv; v++) {
                u32 off, cn;
                if (variable) { off = lookup[v] >> 8; cn = lookup[v] & 0xff; }
                else { off = (wide ? 3 : 2) * maxinf * (u32)v; cn = maxinf; }
                if (cn > MAX_INF) cn = MAX_INF;
                for (u32 i = 0; i < cn; i++) {
                    u32 li = wide ? ((unsigned short *)(data + off))[i] : data[off + i];
                    out[v].bones[i] = li < (u32)nbmap ? bmap[li] : 0;
                    out[v].weights[i] = data[off + (wide ? 2 : 1) * cn + i];
                }
            }
        }
    }
    return 0;
}

// "y<src>,<lod>,<dst>,...": src's weights now on copies of its mesh asset on src's pose (another mod's overlay: Ultra
// Violence draws her outfit blood on a see-through copy of her mesh). They kept her whole skin and stretched from the
// stump to the flying limb. The sinks are the asset's, shared; with no override on src, theirs go too
static void skin_copy(u64 src, int lod, const u64 *dst, int nd)
{
    char msg[48] = "ok copied ", *o = msg + 10;
    u64 sm = *(u64 *)(src + SC_SKELETAL_MESH);
    if (!sm) { skin_result("err no mesh"); return; }
    int has = lod >= 0 && lod < *(int *)(src + SC_LOD_INFO + 8) && *(u64 *)(*(u64 *)(src + SC_LOD_INFO) + (u64)lod * 0x48 + 0x18);
    tarray arr = { 0, 0, 0 };
    if (has) {
        int nv = 0;
        const char *e = read_weights(src, lod, 0, &nv);
        if (e) { skin_result(e); return; }
        skin_info *out = (skin_info *)cut_scratch(0, (u64)nv * sizeof(skin_info));
        if (!out) { skin_result("err out of memory"); return; }
        if ((e = read_weights(src, lod, out, &nv)) != 0) { skin_result(e); return; }
        arr.data = out; arr.num = arr.max = nv;
    }
    int n = 0;
    for (int i = 0; i < nd; i++) {
        u64 d = dst[i];
        if (d < 0x10000 || d == src || *(u64 *)(d + SC_SKELETAL_MESH) != sm) continue;
        if (has) {
            ((set_override_fn)(exe + RVA_SET_SKIN_WEIGHT_OVERRIDE))(d, lod, &arr);
            // src's borrowed bones followed its master's bone (the face's seam on her head): a copy on the same master
            // (Ultra Violence's face blood follows her body, the face's own master) gets the same entries, or that seam
            // stays on the borrowed bone's own transform and its blood stretched from her neck to the flying head
            int *dm = *(int **)(d + SC_MASTER_BONE_MAP), dn = *(int *)(d + SC_MASTER_BONE_MAP + 8);
            for (int r = 0, nr = nremaps; r < nr && dm; r++) {
                if (remaps[r].comp != src || remaps[r].index >= dn || dm[remaps[r].index] != remaps[r].old) continue;
                int dup = 0;
                for (int j = 0; j < nremaps; j++) if (remaps[j].comp == d && remaps[j].index == remaps[r].index) dup = 1;
                if (dup || nremaps >= MAX_REMAPS) continue;
                remaps[nremaps] = remaps[r];
                remaps[nremaps].comp = d;
                if (remaps[r].applied) dm[remaps[r].index] = remaps[r].to;
                nremaps++;
            }
            // its seams are on src's sinks now: d's own cuts must leave them there (a split's copy of a body with an
            // arm cut off put the stump's seam back on the arm, stretched out to where the arm flew)
            for (int k = 0; k < nsinks; k++)
                if (sinks[k].mesh == sm && sinks[k].comp == src && sinks[k].also[0] != d && sinks[k].also[1] != d) {
                    if (!sinks[k].also[0]) sinks[k].also[0] = d; else sinks[k].also[1] = d;
                }
        }
        else if (lod < *(int *)(d + SC_LOD_INFO + 8) && *(u64 *)(*(u64 *)(d + SC_LOD_INFO) + (u64)lod * 0x48 + 0x18)) {
            ((lodinfo_fn)(exe + RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS))(*(u64 *)(d + SC_LOD_INFO) + (u64)lod * 0x48);
            unremap(d);
            ((comp_fn)(exe + RVA_MARK_RENDER_STATE_DIRTY))(d);
        } else continue;
        n++;
    }
    o = put_int(o, n);
    for (const char *t = has ? " weights" : " cleared"; *t; t++) *o++ = *t;
    *o = 0;
    skin_result(msg);
}

// "S<comp>,<lod>" / "R<comp>,<lod>[,<other>...]": a cut that may still fail on a body cut before (a split after her
// arm came off, gore.lua's blow) saves her weights and the sinks first; R puts the weights back (or lets go of the
// override when she had none), drops what the cuts since recorded for her and the others named (the split's copy:
// sinks, borrowed BoneMap entries), puts back any of those sinks already collapsed, and the co-owners as they were.
// "x" there (on either half: the sinks are the asset's) wiped the arm cut with them (the arm grew back on its stump).
// "S<comp>,<lod>,1" forgets the save (the cut held); "r" forgets them all
#define MAX_SAVES 4
// the sinks and borrowed BoneMap entries at the save, by what they are (an enemy's "r<asset>" or another component's
// "x" meanwhile compacts the lists)
typedef struct { u64 mesh, comp, also[2]; int bone; } sink_id;
static struct { u64 comp; int lod, has, nv, nsinks, nremaps; skin_info *w; sink_id ids[MAX_SINKS]; u64 rcomp[MAX_REMAPS]; int rindex[MAX_REMAPS]; } saves[MAX_SAVES];

static void forget_saves(u64 comp)
{
    for (int i = 0; i < MAX_SAVES; i++) if (saves[i].comp && (!comp || saves[i].comp == comp)) {
        if (saves[i].w) mem_free(saves[i].w);
        saves[i].w = 0; saves[i].comp = 0;
    }
}

static int has_override(u64 comp, int lod)
{
    return lod >= 0 && lod < *(int *)(comp + SC_LOD_INFO + 8) && *(u64 *)(*(u64 *)(comp + SC_LOD_INFO) + (u64)lod * 0x48 + 0x18);
}

static void skin_save(u64 comp, int lod)
{
    int k = -1;
    for (int i = 0; i < MAX_SAVES && k < 0; i++) if (saves[i].comp == comp) k = i;
    for (int i = 0; i < MAX_SAVES && k < 0; i++) if (!saves[i].comp) k = i;
    if (k < 0) { skin_result("err no save slot"); return; }
    if (saves[k].w) { mem_free(saves[k].w); saves[k].w = 0; }
    saves[k].comp = comp; saves[k].lod = lod; saves[k].nv = 0;
    saves[k].has = has_override(comp, lod);
    if (saves[k].has) {
        int nv = 0;
        const char *e = read_weights(comp, lod, 0, &nv);
        if (!e && !(saves[k].w = (skin_info *)mem_alloc((u64)nv * sizeof(skin_info)))) e = "err out of memory";
        if (!e) e = read_weights(comp, lod, saves[k].w, &nv);
        if (e) { if (saves[k].w) mem_free(saves[k].w); saves[k].w = 0; saves[k].comp = 0; skin_result(e); return; }
        saves[k].nv = nv;
    }
    saves[k].nsinks = nsinks; saves[k].nremaps = nremaps;
    for (int i = 0; i < nsinks; i++) {
        sink_id *d = &saves[k].ids[i];
        d->mesh = sinks[i].mesh; d->comp = sinks[i].comp; d->bone = sinks[i].bone; d->also[0] = sinks[i].also[0]; d->also[1] = sinks[i].also[1];
    }
    for (int i = 0; i < nremaps; i++) { saves[k].rcomp[i] = remaps[i].comp; saves[k].rindex[i] = remaps[i].index; }
    char msg[48] = "ok saved ", *o = msg + 9;
    if (saves[k].has) o = put_int(o, saves[k].nv); else for (const char *t = "none"; *t; t++) *o++ = *t;
    *o = 0;
    skin_result(msg);
}

static int named(u64 c, u64 comp, const u64 *more, int nm)
{
    if (c == comp) return 1;
    for (int i = 0; i < nm; i++) if (more[i] == c) return 1;
    return 0;
}

static void skin_back(u64 comp, int lod, const u64 *more, int nm)
{
    int k = -1;
    for (int i = 0; i < MAX_SAVES; i++) if (saves[i].comp == comp && saves[i].lod == lod) k = i;
    if (k < 0) { skin_result("err nothing saved"); return; }
    if (saves[k].has) {
        tarray arr = { saves[k].w, saves[k].nv, saves[k].nv };
        ((set_override_fn)(exe + RVA_SET_SKIN_WEIGHT_OVERRIDE))(comp, lod, &arr);
    } else if (has_override(comp, lod))
        ((lodinfo_fn)(exe + RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS))(*(u64 *)(comp + SC_LOD_INFO) + (u64)lod * 0x48);
    // the sinks since, hers and the others named, go (a collapsed one's matrix back first); the rest stay, and the
    // ones from before get their co-owners back
    int n = 0, dropped = 0;
    for (int i = 0; i < nsinks; i++) {
        const sink_id *was = 0;
        for (int j = 0; j < saves[k].nsinks && !was; j++) {
            const sink_id *d = &saves[k].ids[j];
            if (d->mesh == sinks[i].mesh && d->comp == sinks[i].comp && d->bone == sinks[i].bone) was = d;
        }
        if (was) { sinks[i].also[0] = was->also[0]; sinks[i].also[1] = was->also[1]; }
        if (was || !named(sinks[i].comp, comp, more, nm)) { sinks[n++] = sinks[i]; continue; }
        if (sinks[i].down) {
            float *ri = *(float **)(sinks[i].mesh + SM_REF_BASES_INV);
            int num = *(int *)(sinks[i].mesh + SM_REF_BASES_INV + 8);
            if (ri && sinks[i].bone < num) for (int j = 0; j < 16; j++) ri[(u64)sinks[i].bone * 16 + j] = sinks[i].m[j];
        }
        dropped++;
    }
    nsinks = n;
    n = 0;
    for (int i = 0; i < nremaps; i++) {
        int was = 0;
        for (int j = 0; j < saves[k].nremaps && !was; j++) was = saves[k].rcomp[j] == remaps[i].comp && saves[k].rindex[j] == remaps[i].index;
        if (was || !named(remaps[i].comp, comp, more, nm)) { remaps[n++] = remaps[i]; continue; }
        int *map = *(int **)(remaps[i].comp + SC_MASTER_BONE_MAP);
        if (remaps[i].applied && map && remaps[i].index < *(int *)(remaps[i].comp + SC_MASTER_BONE_MAP + 8)) map[remaps[i].index] = remaps[i].old;
    }
    nremaps = n;
    ((comp_fn)(exe + RVA_MARK_RENDER_STATE_DIRTY))(comp);
    forget_saves(comp);
    char msg[48] = "ok back, dropped ", *o = msg + 17;
    o = put_int(o, dropped);
    *o = 0;
    skin_result(msg);
}

// keep: the asset's sinks stay collapsed (another cut component on the same asset, an enemy's, still rides them)
static void skin_clear(u64 comp, int lod, int keep)
{
    char msg[64] = "ok cleared, restored ", *o = msg + 21;
    u64 sm = keep ? 0 : *(u64 *)(comp + SC_SKELETAL_MESH);
    if (lod >= 0 && lod < *(int *)(comp + SC_LOD_INFO + 8) && *(u64 *)(*(u64 *)(comp + SC_LOD_INFO) + (u64)lod * 0x48 + 0x18))
        ((lodinfo_fn)(exe + RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS))(*(u64 *)(comp + SC_LOD_INFO) + (u64)lod * 0x48);
    o = put_int(o, sm ? skin_restore(sm) : 0);
    *o = 0;
    unremap(comp);
    ((comp_fn)(exe + RVA_MARK_RENDER_STATE_DIRTY))(comp);
    skin_result(msg);
}

// "s<comp>,<lod>": where the skin stretches now. Every vertex skinned as the GPU does (the weights in use, the mesh's
// inverse bind matrices with the collapsed sinks, the live pose), every triangle's edges against the bind pose's: a
// triangle stretches when an edge is over 3x and 15 cm longer than at bind. Reports how many, the longest edge, and
// the bones (each vertex's strongest) most of them hang on, with how far that bone's vertices got from the bone.
// hidden= counts the stretched triangles wholly on sinks (the flattened other side, meant to sit behind the lids)
// the skin as the probe posed it, to ue4ss\Mods\StellarBladeGore\probe<dump>.obj (component space, cm): every vertex,
// "vb <bone>" its strongest mesh bone after it, every triangle. To look at what a half shows in game
static void probe_obj(int dump, const float *xs, int nv, const int *top, const u32 *ix, int ni)
{
    u16 path[64];
    const char *base = "ue4ss\\Mods\\StellarBladeGore\\probe";
    int k = 0;
    while (base[k]) { path[k] = (u16)base[k]; k++; }
    path[k++] = (u16)"0123456789abcdef"[dump & 0xf];
    path[k++] = '.'; path[k++] = 'o'; path[k++] = 'b'; path[k++] = 'j'; path[k] = 0;
    HANDLE h = CreateFileW(path, 0x40000000 /*GENERIC_WRITE*/, 1, 0, 2 /*CREATE_ALWAYS*/, 0x80, 0);
    if (h == INVALID_HANDLE) return;
    static char buf[1 << 16];
    char *o = buf;
    u32 w;
    for (int i = 0; i < nv + ni / 3; i++) {
        if (o - buf > (long)sizeof buf - 128) { WriteFile(h, buf, (u32)(o - buf), &w, 0); o = buf; }
        if (i < nv) {
            const float *x = xs + (u64)i * 3;
            o = put(o, "v "); o = put_f(o, x[0]); o = put(o, " "); o = put_f(o, x[1]); o = put(o, " "); o = put_f(o, x[2]);
            o = put(o, "\nvb "); o = put_int(o, top[i]); o = put(o, "\n");
        } else {
            int t = (i - nv) * 3;
            o = put(o, "f "); o = put_int(o, ix[t] + 1); o = put(o, " "); o = put_int(o, ix[t + 1] + 1); o = put(o, " ");
            o = put_int(o, ix[t + 2] + 1); o = put(o, "\n");
        }
    }
    WriteFile(h, buf, (u32)(o - buf), &w, 0);
    CloseHandle(h);
}

static void skin_probe(u64 comp, int lod, int dump)
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
        skin_result("err no CPU copy of positions / skin weights / indices"); return;
    }
    int ni = ((index_num_fn)(*(u64 *)(*(u64 *)ib + 0x58)))(ib);
    index_get_fn index_get = (index_get_fn)(*(u64 *)(*(u64 *)ib + 0x68));
    const u32 *ix = ib_indices(ib, ni, index_get);
    if (!ix) { skin_result("err no memory for the indices"); return; }
    c.nb = *(int *)(c.sm + SM_REF_BONE_INFO + 8);
    c.binfo = *(unsigned char **)(c.sm + SM_REF_BONE_INFO);
    c.refinv = *(float **)(c.sm + SM_REF_BASES_INV);
    if (!c.refinv || c.nb <= 0 || c.nb > MAX_BONES) { skin_result("err no bones"); return; }
    u64 master = ((weak_get_fn)(exe + RVA_WEAK_PTR_GET))(comp + SC_MASTER_POSE);
    u64 src = master ? master : comp;
    if (master) {
        static int namemap[MAX_BONES];
        u64 msm = *(u64 *)(master + SC_SKELETAL_MESH);
        const unsigned char *mbi = msm ? *(unsigned char **)(msm + SM_REF_BONE_INFO) : 0;
        int mnb = msm ? *(int *)(msm + SM_REF_BONE_INFO + 8) : 0;
        if (!mbi || mnb <= 0) { skin_result("err no master skeleton"); return; }
        for (int i = 0; i < c.nb; i++) {
            u64 nm = *(const u64 *)(c.binfo + (u64)i * 0xc);
            namemap[i] = -1;
            for (int j = 0; j < mnb; j++) if (*(const u64 *)(mbi + (u64)j * 0xc) == nm) { namemap[i] = j; break; }
        }
        // the engine's own map where it has one: a borrowed sink remapped onto the master's head ("k") is skinned
        // where the head is, not where its name says (the face's Spine1)
        const int *mbm = *(const int **)(comp + SC_MASTER_BONE_MAP);
        if (mbm && *(int *)(comp + SC_MASTER_BONE_MAP + 8) == c.nb)
            for (int i = 0; i < c.nb; i++) namemap[i] = mbm[i] < mnb ? mbm[i] : -1;
        c.mmap = namemap;
    }
    c.space = *(float **)(src + SC_SPACE_BASES + (u64)*(int *)(src + SC_SPACE_READ) * 0x10);
    c.nspace = *(int *)(src + SC_SPACE_BASES + (u64)*(int *)(src + SC_SPACE_READ) * 0x10 + 8);
    if (!c.space) { skin_result("err no bone transforms"); return; }
    u64 secs = *(u64 *)(ld + LOD_SECTIONS);
    int nsec = *(int *)(ld + LOD_SECTIONS + 8), nv = c.nv, nb = c.nb;
    unsigned char *mem = mem_alloc((u64)nv * 17 + (u64)nb * 16 + 64);
    if (!mem) { skin_result("err out of memory"); return; }
    float *xs = (float *)mem;
    int *top = (int *)(xs + (u64)nv * 3);
    int *count = top + nv, *far = count + nb;   // per bone: stretched triangle corners, farthest vertex (mm)
    int *vcount = far + nb;                     // per bone: corners of stretched triangles that show (not all on sinks)
    unsigned char *onsink = (unsigned char *)(vcount + nb);   // per vertex: every weight on a sink
    unsigned char *data = *(unsigned char **)(sw + SW_DATA);
    u32 *lookup = *(u32 **)(sw + SW_LOOKUP);
    int variable = *(unsigned char *)(sw + SW_VARIABLE) && lookup;
    u32 maxinf = *(u32 *)(sw + SW_MAX_INFLUENCES);
    int wide = *(unsigned char *)(sw + SW_16BIT_INDEX) != 0;
    for (int v = 0; v < nv; v++) top[v] = -1;
    for (int s = 0; s < nsec; s++) {
        u64 sec = secs + (u64)s * 0xe8;
        int base = *(int *)(sec + SEC_BASE_VERTEX), cnt = *(int *)(sec + SEC_NUM_VERTICES);
        unsigned short *bmap = *(unsigned short **)(sec + SEC_BONE_MAP);
        int nbmap = *(int *)(sec + SEC_BONE_MAP + 8);
        for (int v = base; v < base + cnt && v < nv; v++) {
            skin_info o;
            u32 off, cn;
            if (variable) { off = lookup[v] >> 8; cn = lookup[v] & 0xff; }
            else { off = (wide ? 3 : 2) * maxinf * (u32)v; cn = maxinf; }
            if (cn > MAX_INF) cn = MAX_INF;
            int tw = 0, sunk = 1;
            for (int i = 0; i < MAX_INF; i++) { o.bones[i] = 0; o.weights[i] = 0; }
            for (u32 i = 0; i < cn; i++) {
                u32 li = wide ? ((unsigned short *)(data + off))[i] : data[off + i];
                unsigned char w = data[off + (wide ? 2 : 1) * cn + i];
                int mb = li < (u32)nbmap ? bmap[li] : 0;
                o.bones[i] = mb; o.weights[i] = w;
                if (w > tw && mb < nb) { tw = w; top[v] = mb; }
                if (w && (!is_sink(&c, mb) || is_carrier(&c, mb))) sunk = 0;
            }
            onsink[v] = (unsigned char)sunk;
            skin_point(&c, &o, (const float *)(pos + (u64)v * pstride), xs + (u64)v * 3);
        }
    }
    if (dump) probe_obj(dump, xs, nv, top, ix, ni);
    int bad = 0, hidden = 0;
    float longest = 0;
    for (int t = 0; t + 2 < ni; t += 3) {
        u32 a[3] = { ix[t], ix[t + 1], ix[t + 2] };
        if (a[0] >= (u32)nv || a[1] >= (u32)nv || a[2] >= (u32)nv) continue;
        float worst = 0;
        for (int e = 0; e < 3; e++) {
            u32 i = a[e], j = a[(e + 1) % 3];
            const float *bi = (const float *)(pos + (u64)i * pstride), *bj = (const float *)(pos + (u64)j * pstride);
            float db[3] = { bi[0] - bj[0], bi[1] - bj[1], bi[2] - bj[2] };
            float dl[3] = { xs[i * 3] - xs[j * 3], xs[i * 3 + 1] - xs[j * 3 + 1], xs[i * 3 + 2] - xs[j * 3 + 2] };
            float lb = __builtin_sqrtf(db[0] * db[0] + db[1] * db[1] + db[2] * db[2]);
            float ll = __builtin_sqrtf(dl[0] * dl[0] + dl[1] * dl[1] + dl[2] * dl[2]);
            if (ll > 3 * lb && ll > lb + 15 && ll > worst) worst = ll;
        }
        if (worst <= 0) continue;
        bad++;
        // hidden: all on sinks and with no area left. A split's flattening sinks only squash the skin onto the plane,
        // so a triangle all on them can still show, as a flat sheet stretched between two bands: counted hidden, the
        // flat shards off a split half on the floor never showed up here (eighteenth playtest)
        int hid = onsink[a[0]] && onsink[a[1]] && onsink[a[2]];
        if (hid) {
            const float *p0 = xs + (u64)a[0] * 3, *p1 = xs + (u64)a[1] * 3, *p2 = xs + (u64)a[2] * 3;
            float e1[3] = { p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2] }, e2[3] = { p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2] };
            float cr[3] = { e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0] };
            if (cr[0] * cr[0] + cr[1] * cr[1] + cr[2] * cr[2] > 4.0f) hid = 0; // over 1 cm²
        }
        hidden += hid;
        if (worst > longest) longest = worst;
        for (int e = 0; e < 3; e++) {
            int b = top[a[e]];
            if (b < 0 || b >= nb) continue;
            count[b]++;
            if (!hid) vcount[b]++;
            const float *bt = pose_of(&c, b);
            if (!bt) continue;
            const float *x = xs + (u64)a[e] * 3;
            float d[3] = { x[0] - bt[4], x[1] - bt[5], x[2] - bt[6] };
            int mm = (int)(__builtin_sqrtf(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]) * 10);
            if (mm > far[b]) far[b] = mm;
        }
    }
    char msg[512], *o = put(msg, "ok stretched=");
    o = put_int(o, bad); o = put(o, " of "); o = put_int(o, ni / 3); o = put(o, " hidden="); o = put_int(o, hidden);
    o = put(o, " longest="); o = put_f(o, longest);
    o = put(o, " bones=");
    for (int k = 0; k < 8; k++) {
        int best = -1;
        for (int b = 0; b < nb; b++) if (count[b] > 0 && (best < 0 || count[b] > count[best])) best = b;
        if (best < 0) break;
        if (k) o = put(o, ";");
        o = put_int(o, best); o = put(o, ":"); o = put_int(o, count[best]); o = put(o, ":");
        o = put_f(o, far[best] * 0.1f);
        count[best] = 0;
    }
    // the same for the triangles that show, bone and count only (the stretched skin to look at in game)
    o = put(o, " shown=");
    for (int k = 0; k < 8; k++) {
        int best = -1;
        for (int b = 0; b < nb; b++) if (vcount[b] > 0 && (best < 0 || vcount[b] > vcount[best])) best = b;
        if (best < 0) break;
        if (k) o = put(o, ";");
        o = put_int(o, best); o = put(o, ":"); o = put_int(o, vcount[best]);
        vcount[best] = 0;
    }
    *o = 0;
    mem_free(mem);
    skin_result(msg);
}

// where a ray from inside her meets her skin, nothing changed: a living hit's mark (gore.lua hit_mark) goes on the
// skin there instead of where the physics capsule was hit. The ray starts on the bone's axis (pw) and goes out along
// nw; of the vertices within a lane of it (3, 6, then 12 cm) and no further than reach cm, the first it meets and
// then the outermost within MARK_LAYER_CM of that (a strap or a plate over the skin): the skin it leaves through,
// not an arm hanging beside her body further out. The normal there is the area-weighted normal of
// the triangles within 2 cm, turned to face along the ray; bone: the one that weighs most on that vertex (the mark
// rides it). Answer "ok hit=x,y,z n=x,y,z bone=i out=cm" (world space), in sbslice.cut
#define MARK_LAYER_CM 3.0f
static void skin_mark(u64 comp, int lod, const float *pw, const float *nw, float reach)
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
        skin_result("err no CPU copy of positions / skin weights / indices"); return;
    }
    int ni = ((index_num_fn)(*(u64 *)(*(u64 *)ib + 0x58)))(ib);
    index_get_fn index_get = (index_get_fn)(*(u64 *)(*(u64 *)ib + 0x68));
    const u32 *ix = ib_indices(ib, ni, index_get);
    if (!ix) { skin_result("err no memory for the indices"); return; }
    c.nb = *(int *)(c.sm + SM_REF_BONE_INFO + 8);
    c.binfo = *(unsigned char **)(c.sm + SM_REF_BONE_INFO);
    c.refinv = *(float **)(c.sm + SM_REF_BASES_INV);
    if (!c.refinv || c.nb <= 0 || c.nb > MAX_BONES) { skin_result("err no bones"); return; }
    u64 master = ((weak_get_fn)(exe + RVA_WEAK_PTR_GET))(comp + SC_MASTER_POSE);
    u64 src = master ? master : comp;
    if (master) {
        static int namemap[MAX_BONES];
        u64 msm = *(u64 *)(master + SC_SKELETAL_MESH);
        const unsigned char *mbi = msm ? *(unsigned char **)(msm + SM_REF_BONE_INFO) : 0;
        int mnb = msm ? *(int *)(msm + SM_REF_BONE_INFO + 8) : 0;
        if (!mbi || mnb <= 0) { skin_result("err no master skeleton"); return; }
        for (int i = 0; i < c.nb; i++) {
            u64 nm = *(const u64 *)(c.binfo + (u64)i * 0xc);
            namemap[i] = -1;
            for (int j = 0; j < mnb; j++) if (*(const u64 *)(mbi + (u64)j * 0xc) == nm) { namemap[i] = j; break; }
        }
        c.mmap = namemap;
    }
    c.space = *(float **)(src + SC_SPACE_BASES + (u64)*(int *)(src + SC_SPACE_READ) * 0x10);
    c.nspace = *(int *)(src + SC_SPACE_BASES + (u64)*(int *)(src + SC_SPACE_READ) * 0x10 + 8);
    if (!c.space) { skin_result("err no bone transforms"); return; }
    const float *tm = (float *)(src + SC_TO_WORLD);
    float p[3], n[3];
    world_to_comp(tm, pw, p, 0);
    world_to_comp(tm, nw, n, 1);
    float sc = tm[8] != 0 ? tm[8] : 1, rch = reach / sc;
    u64 secs = *(u64 *)(ld + LOD_SECTIONS);
    int nsec = *(int *)(ld + LOD_SECTIONS + 8), nv = c.nv, nb = c.nb;
    unsigned char *mem = mem_alloc((u64)nv * 17 + 64);
    if (!mem) { skin_result("err out of memory"); return; }
    float *xs = (float *)mem;
    int *top = (int *)(xs + (u64)nv * 3);
    unsigned char *has = (unsigned char *)(top + nv);
    unsigned char *data = *(unsigned char **)(sw + SW_DATA);
    u32 *lookup = *(u32 **)(sw + SW_LOOKUP);
    int variable = *(unsigned char *)(sw + SW_VARIABLE) && lookup;
    u32 maxinf = *(u32 *)(sw + SW_MAX_INFLUENCES);
    int wide = *(unsigned char *)(sw + SW_16BIT_INDEX) != 0;
    for (int s = 0; s < nsec; s++) {
        u64 sec = secs + (u64)s * 0xe8;
        int base = *(int *)(sec + SEC_BASE_VERTEX), cnt = *(int *)(sec + SEC_NUM_VERTICES);
        unsigned short *bmap = *(unsigned short **)(sec + SEC_BONE_MAP);
        int nbmap = *(int *)(sec + SEC_BONE_MAP + 8);
        for (int v = base; v < base + cnt && v < nv; v++) {
            skin_info o;
            u32 off, cn;
            if (variable) { off = lookup[v] >> 8; cn = lookup[v] & 0xff; }
            else { off = (wide ? 3 : 2) * maxinf * (u32)v; cn = maxinf; }
            if (cn > MAX_INF) cn = MAX_INF;
            int tw = 0;
            top[v] = -1;
            for (int i = 0; i < MAX_INF; i++) { o.bones[i] = 0; o.weights[i] = 0; }
            for (u32 i = 0; i < cn; i++) {
                u32 li = wide ? ((unsigned short *)(data + off))[i] : data[off + i];
                unsigned char w = data[off + (wide ? 2 : 1) * cn + i];
                int mb = li < (u32)nbmap ? bmap[li] : 0;
                o.bones[i] = mb; o.weights[i] = w;
                if (w > tw && mb < nb) { tw = w; top[v] = mb; }
            }
            skin_point(&c, &o, (const float *)(pos + (u64)v * pstride), xs + (u64)v * 3);
            has[v] = 1;
        }
    }
    int hv = -1;
    float best = -1e30f;
    for (float lane = 3.0f; lane <= 12.0f && hv < 0; lane *= 2) {
        float l2 = lane * lane / (sc * sc), first = 1e30f;
        for (int pass = 0; pass < 2; pass++)
            for (int v = 0; v < nv; v++) {
                if (!has[v]) continue;
                const float *x = xs + (u64)v * 3;
                float d[3] = { x[0] - p[0], x[1] - p[1], x[2] - p[2] }, h = d[0] * n[0] + d[1] * n[1] + d[2] * n[2];
                if (h <= 0 || h > rch || d[0] * d[0] + d[1] * d[1] + d[2] * d[2] - h * h >= l2) continue;
                if (!pass) { if (h < first) first = h; }
                else if (h <= first + MARK_LAYER_CM / sc && h > best) { best = h; hv = v; }
            }
    }
    if (hv < 0) { mem_free(mem); skin_result("err the ray misses the skin"); return; }
    const float *hc = xs + (u64)hv * 3;
    float nm[3] = { 0, 0, 0 }, r2 = 4.0f / (sc * sc);
    for (int t = 0; t + 2 < ni; t += 3) {
        u32 a = ix[t], e = ix[t + 1], f = ix[t + 2];
        if (a >= (u32)nv || e >= (u32)nv || f >= (u32)nv || !has[a] || !has[e] || !has[f]) continue;
        const float *p0 = xs + (u64)a * 3, *p1 = xs + (u64)e * 3, *p2 = xs + (u64)f * 3;
        float d[3] = { p0[0] - hc[0], p0[1] - hc[1], p0[2] - hc[2] };
        if (d[0] * d[0] + d[1] * d[1] + d[2] * d[2] > r2) continue;
        float e1[3] = { p1[0] - p0[0], p1[1] - p0[1], p1[2] - p0[2] }, e2[3] = { p2[0] - p0[0], p2[1] - p0[1], p2[2] - p0[2] };
        float cr[3] = { e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0] };
        float k = cr[0] * n[0] + cr[1] * n[1] + cr[2] * n[2] < 0 ? -1.0f : 1.0f; // winding either way: face along the ray
        for (int i = 0; i < 3; i++) nm[i] += k * cr[i];
    }
    float l2 = nm[0] * nm[0] + nm[1] * nm[1] + nm[2] * nm[2];
    if (l2 < 1e-12f) { nm[0] = n[0]; nm[1] = n[1]; nm[2] = n[2]; }
    else { float k = rsqrt(l2); for (int i = 0; i < 3; i++) nm[i] *= k; }
    float hw[3], nw2[3];
    comp_to_world(tm, hc, hw);
    quat_rot(tm, nm, nw2);
    char msg[160], *o = put(msg, "ok");
    o = put_v(o, " hit=", hw, 1);
    o = put_v(o, " n=", nw2, 100);
    o = put(o, " bone="); o = put_int(o, top[hv]);
    o = put(o, " out="); o = put_f(o, best * sc);
    *o = 0;
    mem_free(mem);
    skin_result(msg);
}

// "c<comp>,<lod>,<bone>[,<mode>,<radius>]" / "x<comp>,<lod>" / "r", fields in hex
// ---- a weapon split ("e<compA>,<compB>,<lod>", the plane in the cheat's location and direction, world) ----------
// Her sword cut in two by the killing blade (active.lua): compB is a second component of the same mesh asset on
// compA's pose (its master pose component), each on its own physics box. A keeps what is in front of the plane, B
// what is behind, each through its own skin weight override; what one gives up goes onto a sink bone of the asset:
// a part the plane crosses (a bone with vertices on both sides) is flattened onto the plane there, so the cut face
// is that part's own surface pressed flat, and a part wholly on the far side collapses to a point on the plane,
// out of sight. The sword is rigid on its box, so a sink fixed at the cut's pose stays right. Sinks are bones no
// vertex uses (helpers and markers: the sword has 90 bones), borrowed into the sections that need them; a bone the
// plane crosses is pressed flat through one sink per half, shared by the parts moved off their bind pose alike
// (WEAPON_PARTS sinks at most, the rest collapse). Undone by "x" on each component (the asset's sinks with it) and "r"
// (the borrowed BoneMap entries)
#define WEAPON_PARTS 12   // most flat sinks per half (groups of crossed parts)
#define WEAPON_CROSSED 64 // most crossed parts
// row-vector 4x4 of a component-space transform (scale, rotate, translate), and its inverse
static void tm_mat(const float *t, float *m)
{
    for (int r = 0; r < 3; r++) {
        float e[3] = { r == 0, r == 1, r == 2 }, o[3];
        quat_rot(t, e, o);
        for (int k = 0; k < 3; k++) m[r * 4 + k] = o[k] * t[8 + r];
        m[r * 4 + 3] = 0;
    }
    m[12] = t[4]; m[13] = t[5]; m[14] = t[6]; m[15] = 1;
}
static void tm_inv_mat(const float *t, float *m)
{
    float iq[4] = { -t[0], -t[1], -t[2], t[3] }, mt[3] = { -t[4], -t[5], -t[6] }, l[3];
    quat_rot(iq, mt, l);
    for (int r = 0; r < 3; r++) {
        float e[3] = { r == 0, r == 1, r == 2 }, o[3];
        quat_rot(iq, e, o);
        for (int k = 0; k < 3; k++) m[r * 4 + k] = o[k] / (t[8 + k] != 0 ? t[8 + k] : 1);
        m[r * 4 + 3] = 0;
    }
    for (int k = 0; k < 3; k++) m[12 + k] = l[k] / (t[8 + k] != 0 ? t[8 + k] : 1);
    m[15] = 1;
}
static void mat_mul(const float *a, const float *b, float *o)
{
    for (int r = 0; r < 4; r++)
        for (int k = 0; k < 4; k++) {
            float acc = 0;
            for (int j = 0; j < 4; j++) acc += a[r * 4 + j] * b[j * 4 + k];
            o[r * 4 + k] = acc;
        }
}
// ---- her grip eased ("F<comp>,<hand>,<permille>[,...]" every frame while it shows; "F" alone puts every hand back) --
// A ragdoll's fingers have no bodies of their own: they keep the animation's fist after her sword slipped out of it
// (playtest). Each bone under the hand bone is posed that far back toward its bind pose (the open hand), against the
// hand as it is posed now, through its inverse bind matrix as the sinks are: it becomes invBind * Open * Posed^-1,
// and the skinning's Posed cancels down to Open. The asset is shared, so each matrix is kept and put back ("F", "r").
// No answer file: her tick sends it every frame, and reading one every frame stuttered
#define MAX_RELAX 128
static struct { u64 mesh; int bone; float m[16]; } relaxed[MAX_RELAX];
static int nrelaxed;
static int relax_restore(void)
{
    int n = 0;
    for (int i = 0; i < nrelaxed; i++) {
        float *ri = *(float **)(relaxed[i].mesh + SM_REF_BASES_INV);
        int num = *(int *)(relaxed[i].mesh + SM_REF_BASES_INV + 8);
        if (!ri || relaxed[i].bone >= num) continue;
        for (int k = 0; k < 16; k++) ri[(u64)relaxed[i].bone * 16 + k] = relaxed[i].m[k];
        n++;
    }
    nrelaxed = 0;
    return n;
}
// a component's pose as the skinning reads it (its master's, through the bone map, for a follower)
static int pose_ctx(u64 comp, cut_ctx *c, int *namemap)
{
    *c = (cut_ctx){ 0 };
    c->comp = comp;
    c->sm = *(u64 *)(comp + SC_SKELETAL_MESH);
    if (!c->sm) return 0;
    c->nb = *(int *)(c->sm + SM_REF_BONE_INFO + 8);
    c->binfo = *(unsigned char **)(c->sm + SM_REF_BONE_INFO);
    c->refinv = *(float **)(c->sm + SM_REF_BASES_INV);
    if (!c->binfo || !c->refinv || c->nb <= 0 || c->nb > MAX_BONES || *(int *)(c->sm + SM_REF_BASES_INV + 8) != c->nb) return 0;
    u64 master = ((weak_get_fn)(exe + RVA_WEAK_PTR_GET))(comp + SC_MASTER_POSE);
    u64 src = master ? master : comp;
    if (master) {
        u64 msm = *(u64 *)(master + SC_SKELETAL_MESH);
        const unsigned char *mbi = msm ? *(unsigned char **)(msm + SM_REF_BONE_INFO) : 0;
        int mnb = msm ? *(int *)(msm + SM_REF_BONE_INFO + 8) : 0;
        if (!mbi || mnb <= 0) return 0;
        for (int b = 0; b < c->nb; b++) {
            u64 nm = *(const u64 *)(c->binfo + (u64)b * 0xc);
            namemap[b] = -1;
            for (int j = 0; j < mnb; j++) if (*(const u64 *)(mbi + (u64)j * 0xc) == nm) { namemap[b] = j; break; }
        }
        c->mmap = namemap;
    }
    int rd = *(int *)(src + SC_SPACE_READ);
    if (rd < 0 || rd > 1) return 0;
    c->space = *(float **)(src + SC_SPACE_BASES + (u64)rd * 0x10);
    c->nspace = *(int *)(src + SC_SPACE_BASES + (u64)rd * 0x10 + 8);
    return c->space && c->nspace > 0;
}
static void quat_mul(const float *a, const float *b, float *o) // o = a * b (b's turn first)
{
    float x = a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1];
    float y = a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0];
    float z = a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3];
    float w = a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2];
    o[0] = x; o[1] = y; o[2] = z; o[3] = w;
}
static void relax_hand(u64 comp, int hand, float a)
{
    static int namemap[MAX_BONES];
    static float open[MAX_BONES][12];
    static unsigned char under[MAX_BONES];
    cut_ctx c;
#ifndef SBSLICE_HOSTED
    if (!mem_readable(comp, SC_SPACE_READ + 8)) return;
#endif
    if (!pose_ctx(comp, &c, namemap) || hand < 0 || hand >= c.nb) return;
    const float *refpose = *(float **)(c.sm + SM_REF_BONE_POSE);
    if (!refpose || *(int *)(c.sm + SM_REF_BONE_POSE + 8) != c.nb) return;
    const float *th = pose_of(&c, hand);
    if (!th) return;
    for (int k = 0; k < 12; k++) open[hand][k] = th[k];
    under[hand] = 0;
    // (a bone comes after its parent in a reference skeleton)
    for (int b = 0; b < c.nb; b++) {
        if (b == hand) continue;
        int p = parent_of(&c, b);
        under[b] = p >= 0 && p < b && (p == hand || under[p]);
        if (!under[b]) continue;
        const float *tb = pose_of(&c, b), *tp = pose_of(&c, p), *rb = refpose + (u64)b * 12;
        if (!tb || !tp) { under[b] = 0; continue; }
        // its pose against its parent now, and in the bind pose; a of the way from one to the other
        float ip[4] = { -tp[0], -tp[1], -tp[2], tp[3] }, ql[4], d[3] = { tb[4] - tp[4], tb[5] - tp[5], tb[6] - tp[6] }, tl[3];
        quat_mul(ip, tb, ql);
        quat_rot(ip, d, tl);
        for (int k = 0; k < 3; k++) tl[k] /= tp[8 + k] != 0 ? tp[8 + k] : 1;
        float sg = ql[0] * rb[0] + ql[1] * rb[1] + ql[2] * rb[2] + ql[3] * rb[3] < 0 ? -1.0f : 1.0f, q[4], t[3], ql2 = 0;
        for (int k = 0; k < 4; k++) { q[k] = ql[k] + (sg * rb[k] - ql[k]) * a; ql2 += q[k] * q[k]; }
        ql2 = __builtin_sqrtf(ql2);
        if (ql2 < 1e-6f) { under[b] = 0; continue; }
        for (int k = 0; k < 4; k++) q[k] /= ql2;
        for (int k = 0; k < 3; k++) t[k] = tl[k] + (rb[4 + k] - tl[k]) * a;
        // on the parent's eased pose
        const float *op = open[p];
        float *o = open[b], st[3] = { t[0] * op[8], t[1] * op[9], t[2] * op[10] }, rt[3];
        quat_mul(op, q, o);
        quat_rot(op, st, rt);
        for (int k = 0; k < 3; k++) { o[4 + k] = op[4 + k] + rt[k]; o[8 + k] = op[8 + k] * (tb[8 + k] / (tp[8 + k] != 0 ? tp[8 + k] : 1)); }
        o[7] = 0; o[11] = 0;
        // not a bone a cut holds (a sink), nor one with a body of its own
        int held = nosink_mesh == c.sm && hasbody[b];
        for (int i = 0; i < nsinks && !held; i++) held = sinks[i].mesh == c.sm && sinks[i].bone == b;
        if (held) continue;
        int r = -1;
        for (int i = 0; i < nrelaxed; i++) if (relaxed[i].mesh == c.sm && relaxed[i].bone == b) { r = i; break; }
        float *ri = c.refinv + (u64)b * 16;
        if (r < 0) {
            if (nrelaxed >= MAX_RELAX) continue;
            r = nrelaxed++;
            relaxed[r].mesh = c.sm; relaxed[r].bone = b;
            for (int k = 0; k < 16; k++) relaxed[r].m[k] = ri[k];
        }
        float mo[16], mi[16], m1[16];
        tm_mat(o, mo);
        tm_inv_mat(tb, mi);
        mat_mul(relaxed[r].m, mo, m1);
        mat_mul(m1, mi, ri);
    }
}
static void relax_cmd(const u64 *f, int k)
{
    if (k < 3 || f[0] < 0x10000) { relax_restore(); return; }
    for (int i = 0; i + 2 < k; i += 3) {
        if (f[i] < 0x10000) continue;
        float a = (float)(f[i + 2] > 1000 ? 1000 : f[i + 2]) / 1000.0f;
        relax_hand(f[i], (int)f[i + 1], a);
    }
}

// ---- a weapon's real size ("W<comp>,<lod>"): its vertices' box in its mesh's space, "ok W minx,miny,minz,maxx,..." --
// The asset's imported bounds are not its geometry: her sword's are twice as wide and much longer than its 140 cm, so
// a guarded blow's break "across its middle" landed by the hilt and the blade stayed whole (playtest)
static void weapon_bounds(u64 comp, int lod)
{
    u64 sm = *(u64 *)(comp + SC_SKELETAL_MESH);
    if (!sm) { skin_result("err no mesh"); return; }
    u64 rd = *(u64 *)(comp + SC_MESH_OBJECT) ? *(u64 *)(*(u64 *)(comp + SC_MESH_OBJECT) + 0x40) : *(u64 *)(sm + SM_RENDER_DATA);
    if (!rd || lod < 0 || lod >= *(int *)(rd + 8)) { skin_result("err no render data for lod"); return; }
    u64 ld = ((u64 *)*(u64 *)rd)[lod];
    int nv = *(int *)(ld + LOD_NUM_VERTICES);
    unsigned char *pos = *(unsigned char **)(ld + LOD_POSITIONS + 0x28);
    u32 pstride = *(u32 *)(ld + LOD_POSITIONS + 0x30);
    if (!pos || nv <= 0 || pstride < 12) { skin_result("err no CPU copy of positions"); return; }
    float lo[3] = { 1e30f, 1e30f, 1e30f }, hi[3] = { -1e30f, -1e30f, -1e30f };
    for (int v = 0; v < nv; v++) {
        const float *p = (const float *)(pos + (u64)v * pstride);
        for (int k = 0; k < 3; k++) { if (p[k] < lo[k]) lo[k] = p[k]; if (p[k] > hi[k]) hi[k] = p[k]; }
    }
    char msg[128], *o = put(msg, "ok W ");
    for (int k = 0; k < 6; k++) { if (k) *o++ = ','; o = put_f(o, k < 3 ? lo[k] : hi[k - 3]); }
    *o = 0;
    skin_result(msg);
}

static void weapon_split(u64 ca, u64 cb, int lod, const float *pw, const float *nw)
{
    cut_ctx c = { 0 };
    c.comp = ca;
    c.sm = *(u64 *)(ca + SC_SKELETAL_MESH);
    if (!c.sm || *(u64 *)(cb + SC_SKELETAL_MESH) != c.sm) { skin_result("err the two components want one mesh"); return; }
    u64 rd = *(u64 *)(ca + SC_MESH_OBJECT) ? *(u64 *)(*(u64 *)(ca + SC_MESH_OBJECT) + 0x40) : *(u64 *)(c.sm + SM_RENDER_DATA);
    if (!rd || lod < 0 || lod >= *(int *)(rd + 8)) { skin_result("err no render data for lod"); return; }
    u64 ld = ((u64 *)*(u64 *)rd)[lod];
    u64 sw = ((get_buffer_fn)(exe + RVA_GET_SKIN_WEIGHT_BUFFER))(ca, lod);
    c.nv = *(int *)(ld + LOD_NUM_VERTICES);
    unsigned char *pos = *(unsigned char **)(ld + LOD_POSITIONS + 0x28);
    u32 pstride = *(u32 *)(ld + LOD_POSITIONS + 0x30);
    if (!sw || !*(u64 *)(sw + SW_DATA) || !pos || *(int *)(sw + SW_NUM_VERTICES) != c.nv) {
        skin_result("err no CPU copy of positions / skin weights"); return;
    }
    c.nb = *(int *)(c.sm + SM_REF_BONE_INFO + 8);
    c.binfo = *(unsigned char **)(c.sm + SM_REF_BONE_INFO);
    c.refinv = *(float **)(c.sm + SM_REF_BASES_INV);
    int nb = c.nb, nv = c.nv;
    if (nb <= 1 || nb > MAX_BONES || !c.refinv || *(int *)(c.sm + SM_REF_BASES_INV + 8) != nb) { skin_result("err bad skeleton"); return; }
    c.space = *(float **)(ca + SC_SPACE_BASES + (u64)*(int *)(ca + SC_SPACE_READ) * 0x10);
    c.nspace = *(int *)(ca + SC_SPACE_BASES + (u64)*(int *)(ca + SC_SPACE_READ) * 0x10 + 8);
    if (!c.space || c.nspace < nb) { skin_result("err no bone transforms"); return; }
    u64 secs = *(u64 *)(ld + LOD_SECTIONS);
    c.nsec = *(int *)(ld + LOD_SECTIONS + 8);
    if (c.nsec <= 0 || c.nsec > 0xfffe) { skin_result("err no sections"); return; }
    const float *tm = (float *)(ca + SC_TO_WORLD);
    float p[3], n[3];
    world_to_comp(tm, pw, p, 0);
    world_to_comp(tm, nw, n, 1);
    float nl = __builtin_sqrtf(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
    if (nl < 1e-6f) { skin_result("err no plane normal"); return; }
    for (int k = 0; k < 3; k++) n[k] /= nl;

    u64 nbsec = (u64)c.nsec * nb;
    u64 bytes = (u64)nv * (3 * sizeof(skin_info) + 2 + 1 + 4) + nbsec + (u64)nb * (4 * 4 + 1) + 64;
    unsigned char *mem = cut_scratch(0, bytes);
    if (!mem) { skin_result("err out of memory"); return; }
    skin_info *orig = (skin_info *)mem, *oa = orig + nv, *ob = oa + nv;
    int *usage = (int *)(ob + nv), *npos = usage + nb, *nneg = npos + nb, *strong = nneg + nb;
    u16 *vsec = (u16 *)(strong + nv);
    unsigned char *side = (unsigned char *)(vsec + nv), *inmap = side + nv, *issink = inmap + nbsec;
    c.inmap = inmap; c.vsec = vsec;

    // the weights as the mesh has them, in mesh bones
    unsigned char *data = *(unsigned char **)(sw + SW_DATA);
    u32 *lookup = *(u32 **)(sw + SW_LOOKUP);
    int variable = *(unsigned char *)(sw + SW_VARIABLE) && lookup;
    u32 maxinf = *(u32 *)(sw + SW_MAX_INFLUENCES);
    int wide = *(unsigned char *)(sw + SW_16BIT_INDEX) != 0;
    for (int v = 0; v < nv; v++) vsec[v] = 0xffff;
    for (int s = 0; s < c.nsec; s++) {
        u64 sec = secs + (u64)s * 0xe8;
        int base = *(int *)(sec + SEC_BASE_VERTEX), cnt = *(int *)(sec + SEC_NUM_VERTICES);
        unsigned short *bmap = *(unsigned short **)(sec + SEC_BONE_MAP);
        int nbmap = *(int *)(sec + SEC_BONE_MAP + 8);
        for (int k = 0; k < nbmap; k++) if (bmap[k] < nb) inmap[(u64)s * nb + bmap[k]] = 1;
        for (int v = base; v < base + cnt && v < nv; v++) {
            u32 off, cn;
            if (variable) { off = lookup[v] >> 8; cn = lookup[v] & 0xff; }
            else { off = (wide ? 3 : 2) * maxinf * (u32)v; cn = maxinf; }
            if (cn > MAX_INF) cn = MAX_INF;
            for (int i = 0; i < MAX_INF; i++) orig[v].bones[i] = 0;
            for (u32 i = 0; i < cn; i++) {
                u32 li = wide ? ((unsigned short *)(data + off))[i] : data[off + i];
                orig[v].bones[i] = li < (u32)nbmap ? bmap[li] : 0;
                orig[v].weights[i] = data[off + (wide ? 2 : 1) * cn + i];
            }
            vsec[v] = (u16)s;
        }
    }
    // the sword's length: the longest side of its bind box
    float blo[3] = { 1e30f, 1e30f, 1e30f }, bhi[3] = { -1e30f, -1e30f, -1e30f };
    for (int v = 0; v < nv; v++) {
        const float *bp = (const float *)(pos + (u64)v * pstride);
        for (int k = 0; k < 3; k++) { if (bp[k] < blo[k]) blo[k] = bp[k]; if (bp[k] > bhi[k]) bhi[k] = bp[k]; }
    }
    int longax = 0;
    for (int k = 1; k < 3; k++) if (bhi[k] - blo[k] > bhi[longax] - blo[longax]) longax = k;
    // each vertex where it is now, its side and its strongest bone; per bone how many of its own lie each side
    for (int v = 0; v < nv; v++) {
        int best = -1, bw = 0;
        for (int i = 0; i < MAX_INF; i++) {
            int b = orig[v].bones[i];
            if (!orig[v].weights[i] || b < 0 || b >= nb) continue;
            usage[b]++;
            if (orig[v].weights[i] > bw) { bw = orig[v].weights[i]; best = b; }
        }
        strong[v] = best;
        float x[3];
        skin_point(&c, &orig[v], (float *)(pos + (u64)v * pstride), x);
        side[v] = (x[0] - p[0]) * n[0] + (x[1] - p[1]) * n[1] + (x[2] - p[2]) * n[2] >= 0;
        if (best >= 0) { if (side[v]) npos[best]++; else nneg[best]++; }
    }
    // the parts the plane crosses (most vertices first), each pressed flat through a sink per half. Parts moved off
    // their bind pose alike (the sword is rigid) share one: CH_W_Sword_01 has 12 free bones for 8 crossed parts near
    // its guard, and the parts past the fifth collapsed to the plane point, their faces stretched over the cut (playtest)
    int parts[WEAPON_CROSSED], pgroup[WEAPON_CROSSED], grep_[WEAPON_PARTS], np = 0, ng = 0, any[2] = { 0, 0 };
    for (int v = 0; v < nv; v++) any[side[v]] = 1;
    if (!any[0] || !any[1]) { skin_result("err the plane misses it"); return; }
    for (;;) {
        int pick = -1;
        for (int b = 0; b < nb; b++) {
            if (!npos[b] || !nneg[b]) continue;
            int taken = 0;
            for (int k = 0; k < np; k++) taken |= parts[k] == b;
            if (!taken && (pick < 0 || npos[b] + nneg[b] > npos[pick] + nneg[pick])) pick = b;
        }
        if (pick < 0 || np == WEAPON_CROSSED) break;
        parts[np++] = pick;
    }
    // sinks: bones no vertex uses, not the root, not already a sink of an earlier cut on this asset. Roles: 0 A's
    // point, 1 B's point, then A's and B's flat sink of each group of crossed parts
    int sink[2 + 2 * WEAPON_PARTS], ns = 0;
    for (int i = 0; i < nsinks; i++) if (sinks[i].mesh == c.sm && sinks[i].bone < nb) issink[sinks[i].bone] = 1;
    for (int b = nb - 1; b >= 1 && ns < 2 + 2 * WEAPON_PARTS; b--) if (!usage[b] && !issink[b] && c.space && pose_of(&c, b)) sink[ns++] = b;
    if (ns < 2) { skin_result("err no free bone for a sink"); return; }
    // each part's move off its bind pose (bind -> now), grouped where it matches a group's first part's
    for (int k = 0; k < np; k++) {
        const float *tq = pose_of(&c, parts[k]);
        float wq[16], dk[16];
        pgroup[k] = -1;
        if (!tq) continue;
        tm_mat(tq, wq);
        mat_mul(c.refinv + (u64)parts[k] * 16, wq, dk);
        for (int g = 0; g < ng && pgroup[k] < 0; g++) {
            const float *tg = pose_of(&c, grep_[g]);
            float wg[16], dg[16], diff = 0;
            tm_mat(tg, wg);
            mat_mul(c.refinv + (u64)grep_[g] * 16, wg, dg);
            for (int j = 0; j < 16; j++) { float e = dk[j] - dg[j]; if (j >= 12) e *= 0.05f; diff += e * e; } // (1 cm off counts as 0.05)
            if (diff < 1e-4f) pgroup[k] = g;
        }
        if (pgroup[k] < 0 && ng < WEAPON_PARTS && 2 + 2 * (ng + 1) <= ns) { grep_[ng] = parts[k]; pgroup[k] = ng++; }
    }
    int ngparts = 0;
    for (int k = 0; k < np; k++) ngparts += pgroup[k] >= 0;
    if (nsinks + 2 + 2 * ng > MAX_SINKS) { skin_result("err too many sinks"); return; }
    // the active bones as the mesh had them, for borrowing
    for (int i = 0; i < MAX_BONES; i++) bactive[i] = 0;
    for (int s = 0; s < c.nsec; s++) {
        u64 arr = secs + (u64)s * 0xe8 + SEC_BONE_MAP;
        unsigned short *bmap = *(unsigned short **)arr;
        int n0 = *(int *)(arr + 8);
        for (int i = 0; i < nbmfix; i++) if (bmfix[i].arr == arr && bmfix[i].num < n0) n0 = bmfix[i].num;
        for (int k = 0; k < n0; k++) for (int j = bmap[k]; j >= 0 && j < nb && !bactive[j]; j = parent_of(&c, j)) bactive[j] = 1;
    }
    int nact = 0;
    for (int i = 0; i < nb; i++) nact += bactive[i];
    find_active(ld, nb, nact);
    // each half's weights: kept as they are on its side, onto a sink past it
    int borrowfail = 0, flat[2] = { 0, 0 }, gone[2] = { 0, 0 };
    for (int v = 0; v < nv; v++) {
        oa[v] = orig[v]; ob[v] = orig[v];
        int s = vsec[v];
        if (s == 0xffff) continue;
        for (int half = 0; half < 2; half++) {
            // A (half 0) keeps the front (side 1), B the back
            if ((half == 0) == (side[v] != 0)) continue;
            int role = half, part = -1;
            for (int k = 0; k < np; k++) if (parts[k] == strong[v]) part = pgroup[k];
            if (part >= 0) role = 2 + 2 * part + half;
            int b = sink[role];
            if (!inmap[(u64)s * nb + b] && !borrow_bone(secs, s, b, inmap, nb)) {
                // no room in the section's map: its point sink, else the vertex stays
                b = sink[half];
                if (!inmap[(u64)s * nb + b] && !borrow_bone(secs, s, b, inmap, nb)) { borrowfail++; continue; }
                role = half;
            }
            skin_info *o = half ? &ob[v] : &oa[v];
            for (int i = 0; i < MAX_INF; i++) { o->bones[i] = 0; o->weights[i] = 0; }
            o->bones[0] = b; o->weights[0] = 255;
            if (role >= 2) flat[half]++; else gone[half]++;
        }
    }
    // the sinks' matrices, collapsed on "k" (the new weights first)
    for (int r = 0; r < 2 + 2 * ng; r++) {
        int b = sink[r];
        const float *ts = pose_of(&c, b);
        if (!ts) continue;
        int i = nsinks++;
        sinks[i].mesh = c.sm; sinks[i].comp = r & 1 ? cb : ca; sinks[i].bone = b;
        sinks[i].down = 0; sinks[i].carry = 0; sinks[i].anchor = -1; sinks[i].also[0] = sinks[i].also[1] = 0;
        for (int k = 0; k < 16; k++) sinks[i].m[k] = c.refinv[(u64)b * 16 + k];
        if (r < 2) {
            sinks[i].proj = 0;
            local_of_cs(ts, p, sinks[i].at);
        } else {
            // the crossed part's bind position to where it is now, into the sink's frame, pressed onto the plane
            int q = grep_[(r - 2) / 2];
            const float *tq = pose_of(&c, q);
            float wq[16], is[16], t1[16], base[16];
            tm_mat(tq ? tq : ts, wq);
            tm_inv_mat(ts, is);
            mat_mul(c.refinv + (u64)q * 16, wq, t1);
            mat_mul(t1, is, base);
            sinks[i].proj = 1;
            // slid onto the plane along the sword (its longest axis as the part lies now), so the far side lands on
            // its own cross-section: pressed straight along a plane's normal tilted across the sword, the blade's
            // whole far side lay squashed on the plane, slanted off the break, a small bent copy of the sword (playtest)
            float along[3], al = 0;
            for (int k = 0; k < 3; k++) { along[k] = t1[longax * 4 + k]; al += along[k] * along[k]; }
            al = __builtin_sqrtf(al);
            if (al > 1e-6f) for (int k = 0; k < 3; k++) along[k] /= al;
            proj_matrix_along(base, ts, p, n, al > 1e-6f ? along : 0, sinks[i].pm);
        }
    }
    tarray arr = { oa, nv, nv };
    ((set_override_fn)(exe + RVA_SET_SKIN_WEIGHT_OVERRIDE))(ca, lod, &arr);
    arr.data = ob;
    ((set_override_fn)(exe + RVA_SET_SKIN_WEIGHT_OVERRIDE))(cb, lod, &arr);
    // each half's own box (bind space, what it keeps): the tip has no guard, and on the whole sword's 14 x 6 cm
    // section its box held it 2-3 cm over the floor (playtest)
    float hlo[2][3], hhi[2][3];
    for (int h = 0; h < 2; h++) for (int k = 0; k < 3; k++) { hlo[h][k] = 1e30f; hhi[h][k] = -1e30f; }
    for (int v = 0; v < nv; v++) {
        if (vsec[v] == 0xffff) continue;
        int h = side[v] ? 0 : 1; // A keeps the front (side 1)
        const float *bp = (const float *)(pos + (u64)v * pstride);
        for (int k = 0; k < 3; k++) { if (bp[k] < hlo[h][k]) hlo[h][k] = bp[k]; if (bp[k] > hhi[h][k]) hhi[h][k] = bp[k]; }
    }
    char msg[400], *o = put(msg, "ok split parts=");
    o = put_int(o, np); o = put(o, " flat="); o = put_int(o, ngparts); o = put(o, " sinks="); o = put_int(o, 2 + 2 * ng);
    o = put(o, " a_flat="); o = put_int(o, flat[0]); o = put(o, " a_gone="); o = put_int(o, gone[0]);
    o = put(o, " b_flat="); o = put_int(o, flat[1]); o = put(o, " b_gone="); o = put_int(o, gone[1]);
    o = put(o, " nomap="); o = put_int(o, borrowfail); o = put(o, " active="); o = put_int(o, act_arr != 0);
    for (int h = 0; h < 2; h++) {
        o = put(o, h ? " bbox=" : " abox=");
        for (int k = 0; k < 6; k++) { if (k) *o++ = ','; o = put_f(o, k < 3 ? hlo[h][k] : hhi[h][k - 3]); }
    }
    *o = 0;
    skin_result(msg);
}

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
//   c<comp>,<lod>,<bone>[,<mode>[,<radius mm>]]
//                        skin cut (mode: MODE_CUT default, WHOLE, PLANE, SIDE),
//                        plane point LocX/Y/Z, normal
//                        DirX/Y/Z; answer in sbslice.cut
//   c...,<sink>,<remap>  a borrowed sink bone that follows the master's bone <remap>: MODE_SIDE's vanishing side, MODE_CUT's limb side
//   p<src>,<dst>         copy src's pose onto dst (same skeleton): a split's clone
//   s<comp>,<lod>        where comp's skin stretches now (see skin_probe)
//   m<comp>,<lod>,<reach cm>  where a ray meets her skin (see skin_mark): from LocX/Y/Z out along DirX/Y/Z
//   k                    collapse the sinks the last cuts recorded (call once their weights are in use)
//   x<comp>,<lod>        undo the cut on that component
//   y<src>,<lod>,<dst>,...  src's weights on copies of its mesh on its pose (another mod's overlay), none when src has none
//   x<comp>,<lod>,1      only its weights: the asset's sinks stay for another cut component on it (an enemy's kind)
//   r                    put back every collapsed sink (a mesh asset outlives the component)
//   r<mesh asset>        put back that asset's sinks only (an enemy corpse's, whose component may be going)
//   F<comp>,<hand>,<permille>,...  ease that hand's grip that far toward its bind pose (every frame; see relax_hand),
//                        F alone (or r) puts every eased hand back
//   W<comp>,<lod>        a weapon's vertex box in its mesh's space (see weapon_bounds)
//   G<object>,<index>,...  whether each object is still alive, by its GUObjectArray item (see alive_cmd)
//   n<comp>,<bone>,...[,ffff,<bone>,...]   bones of comp's mesh asset that may never be a sink (until the next "n"),
//                        and after ffff the ones that may never carry a stub, after fffe the ones with a physics body,
//                        after fffd the ones a driver moves (a sink only when nothing else is left), after fffc
//                        the ones a driver moves after a limb the next split half lets go (its kept skin lets go too)
//   g<comp>,<gone root>,...,0,<kept root>,...[,0,<ride bone>,...]
//                        a split half's limbs for the next MODE_SIDE cut on comp (0 = Root, never a limb root), and
//                        the spine bones its lid rides (its flattening sinks band by them). Before a MODE_CUT: no
//                        gone roots, and the kept roots are accessory chains on the limb that stay on the body
//   o<object>            keep that asset loaded for good (root it: see root_object)
//   w<comp>              watch her bones once for the stub carriers (Lua, every few ticks while she is alive)
//   v...                 actor stats, for the glass cannon mode (see stats.c)
//   h<comp>,<mode>,<head bone>
//                        a split half's neck plane for its next MODE_SIDE cut (mode HEAD_KEEP / HEAD_DROP, 0 none):
//                        point LocX/Y/Z, normal DirX/Y/Z up the neck
int stats_cmd(const u16 *txt, int len, const float *loc, const float *dir); // stats.c

// keep an asset loaded for good: its object item's RootSet flag in GUObjectArray. Nothing held the cut's assets
// (the bone stub, the cap material, the blood and bleed effects, the sound cues) between deaths, so garbage
// collection freed them and every cut loaded them again from the pak on the game thread: 112 + 61 ms of stutter a
// cut (twenty-fifth playtest). The item is found by the object's own index and must point back at it, or nothing is
// written (UE 4.26: ObjObjects at +0x10, chunks of 64Ki items of 0x18 bytes, Object then Flags)
#define GUO_OBJOBJECTS 0x10
#define UOBJ_INTERNAL_INDEX 0xc
#define GUO_CHUNK 65536
#define GUO_ITEM 0x18
#define EIF_ROOTSET (1u << 30)
static const char *root_object(u64 obj)
{
    if (!mem_readable(obj, 0x10)) return "err bad object";
    if (!RVA_GUOBJECTARRAY) return "err no object array in this game build";
    int index = *(int *)(obj + UOBJ_INTERNAL_INDEX);
    u64 arr = exe + RVA_GUOBJECTARRAY + GUO_OBJOBJECTS;
    if (index < 0 || !mem_readable(arr, 0x20) || index >= *(int *)(arr + 0x14)) return "err bad index";
    u64 *chunks = *(u64 **)arr;
    if (!mem_readable((u64)chunks + (u64)(index / GUO_CHUNK) * 8, 8)) return "err no chunk";
    u64 item = chunks[index / GUO_CHUNK] + (u64)(index % GUO_CHUNK) * GUO_ITEM;
    if (!mem_readable(item, 0x10) || *(u64 *)item != obj) return "err not its item";
    u32 *flags = (u32 *)(item + 8);
    if (*flags & EIF_ROOTSET) return "ok already";
    __atomic_or_fetch(flags, EIF_ROOTSET, __ATOMIC_SEQ_CST);
    return "ok rooted";
}
// ---- is it still there? ("G<object>,<index>,..." for the script's held objects, "ok " and a 1 or 0 for each) -----------
// UE4SS's StaticFindObject finds no level actor by its path (":PersistentLevel."), so the script's name table check
// held none: no enemy was followed and every death rolled its cut (playtest). The object's item in GUObjectArray
// says it without touching the object: freed, the item no longer points at it; Unreachable or PendingKill, it is about
// to be. index ffffffff: read it off the object (the script asks so only for one it just got, alive), answered as
// "<1 or 0>:<index>"
#define EIF_UNREACHABLE (1u << 28)
#define EIF_PENDINGKILL (1u << 29)
static int object_alive(u64 obj, int index)
{
    if (!RVA_GUOBJECTARRAY || obj < 0x10000) return 0;
    u64 arr = exe + RVA_GUOBJECTARRAY + GUO_OBJOBJECTS;
    if (index < 0 || !mem_readable(arr, 0x20) || index >= *(int *)(arr + 0x14)) return 0;
    u64 *chunks = *(u64 **)arr;
    if (!mem_readable((u64)chunks + (u64)(index / GUO_CHUNK) * 8, 8)) return 0;
    u64 item = chunks[index / GUO_CHUNK] + (u64)(index % GUO_CHUNK) * GUO_ITEM;
    if (!mem_readable(item, 0x10) || *(u64 *)item != obj) return 0;
    return !(*(u32 *)(item + 8) & (EIF_UNREACHABLE | EIF_PENDINGKILL));
}
static void alive_cmd(const u64 *f, int k)
{
    static char msg[4 + 64 * 16];
    char *o = put(msg, "ok ");
    for (int i = 0; i + 1 < k; i += 2) {
        int index = (int)(u32)f[i + 1];
        int ask = f[i + 1] == 0xffffffff;
        if (ask) index = mem_readable(f[i], 0x10) ? *(int *)(f[i] + UOBJ_INTERNAL_INDEX) : -1;
        *o++ = object_alive(f[i], index) ? '1' : '0';
        if (ask) { *o++ = ':'; o = put_int(o, index); *o++ = ' '; }
    }
    *o = 0;
    skin_result(msg);
}
// ---- outfit physics at runtime (physfix.lua): what the data mod's outfits container does, for any outfit ----------
// "b<skeletal mesh>,<bone>,...": each bone's bind pose in component space, composed from FinalRefBonePose (local
// rotation and translation; scale is 1 on her skeleton, as the build's outfits.py takes it). Answer
// "ok <bone> qx qy qz qw tx ty tz|..." in the order asked.
static char *put_d(char *o, double f) // 6 decimals: unit quaternions and cm
{
    long long t = (long long)(f * 1e6 + (f < 0 ? -0.5 : 0.5));
    if (t < 0) { *o++ = '-'; t = -t; }
    o = put_int(o, t / 1000000); *o++ = '.';
    long long r = t % 1000000;
    for (long long d = 100000; d; d /= 10) { *o++ = '0' + (char)(r / d); r %= d; }
    return o;
}
static int bind_pose(u64 sm, int bone, double *q, double *t)
{
    const unsigned char *info = *(const unsigned char **)(sm + SM_REF_BONE_INFO);
    const float *pose = *(const float **)(sm + SM_REF_BONE_POSE);
    int nb = *(int *)(sm + SM_REF_BONE_INFO + 8);
    if (!info || !pose || bone < 0 || bone >= nb || *(int *)(sm + SM_REF_BONE_POSE + 8) != nb) return 0;
    int chain[MAX_BONES], n = 0;
    for (int b = bone; b >= 0 && n < MAX_BONES; b = *(const int *)(info + b * 0xc + 8)) {
        if (b >= nb) return 0;
        chain[n++] = b;
    }
    q[0] = q[1] = q[2] = 0; q[3] = 1; t[0] = t[1] = t[2] = 0;
    while (n--) { // root first: R = R * r, T = T + R * t (outfits.py's world_pose)
        const float *l = pose + chain[n] * 12;
        double lq[4] = { l[0], l[1], l[2], l[3] }, lt[3] = { l[4], l[5], l[6] };
        double u[3] = { q[0], q[1], q[2] }, w = q[3];
        double c1[3] = { u[1] * lt[2] - u[2] * lt[1] + w * lt[0], u[2] * lt[0] - u[0] * lt[2] + w * lt[1], u[0] * lt[1] - u[1] * lt[0] + w * lt[2] };
        double c2[3] = { u[1] * c1[2] - u[2] * c1[1], u[2] * c1[0] - u[0] * c1[2], u[0] * c1[1] - u[1] * c1[0] };
        for (int k = 0; k < 3; k++) t[k] += lt[k] + 2 * c2[k];
        double x = q[0], y = q[1], z = q[2];
        q[0] = w * lq[0] + x * lq[3] + y * lq[2] - z * lq[1];
        q[1] = w * lq[1] - x * lq[2] + y * lq[3] + z * lq[0];
        q[2] = w * lq[2] + x * lq[1] - y * lq[0] + z * lq[3];
        q[3] = w * lq[3] - x * lq[0] - y * lq[1] - z * lq[2];
    }
    return 1;
}
static void bind_cmd(const u64 *f, int k)
{
    static char out[64 * 1024];
    if (k < 1 || f[0] < 0x10000) { skin_result("err bad mesh"); return; }
    char *o = put(out, "ok");
    for (int i = 1; i < k && o < out + sizeof out - 160; i++) {
        double q[4], t[3];
        *o++ = i == 1 ? ' ' : '|';
        o = put_int(o, (long long)f[i]);
        if (!bind_pose(f[0], (int)f[i], q, t)) { o = put(o, " -"); continue; }
        for (int j = 0; j < 4; j++) { *o++ = ' '; o = put_d(o, q[j]); }
        for (int j = 0; j < 3; j++) { *o++ = ' '; o = put_d(o, t[j]); }
    }
    *o = 0;
    skin_result(out);
}

// "t<physics asset>,<bodies>[,<a>,<b>...]": no body of the asset collides with another but the pairs listed (body
// indices, a < b: her arms and her chest, physfix.lua), always rewritten when there are any (the build's self_collision false, every
// pair in UPhysicsAsset::CollisionDisableTable, a TMap<FRigidBodyIndexPair, bool> the engine hands the physics scene
// by pointer when it makes her ragdoll's bodies, so a table changed before then is the one used). The map isn't
// reflected, so it is found by its contents: a TSet (TSparseArray of 20 byte elements {a, b, bool, HashNextId,
// HashIndex}, TBitArray with 4 words inline, FirstFreeIndex, NumFreeIndices; one inline hash bucket and its heap
// pointer; HashSize) whose every element is a pair a < b < bodies sitting in the bucket the pair's hash puts it in,
// every bucket's chain reaching exactly its elements. That both finds it and proves the hash and the layout; any
// doubt and the asset is left as it is. The new arrays come from GMalloc (the engine frees them with the asset).
#define PT_SCAN 0x400
#define PT_ELEM 20
static u32 pair_hash(int variant, int a, int b) { return variant ? (u32)b + (u32)a * 23 : (u32)a + (u32)b * 23; }
static u32 hash_buckets(u32 n) // FDefaultSetAllocator::GetNumberOfHashBuckets
{
    if (n < 4) return 1;
    u32 want = n / 2 + 8, r = 1;
    while (r < want) r <<= 1;
    return r;
}
// the variant whose hash every element of the TSet at s obeys, or -1
static int pair_set(u64 s, int nbodies)
{
    u64 data = *(u64 *)s;
    int num = *(int *)(s + 8), max = *(int *)(s + 12), nbits = *(int *)(s + 40), maxbits = *(int *)(s + 44);
    int nfree = *(int *)(s + 52), hs = *(int *)(s + 72);
    if (num < 1 || max < num || max > (1 << 20) || !data || (data & 3) || nbits != num || maxbits < nbits || nfree != 0) return -1;
    if (hs < 1 || (hs & (hs - 1)) || hs > (1 << 20)) return -1;
    u64 bits = *(u64 *)(s + 32) ? *(u64 *)(s + 32) : s + 16;
    u64 hash = hs > 1 ? *(u64 *)(s + 64) : s + 56;
    if (!mem_readable(data, (u64)num * PT_ELEM) || !mem_readable(bits, (u64)(nbits + 31) / 32 * 4) || !mem_readable(hash, (u64)hs * 4)) return -1;
    for (int i = 0; i < num; i++) if (!(((const u32 *)bits)[i >> 5] >> (i & 31) & 1)) return -1;
    for (int v = 0; v < 2; v++) {
        int ok = 1;
        for (int i = 0; i < num && ok; i++) {
            const int *e = (const int *)(data + (u64)i * PT_ELEM);
            ok = e[0] >= 0 && e[0] < e[1] && e[1] < nbodies && e[4] == (int)(pair_hash(v, e[0], e[1]) & (u32)(hs - 1));
        }
        int seen = 0;
        for (int b = 0; b < hs && ok; b++)
            for (int id = ((const int *)hash)[b], steps = 0; id != -1 && ok; steps++) {
                ok = id >= 0 && id < num && steps < num && ((const int *)(data + (u64)id * PT_ELEM))[4] == b;
                if (ok) { seen++; id = ((const int *)(data + (u64)id * PT_ELEM))[3]; }
            }
        if (ok && seen == num) return v;
    }
    return -1;
}
static int known_at = -1, known_variant = -1; // where the first table was, and its hash
#define PT_KEEP 256 // pairs that collide: her arms and legs, and every cut-off piece against the rest of her
static int kept_pair(const u64 *keep, int nkeep, int a, int b)
{
    for (int i = 0; i < nkeep; i++) if ((int)keep[2 * i] == a && (int)keep[2 * i + 1] == b) return 1;
    return 0;
}
static void table_cmd(u64 pa, int nbodies, const u64 *keep, int nkeep)
{
    if (pa < 0x10000 || nbodies < 2 || nbodies > 4096) { skin_result("err bad asset"); return; }
    // the first one from the asset's start: the scan reaches past its end, where the next asset in memory may keep a
    // table of its own (CH_P_EVE_08's, playtest 38). Once found, every asset's is at that offset (one class). Only
    // what is read is asked readable: an asset near the end of its pages failed the whole scan's check once the table's
    // place was known, and her bodies collided with each other (a cut-off leg thrown off her, playtest)
    if (!mem_readable(pa, (known_at >= 0 ? (u64)known_at : 0x28) + 80)) { skin_result("err asset unreadable"); return; }
    int at = -1, variant = -1;
    if (known_at >= 0) {
        if (pair_set(pa + known_at, nbodies) == known_variant) at = known_at, variant = known_variant;
    } else {
        for (int off = 0x28; off < PT_SCAN && at < 0 && mem_readable(pa + off, 80); off += 8) {
            int v = pair_set(pa + off, nbodies);
            if (v >= 0) at = off, variant = v;
        }
    }
    if (at < 0) { skin_result(known_at >= 0 ? "err no table where the others were" : "err no table"); return; }
    known_at = at; known_variant = variant;
    u64 s = pa + at;
    int nk = 0;
    for (int i = 0; i < nkeep; i++)
        if ((int)keep[2 * i] >= 0 && keep[2 * i] < keep[2 * i + 1] && (int)keep[2 * i + 1] < nbodies
            && !kept_pair(keep, i, (int)keep[2 * i], (int)keep[2 * i + 1])) nk++;
    int old = *(int *)(s + 8), m = nbodies * (nbodies - 1) / 2 - nk;
    if (m < 1) { skin_result("err nothing left in the table"); return; }
    char msg[96], *o = put(msg, "ok table +");
    o = put_int(o, at); o = put(o, " "); o = put_int(o, old); o = put(o, " -> "); o = put_int(o, m);
    if (nkeep) { o = put(o, " colliding "); o = put_int(o, nk); }
    if (old == m && !nkeep) { o = put(o, " already"); *o = 0; skin_result(msg); return; }
    u32 hs = hash_buckets((u32)m), words = ((u32)m + 31) / 32;
    unsigned char *data = ue_malloc((u64)m * PT_ELEM);
    u32 *bits = ue_malloc((u64)words * 4);
    int *hash = ue_malloc((u64)hs * 4);
    if (!data || !bits || !hash) {
        if (data) ue_free(data);
        if (bits) ue_free(bits);
        if (hash) ue_free(hash);
        skin_result("err no memory"); return;
    }
    for (u32 b = 0; b < hs; b++) hash[b] = -1;
    for (u32 w = 0; w < words; w++) bits[w] = 0;
    int i = 0;
    for (int a = 0; a < nbodies; a++)
        for (int b = a + 1; b < nbodies; b++) {
            if (nkeep && kept_pair(keep, nkeep, a, b)) continue;
            int *e = (int *)(data + (u64)i * PT_ELEM);
            int bucket = (int)(pair_hash(variant, a, b) & (hs - 1));
            e[0] = a; e[1] = b; e[2] = 0; e[3] = hash[bucket]; e[4] = bucket;
            hash[bucket] = i;
            bits[i >> 5] |= 1u << (i & 31);
            i++;
        }
    void *odata = *(void **)s, *obits = *(void **)(s + 32), *ohash = *(int *)(s + 72) > 1 ? *(void **)(s + 64) : 0;
    // (game thread, before the physics step: nothing reads the table meanwhile)
    *(u64 *)s = (u64)data; *(int *)(s + 8) = m; *(int *)(s + 12) = m;
    *(u64 *)(s + 32) = (u64)bits; *(int *)(s + 40) = m; *(int *)(s + 44) = (int)(words * 32);
    *(int *)(s + 48) = -1; *(int *)(s + 52) = 0;
    *(u64 *)(s + 64) = (u64)hash; *(int *)(s + 72) = (int)hs;
    if (odata) ue_free(odata);
    if (obits) ue_free(obits);
    if (ohash) ue_free(ohash);
    o = put(o, variant ? " hash b+23a" : " hash a+23b"); *o = 0;
    skin_result(msg);
}

// "j<physics asset>,<joints>,<its first joint>,<new joint>...": new UPhysicsConstraintTemplates (physfix.lua makes
// them, the asset their outer) appended to UPhysicsAsset::ConstraintSetup, the joints the engine makes a ragdoll's
// constraints from: a locked joint for each body no joint holds, as the build's outfits.py adds them (CH_P_EVE_29's
// thigh twists, which carry her upper thighs' skin: a constraint component made at the ragdoll's start didn't hold
// them, playtest 39). The array is found as the TArray of the asset whose length is <joints> and whose first element
// is <its first joint>; the longer copy comes from GMalloc and the old one goes back to it
static void joints_cmd(const u64 *f, int k)
{
    u64 pa = f[0];
    int n = (int)f[1], add = k - 3;
    if (pa < 0x10000 || n < 1 || f[2] < 0x10000 || add < 1) { skin_result("err want j<asset>,<joints>,<first>,<new>..."); return; }
    if (!mem_readable(pa, 0x200)) { skin_result("err asset unreadable"); return; }
    for (int i = 3; i < k; i++) if (f[i] < 0x10000) { skin_result("err bad joint"); return; }
    int at = -1;
    for (int off = 0x28; off + 16 <= 0x200; off += 8) {
        u64 data = *(u64 *)(pa + off);
        int num = *(int *)(pa + off + 8), max = *(int *)(pa + off + 12);
        if (num == n && max >= num && data && !(data & 7) && mem_readable(data, (u64)num * 8) && *(u64 *)data == f[2]) {
            if (at >= 0) { skin_result("err two joint arrays"); return; }
            at = off;
        }
    }
    if (at < 0) { skin_result("err no joint array"); return; }
    u64 *old = *(u64 **)(pa + at), *arr = ue_malloc((u64)(n + add) * 8);
    if (!arr) { skin_result("err no memory"); return; }
    for (int i = 0; i < n; i++) arr[i] = old[i];
    for (int i = 0; i < add; i++) arr[n + i] = f[3 + i];
    *(u64 *)(pa + at) = (u64)arr; *(int *)(pa + at + 8) = n + add; *(int *)(pa + at + 12) = n + add;
    ue_free(old);
    char msg[64], *o = put(msg, "ok joints +");
    o = put_int(o, at); o = put(o, " "); o = put_int(o, n); o = put(o, " -> "); o = put_int(o, n + add); *o = 0;
    skin_result(msg);
}

// ---- photo mode in a held death (main.lua, Shift+F4) -----------------------------------------------------------------
// The game's named constants: a singleton (RVA_SB_CONFIG) whose part at +0x378 is filled at 0x25d3ad0 with defaults,
// its bools a TMap<u32, bool> at +0xf0 (TSet elements of 16 bytes: key, value, hash links), keyed by
// FCrc::Strihash_DEPRECATED of the name (RVA_STRIHASH, called for the keys). The shipping cheat that overrides one (SBConfigOverrideBool) is a
// stub, so "f<0|1>" writes SBPhotoMode_Bypass_ActivationConditionChecks (default 0) itself: photo mode's checks
// (her being dead among them) skipped while it is 1. SBPhotoMode_Trim_LetterBox (default 1, added right after it)
// is looked for too, as a check that this is the table. Answer "ok photo <0|1> (was <0|1>)".
#define CFG_BOOLS (0x378 + 0xf0)
typedef u32 (*strihash_fn)(const u16 *);
static void photo_cmd(int on)
{
    if (!RVA_SB_CONFIG) { skin_result("err the constants not found in this game build"); return; }
    const strihash_fn strihash = (strihash_fn)(exe + RVA_STRIHASH);
    const u32 bypass = strihash(u"SBPhotoMode_Bypass_ActivationConditionChecks");
    const u32 letterbox_key = strihash(u"SBPhotoMode_Trim_LetterBox");
    u64 cfg = *(u64 *)(exe + RVA_SB_CONFIG);
    if (!mem_readable(cfg, CFG_BOOLS + 0x10)) { skin_result("err no constants object"); return; }
    u64 data = *(u64 *)(cfg + CFG_BOOLS);
    int num = *(int *)(cfg + CFG_BOOLS + 8);
    if (num <= 0 || num > 100000 || !mem_readable(data, (u64)num * 16)) { skin_result("err bad bool table"); return; }
    unsigned char *at = 0;
    int letterbox = 0;
    for (int i = 0; i < num; i++) {
        u32 key = *(u32 *)(data + (u64)i * 16);
        if (key == bypass) at = (unsigned char *)(data + (u64)i * 16 + 4);
        else if (key == letterbox_key) letterbox = 1;
    }
    if (!at || !letterbox) { skin_result(at ? "err no letterbox key (not the table?)" : "err no bypass key"); return; }
    char msg[40] = "ok photo ";
    char *o = put_int(msg + 9, on);
    o = put(o, " (was ");
    o = put_int(o, *at);
    *put(o, ")") = 0;
    *at = (unsigned char)(on != 0);
    skin_result(msg);
}

// Opening it without the key: the death keeps P from ever reaching photo mode's key handler (0x142362d00). Both key
// handlers call 0x142361aa0(manager), which queues a PhotoModeActive event; its handler (0x141abe100) asks
// 0x141cd3b10 whether photo mode may open (her state at +0x2600, the open UI list SBPhotoMode_CheckUITypeList, ...;
// SBPhotoMode_Bypass_ActivationConditionChecks is never read there in the shipping build) and, for the free camera,
// then calls 0x1422a98b0(): the enter itself (no arguments: it takes the manager, a singleton made at 0x141adc360,
// checks 0x14236b800, sets +0x84 to 1 and registers photo mode's tick). So "f2" calls that enter, the gate skipped,
// when the manager is idle (+0x38 0, +0x84 0); "f3" only reports.
// Answer "ok photo open|state: mgr 38=<b> 84=<i> 4c=<i> gate=<0|1|-> ui=<+184>/<+17c> blocked=<n> 48=<i>[ mesh shielded -> entered <0|1> 84=<i>]".
typedef u64 (*getter_fn)(void);
typedef unsigned char (*photo_enter_fn)(void);
// Photo mode, once in, sets every character mesh's collision to query only and its Pawn channel to overlap
// (0x1423a33e0: the MeshInfoList slots, virtuals +0x668 SetCollisionEnabled(1) and +0x860
// SetCollisionResponseToChannel(2, 1)), and puts them back on leaving. On her ragdoll that ended the physics: the mesh
// went back to its animated pose, a cut-off head back on her neck, and was flung from there as photo mode closed
// (playtest). So her mesh ("f2<mesh>", or "f4<mesh>" alone once a piece is off her: the game's own key opens photo
// mode too) gets its own copy of its vtable with those two slots stubbed out while photo mode is on (the manager's
// +0x84 not 0), passed on otherwise. The copy stays: an object that may be gone is only written back to when it
// still holds our copy.
#define VT_COPY 0x1400
#define VT_SET_COLLISION 0x668
#define VT_SET_RESPONSE 0x860
typedef void (*vcall4_fn)(u64, u64, u64, u64);
static u64 shield_buf[1 + VT_COPY / 8]; // [0]: the slot before the vtable (MSVC's RTTI locator), kept
#define shield_vt (shield_buf + 1)
static u64 shield_obj, shield_old_vt;
static int shield_blocked; // calls stubbed out, reported by f2 / f3
static int photo_on(void)
{
    if (!RVA_PHOTO_MGR) return 0;
    u64 mgr = RVA_PHOTO_MGR ? *(u64 *)(exe + RVA_PHOTO_MGR) : 0;
    return mem_readable(mgr, 0x88) && *(int *)(mgr + 0x84) != 0;
}
static void shield_set_collision(u64 self, u64 a, u64 b, u64 c)
{
    if (photo_on()) { shield_blocked++; return; }
    ((vcall4_fn)(*(u64 *)(shield_old_vt + VT_SET_COLLISION)))(self, a, b, c);
}
static void shield_set_response(u64 self, u64 a, u64 b, u64 c)
{
    if (photo_on()) { shield_blocked++; return; }
    ((vcall4_fn)(*(u64 *)(shield_old_vt + VT_SET_RESPONSE)))(self, a, b, c);
}
// 1 shielded now, 0 not (no object, its vtable unreadable or another class's than the first one's)
static int photo_shield(u64 obj)
{
    if (!mem_readable(obj, 8)) return 0;
    u64 vt = *(u64 *)obj;
    if (vt == (u64)shield_vt) return 1;
    if (shield_old_vt && vt != shield_old_vt) return 0; // (one copy: a mesh of another class is left alone)
    if (!mem_readable(vt - 8, VT_COPY + 8)) return 0;
    if (!shield_old_vt) {
        for (int i = 0; i < 1 + VT_COPY / 8; i++) shield_buf[i] = ((u64 *)vt)[i - 1];
        shield_vt[VT_SET_COLLISION / 8] = (u64)shield_set_collision;
        shield_vt[VT_SET_RESPONSE / 8] = (u64)shield_set_response;
        shield_old_vt = vt;
    }
    if (shield_obj && shield_obj != obj && mem_readable(shield_obj, 8) && *(u64 *)shield_obj == (u64)shield_vt)
        *(u64 *)shield_obj = shield_old_vt;
    *(u64 *)obj = (u64)shield_vt;
    shield_obj = obj;
    return 1;
}
// her mesh back on its own vtable ("f5": no piece off her any more)
static int photo_unshield(void)
{
    int was = shield_obj && mem_readable(shield_obj, 8) && *(u64 *)shield_obj == (u64)shield_vt;
    if (was) *(u64 *)shield_obj = shield_old_vt;
    shield_obj = 0;
    return was;
}
// Photo mode's camera up close hides her whole actor (playtest: AActor::bHidden set at ~80 cm, the virtual
// SetActorHiddenInGame never called). Photo mode's subject visibility (0x14239c410) hides a subject while any of its
// reasons is set: +0x220 (hidden as photo mode opened), +0x231, +0x228 (a count), +0x22d, +0x22f (the close-range
// one, 0x14239b2c0: the camera within SBPhotoMode_CloseRange_BoneToCamDistanceThreshold of her bone). Keeping
// +0x22f alone from being set wasn't enough (playtest), so "f6<0|1>" NOPs the jumps of all but +0x220 (1: a subject
// hidden before photo mode stays hidden) or puts them back (0), each one's bytes checked first. Photo mode's own
// hide-a-subject option goes with them. Answer "ok photo close <0|1> (was <0|1>)".
static const struct { u32 rva; unsigned char len, code[6]; } photo_jumps[] = {
    { 0x239c45b, 6, { 0x0f, 0x85, 0x89, 0x00, 0x00, 0x00 } }, // +0x231
    { 0x239c46b, 2, { 0x7f, 0x7d } },                         // +0x228
    { 0x239c478, 2, { 0x75, 0x70 } },                         // +0x22d
    { 0x239c485, 2, { 0x75, 0x63 } },                         // +0x22f
};
#define PHOTO_JUMPS (int)(sizeof photo_jumps / sizeof photo_jumps[0])
static void photo_close_cmd(int keep)
{
    int was = 1;
    for (int i = 0; i < PHOTO_JUMPS; i++) {
        unsigned char *p = (unsigned char *)(exe + photo_jumps[i].rva);
        int orig = 1, nops = 1;
        for (int k = 0; k < photo_jumps[i].len; k++) {
            if (p[k] != photo_jumps[i].code[k]) orig = 0;
            if (p[k] != 0x90) nops = 0;
        }
        if (!orig && !nops) { skin_result("err photo close: not the expected code"); return; }
        if (orig) was = 0;
    }
    for (int i = 0; i < PHOTO_JUMPS; i++) {
        unsigned char *p = (unsigned char *)(exe + photo_jumps[i].rva);
        u32 old;
        if (!VirtualProtect(p, photo_jumps[i].len, 0x40 /*PAGE_EXECUTE_READWRITE*/, &old)) { skin_result("err photo close: VirtualProtect"); return; }
        for (int k = 0; k < photo_jumps[i].len; k++) p[k] = keep ? 0x90 : photo_jumps[i].code[k];
        VirtualProtect(p, photo_jumps[i].len, old, &old);
    }
    char msg[40];
    char *o = put(msg, "ok photo close ");
    o = put_int(o, keep);
    o = put(o, " (was "); o = put_int(o, was);
    *put(o, ")") = 0;
    skin_result(msg);
}
// What hides her, read without calling anything ("f9<actor>", from the script's async watcher while photo mode's
// pause stops its tick): AActor::bHidden and the flags SBCharacter's own hidden state is made from (0x14203f660:
// +0x3040 forced hidden, +0x31bb / +0x8e9 forced shown, else hidden unless +0x2988 or +0x2997 is set with +0x14f8,
// +0x1508, +0x3043 and +0x3044 clear), with photo mode's manager state. Answer "ok vis hidden=<0|1> <offset>=<b> ... 84=<i> 48=<i>".
static void vis_cmd(u64 a)
{
    static const u32 offs[] = { 0x3040, 0x3041, 0x3042, 0x3043, 0x3044, 0x8e9, 0x31bb, 0x1508, 0x14f8, 0x2988, 0x2997 };
    if (!mem_readable(a, 0x31c0)) { skin_result("err vis: actor unreadable"); return; }
    char msg[300];
    char *o = put(msg, "ok vis hidden=");
    o = put_int(o, (*(unsigned char *)(a + 0x58) >> 5) & 1);
    for (unsigned i = 0; i < sizeof offs / sizeof offs[0]; i++) {
        static const char hx[] = "0123456789abcdef";
        o = put(o, " ");
        for (int sh = 12; sh >= 0; sh -= 4) if (offs[i] >> sh || sh == 0) *o++ = hx[(offs[i] >> sh) & 15];
        o = put(o, "=");
        o = put_int(o, *(unsigned char *)(a + offs[i]));
    }
    u64 mgr = RVA_PHOTO_MGR ? *(u64 *)(exe + RVA_PHOTO_MGR) : 0;
    if (mem_readable(mgr, 0x88)) {
        o = put(o, " 84="); o = put_int(o, *(int *)(mgr + 0x84));
        o = put(o, " 48="); o = put_int(o, *(int *)(mgr + 0x48));
    }
    *o = 0;
    skin_result(msg);
}
static void photo_open(int go, u64 mesh)
{
    if (!RVA_PHOTO_MGR) { skin_result("err photo mode not found in this game build"); return; }
    u64 mgr = RVA_PHOTO_MGR ? *(u64 *)(exe + RVA_PHOTO_MGR) : 0;
    if (!mem_readable(mgr, 0x600)) { skin_result("err no photo mode manager"); return; }
    u64 gate = ((getter_fn)(exe + RVA_PHOTO_GATE))();
    u64 ui = ((getter_fn)(exe + RVA_UI_STACK))();
    char msg[200];
    char *o = put(msg, go ? "ok photo open: mgr 38=" : "ok photo state: mgr 38=");
    o = put_int(o, *(unsigned char *)(mgr + 0x38));
    o = put(o, " 84="); o = put_int(o, *(int *)(mgr + 0x84));
    o = put(o, " 4c="); o = put_int(o, *(int *)(mgr + 0x4c));
    o = put(o, " gate=");
    o = mem_readable(gate, 0x78) ? put_int(o, (*(unsigned char *)(gate + 0x74) & 8) != 0) : put(o, "-");
    o = put(o, " ui=");
    if (mem_readable(ui, 0x188)) {
        o = put_int(o, (long long)(*(float *)(ui + 0x184) * 1000)); o = put(o, "/");
        o = put_int(o, (long long)(*(float *)(ui + 0x17c) * 1000));
    } else o = put(o, "-");
    o = put(o, " blocked="); o = put_int(o, shield_blocked);
    o = put(o, " 48="); o = put_int(o, *(int *)(mgr + 0x48));
    if (go && !*(unsigned char *)(mgr + 0x38) && !*(int *)(mgr + 0x84)) {
        o = put(o, mesh ? (photo_shield(mesh) ? " mesh shielded" : " mesh NOT shielded") : " no mesh");
        unsigned char in = ((photo_enter_fn)(exe + RVA_PHOTO_ENTER))();
        o = put(o, " -> entered "); o = put_int(o, in);
        o = put(o, " 84="); o = put_int(o, *(int *)(mgr + 0x84));
    } else if (go) o = put(o, " -> busy, not entered");
    *o = 0;
    skin_result(msg);
}

// ---- data table row field: "d<table>,<row struct>,<name index>,<name number>,<offset>[,<u32>]" ---------------
// UE4SS's Lua can't reach a UDataTable's rows (RowMap isn't reflected), so the 4 bytes <offset> into the row named
// (the FName's comparison index and number) are read, and written with <u32> when it is given. UDataTable: RowStruct
// at +0x28 (checked against <row struct>), RowMap (TMap<FName, uint8*>) at +0x30, its elements FName, row pointer and
// two hash links (24 bytes). Answer "ok row <row address> <old> <new>" (hex). main.lua's holdDown: Down_Eve's LifeTime
#define DT_ROWSTRUCT 0x28
#define DT_ROWMAP 0x30
#define DT_ELEM 24
static void row_cmd(const u64 *f, int k)
{
    if (k < 5 || f[0] < 0x10000 || !mem_readable(f[0], DT_ROWMAP + 0x40)) { skin_result("err bad table"); return; }
    if (*(u64 *)(f[0] + DT_ROWSTRUCT) != f[1]) { skin_result("err not its row struct"); return; }
    u64 s = f[0] + DT_ROWMAP, data = *(u64 *)s;
    int num = *(int *)(s + 8), max = *(int *)(s + 12), nbits = *(int *)(s + 40);
    if (num < 1 || max < num || num > (1 << 20) || nbits < num || !data || (data & 7) || !mem_readable(data, (u64)num * DT_ELEM)) {
        skin_result("err bad row map");
        return;
    }
    u64 bits = *(u64 *)(s + 32) ? *(u64 *)(s + 32) : s + 16;
    if (!mem_readable(bits, (u64)(num + 31) / 32 * 4)) { skin_result("err bad row map bits"); return; }
    for (int i = 0; i < num; i++) {
        if (!(((const u32 *)bits)[i >> 5] >> (i & 31) & 1)) continue;
        const u32 *e = (const u32 *)(data + (u64)i * DT_ELEM);
        if (e[0] != (u32)f[2] || e[1] != (u32)f[3]) continue;
        u64 row = *(const u64 *)(e + 2);
        if (f[4] > 0x4000 || (f[4] & 3) || !mem_readable(row + f[4], 4)) { skin_result("err bad row"); return; }
        u32 *at = (u32 *)(row + f[4]), was = *at;
        if (k > 5) *at = (u32)f[5];
        char msg[64] = "ok row ", *o = msg + 7;
        hex64(o, row); o += 16; *o++ = ' ';
        hex64(o, was); o += 16; *o++ = ' ';
        hex64(o, *at);
        skin_result(msg);
        return;
    }
    skin_result("err no such row");
}

// ---- data table rows edited in place (a table in our pak overrode every other mod's: Nexus reports of outfits gone
// with a moveset mod, a shop mod's purchase crashing). Shared by D, R and N below:
//   find the row map's element for the FName (index, number); 0 when there is none
// the hash a TMap<FName, ...> files a name under: UE 4.26's FNameEntryHandle hash (its block and offset spread
// apart) plus the number. Not the index plus the number: every one of the effect table's 4227 rows failed that check
// in game (Down_Eve never made since 0.4.0), and 40 of 40 sampled match this
static u32 fname_hash(u32 idx, u32 num)
{
    u32 block = idx >> 16, off = idx & 0xffff;
    return (block << 19) + block + (off << 16) + off + (off >> 4) + num;
}
static u64 rowmap_find(u64 table, u64 rs, u32 idx, u32 num, const char **err)
{
    *err = 0;
    if (table < 0x10000 || !mem_readable(table, DT_ROWMAP + 0x50)) { *err = "err bad table"; return 0; }
    if (*(u64 *)(table + DT_ROWSTRUCT) != rs) { *err = "err not its row struct"; return 0; }
    u64 s = table + DT_ROWMAP, data = *(u64 *)s;
    int num_e = *(int *)(s + 8), max = *(int *)(s + 12), nbits = *(int *)(s + 40);
    if (num_e < 1 || max < num_e || num_e > (1 << 20) || nbits < num_e || !data || (data & 7) || !mem_readable(data, (u64)num_e * DT_ELEM)) {
        *err = "err bad row map";
        return 0;
    }
    u64 bits = *(u64 *)(s + 32) ? *(u64 *)(s + 32) : s + 16;
    if (!mem_readable(bits, (u64)(num_e + 31) / 32 * 4)) { *err = "err bad row map bits"; return 0; }
    for (int i = 0; i < num_e; i++) {
        if (!(((const u32 *)bits)[i >> 5] >> (i & 31) & 1)) continue;
        const u32 *e = (const u32 *)(data + (u64)i * DT_ELEM);
        if (e[0] == idx && e[1] == num) return (u64)e;
    }
    return 0;
}

// an FString field set to text (ASCII, n chars). The old buffer is left to leak: something may still hold it
static int fstring_set(u64 at, const u16 *text, int n)
{
    if (!mem_readable(at, 16) || n < 0 || n > 1000) return 0;
    u16 *old = *(u16 **)at;
    int on = *(int *)(at + 8);
    if (on == n + 1 && old && mem_readable((u64)old, (u64)on * 2)) {
        int same = 1;
        for (int i = 0; i < n && same; i++) same = old[i] == text[i];
        if (same) return 2;
    }
    u16 *buf = (u16 *)ue_malloc((u64)(n + 1) * 2);
    if (!buf) return 0;
    for (int i = 0; i < n; i++) buf[i] = text[i];
    buf[n] = 0;
    *(u16 **)at = buf;
    *(int *)(at + 8) = n + 1;
    *(int *)(at + 12) = n + 1;
    return 1;
}

// "D<table>,<row struct>,<name index>,<name number>,<offset>;<text>": the row's FString at <offset> set to <text>.
// Answer "ok str set|same"
static void row_str_cmd(const u16 *txt, int len)
{
    int semi = 0;
    while (semi < len && txt[semi] && txt[semi] != ';') semi++;
    if (semi >= len) { skin_result("err no text"); return; }
    u64 f[5] = { 0 };
    if (parse_fields(txt, semi, f, 5) < 5) { skin_result("err fields"); return; }
    const char *err;
    u64 e = rowmap_find(f[0], f[1], (u32)f[2], (u32)f[3], &err);
    if (!e) { skin_result(err ? err : "err no such row"); return; }
    u64 row = *(u64 *)(e + 8);
    if (f[4] > 0x4000 || (f[4] & 7) || !mem_readable(row + f[4], 16)) { skin_result("err bad row"); return; }
    int n = 0;
    while (semi + 1 + n < len && txt[semi + 1 + n]) n++;
    int r = fstring_set(row + f[4], txt + semi + 1, n);
    skin_result(r == 2 ? "ok str same" : r ? "ok str set" : "err str");
}

// "N<table>,<row struct>,<name index>,<name number>,<offset>,<from index>,<from number>,<to index>,<to number>":
// in the row's TArray<FName> at <offset>, every <from> becomes <to>. Answer "ok names <replaced> of <count>"
static void row_names_cmd(const u16 *txt, int len)
{
    u64 f[9] = { 0 };
    if (parse_fields(txt, len, f, 9) < 9) { skin_result("err fields"); return; }
    const char *err;
    u64 e = rowmap_find(f[0], f[1], (u32)f[2], (u32)f[3], &err);
    if (!e) { skin_result(err ? err : "err no such row"); return; }
    u64 row = *(u64 *)(e + 8);
    if (f[4] > 0x4000 || (f[4] & 7) || !mem_readable(row + f[4], 16)) { skin_result("err bad row"); return; }
    u32 *names = *(u32 **)(row + f[4]);
    int n = *(int *)(row + f[4] + 8), done = 0;
    if (n < 0 || n > 4096 || (n && (!names || !mem_readable((u64)names, (u64)n * 8)))) { skin_result("err bad array"); return; }
    for (int i = 0; i < n; i++)
        if (names[i * 2] == (u32)f[5] && names[i * 2 + 1] == (u32)f[6]) { names[i * 2] = (u32)f[7]; names[i * 2 + 1] = (u32)f[8]; done++; }
    char msg[48] = "ok names ", *o = put_int(msg + 9, done);
    o = put(o, " of "); *put_int(o, n) = 0;
    skin_result(msg);
}

// "Y<value>" or "Y<table>,<row struct>,<name index>,<name number>" (the row's data pointer): where the value sits in
// private read-write memory, with the 4 qwords before and after each (a probe for the game's own lookups of a data
// table's rows). Answer "ok <value> hits N: <at> <8 qwords> | ..."
int mem_scan(u64 needle, u64 *hits, int max); // stats.c
static char *put_hex(char *o, u64 v);
int mem_scan_set(u64 addr, int esz, u64 *hits, int max); // stats.c
static void scan_cmd(const u16 *txt, int len)
{
    static u64 hits[24];
    static char out[24 * 200 + 64];
    u64 f[4] = { 0 }, needle;
    if (len > 0 && txt[0] == 'd') {
        // "Yd<value>": a 4-byte value, with the 4 qwords before and after each (from its own 8-aligned qword)
        int mem_scan32(u32 needle, u64 *hits, int max);
        int n = mem_scan32((u32)parse_hex(txt + 1, len - 1), hits, 24);
        char *o = put(out, "ok hits ");
        o = put_int(o, n);
        o = put(o, ":");
        for (int i = 0; i < n; i++) {
            o = put(o, i ? " | " : " ");
            o = put_hex(o, hits[i]);
            u64 b = hits[i] & ~7ull;
            for (int k = -4; k <= 4; k++) {
                u64 a = b + (u64)(k * 8);
                *o++ = ' ';
                o = mem_readable(a, 8) ? put_hex(o, *(u64 *)a) : put(o, "?");
            }
        }
        *o = 0;
        skin_result(out);
        return;
    }
    if (len > 0 && txt[0] == 'h') {
        // "Yh<element>,<element size>": TSet headers holding that element, with the 10 qwords from each
        if (parse_fields(txt + 1, len - 1, f, 2) < 2) { skin_result("err fields"); return; }
        int n = mem_scan_set(f[0], (int)f[1], hits, 24);
        char *o = put(out, "ok sets ");
        o = put_int(o, n);
        o = put(o, ":");
        for (int i = 0; i < n; i++) {
            o = put(o, i ? " | " : " ");
            o = put_hex(o, hits[i]);
            for (int k = 0; k < 10; k++) {
                u64 a = hits[i] + (u64)(k * 8);
                *o++ = ' ';
                o = mem_readable(a, 8) ? put_hex(o, *(u64 *)a) : put(o, "?");
            }
        }
        *o = 0;
        skin_result(out);
        return;
    }
    if (parse_fields(txt, len, f, 4) == 4) {
        const char *err;
        u64 e = rowmap_find(f[0], f[1], (u32)f[2], (u32)f[3], &err);
        if (!e) { skin_result(err ? err : "err no such row"); return; }
        needle = *(u64 *)(e + 8);
    } else needle = f[0];
    int n = mem_scan(needle, hits, 24);
    char *o = put(out, "ok ");
    o = put_hex(o, needle);
    o = put(o, " hits ");
    o = put_int(o, n);
    o = put(o, ":");
    for (int i = 0; i < n; i++) {
        o = put(o, i ? " | " : " ");
        o = put_hex(o, hits[i]);
        for (int k = -4; k <= 4; k++) {
            u64 a = hits[i] + (u64)(k * 8);
            if (k == 0) continue;
            *o++ = ' ';
            o = mem_readable(a, 8) ? put_hex(o, *(u64 *)a) : put(o, "?");
        }
    }
    *o = 0;
    skin_result(out);
}

// a TArray at p (Data, Num, Max) given a buffer of its own: esz bytes an element, the FStrings at subs[] in each too
static int tarray_own(u64 p, int esz, const int *subs, int nsub)
{
    u64 data = *(u64 *)p;
    int n = *(int *)(p + 8);
    if (n <= 0) { *(u64 *)p = 0; *(int *)(p + 8) = 0; *(int *)(p + 12) = 0; return 1; }
    if (n > 100000 || esz <= 0 || esz > 0x1000 || !data || !mem_readable(data, (u64)n * esz)) return 0;
    unsigned char *buf = (unsigned char *)ue_malloc((u64)n * esz);
    if (!buf) return 0;
    for (u64 i = 0; i < (u64)n * esz; i++) buf[i] = ((const unsigned char *)data)[i];
    for (int i = 0; i < n; i++)
        for (int s = 0; s < nsub; s++)
            if (!tarray_own((u64)buf + (u64)i * esz + subs[s], 2, 0, 0)) return 0;
    *(u64 *)p = (u64)buf;
    *(int *)(p + 12) = n;
    return 1;
}

// ---- a TSet<TPair<FName, V>> at s: sparse array (data, num, max; bits inline 4 or heap, num bits, max bits; first
// free, free count), hash (inline 1 or heap), hash size. Elements of esz bytes: the key, the value, then the hash
// chain's next index and the element's hash slot (the data table's row map, 24; the game's alias -> ID map, 20)
// a key's hash: an FName's (fname_hash), or an int's own value (ik: a TMap<int32, ...>, the key's 4 bytes then the
// value's, as aligned)
static u32 key_hash(const u32 *e, int ik) { return ik ? e[0] : fname_hash(e[0], e[1]); }
static int key_is(const u32 *e, int ik, u32 idx, u32 num) { return ik ? e[0] == idx : e[0] == idx && e[1] == num; }
// whether it reads as one, every used element filed under its key's FName hash; err says why not (the hash check
// told with how many differ and the first few's name and slot)
static int tset_ok(u64 s, int esz, int ik, const char **err)
{
    *err = 0;
    if (s < 0x10000 || !mem_readable(s, 80)) { *err = "err bad map"; return 0; }
    u64 data = *(u64 *)s;
    int num = *(int *)(s + 8), max = *(int *)(s + 12);
    u32 *bits = *(u64 *)(s + 32) ? *(u32 **)(s + 32) : (u32 *)(s + 16);
    int nbits = *(int *)(s + 40), maxbits = *(int *)(s + 44);
    int *hash = *(u64 *)(s + 64) ? *(int **)(s + 64) : (int *)(s + 56);
    int hsize = *(int *)(s + 72);
    if (num < 1 || max < num || num > (1 << 20) || !data || (data & 3) || !mem_readable(data, (u64)num * esz)
        || !mem_readable((u64)bits, (u64)(num + 31) / 32 * 4)) { *err = "err bad row map"; return 0; }
    if (hsize <= 0 || hsize > (1 << 22) || (hsize & (hsize - 1)) || !mem_readable((u64)hash, (u64)hsize * 4) || nbits != num
        || maxbits < nbits) { *err = "err row map layout"; return 0; }
    int bad = 0, used = 0;
    static char hm[1200];
    char *ho = put(hm, "err row map hash differs:");
    for (int i = 0; i < num; i++) {
        if (!(bits[i >> 5] >> (i & 31) & 1)) continue;
        used++;
        const u32 *e = (const u32 *)(data + (u64)i * esz);
        if (*(const int *)((const char *)e + esz - 4) == (int)(key_hash(e, ik) & (u32)(hsize - 1))) continue;
        if (bad++ < 40) {
            ho = put(ho, " "); ho = put_int(ho, (int)e[0]); ho = put(ho, "/"); ho = put_int(ho, (int)e[1]);
            ho = put(ho, "->"); ho = put_int(ho, *(const int *)((const char *)e + esz - 4));
        }
    }
    if (bad) {
        ho = put(ho, " ("); ho = put_int(ho, bad); ho = put(ho, " of "); ho = put_int(ho, used); ho = put(ho, ", hash size ");
        ho = put_int(ho, hsize); ho = put(ho, ")"); *ho = 0;
        *err = hm;
        return 0;
    }
    return 1;
}
// the element keyed (idx, num), or 0 (s checked with tset_ok)
static u64 tset_find(u64 s, int esz, int ik, u32 idx, u32 num)
{
    u64 data = *(u64 *)s;
    int n = *(int *)(s + 8);
    u32 *bits = *(u64 *)(s + 32) ? *(u32 **)(s + 32) : (u32 *)(s + 16);
    for (int i = 0; i < n; i++) {
        if (!(bits[i >> 5] >> (i & 31) & 1)) continue;
        const u32 *e = (const u32 *)(data + (u64)i * esz);
        if (key_is(e, ik, idx, num)) return (u64)e;
    }
    return 0;
}
// a new element keyed (idx, num) holding the vsz bytes at val (s checked with tset_ok, the key not in it): a free
// slot, else one more at the end (the arrays grown in the engine's memory; the old ones are left, a reader on another
// thread may be walking them). Returns it, or 0 out of memory
static u64 tset_add(u64 s, int esz, int ik, u32 idx, u32 num, const void *val, int vsz)
{
    u64 data = *(u64 *)s;
    int n = *(int *)(s + 8), max = *(int *)(s + 12);
    u32 *bits = *(u64 *)(s + 32) ? *(u32 **)(s + 32) : (u32 *)(s + 16);
    int nbits = *(int *)(s + 40), maxbits = *(int *)(s + 44);
    int firstfree = *(int *)(s + 48), nfree = *(int *)(s + 52);
    int *hash = *(u64 *)(s + 64) ? *(int **)(s + 64) : (int *)(s + 56);
    int hsize = *(int *)(s + 72);
    int at;
    if (nfree > 0 && firstfree >= 0 && firstfree < n) {
        at = firstfree;
        int next = *(int *)(data + (u64)at * esz + 4);
        *(int *)(s + 48) = next;
        *(int *)(s + 52) = nfree - 1;
        if (nfree > 1 && next >= 0 && next < n) *(int *)(data + (u64)next * esz) = -1;
    } else {
        if (n == max) {
            int nmax = max + 16;
            unsigned char *nd = (unsigned char *)ue_malloc((u64)nmax * esz);
            if (!nd) return 0;
            for (u64 i = 0; i < (u64)n * esz; i++) nd[i] = ((const unsigned char *)data)[i];
            data = (u64)nd;
            *(u64 *)s = data;
            *(int *)(s + 12) = nmax;
        }
        if (nbits == maxbits) {
            int nmaxb = (maxbits + 32 + 31) & ~31;
            u32 *nb = (u32 *)ue_malloc((u64)nmaxb / 8);
            if (!nb) return 0;
            for (int i = 0; i < nmaxb / 32; i++) nb[i] = i < (maxbits + 31) / 32 ? bits[i] : 0;
            bits = nb;
            *(u32 **)(s + 32) = nb;
            *(int *)(s + 44) = nmaxb;
        }
        at = n;
        *(int *)(s + 8) = n + 1;
        *(int *)(s + 40) = nbits + 1;
    }
    unsigned char *e = (unsigned char *)(data + (u64)at * esz);
    int ksz = ik ? 4 : 8;
    ((u32 *)e)[0] = idx;
    if (!ik) ((u32 *)e)[1] = num;
    for (int i = 0; i < vsz; i++) e[ksz + i] = ((const unsigned char *)val)[i];
    int hi = (int)(key_hash((const u32 *)e, ik) & (u32)(hsize - 1));
    *(int *)(e + esz - 8) = hash[hi];
    *(int *)(e + esz - 4) = hi;
    bits[at >> 5] |= 1u << (at & 31);
    hash[hi] = at;
    return (u64)e;
}

// heap fields of a row as A and M take them: "<offset>:<element size>[:<FString offset in an element>/...]" comma
// separated, from txt[i]
#define MAX_HEAP_FIELDS 64
typedef struct { int off[MAX_HEAP_FIELDS], esz[MAX_HEAP_FIELDS], sub[MAX_HEAP_FIELDS][4], nsub[MAX_HEAP_FIELDS], n; } HeapFields;
static int heap_parse(const u16 *txt, int i, int len, HeapFields *h)
{
    h->n = 0;
    while (i < len && txt[i] && h->n < MAX_HEAP_FIELDS) {
        u64 v[6] = { 0 };
        int k = 0;
        u64 x = 0;
        for (; i < len && txt[i] && txt[i] != ','; i++) {
            int d = hexval(txt[i]);
            if (d >= 0) { x = x << 4 | (u64)d; continue; }
            if ((txt[i] == ':' || txt[i] == '/') && k < 5) { v[k++] = x; x = 0; continue; }
            return 0;
        }
        if (k < 6) v[k++] = x;
        if (k < 2) return 0;
        h->off[h->n] = (int)v[0]; h->esz[h->n] = (int)v[1]; h->nsub[h->n] = k - 2;
        for (int s = 2; s < k; s++) h->sub[h->n][s - 2] = (int)v[s];
        h->n++;
        if (i < len && txt[i] == ',') i++;
    }
    return 1;
}
// the row struct's size: its PropertiesSize, the one int in its header between least and 16 bytes more followed by
// an alignment; 0 when not found once
static int row_size(u64 rs, int least)
{
    int size = 0, found = 0;
    if (!mem_readable(rs, 0xa0)) return 0;
    for (int at = 0x30; at <= 0x90; at += 4) {
        int v = *(int *)(rs + at), al = *(int *)(rs + at + 4);
        if (v >= least && v <= least + 16 && !(v & 3) && (al == 4 || al == 8 || al == 16)) { size = v; found++; }
    }
    return found == 1 && size > 0 && size <= 0x4000 ? size : 0;
}
// a copy of the size bytes at src in the engine's memory, its heap fields given buffers of their own; 0 on failure
static u64 row_copy(u64 src, int size, const HeapFields *h)
{
    for (int i = 0; i < h->n; i++) if (h->off[i] < 0 || h->off[i] + 16 > size) return 0;
    if (!mem_readable(src, (u64)size)) return 0;
    unsigned char *row = (unsigned char *)ue_malloc((u64)size);
    if (!row) return 0;
    for (int i = 0; i < size; i++) row[i] = ((const unsigned char *)src)[i];
    for (int i = 0; i < h->n; i++)
        if (!tarray_own((u64)row + h->off[i], h->esz[i], h->sub[i], h->nsub[i])) return 0;
    return (u64)row;
}

// "A<table>,<row struct>,<from index>,<from number>,<new index>,<new number>,<least size>;<heap fields>": a new row
// <new> made a copy of <from>, added to the table's row map. Heap fields (FString, TArray) get buffers of their own
// (heap_parse). The row size is the row struct's (row_size). The map's hash must place every row as UE 4.26's
// GetTypeHash(FName) does (fname_hash), or nothing is added. Answer "ok row added <row>" or "ok row exists <row>"
static void row_add_cmd(const u16 *txt, int len)
{
    int semi = 0;
    while (semi < len && txt[semi] && txt[semi] != ';') semi++;
    u64 f[7] = { 0 };
    if (parse_fields(txt, semi, f, 7) < 7) { skin_result("err fields"); return; }
    static HeapFields hf;
    if (!heap_parse(txt, semi + 1, len, &hf)) { skin_result("err heap fields"); return; }
    const char *err;
    u64 have = rowmap_find(f[0], f[1], (u32)f[4], (u32)f[5], &err);
    if (err) { skin_result(err); return; }
    char msg[64], *o;
    if (have) {
        o = put(msg, "ok row exists "); hex64(o, *(u64 *)(have + 8)); o[16] = 0;
        skin_result(msg);
        return;
    }
    u64 src = rowmap_find(f[0], f[1], (u32)f[2], (u32)f[3], &err);
    if (!src) { skin_result(err ? err : "err no source row"); return; }
    int size = row_size(f[1], (int)f[6]);
    if (!size || !mem_readable(*(u64 *)(src + 8), (u64)size)) { skin_result("err row size"); return; }
    u64 s = f[0] + DT_ROWMAP;
    if (!tset_ok(s, DT_ELEM, 0, &err)) { skin_result(err); return; }
    u64 row = row_copy(*(u64 *)(src + 8), size, &hf);
    if (!row) { skin_result("err heap field copy"); return; }
    if (!tset_add(s, DT_ELEM, 0, (u32)f[4], (u32)f[5], &row, 8)) { skin_result("err no memory"); return; }
    o = put(msg, "ok row added "); hex64(o, row); o[16] = 0;
    skin_result(msg);
}

// ---- the game's own lookups of the effect table, made from it at load: alias -> ID, a TMap<FName, int32>, and ID ->
// alias, a TMap<int32, FName> (elements of 20 both). Down_Eve in the table alone was in neither: a knockdown chained
// into it stood her straight up, no getup (playtest). Found by where a row's name (Y) and ID (Yd) sit in memory, their
// headers by Mh / Mi.
// "Mh<element>,<element size>" (FName keys) or "Mi..." (int keys): the header of the TSet holding that element
// (mem_scan_set's candidates, the first that reads as one: tset_ok). Answer "ok set <header>", else each candidate
// and why not
static void game_set_cmd(const u64 *f, int ik)
{
    static u64 hits[64];
    int n = mem_scan_set(f[0], (int)f[1], hits, 64);
    static char msg[2400];
    char *o = put(msg, "err no set of ");
    o = put_int(o, n);
    o = put(o, " candidates:");
    for (int i = 0; i < n; i++) {
        const char *e2;
        int ok = tset_ok(hits[i], (int)f[1], ik, &e2);
        if (ok && tset_find(hits[i], (int)f[1], ik, ((const u32 *)f[0])[0], ((const u32 *)f[0])[1]) == f[0]) {
            o = put(msg, "ok set ");
            *put_hex(o, hits[i]) = 0;
            skin_result(msg);
            return;
        }
        if (i < 16) {
            o = put(o, " "); o = put_hex(o, hits[i]); o = put(o, " ");
            o = put(o, ok ? "not in it" : e2 && e2[0] == 'e' ? e2 + 4 : "?");
        }
    }
    *o = 0;
    skin_result(msg);
}
// "M<alias map>,<ID map>,<table>,<row struct>,<from index>,<new index>,<ID offset>": <new> added to both with its row's
// ID, once <from> reads in them as its row (its ID under its alias, its alias under its ID). Answer "ok ids added <ID>"
// or "ok ids exists <ID>"
static void game_add_cmd(const u64 *f, int k)
{
    const char *err;
    if (k < 7) { skin_result("err fields"); return; }
    if (!tset_ok(f[0], 20, 0, &err) || !tset_ok(f[1], 20, 1, &err)) { skin_result(err); return; }
    u64 se = rowmap_find(f[2], f[3], (u32)f[4], 0, &err), ne = se ? rowmap_find(f[2], f[3], (u32)f[5], 0, &err) : 0;
    if (!se || !ne) { skin_result(err ? err : "err no such row"); return; }
    u64 srow = *(u64 *)(se + 8), nrow = *(u64 *)(ne + 8);
    if (f[6] > 0x4000 || (f[6] & 3) || !mem_readable(srow + f[6], 4) || !mem_readable(nrow + f[6], 4)) { skin_result("err bad row"); return; }
    int sid = *(int *)(srow + f[6]), id = *(int *)(nrow + f[6]);
    u64 ia = tset_find(f[0], 20, 0, (u32)f[4], 0), ib = tset_find(f[1], 20, 1, (u32)sid, 0);
    if (!ia || *(int *)(ia + 8) != sid) { skin_result("err the alias map's ID for the source isn't its row's"); return; }
    if (!ib || *(u32 *)(ib + 4) != (u32)f[4] || *(u32 *)(ib + 8) != 0) { skin_result("err the ID map's alias for the source isn't it"); return; }
    u64 na = tset_find(f[0], 20, 0, (u32)f[5], 0), nb = tset_find(f[1], 20, 1, (u32)id, 0);
    if (nb && *(u32 *)(nb + 4) != (u32)f[5]) { skin_result("err its ID is another row's in the ID map"); return; }
    char msg[64], *o;
    int added = 0;
    if (na) *(int *)(na + 8) = id;
    else if (tset_add(f[0], 20, 0, (u32)f[5], 0, &id, 4)) added++;
    else { skin_result("err no memory"); return; }
    u32 nm[2] = { (u32)f[5], 0 };
    if (!nb) { if (tset_add(f[1], 20, 1, (u32)id, 0, nm, 8)) added++; else { skin_result("err no memory"); return; } }
    o = put(msg, added ? "ok ids added " : "ok ids exists "); *put_int(o, id) = 0;
    skin_result(msg);
}
static void game_cmd(const u16 *txt, int len)
{
    static u64 gf[8];
    for (int i = 0; i < 8; i++) gf[i] = 0;
    if (len > 0 && (txt[0] == 'h' || txt[0] == 'i')) {
        if (parse_fields(txt + 1, len - 1, gf, 2) < 2) skin_result("err fields"); else game_set_cmd(gf, txt[0] == 'i');
        return;
    }
    game_add_cmd(gf, parse_fields(txt, len, gf, 7));
}

// the command running on the game thread now (its first letters), and since when (ms): the worker thread tells a
// command that never ends (sbslice.stuck) and the crash handler which one a crash came in (sbslice.crash). Gore.lua
// logs both on the next start (the Nexus report of an endless loading screen: the log ended in a death's cut, with
// nothing to say where the game stopped)
static volatile u64 cmd_since;
static char cmd_now[48];
static void exec_slice_cmd(void *context, unsigned char *stack, void *result);
static void exec_slice(void *context, unsigned char *stack, void *result)
{
    unsigned char *p = *(unsigned char **)(stack + 0x28);
    u16 *txt = *(u16 **)(p + 0x18);
    int len = *(int *)(p + 0x20);
#ifndef SBSLICE_HOSTED
    // ("H" and "v" come every frame: cheap, never what hangs, and not worth the stamp)
    int stamp = txt && len >= 2 && txt[0] != 'H' && txt[0] != 'v';
    if (stamp) {
        int n = 0;
        for (; n < (int)sizeof cmd_now - 1 && n < len - 1 && txt[n]; n++) cmd_now[n] = txt[n] < 128 ? (char)txt[n] : '?';
        cmd_now[n] = 0;
        cmd_since = GetTickCount64();
    }
    exec_slice_cmd(context, stack, result);
    if (stamp) cmd_since = 0;
#else
    (void)txt; (void)len;
    exec_slice_cmd(context, stack, result);
#endif
}
// "&<command>": one of the memory scans (Y, Yd, Mh, Mi: read only, each a pass over all the game's private memory,
// about 0.5 s) on a thread of its own, the game going on meanwhile: tables.lua's four held one frame 2.2 s at the
// level's start (playtest). Answer "ok started" or "err busy". "&?": "busy" while it runs, then "done <its answer>"
static volatile int async_busy, async_have;
static u16 async_txt[256];
static int async_len;
static void scan_cmd(const u16 *txt, int len);
static void game_cmd(const u16 *txt, int len);
static u32 WINAPI async_main(void *arg)
{
    (void)arg;
    async_tid = GetCurrentThreadId();
    if (async_txt[0] == 'Y') scan_cmd(async_txt + 1, async_len - 1); else game_cmd(async_txt + 1, async_len - 1);
    async_tid = 0;
    async_have = 1;
    __atomic_store_n(&async_busy, 0, __ATOMIC_SEQ_CST);
    return 0;
}
static void async_cmd(const u16 *txt, int len)
{
    if (len > 0 && txt[0] == '?') {
        if (__atomic_load_n(&async_busy, __ATOMIC_SEQ_CST)) { skin_result("busy"); return; }
        if (!async_have) { skin_result("err none"); return; }
        static char out[sizeof async_out + 8];
        char *o = put(out, "done ");
        for (int i = 0; async_out[i]; i++) *o++ = async_out[i];
        *o = 0;
        skin_result(out);
        return;
    }
    if (async_busy) { skin_result("err busy"); return; }
    if (len < 1 || len > 255 || !(txt[0] == 'Y' || (txt[0] == 'M' && len > 1 && (txt[1] == 'h' || txt[1] == 'i')))) {
        skin_result("err not a scan");
        return;
    }
    for (int i = 0; i < len; i++) async_txt[i] = txt[i];
    async_txt[len] = 0;
    async_len = len;
    async_have = 0;
    async_out[0] = 0;
    async_busy = 1;
    if (!CreateThread(0, 0, async_main, 0, 0, 0)) { async_busy = 0; skin_result("err no thread"); return; }
    skin_result("ok started");
}
static void exec_slice_cmd(void *context, unsigned char *stack, void *result)
{
    (void)context; (void)result;
    unsigned char *p = *(unsigned char **)(stack + 0x28);
    float *loc = (float *)(p + 8);
    u16 *txt = *(u16 **)(p + 0x18);
    int len = *(int *)(p + 0x20);
    float *dir = (float *)(p + 0x28);
    if (!txt || len < 2) return;
    if (txt[0] == '&') { async_cmd(txt + 1, len - 1); return; }
    // "H[comp,comp,...]": hold stump seams on their rim bones. No answer file — her tick sends it every frame, and a
    // command's result file is what made per-frame calls stutter. comps still alive; none means every cut
    if (txt[0] == 'H') {
        u64 hf[64];
        int k = len > 2 ? parse_fields(txt + 1, len - 1, hf, 64) : 0, any = 0;
        for (int i = 0; i < k; i++) if (hf[i] >= 0x10000) any = 1;
        sink_hold(any ? hf : 0, any ? k : 0);
        return;
    }
    if (stats_cmd(txt, len, loc, dir)) return; // v...: actor stats (stats.c)
    if (txt[0] == 'b') {
        static u64 bf[257];
        bind_cmd(bf, parse_fields(txt + 1, len - 1, bf, 257));
        return;
    }
    if (txt[0] == 'j') {
        static u64 jf[67];
        joints_cmd(jf, parse_fields(txt + 1, len - 1, jf, 67));
        return;
    }
    if (txt[0] == 't') {
        static u64 tf[2 + 2 * PT_KEEP]; // (static: 4 KB on the stack wants a stack probe; game thread only)
        for (int i = 0; i < 2 + 2 * PT_KEEP; i++) tf[i] = 0;
        int k = parse_fields(txt + 1, len - 1, tf, 2 + 2 * PT_KEEP);
        table_cmd(tf[0], (int)tf[1], tf + 2, k > 2 ? (k - 2) / 2 : 0);
        return;
    }
    if (txt[0] == 'D') { row_str_cmd(txt + 1, len - 1); return; }
    if (txt[0] == 'N') { row_names_cmd(txt + 1, len - 1); return; }
    if (txt[0] == 'A') { row_add_cmd(txt + 1, len - 1); return; }
    if (txt[0] == 'M') { game_cmd(txt + 1, len - 1); return; }
    if (txt[0] == 'Y') { scan_cmd(txt + 1, len - 1); return; }
    if (txt[0] == 'd') {
        u64 df[6] = { 0, 0, 0, 0, 0, 0 };
        row_cmd(df, parse_fields(txt + 1, len - 1, df, 6));
        return;
    }
    if (txt[0] == 'f') {
        if (txt[1] == '2' || txt[1] == '3') photo_open(txt[1] == '2', len > 2 ? parse_hex(txt + 2, len - 2) : 0);
        else if (txt[1] == '4') skin_result(len > 2 && photo_shield(parse_hex(txt + 2, len - 2)) ? "ok photo shield 1" : "ok photo shield 0");
        else if (txt[1] == '5') skin_result(photo_unshield() ? "ok photo unshield 1" : "ok photo unshield 0");
        else if (txt[1] == '6') photo_close_cmd(len > 2 && txt[2] == '1');
        else if (txt[1] == '9') { if (len > 2) vis_cmd(parse_hex(txt + 2, len - 2)); else skin_result("err vis: no actor"); }
        else photo_cmd(txt[1] == '1');
        return;
    }
    if (txt[0] == 'u') {
        u64 component = parse_hex(txt + 1, len - 1);
        if (component >= 0x10000) unpin(component);
        return;
    }
    if (txt[0] == 'o') {
        u64 obj = parse_hex(txt + 1, len - 1);
        skin_result(root_object(obj));
        return;
    }
    if (txt[0] == 'w') {
        u64 component = parse_hex(txt + 1, len - 1);
        if (component >= 0x10000) skin_watch(component); else skin_result("err bad component");
        return;
    }
    if (txt[0] == 'k') {
        char msg[32] = "ok collapsed ";
        *put_int(msg + 13, skin_collapse()) = 0;
        skin_result(msg);
        return;
    }
    if (txt[0] == 'r') {
        // "r<mesh asset>": that asset's sinks only (an enemy's corpse going away; its component may be gone with it)
        u64 rf[1] = { 0 };
        if (len > 1) parse_fields(txt + 1, len - 1, rf, 1);
        char msg[32] = "ok restored ";
        *put_int(msg + 12, skin_restore(rf[0] >= 0x10000 ? rf[0] : 0)) = 0;
        if (rf[0] < 0x10000) forget_saves(0), relax_restore();
        skin_result(msg);
        return;
    }
    if (txt[0] == 'n' || txt[0] == 'g') {
        // the nosink list, ffff, the nocarry list, fffe, the bones with bodies, fffd, driven, fffc, driven after a let-go limb
        static u64 lf[5 * MAX_BONES + 5];
        int k = parse_fields(txt + 1, len - 1, lf, 5 * MAX_BONES + 5);
        if (k < 1 || lf[0] < 0x10000) { skin_result("err bad component"); return; }
        int cnt = 0;
        if (txt[0] == 'n') {
            for (int i = 0; i < MAX_BONES; i++) nosink[i] = nocarry[i] = hasbody[i] = drivenb[i] = 0;
            nosink_mesh = *(u64 *)(lf[0] + SC_SKELETAL_MESH);
            int nc = 0;
            nbodies = 0;
            for (int i = 1; i < k; i++) {
                if (lf[i] == 0xffff) { nc = 1; continue; }
                if (lf[i] == 0xfffe) { nc = 2; continue; }
                if (lf[i] == 0xfffd) { nc = 3; continue; }
                if (lf[i] == 0xfffc) { nc = 4; continue; }
                if (lf[i] < MAX_BONES) {
                    if (nc >= 3) drivenb[lf[i]] = (unsigned char)(nc - 2);
                    else if (nc == 2) { hasbody[lf[i]] = 1; nbodies++; }
                    else if (nc) nocarry[lf[i]] = 1; else { nosink[lf[i]] = 1; cnt++; }
                }
            }
        } else {
            limbs_comp = lf[0]; ngone = nkeep = nride = ndrop = 0;
            free_spine = -1; free_upper = 0;
            int keep = 0, nfs = 0;
            for (int i = 1; i < k; i++) {
                if (lf[i] == 0) { keep++; continue; }
                if (keep >= 4) { if (nfs == 0) free_spine = lf[i] < MAX_BONES ? (int)lf[i] : -1; else if (nfs == 1) free_upper = lf[i] == 1; nfs++; }
                else if (keep == 3) { if (ndrop < MAX_KEEP_ROOTS) drop_roots[ndrop++] = (int)lf[i]; }
                else if (keep == 2) { if (nride < MAX_RIDE) ride_bones[nride++] = (int)lf[i]; }
                else if (keep) { if (nkeep < MAX_KEEP_ROOTS) keep_roots[nkeep++] = (int)lf[i]; }
                else if (ngone < MAX_LIMB_ROOTS) gone_roots[ngone++] = (int)lf[i];
            }
            cnt = ngone * 100 + nkeep;
        }
        char msg[32] = "ok ";
        *put_int(msg + 3, cnt) = 0;
        skin_result(msg);
        return;
    }
    if (txt[0] == 'h') {
        u64 hf[3] = { 0, 0, 0 };
        parse_fields(txt + 1, len - 1, hf, 3);
        if (hf[0] < 0x10000) { skin_result("err bad component"); return; }
        float l2 = dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2];
        if (hf[1] && l2 < 1e-8f) { skin_result("err no neck normal"); return; }
        head_comp = hf[1] ? hf[0] : 0;
        head_mode = (int)hf[1];
        head_bone = (int)hf[2];
        float kk = l2 > 0 ? rsqrt(l2) : 0;
        for (int k = 0; k < 3; k++) { head_pw[k] = loc[k]; head_nw[k] = dir[k] * kk; }
        skin_result("ok neck");
        return;
    }
    if (txt[0] == 'p') {
        u64 pf[2] = { 0, 0 };
        parse_fields(txt + 1, len - 1, pf, 2);
        if (pf[0] < 0x10000 || pf[1] < 0x10000) { skin_result("err bad component"); return; }
        copy_pose(pf[0], pf[1]);
        return;
    }
    if (txt[0] == 'm') {
        u64 mf[3] = { 0, 0, 0 };
        parse_fields(txt + 1, len - 1, mf, 3);
        if (mf[0] < 0x10000) { skin_result("err bad component"); return; }
        float l2 = dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2];
        if (l2 < 1e-8f) { skin_result("err no ray"); return; }
        float kk = rsqrt(l2), nrm[3] = { dir[0] * kk, dir[1] * kk, dir[2] * kk };
        skin_mark(mf[0], (int)mf[1], loc, nrm, mf[2] ? (float)mf[2] : 30.0f);
        return;
    }
    if (txt[0] == 's') {
        u64 sf[3] = { 0, 0, 0 };
        parse_fields(txt + 1, len - 1, sf, 3);
        if (sf[0] < 0x10000) { skin_result("err bad component"); return; }
        skin_probe(sf[0], (int)sf[1], (int)(sf[2] & 0xf));
        return;
    }
    if (txt[0] == 'G') {
        static u64 gf[2 * 64];
        alive_cmd(gf, len > 1 ? parse_fields(txt + 1, len - 1, gf, 2 * 64) : 0);
        return;
    }
    if (txt[0] == 'F') {
        static u64 ff[3 * 8];
        relax_cmd(ff, len > 1 ? parse_fields(txt + 1, len - 1, ff, 3 * 8) : 0);
        return;
    }
    if (txt[0] == 'W') {
        u64 wf[2] = { 0, 0 };
        parse_fields(txt + 1, len - 1, wf, 2);
        if (wf[0] < 0x10000) { skin_result("err bad component"); return; }
        weapon_bounds(wf[0], (int)wf[1]);
        return;
    }
    if (txt[0] == 'e') {
        u64 ef[3] = { 0, 0, 0 };
        parse_fields(txt + 1, len - 1, ef, 3);
        if (ef[0] < 0x10000 || ef[1] < 0x10000 || ef[0] == ef[1]) { skin_result("err bad component"); return; }
        weapon_split(ef[0], ef[1], (int)ef[2], loc, dir);
        return;
    }
    if (txt[0] == 'S' || txt[0] == 'R') {
        u64 sf[2 + 4] = { 0, 0, 0, 0, 0, 0 };
        int k = parse_fields(txt + 1, len - 1, sf, 6);
        if (sf[0] < 0x10000) { skin_result("err bad component"); return; }
        if (txt[0] == 'S' && k > 2 && sf[2]) { forget_saves(sf[0]); skin_result("ok forgotten"); }
        else if (txt[0] == 'S') skin_save(sf[0], (int)sf[1]); else skin_back(sf[0], (int)sf[1], sf + 2, k > 2 ? k - 2 : 0);
        return;
    }
    if (txt[0] == 'y') {
        u64 yf[2 + 16];
        for (int i = 0; i < 18; i++) yf[i] = 0;
        int k = parse_fields(txt + 1, len - 1, yf, 18);
        if (k < 2 || yf[0] < 0x10000) { skin_result("err bad component"); return; }
        skin_copy(yf[0], (int)yf[1], yf + 2, k - 2);
        return;
    }
    if (txt[0] != 'c' && txt[0] != 'x') { skin_result("err unknown command"); return; }
    u64 f[7] = { 0, 0, 0, 0, 0, 0, 0 };
    int k = parse_fields(txt + 1, len - 1, f, 7);
    if (f[0] < 0x10000) { skin_result("err bad component"); return; }
    if (txt[0] == 'x') { skin_clear(f[0], (int)f[1], k > 2 && f[2]); return; }
    if (k < 3) { skin_result("err want c<comp>,<lod>,<bone>"); return; }
    float l2 = dir[0] * dir[0] + dir[1] * dir[1] + dir[2] * dir[2];
    if (l2 < 1e-8f) { skin_result("err no plane normal"); return; }
    float kk = rsqrt(l2), nrm[3] = { dir[0] * kk, dir[1] * kk, dir[2] * kk };
    skin_cut(f[0], (int)f[1], (int)f[2], loc, nrm, (int)f[3], (float)f[4] * 0.1f, (int)f[5], k > 6 ? (int)f[6] : -1);
}

static const u16 REQ[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.req";
static const u16 OK[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.ok";
static const u16 ERR[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.err";

void spawner_start(void); // spawner.c: the enemy spawner window

// ---- the addresses on another build of the game --------------------------------------------------------------------
// Each function's first bytes (rip-relative and branch fields left out, "??"), each global through an instruction that
// reads it. On the Steam build every one matches where it is; elsewhere the code section is searched, and a function
// that isn't found exactly once (FWeakObjectPtr::Get: its copies are the same code, the first one is taken; IsValid
// differs only at its end) is 0,
// with what needs it turned off (Nexus: an older or modified exe, sbslice.dll refused and no cuts at all)
typedef struct { const char *name; u64 *rva; const char *pat; int any; } sig_def;
static const sig_def SIGS[] = {
    { "exec thunk", &RVA_EXEC_REWARD_DROP_FORMATION_PATH_LOCATION, "48 8b c4 55 53 48 8b ec 48 83 ec 78 48 89 70 08 48 8b da 48 89 78 e8 4c 89 70 e0 45 33 f6 4c 89 75 b8", 0 },
    { "SetSkinWeightOverride", &RVA_SET_SKIN_WEIGHT_OVERRIDE, "48 89 5c 24 18 56 57 41 56 48 83 ec 30 4d 8b f0 48 63 fa 48 8b f1 e8 ?? ?? ?? ?? 48 8b 9e e8 07 00 00", 0 },
    { "GetSkinWeightBuffer", &RVA_GET_SKIN_WEIGHT_BUFFER, "48 8b 81 68 05 00 00 4c 8b c1 48 85 c0 0f 84 ?? ?? ?? ?? 48 8b 80 80 00 00 00", 0 },
    { "ReleaseOverrideSkinWeights", &RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS, "48 89 5c 24 08 57 48 83 ec 20 48 8b 59 18 48 8b f9 48 85 db 74 ?? 48 8d 4b 48 e8", 0 },
    { "MarkRenderStateDirty", &RVA_MARK_RENDER_STATE_DIRTY, "40 56 48 83 ec 20 48 8b f1 0f b6 89 98 00 00 00 0f b6 c1 24 03 3c 03 0f 85", 0 },
    { "FWeakObjectPtr::Get", &RVA_WEAK_PTR_GET, "44 8b 41 04 45 85 c0 74 ?? 8b 01 85 c0 78 ?? 3b 05 ?? ?? ?? ?? 7d ?? 99 0f b7 d2 03 c2 8b c8 0f b7 c0 2b c2 c1 f9 10 48 98 48 63 c9 48 8d 14 40 48 8b 05 ?? ?? ?? ?? 48 8b 0c c8 48 8d 04 d1 48 85 c0 74 ?? 44 39 40 10 75 ?? f7 40 08 00 00 00 30 75 ?? 48 8b 00 c3", 1 },
    { "NeedCPUData", &RVA_NEED_CPU_DATA, "85 d2 78 ?? 3b 91 08 01 00 00 7d ?? 48 63 c2 4c 69 c0 b8 00 00 00", 0 },
    { "Strihash", &RVA_STRIHASH, "44 0f b7 01 33 c0 4c 8b c9 66 45 85 c0 74 ?? 4c 8d 15 ?? ?? ?? ?? 66 66 0f 1f 84 00 00 00 00 00 41 0f b7 d0", 0 },
    { "photo enter", &RVA_PHOTO_ENTER, "40 53 48 83 ec 20 e8 ?? ?? ?? ?? 48 8b d8 48 85 c0 75 ?? 48 83 c4 20 5b c3 48 8b cb 48 89 7c 24 30", 0 },
    { "photo gate", &RVA_PHOTO_GATE, "48 83 ec 28 e8 ?? ?? ?? ?? 48 85 c0 74 ?? 48 89 5c 24 20 48 8b 98 08 03 00 00", 0 },
    { "UI stack", &RVA_UI_STACK, "48 83 ec 28 48 8b 05 ?? ?? ?? ?? 48 85 c0 75 ?? 48 8b 0d ?? ?? ?? ?? 48 85 c9 75 ?? e8 ?? ?? ?? ?? 48 8b 0d ?? ?? ?? ?? 48 8b 01 45 33 c0 ba 20 02 00 00", 0 },
};
// the game's constants singleton's getter: made 0x698 bytes in GMalloc (its two globals, +7 and +0x13)
static const char SIG_CONFIG_GETTER[] = "48 83 ec 28 48 8b 05 ?? ?? ?? ?? 48 85 c0 75 ?? 48 8b 0d ?? ?? ?? ?? 48 85 c9 75 ?? e8 ?? ?? ?? ?? 48 8b 0d ?? ?? ?? ?? 48 8b 01 45 33 c0 ba 98 06 00 00 ff 50 10";
static u64 code_lo, code_hi; // the code section, as RVAs
static int sig_parse(const char *s, unsigned char *b, unsigned char *m)
{
    int n = 0;
    while (*s && n < 96) {
        while (*s == ' ') s++;
        if (!*s) break;
        if (s[0] == '?') { b[n] = 0; m[n++] = 0; s += 2; continue; }
        b[n] = (unsigned char)(hexval((unsigned char)s[0]) << 4 | hexval((unsigned char)s[1]));
        m[n++] = 1;
        s += 2;
    }
    return n;
}
static int sig_at(u64 rva, const unsigned char *b, const unsigned char *m, int n)
{
    if (rva < code_lo || rva + n > code_hi) return 0;
    const unsigned char *p = (const unsigned char *)(exe + rva);
    for (int i = 0; i < n; i++) if (m[i] && p[i] != b[i]) return 0;
    return 1;
}
// where the pattern is: its place when it matches there, else the one place in the code (the first with any), else 0
static u64 sig_find(const char *pat, u64 guess, int any)
{
    unsigned char b[96], m[96];
    int n = sig_parse(pat, b, m);
    if (sig_at(guess, b, m, n)) return guess;
    u64 found = 0;
    const unsigned char *p = (const unsigned char *)exe;
    for (u64 r = code_lo; r + n <= code_hi; r++) {
        if (p[r] != b[0] || !sig_at(r, b, m, n)) continue;
        if (found) return any ? found : 0;
        found = r;
        if (any) return r;
    }
    return found;
}
static u64 rip_target(u64 rva_of_disp) { return rva_of_disp + 4 + (u64)(long long)*(const int *)(exe + rva_of_disp); }
static char addr_state[240] = "addresses not looked for";
static int addr_missing_core;
static void resolve_addresses(void)
{
    // the code section: the executable one holding the thunk's place, else the biggest executable one
    u64 nt = exe + *(const u32 *)(exe + 0x3c);
    int nsec = *(const unsigned short *)(nt + 6), opt = *(const unsigned short *)(nt + 0x14);
    const unsigned char *sec = (const unsigned char *)(nt + 0x18 + opt);
    u64 best = 0;
    for (int i = 0; i < nsec; i++, sec += 40) {
        u32 va = *(const u32 *)(sec + 12), vs = *(const u32 *)(sec + 8), ch = *(const u32 *)(sec + 36);
        if (!(ch & 0x20000000)) continue; // IMAGE_SCN_MEM_EXECUTE
        if (RVA_EXEC_REWARD_DROP_FORMATION_PATH_LOCATION >= va && RVA_EXEC_REWARD_DROP_FORMATION_PATH_LOCATION < va + vs) { code_lo = va; code_hi = va + vs; break; }
        if (vs > best) { best = vs; code_lo = va; code_hi = va + vs; }
    }
    int moved = 0, missing = 0;
    char *o = addr_state, *mo = 0;
    static char miss[120];
    char *mp = miss;
    for (int i = 0; i < (int)(sizeof SIGS / sizeof SIGS[0]); i++) {
        u64 was = *SIGS[i].rva, r = sig_find(SIGS[i].pat, was, SIGS[i].any);
        *SIGS[i].rva = r;
        if (r != was) moved++;
        if (!r) {
            missing++;
            if (mp - miss < 90) { if (mp != miss) *mp++ = ','; mp = put(mp, SIGS[i].name); }
            if (SIGS[i].rva != &RVA_NEED_CPU_DATA && SIGS[i].rva != &RVA_STRIHASH && SIGS[i].rva != &RVA_PHOTO_ENTER
                && SIGS[i].rva != &RVA_PHOTO_GATE && SIGS[i].rva != &RVA_UI_STACK) addr_missing_core = 1;
        }
    }
    *mp = 0;
    // globals: GUObjectArray from FWeakObjectPtr::Get's `cmp eax, [NumElements]` (+0x24 in it); the constants and
    // GMalloc from the constants' getter; the photo manager from the getter photo enter calls first
    u64 g;
    g = RVA_WEAK_PTR_GET ? rip_target(RVA_WEAK_PTR_GET + 0x11) - 0x24 : 0;
    if (g != RVA_GUOBJECTARRAY) moved++;
    RVA_GUOBJECTARRAY = g;
    u64 cg = sig_find(SIG_CONFIG_GETTER, 0x1a977b0, 0);
    g = cg ? rip_target(cg + 7) : 0;
    if (g != RVA_SB_CONFIG) moved++;
    RVA_SB_CONFIG = g;
    g = cg ? rip_target(cg + 0x13) : 0;
    if (g != RVA_GMALLOC) moved++;
    RVA_GMALLOC = g;
    if (!g) addr_missing_core = 1;
    u64 pg = RVA_PHOTO_ENTER ? rip_target(RVA_PHOTO_ENTER + 7) : 0;
    g = pg && pg >= code_lo && pg < code_hi && *(const unsigned char *)(exe + pg + 4) == 0x48 ? rip_target(pg + 7) : 0;
    if (g != RVA_PHOTO_MGR) moved++;
    RVA_PHOTO_MGR = g;
    if (!cg) { if (mp - miss < 90) { if (mp != miss) *mp++ = ','; mp = put(mp, "constants"); *mp = 0; } missing++; }
    if (!RVA_PHOTO_MGR && RVA_PHOTO_ENTER) { if (mp - miss < 90) { if (mp != miss) *mp++ = ','; mp = put(mp, "photo manager"); *mp = 0; } missing++; }
    if (!RVA_SB_CONFIG || !RVA_STRIHASH) RVA_SB_CONFIG = RVA_STRIHASH = 0;
    if (!RVA_PHOTO_MGR || !RVA_PHOTO_GATE || !RVA_UI_STACK) RVA_PHOTO_MGR = RVA_PHOTO_ENTER = 0;
    if (!moved && !missing) { put(o, "addresses as in the Steam build"); return; }
    o = put(o, "another game build: ");
    o = put_int(o, moved);
    o = put(o, " addresses found elsewhere");
    if (missing) { o = put(o, ", not found: "); o = put(o, miss); }
    *o = 0;
    (void)mo;
}

// Every skeletal mesh keeps a CPU copy of its LOD 0 (the cut reads it), so outfit mods need no bAllowCPUAccess
// repack. NeedCPUData opens with `test edx,edx; js <null LODInfo>`; the js becomes `jle <return 1>`, so LOD <= 0
// answers yes and the rest still read bAllowCPUAccess. The render data asks it while a mesh loads: anything loaded
// before this DLL keeps what it had.
static const char *cpu_state = "cpu copy patch not tried";

static void patch_cpu_access(void)
{
    if (!RVA_NEED_CPU_DATA) { cpu_state = "cpu copy patch skipped: NeedCPUData not found (other game build)"; return; }
    unsigned char *p = (unsigned char *)(exe + RVA_NEED_CPU_DATA);
    static const unsigned char want[] = { 0x85, 0xd2, 0x78, 0x00, 0x3b, 0x91, 0x08, 0x01, 0x00, 0x00 };
    // its `mov al,1; ret` (0x28 on: the js's target and the jle's on the Steam build)
    int yes = 0;
    for (int i = 12; i < 0x60 && !yes; i++) if (p[i] == 0xb0 && p[i + 1] == 0x01 && p[i + 2] == 0xc3) yes = i;
    if (!yes || yes - 4 > 127) { cpu_state = "cpu copy patch skipped: NeedCPUData's return 1 not found (other game build?)"; return; }
    if (p[2] == 0x7e && p[3] == yes - 4) { cpu_state = "cpu copy LOD0 on (already)"; return; }
    for (int i = 0; i < (int)sizeof want; i++)
        if (i != 3 && p[i] != want[i]) { cpu_state = "cpu copy patch skipped: NeedCPUData bytes differ (other game build?)"; return; }
    u32 old;
    if (!VirtualProtect(p, 4, 0x40 /*PAGE_EXECUTE_READWRITE*/, &old)) { cpu_state = "cpu copy patch failed: VirtualProtect"; return; }
    *(volatile unsigned short *)(p + 2) = (unsigned short)(0x7e | (yes - 4) << 8); // jle to the `mov al,1; ret`, one aligned 2-byte store
    VirtualProtect(p, 4, old, &old);
    FlushInstructionCache(GetCurrentProcess(), p, 4);
    cpu_state = "cpu copy LOD0 on";
}

static const u16 STUCK[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.stuck";
static const u16 CRASH[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.crash";
// (by this DLL's own path, Mods\SBSlice\dlls\main.dll: the game's working directory may not be set yet in DllMain)
static u16 BOOT[600];
static void boot_path(void *inst)
{
    static const u16 tail[] = u"StellarBladeGore\\sbslice.boot";
    u32 n = GetModuleFileNameW(inst, BOOT, 512);
    int cut = 0;
    for (int i = (int)n - 1, seen = 0; i >= 0; i--) if (BOOT[i] == '\\' && ++seen == 3) { cut = i + 1; break; }
    if (!cut) { BOOT[0] = 0; return; }
    for (int i = 0; tail[i]; i++) BOOT[cut++] = tail[i];
    BOOT[cut] = 0;
}
static u64 self_lo, self_hi; // this DLL's image
static char *put_hex(char *o, u64 v) { char h[17]; hex64(h, v); int i = 0; while (i < 15 && h[i] == '0') i++; return put(o, h + i); }
// a crash on any thread in this DLL's code, or on the game thread inside a mod command: where (the DLL's own offset,
// or the game's), the code, the command. Looked at, never handled (the engine's crash handling goes on as before)
static volatile long crash_seen;
static long WINAPI crash_note(void *info)
{
    u32 *rec = *(u32 **)info;  // EXCEPTION_POINTERS.ExceptionRecord
    u32 code = rec[0];
    u64 at = *(u64 *)((char *)rec + 16);
    // access violation, illegal instruction, stack overflow, divide by zero, privileged instruction
    if (code != 0xc0000005 && code != 0xc000001d && code != 0xc00000fd && code != 0xc0000094 && code != 0xc0000096) return 0;
    int mine = at >= self_lo && at < self_hi;
    if ((!mine && !cmd_since) || crash_seen) return 0;
    crash_seen = 1;
    static char msg[256];
    char *o = put(msg, "crash ");
    o = put_hex(o, code);
    o = put(o, mine ? " in sbslice.dll +" : " in the game +");
    o = put_hex(o, mine ? at - self_lo : at - exe);
    if (code == 0xc0000005) { o = put(o, " at address "); o = put_hex(o, *(u64 *)((char *)rec + 40)); }
    if (cmd_since) { o = put(o, " in command "); o = put(o, cmd_now); }
    *o = 0;
    write_file(CRASH, msg);
    return 0; // EXCEPTION_CONTINUE_SEARCH
}

static u32 WINAPI worker(void *arg)
{
    (void)arg;
    const u64 thunk = RVA_EXEC_REWARD_DROP_FORMATION_PATH_LOCATION ? exe + RVA_EXEC_REWARD_DROP_FORMATION_PATH_LOCATION : 0;
    u64 stuck_since = 0;
    static char stuck_cmd[48];
    for (;;) {
        Sleep(250);
        // a mod command running 3 s and more: told once (and again when it ends, if it does)
        u64 since = cmd_since, now = GetTickCount64();
        if (since && since != stuck_since && now - since > 3000) {
            stuck_since = since;
            int n = 0;
            for (; n < (int)sizeof stuck_cmd - 1 && cmd_now[n]; n++) stuck_cmd[n] = cmd_now[n];
            stuck_cmd[n] = 0;
            char msg[96], *o = put(msg, "stuck over 3 s in command ");
            o = put(o, stuck_cmd); *o = 0;
            write_file(STUCK, msg);
        } else if (stuck_since && since != stuck_since) {
            char msg[112], *o = put(msg, "a command ran over 3 s (it ended): ");
            o = put(o, stuck_cmd); *o = 0;
            write_file(STUCK, msg);
            stuck_since = 0;
        }
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
        // UFunction::Func holds the thunk address; find that field instead of trusting a layout offset (on another
        // build, where the thunk wasn't found by its code: UE 4.27's +0xd8, when it holds an address in the code)
        char msg[256] = "no thunk pointer in UFunction ";
        if (addr_missing_core) {
            char *o = put(msg, "this game build isn't one sbslice.dll can work with (");
            o = put(o, addr_state);
            *put(o, "): no cuts, and no outfit physics fix") = 0;
            write_file(ERR, msg);
            continue;
        }
        // (readable first: a Steam Deck read an unmapped address here and the game closed, Nexus report)
        if (ufunc >= 0x10000 && !mem_readable(ufunc, 0x40 * 8 + 8)) {
            char *o = put(msg, "the UFunction's address isn't readable: ");
            hex64(o, ufunc);
            o[16] = 0;
            write_file(ERR, msg);
            continue;
        }
        if (ufunc >= 0x10000) {
            u64 *f = (u64 *)ufunc;
            int at = -1;
            for (int i = 0; i < 0x40 && at < 0; i++) if ((thunk && f[i] == thunk) || f[i] == (u64)exec_slice) at = i;
            if (at < 0 && f[0xd8 / 8] >= exe + code_lo && f[0xd8 / 8] < exe + code_hi) at = 0xd8 / 8;
            if (at >= 0) {
                f[at] = (u64)exec_slice;
                char ok[400] = "patched +0x";
                hex64(ok + 11, (u64)at * 8);
                int n = 0;
                while (ok[n]) n++;
                ok[n++] = ',';
                ok[n++] = ' ';
                for (const char *c = cpu_state; *c && n < (int)sizeof ok - 1; c++) ok[n++] = *c;
                if (n < (int)sizeof ok - 3) { ok[n++] = ','; ok[n++] = ' '; }
                for (const char *c = addr_state; *c && n < (int)sizeof ok - 1; c++) ok[n++] = *c;
                ok[n] = 0;
                write_file(OK, ok);
                goto next;
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
        self_lo = (u64)inst;
        self_hi = self_lo + *(u32 *)(self_lo + *(u32 *)(self_lo + 0x3c) + 0x50); // SizeOfImage
        AddVectoredExceptionHandler(0, crash_note);
        // (a note of each step at the start: a launch that closed before the first window left nothing else)
        boot_path(inst);
        write_file(BOOT, "boot: looking for the addresses");
        resolve_addresses();
        write_file(BOOT, "boot: addresses looked for, patching the cpu copy");
        patch_cpu_access();
        {
            static char note[420];
            char *o = put(note, "boot: done, ");
            o = put(o, addr_state);
            o = put(o, ", ");
            o = put(o, cpu_state);
            *o = 0;
            write_file(BOOT, note);
        }
        CreateThread(0, 0, worker, 0, 0, 0);
        spawner_start();
    }
    return 1;
}
