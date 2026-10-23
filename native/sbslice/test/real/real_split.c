// Real-mesh harness: runs the vertical split (both halves, as gore.lua does) on a packed outfit mesh (pack.py) and
// checks what each half shows once the shared mesh asset's sinks are collapsed. Both halves are components of the
// same mesh asset, so a sink one half collapses moves every vertex the other half still weights to it.
//   real_split <mesh.bin> [obj prefix]   writes <prefix>_a.obj / _b.obj (posed halves) when given
// Run through ./run.sh.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#define __declspec(x)
#define __stdcall
#define CreateThread CreateThread_
#define Sleep Sleep_
#define CreateFileW CreateFileW_
#define ReadFile ReadFile_
#define WriteFile WriteFile_
#define CloseHandle CloseHandle_
#define DeleteFileW DeleteFileW_
#define GetModuleHandleW GetModuleHandleW_
#define GetModuleHandleExW GetModuleHandleExW_
#define DisableThreadLibraryCalls DisableThreadLibraryCalls_
#define VirtualAlloc VirtualAlloc_
#define VirtualFree VirtualFree_
#define VirtualProtect VirtualProtect_
#define FlushInstructionCache FlushInstructionCache_
#define GetCurrentProcess GetCurrentProcess_
#define DllMain DllMain_
#define SBSLICE_HOSTED
#include "../../sbslice.c"
void spawner_start(void) {} // the window is Win32 only
int stats_cmd(const u16 *t, int l, const float *a, const float *b) { (void)t; (void)l; (void)a; (void)b; return 0; } // stats.c: test_stats.c
static u64 ld_buf[0x900 / 8];
static u16 *act_buf; static int act_n;   // the LOD's ActiveBoneIndices as the engine built it
// (stats.c) the DLL looks for ActiveBoneIndices in the LOD's render data: those two are all there is to read
int mem_readable(u64 p, u64 n)
{
    return (p >= (u64)ld_buf && p + n <= (u64)ld_buf + sizeof ld_buf) || (act_buf && p >= (u64)act_buf && p + n <= (u64)(act_buf + act_n));
}
#undef CreateThread
#undef Sleep
#undef CreateFileW
#undef ReadFile
#undef WriteFile
#undef CloseHandle
#undef DeleteFileW
#undef GetModuleHandleW
#undef GetModuleHandleExW
#undef DisableThreadLibraryCalls
#undef VirtualAlloc
#undef VirtualFree
#undef VirtualProtect
#undef FlushInstructionCache
#undef GetCurrentProcess
static char lastres[65536];
HANDLE CreateThread_(void *a, u64 b, u32(WINAPI *c)(void *), void *d, u32 e, u32 *f) { (void)a;(void)b;(void)c;(void)d;(void)e;(void)f; return 0; }
void Sleep_(u32 x) { (void)x; }
HANDLE CreateFileW_(const u16 *p, u32 a, u32 b, void *c, u32 d, u32 e, HANDLE f) { (void)p;(void)a;(void)b;(void)c;(void)d;(void)e;(void)f; return (HANDLE)1; }
int ReadFile_(HANDLE h, void *b, u32 n, u32 *g, void *o) { (void)h;(void)b;(void)n;(void)o; *g = 0; return 1; }
int WriteFile_(HANDLE h, const void *b, u32 n, u32 *w, void *o) { (void)h;(void)o; if (n >= sizeof lastres) n = sizeof lastres - 1; memcpy(lastres, b, n); lastres[n] = 0; *w = n; return 1; }
int CloseHandle_(HANDLE h) { (void)h; return 1; }
int DeleteFileW_(const u16 *p) { (void)p; return 1; }
void *GetModuleHandleW_(const u16 *p) { (void)p; return 0; }
int GetModuleHandleExW_(u32 a, const void *b, void **c) { (void)a;(void)b;(void)c; return 1; }
int DisableThreadLibraryCalls_(void *a) { (void)a; return 1; }
void *VirtualAlloc_(void *a, u64 n, u32 t, u32 p) { (void)a;(void)t;(void)p; void *m = mmap(0, n, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0); return m == MAP_FAILED ? 0 : m; }
int VirtualFree_(void *a, u64 n, u32 t) { (void)a;(void)n;(void)t; return 1; }
int VirtualProtect_(void *a, u64 n, u32 p, u32 *o) { (void)a;(void)n;(void)p;(void)o; return 0; } // the NeedCPUData patch: never in the harness
int FlushInstructionCache_(HANDLE h, const void *a, u64 n) { (void)h;(void)a;(void)n; return 1; }
HANDLE GetCurrentProcess_(void) { return 0; }

static int NB, NV, NSEC, NIDX;
static int *bparent; static char (*bname)[32];
static float *local, *space, *refinv, *refpose, *pos;
static unsigned char *wts, *binfo;
static u32 *idx;
static u64 *secbuf; static u16 **bmaps;
static u64 sw_buf[32], sm_buf[128], rd_buf[4], lodptrs[1], ib_obj[1], ib_vt[16];
static unsigned char comp_a[0x2000], comp_b[0x2000];
static skin_info *ov_a, *ov_b;
static int ib_num(u64 s) { (void)s; return NIDX; }
static u32 ib_get(u64 s, u32 i) { (void)s; return idx[i]; }
// as the engine: a component with an override reads it back (section-local indices through the BoneMaps as they are
// now, borrowed entries included), else the mesh's own buffer
#define ACT_AT 0x3a8   // where the harness puts ActiveBoneIndices in the LOD's render data (the DLL finds it)
static u16 *act_base;  // the engine's active bones, kept for NOACTIVE=1
static int unskinned;  // vertices an override left on a bone the GPU doesn't skin
static u64 sw_ov[2][32];
static unsigned char *ov_wts[2];
static u64 st_get_buffer(u64 c, int l)
{
    (void)l;
    int k = c == (u64)comp_b;
    return ov_wts[k] ? (u64)sw_ov[k] : (u64)sw_buf;
}
static void st_set_override(u64 c, int l, const tarray *a)
{
    (void)l;
    int k = c == (u64)comp_b;
    skin_info **o = k ? &ov_b : &ov_a;
    free(*o); *o = malloc(sizeof(skin_info) * a->num); memcpy(*o, a->data, sizeof(skin_info) * a->num);
    free(ov_wts[k]); ov_wts[k] = calloc(NV, 16);
    int lost = 0;
    for (int sc = 0; sc < NSEC; sc++) {
        unsigned char *sec = (unsigned char *)secbuf + sc * 0xe8;
        int base = *(int *)(sec + SEC_BASE_VERTEX), n = *(int *)(sec + SEC_NUM_VERTICES), nm = *(int *)(sec + SEC_BONE_MAP + 8);
        u16 *bm = *(u16 **)(sec + SEC_BONE_MAP);
        for (int v = base; v < base + n && v < a->num; v++)
            for (int i = 0; i < 8; i++) {
                if (!(*o)[v].weights[i]) continue;
                int li = -1;
                for (int j = 0; j < nm; j++) if (bm[j] == (*o)[v].bones[i]) { li = j; break; }
                if (li < 0 || li > 255) { lost++; continue; }
                ov_wts[k][v * 16 + i] = (unsigned char)li; ov_wts[k][v * 16 + 8 + i] = (*o)[v].weights[i];
            }
    }
    if (lost) printf("override %c: %d weights on bones outside their section's BoneMap\n", k ? 'B' : 'A', lost);
    // as the GPU skins it: a matrix only for the LOD's active bones (ActiveBoneIndices as it is now, borrowed bones
    // included; with NOACTIVE=1 the DLL can't find it and it stays the engine's), anything else is garbage that frame
    {
        const u16 *act = act_buf ? *(u16 **)((unsigned char *)ld_buf + ACT_AT) : act_base;
        int an = act_buf ? *(int *)((unsigned char *)ld_buf + ACT_AT + 8) : act_n, dead = 0;
        for (int v = 0; v < a->num; v++)
            for (int i = 0; i < 8; i++) {
                if (!(*o)[v].weights[i]) continue;
                int in = 0;
                for (int j = 0; j < an && !in; j++) in = act[j] == (*o)[v].bones[i];
                if (!in) { dead++; break; }
            }
        if (dead) { printf("override %c: %d vertices on bones the GPU doesn't skin\n", k ? 'B' : 'A', dead); unskinned += dead; }
    }
    unsigned char *sw = (unsigned char *)sw_ov[k];
    sw[SW_VARIABLE] = 0; *(u32 *)(sw + SW_MAX_INFLUENCES) = 8; sw[SW_16BIT_INDEX] = 0;
    *(u64 *)(sw + SW_DATA) = (u64)ov_wts[k]; *(int *)(sw + SW_NUM_VERTICES) = NV;
}
static void st_noop(u64 c) { (void)c; }
static u64 st_weak(u64 w) { (void)w; return 0; }
static void tramp(u64 at, void *fn) { unsigned char *p = (unsigned char *)at; p[0] = 0x48; p[1] = 0xb8; memcpy(p + 2, &fn, 8); p[10] = 0xff; p[11] = 0xe0; }

static void qmul(const float *a, const float *b, float *o) // o = a * b
{
    o[0] = a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1];
    o[1] = a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0];
    o[2] = a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3];
    o[3] = a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2];
}
static int bone(const char *n) { for (int i = 0; i < NB; i++) if (!strcmp(bname[i], n)) return i; return -1; }
static float dist3(const float *a, const float *b) { float d0 = a[0] - b[0], d1 = a[1] - b[1], d2 = a[2] - b[2]; return __builtin_sqrtf(d0 * d0 + d1 * d1 + d2 * d2); }

// component space from the local pose (parents come first), and the inverse bind matrices from it
static void pose_from_local(float *dst)
{
    for (int i = 0; i < NB; i++) {
        float *t = dst + i * 12, *l = local + i * 12;
        int p = bparent[i];
        if (p < 0) { memcpy(t, l, 48); continue; }
        float *pt = dst + p * 12, r[3];
        quat_rot(pt, l + 4, r);
        qmul(pt, l, t);
        t[4] = pt[4] + r[0]; t[5] = pt[5] + r[1]; t[6] = pt[6] + r[2]; t[7] = 0;
        t[8] = t[9] = t[10] = 1; t[11] = 0;
    }
}

// bend the local pose: (bone, axis, degrees) applied on top of the bind pose's local rotation
static void bend(float *loc, const char *name, float ax, float ay, float az, float deg)
{
    int i = bone(name);
    if (i < 0) return;
    float l = __builtin_sqrtf(ax * ax + ay * ay + az * az), h = deg * 3.14159265f / 360.0f, sh = __builtin_sinf(h) / l;
    float q[4] = { ax * sh, ay * sh, az * sh, __builtin_cosf(h) }, o[4];
    qmul(loc + i * 12, q, o);
    memcpy(loc + i * 12, o, 16);
}

static void load(const char *fn)
{
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); exit(1); }
    int h[4]; fread(h, 4, 4, f);
    NB = h[0]; NV = h[1]; NSEC = h[2]; NIDX = h[3];
    bparent = malloc(4 * NB); bname = malloc(32 * NB); local = malloc(48 * NB);
    for (int i = 0; i < NB; i++) { fread(&bparent[i], 4, 1, f); fread(local + i * 12, 4, 12, f); fread(bname[i], 1, 32, f); }
    secbuf = calloc(NSEC, 0xe8); bmaps = malloc(sizeof(u16 *) * NSEC);
    for (int s = 0; s < NSEC; s++) {
        int x[3]; fread(x, 4, 3, f);
        bmaps[s] = malloc(2 * (x[2] + 8)); fread(bmaps[s], 2, x[2], f);
        unsigned char *sec = (unsigned char *)secbuf + s * 0xe8;
        *(int *)(sec + SEC_BASE_VERTEX) = x[0]; *(int *)(sec + SEC_NUM_VERTICES) = x[1];
        *(u64 *)(sec + SEC_BONE_MAP) = (u64)bmaps[s]; *(int *)(sec + SEC_BONE_MAP + 8) = x[2]; *(int *)(sec + SEC_BONE_MAP + 12) = x[2] + 8;
    }
    pos = malloc(12 * NV); fread(pos, 12, NV, f);
    wts = malloc(16 * NV); fread(wts, 16, NV, f);
    idx = malloc(4 * NIDX); fread(idx, 4, NIDX, f);
    fclose(f);
    for (int i = 0; i < NIDX; i++) if (idx[i] >= (u32)NV) { fprintf(stderr, "bad index %u\n", idx[i]); exit(1); }
}

// skinned position of vertex v under weights o, with the current refinv and pose
static void skin_v(const skin_info *o, int v, float *x)
{
    cut_ctx c = { 0 }; c.nb = NB; c.binfo = binfo; c.refinv = refinv; c.space = space; c.nspace = NB;
    skin_point(&c, o, pos + v * 3, x);
}
static void orig_info(int v, skin_info *o)
{
    memset(o, 0, sizeof *o);
    int s = 0;
    for (int k = 0; k < NSEC; k++) { unsigned char *sec = (unsigned char *)secbuf + k * 0xe8; int b = *(int *)(sec + SEC_BASE_VERTEX), n = *(int *)(sec + SEC_NUM_VERTICES); if (v >= b && v < b + n) s = k; }
    for (int i = 0; i < 8; i++) { o->bones[i] = bmaps[s][wts[v * 16 + i]]; o->weights[i] = wts[v * 16 + 8 + i]; }
}

// the copy lets its head go (HEAD_DROP): its kept skin hangs nothing on the head's subtree, that weight rides the
// head's parent (the neck) instead. Returns 1 if o had any on it
static int fold_head(skin_info *o, int head)
{
    if (head < 0 || bparent[head] < 0) return 0;
    int add = 0, slot = -1;
    for (int i = 0; i < MAX_INF; i++) {
        if (!o->weights[i]) continue;
        int in = 0;
        for (int a = o->bones[i]; a >= 0 && !in; a = bparent[a]) in = a == head;
        if (in) { add += o->weights[i]; o->weights[i] = 0; }
        else if (o->bones[i] == bparent[head]) slot = i;
    }
    if (add && slot < 0) for (int i = 0; i < MAX_INF; i++) if (!o->weights[i]) { slot = i; o->bones[i] = bparent[head]; break; }
    if (add && slot >= 0) o->weights[slot] = (unsigned char)(o->weights[slot] + add);
    return add > 0;
}

// a vertex the vanilla skin ties to a limb this half lets go (hip skin on the other half's thigh twist): it has to
// stay with the body, so it may shift; not counted
static unsigned char *gone_sub[2], *keep_sub[2];
#define POP_CM 4.0f // see the kept skin check: how far skin on the free side of a broken spine may shift at the cut
// a flag from the environment: set and not empty (test/run.sh passes ACROSS= for "no")
static int env_on(const char *k) { const char *v = getenv(k); return v && *v; }
// tied to a limb this half keeps (its arm hanging below a waist cut, the cape on it): may lie behind the plane
static int tied_to_kept(int h, int v)
{
    skin_info vo; orig_info(v, &vo);
    int w = 0;
    for (int i = 0; i < 8; i++) if (vo.weights[i] && keep_sub[h][vo.bones[i]]) w += vo.weights[i];
    return w > 127;
}
static int tied_to_gone(int h, int v)
{
    skin_info vo; orig_info(v, &vo);
    for (int i = 0; i < 8; i++) if (vo.weights[i] && gone_sub[h][vo.bones[i]]) return 1;
    return 0;
}

// the kept head (gore.lua's neck plane, at the neck's base): above the plane within NECK_BASE_R of the neck axis up to
// halfway to the head bone, NECK_R above, or mostly on the head's bones
static float hp2[3], hn2[3], hmid;
static unsigned char *headbones;
static int in_head(int v, const float *x)
{
    float e[3] = { x[0] - hp2[0], x[1] - hp2[1], x[2] - hp2[2] }, h2 = e[0] * hn2[0] + e[1] * hn2[1] + e[2] * hn2[2];
    float r = h2 > hmid ? NECK_R : NECK_BASE_R;
    if (h2 > 0 && e[0] * e[0] + e[1] * e[1] + e[2] * e[2] - h2 * h2 < r * r) return 1;
    skin_info vo; orig_info(v, &vo);
    int w = 0;
    for (int i = 0; i < 8; i++) if (vo.weights[i] && headbones[vo.bones[i]]) w += vo.weights[i];
    return w > 127;
}
// an opening's outline from a cut's answer ("<tag>p=x,y,z;..."), in the cut plane's 2D frame: simple, and its area
static int outline_of(const char *res, const char *tag, float (*uv)[2], int max, const float *n, float *area)
{
    char key[16]; snprintf(key, sizeof key, " %sp=", tag);
    const char *s = strstr(res, key);
    if (!s) return 0;
    s += strlen(key);
    float ax[3] = { __builtin_fabsf(n[0]) < 0.9f ? 1.0f : 0.0f, __builtin_fabsf(n[0]) < 0.9f ? 0.0f : 1.0f, 0 }, t = ax[0] * n[0] + ax[1] * n[1];
    for (int k = 0; k < 3; k++) ax[k] -= t * n[k];
    float l = __builtin_sqrtf(ax[0] * ax[0] + ax[1] * ax[1] + ax[2] * ax[2]);
    for (int k = 0; k < 3; k++) ax[k] /= l;
    float ay[3] = { n[1] * ax[2] - n[2] * ax[1], n[2] * ax[0] - n[0] * ax[2], n[0] * ax[1] - n[1] * ax[0] };
    int m = 0;
    while (m < max) {
        float x, y, z; int used = 0;
        if (sscanf(s, "%f,%f,%f%n", &x, &y, &z, &used) != 3) break;
        uv[m][0] = x * ax[0] + y * ax[1] + z * ax[2]; uv[m][1] = x * ay[0] + y * ay[1] + z * ay[2]; m++;
        s += used;
        if (*s != ';') break;
        s++;
    }
    float a = 0;
    for (int i = 0; i < m; i++) { int j = (i + 1) % m; a += uv[i][0] * uv[j][1] - uv[j][0] * uv[i][1]; }
    *area = a * 0.5f;
    return m;
}
static int seg_cross(const float *a, const float *b, const float *c, const float *d)
{
    float d1 = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]), d2 = (b[0] - a[0]) * (d[1] - a[1]) - (b[1] - a[1]) * (d[0] - a[0]);
    float d3 = (d[0] - c[0]) * (a[1] - c[1]) - (d[1] - c[1]) * (a[0] - c[0]), d4 = (d[0] - c[0]) * (b[1] - c[1]) - (d[1] - c[1]) * (b[0] - c[0]);
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0));
}

// the DLL's own verdict: a vertex this half lets go is wholly on one of its sinks
static int vanished_in(const skin_info *o, u64 comp)
{
    // all of it on its sinks (a split's sheet may lie between two)
    if (!o->weights[0]) return 0;
    for (int k = 0; k < MAX_INF; k++) {
        if (!o->weights[k]) continue;
        int on = 0;
        for (int i = 0; i < nsinks; i++) if (sinks[i].comp == comp && sinks[i].bone == o->bones[k]) on = 1;
        if (!on) return 0;
    }
    return 1;
}

static void write_obj(const char *fn, const skin_info *o)
{
    FILE *f = fopen(fn, "w");
    for (int v = 0; v < NV; v++) { float x[3]; skin_v(&o[v], v, x); fprintf(f, "v %.3f %.3f %.3f\n", x[0], x[1], x[2]); }
    for (int t = 0; t < NIDX; t += 3) fprintf(f, "f %u %u %u\n", idx[t] + 1, idx[t + 1] + 1, idx[t + 2] + 1);
    fclose(f);
}

static const char *NOSINK_PRE[] = { "Bip001", "SC_", "Ab_" };
static const char *NOSINK_PART[] = { "Hair", "Cape", "Breast", "Prop" };
// the spine bones the lid rides, as gore.lua sends them after the limbs (SPLIT_RIDE.of); NORIDE=1: none (axis bands).
// The copy (half B) lets its head go free, so it never rides it; with the spine broken (brk), each half rides only
// its own side of the break (A the break bone and up)
static void set_ride(int copy, int brk)
{
    static const char *ride[] = { "Bip001-Head", "Bip001-Neck", "Bip001-Spine2", "Bip001-Spine1", "Bip001-Spine", "Bip001-Pelvis" };
    nride = 0;
    if (env_on("NORIDE")) return;
    int si = -1;
    for (int i = 0; i < 6; i++) if (brk >= 0 && bone(ride[i]) == brk) si = i;
    for (int i = 0; i < 6; i++) {
        int ok = si < 0 ? (!copy || i > 0) : copy ? i > si : i <= si;
        if (ok && bone(ride[i]) >= 0) ride_bones[nride++] = bone(ride[i]);
    }
}
static void base_nosink(void)
{
    nosink_mesh = (u64)sm_buf;
    for (int i = 0; i < MAX_BONES; i++) nosink[i] = drivenb[i] = 0;
    for (int i = 0; i < NB; i++) {
        int bad = !strcmp(bname[i], "Root");
        // ENEMY=1: gore.lua's list for an enemy: its Ab_ bones are its own deform helpers (the skulls' and the
        // lurker's head have no others), not accessory chains, so they may be sinks
        for (int k = 0; k < 3 - env_on("ENEMY"); k++) if (!strncmp(bname[i], NOSINK_PRE[k], strlen(NOSINK_PRE[k]))) bad = 1;
        for (int k = 0; k < 4; k++) if (strstr(bname[i], NOSINK_PART[k])) bad = 1;
        nosink[i] = bad;
        // as gore.lua sends: Dm- drivers, and bones with a physics body of their own (every Eve outfit's hip jiggle
        // bodies; gore.lua reads them off her physics asset)
        nocarry[i] = env_on("ENEMY") || !strncmp(bname[i], "Dm-", 3) || !strncmp(bname[i], "Dm_", 3)
            || !strcmp(bname[i], "Ab-L-Hip") || !strcmp(bname[i], "Ab-R-Hip") || !strcmp(bname[i], "Ab-L-Hip-Reg") || !strcmp(bname[i], "Ab-R-Hip-Reg");
    }
    // NOSINKALL=1: no bone may be a sink, as gore.lua sends for an enemy (its mesh asset is shared by every enemy of
    // its kind, alive ones too, and a sink collapses on the asset)
    if (env_on("NOSINKALL")) for (int i = 0; i < NB; i++) nosink[i] = 1;
    // the bones with a physics body, as gore.lua sends them off her physics asset (none for an enemy)
    static const char *BODIES[] = { "Bip001-Pelvis", "Bip001-Spine", "Bip001-Spine1", "Bip001-Spine2", "Bip001-Neck", "Bip001-Head",
        "Bip001-L-Clavicle", "Bip001-L-UpperArm", "Bip001-L-Forearm", "Bip001-L-Hand", "Bip001-R-Clavicle", "Bip001-R-UpperArm",
        "Bip001-R-Forearm", "Bip001-R-Hand", "Bip001-L-Thigh", "Bip001-L-Calf", "Bip001-L-Foot", "Bip001-R-Thigh", "Bip001-R-Calf",
        "Bip001-R-Foot", "Ab-L-Hip", "Ab-L-Hip-Reg", "Ab-R-Hip", "Ab-R-Hip-Reg" };
    nbodies = 0;
    for (int i = 0; i < NB; i++) {
        hasbody[i] = 0;
        if (env_on("ENEMY") || env_on("NOBODIES")) continue;
        for (int k = 0; k < (int)(sizeof BODIES / sizeof *BODIES); k++) if (!strcmp(bname[i], BODIES[k])) { hasbody[i] = 1; nbodies++; }
    }
}
static void set_nosink(void)
{
    base_nosink();
    // her bones watched as gore.lua does while she plays, here in the pose of the cut (a carrier must have held still
    // all along); UNWATCHED=1: never watched, as before the first few seconds of play
    if (!env_on("UNWATCHED")) for (int k = 0; k < CARRY_WATCH; k++) skin_watch((u64)comp_a);
    // HIPMOVED=1: the hip's correctives moved while she played (the watch saw them). In game, ruled out as sinks, a
    // thigh's body-side seam went to a chest helper 44 cm off and stretched the opening up to it
    if (env_on("HIPMOVED")) for (int i = 0; i < NB; i++)
        if (strstr(bname[i], "Venter") || strstr(bname[i], "-AX2")) watch_dt[i] = 1e30f;
    // ALLMOVED=1: every helper moved while she played (a longer watch in game saw them all move). A waist cut found no
    // sink for one side then and left its seam on the old weights, stretched between the halves (playtest 30)
    if (env_on("ALLMOVED")) for (int i = 0; i < NB; i++) if (strncmp(bname[i], "Bip001", 6)) watch_dt[i] = 1e30f;
}

// gore.lua's limb roots: a limb or head cut keeps its sinks off every other limb (OLDNOSINK=1: as before, any). As
// gore.lua's M.limb_of, a helper of a root's name counts as that root (CH_M_NA_40's arm helpers hang off Ab-L-Clavicle)
static const char *LIMB_ROOT_NAMES[] = { "Bip001-L-Clavicle", "Bip001-R-Clavicle", "Bip001-L-Thigh", "Bip001-R-Thigh" };
// gore.lua's driven_list for a cut through the spine: a Dm- driver, or a helper under one before the main skeleton.
// The animation points them across the cut (CH_P_EVE_30's Ab-L-AX2 under Dm-L-AX2 took the waist cut's lower seam,
// and that half's opening stretched 3.5 m after the flying upper body, playtest)
static int under_driver(int i)
{
    for (int j = i; j >= 0 && strncmp(bname[j], "Bip001", 6); j = bparent[j])
        if (!strncmp(bname[j], "Dm-", 3) || !strncmp(bname[j], "Dm_", 3)) return 1;
    return 0;
}
// gore.lua's driver_limb / side_drivers: the limb a Dm- driver follows, read off its name (bits: 1 L arm, 2 R arm, 4 L
// leg, 8 R leg; 0 none: central, a breast's or a cloth's, which follow her chest)
static int driver_limb(const char *nm)
{
    static const char *ARM[] = { "Trape", "Shoulder", "Side", "Pectro", "Arm", "Deltoid", "Tricep", "Elbow", "Forearm", "Brochi", "Clavicle" };
    static const char *LEG[] = { "Thigh", "Hip", "Knee", "Venter", "Calf", "Ankle", "AX2" };
    if (strstr(nm, "Breast") || strstr(nm, "Cloth")) return 0;
    int side = 0;
    for (const char *l = nm; *l && !side; l++) if ((*l == '-' || *l == '_') && (l[1] == 'L' || l[1] == 'R') && (l[2] == '-' || l[2] == '_')) side = l[1] == 'L' ? 1 : 2;
    if (!side) return 0;
    for (unsigned k = 0; k < sizeof ARM / sizeof *ARM; k++) if (strstr(nm, ARM[k])) return side;
    for (unsigned k = 0; k < sizeof LEG / sizeof *LEG; k++) if (strstr(nm, LEG[k])) return side << 2;
    return 0;
}
// a bone a driver of one of those limbs moves (the topmost Dm- bone over it names the limb)
static int side_driver(int i, int limbs)
{
    const char *top = 0;
    for (int j = i; j >= 0 && strncmp(bname[j], "Bip001", 6); j = bparent[j])
        if (!strncmp(bname[j], "Dm-", 3) || !strncmp(bname[j], "Dm_", 3)) top = bname[j];
    return top && (driver_limb(top) & limbs);
}
static int gone_sides(const int *g, int ng)
{
    int limbs = 0;
    for (int r = 0; r < ng; r++) {
        const char *nm = bname[g[r]];
        if (strncmp(nm, "Bip001-", 7) || (nm[7] != 'L' && nm[7] != 'R')) continue;
        int leg = strstr(nm, "Thigh") || strstr(nm, "Calf");
        limbs |= (nm[7] == 'L' ? 1 : 2) << (leg ? 2 : 0);
    }
    return limbs;
}
static int limb_of(int i)
{
    for (int j = i; j >= 0; j = bparent[j]) {
        size_t n = strlen(bname[j]);
        for (int k = 0; k < 4; k++) {
            const char *tail = LIMB_ROOT_NAMES[k] + 6; // "-L-Clavicle"
            size_t m = strlen(tail);
            if (n >= m && (bname[j][n - m] == '-' || bname[j][n - m] == '_') && !strcmp(bname[j] + n - m + 1, tail + 1)) return bone(LIMB_ROOT_NAMES[k]);
        }
    }
    return -1;
}
static void other_limbs_nosink(int b)
{
    if (env_on("OLDNOSINK")) return;
    int own = limb_of(b);
    for (int i = 0; i < NB; i++) { int r = limb_of(i); if (r >= 0 && r != own) nosink[i] = 1; }
}

// the engine's allocator (GMalloc): a BoneMap array swapped into the engine's hands must come from it, or the engine
// can't free it (the Alt+F4 crash, MallocBinned2's canary). Ours tracks what it handed out
static void *gm_out[4096]; static int ngm;
static void *gm_malloc(u64 self, u64 n, u32 al) { (void)self; (void)al; void *p = calloc(1, n); if (ngm < 4096) gm_out[ngm++] = p; return p; }
static void gm_free(u64 self, void *p) { (void)self; for (int i = 0; i < ngm; i++) if (gm_out[i] == p) { gm_out[i] = 0; free(p); return; } fprintf(stderr, "FAIL: GMalloc freed %p it never gave\n", p); _exit(1); }
static u64 gm_vt[16], gm_obj[2];
static void gm_install(void) { gm_vt[2] = (u64)gm_malloc; gm_vt[6] = (u64)gm_free; gm_obj[0] = (u64)gm_vt; *(u64 *)(exe + RVA_GMALLOC) = (u64)gm_obj; }
static int gm_owns(const void *p) { for (int i = 0; i < ngm; i++) if (gm_out[i] == p) return 1; return 0; }
// at exit: every section's BoneMap is its own or one GMalloc gave
static void bonemaps_owned(void)
{
    if (act_buf) {
        u16 *p = *(u16 **)((unsigned char *)ld_buf + ACT_AT);
        if (p != act_buf && !gm_owns(p)) { printf("FAIL: ActiveBoneIndices is %p, not the engine's allocator's\n", (void *)p); fflush(stdout); _exit(1); }
    }
    if (unskinned) { printf("FAIL: %d vertices on bones the GPU doesn't skin (flashing across the screen)\n", unskinned); fflush(stdout); _exit(1); }
    for (int s = 0; s < NSEC; s++) {
        u16 *p = *(u16 **)((unsigned char *)secbuf + s * 0xe8 + SEC_BONE_MAP);
        if (p != bmaps[s] && !gm_owns(p)) { printf("FAIL: section %d's BoneMap is %p, not the engine's allocator's\n", s, (void *)p); fflush(stdout); _exit(1); }
    }
}

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: real_split <mesh.bin> [obj prefix]\n"); return 2; }
    load(argv[1]);
    void *m = mmap(0, 0x7100000, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    exe = (u64)m;
    gm_install();
    atexit(bonemaps_owned);
    tramp(exe + RVA_GET_SKIN_WEIGHT_BUFFER, (void *)st_get_buffer);
    tramp(exe + RVA_SET_SKIN_WEIGHT_OVERRIDE, (void *)st_set_override);
    tramp(exe + RVA_MARK_RENDER_STATE_DIRTY, (void *)st_noop);
    tramp(exe + RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS, (void *)st_noop);
    tramp(exe + RVA_WEAK_PTR_GET, (void *)st_weak);
    space = malloc(48 * NB); refpose = local; refinv = malloc(64 * NB); binfo = calloc(NB, 0xc);
    pose_from_local(space);
    for (int i = 0; i < NB; i++) {
        *(int *)(binfo + i * 0xc + 8) = bparent[i];
        // inverse of the bind (component space) matrix, row vectors: p * R^T - t * R^T
        float *t = space + i * 12, *iv = refinv + i * 16, ax[3][3];
        for (int a = 0; a < 3; a++) { float e[3] = { a == 0, a == 1, a == 2 }; quat_rot(t, e, ax[a]); }
        memset(iv, 0, 64);
        for (int r = 0; r < 3; r++) for (int c = 0; c < 3; c++) iv[r * 4 + c] = ax[c][r];
        for (int c = 0; c < 3; c++) iv[12 + c] = -(t[4] * ax[c][0] + t[5] * ax[c][1] + t[6] * ax[c][2]);
        iv[15] = 1;
    }
    // POSED=1: cut in a bent pose (a ragdoll mid-fall) instead of the bind pose, and bend her more after the collapse
    int posed = env_on("POSED");
    float *bindlocal = malloc(48 * NB); memcpy(bindlocal, local, 48 * NB);
    if (posed) {
        bend(local, "Bip001-Spine1", 1, 0.3f, 0, 25); bend(local, "Bip001-Spine2", 0, 1, 0.2f, 15);
        bend(local, "Bip001-L-UpperArm", 0, 0, 1, 50); bend(local, "Bip001-R-UpperArm", 0, 1, 0, -40);
        bend(local, "Bip001-R-Thigh", 0, 0, 1, 35); bend(local, "Bip001-L-Calf", 0, 0, 1, -50);
        bend(local, "Bip001-Head", 1, 0, 0, 30); bend(local, "Bip001-Neck", 0, 1, 0, 20);
        pose_from_local(space);
        refpose = bindlocal; // the stable test compares against the bind pose
    }
    unsigned char *sm = (unsigned char *)sm_buf, *ld = (unsigned char *)ld_buf, *sw = (unsigned char *)sw_buf;
    *(u64 *)(sm + SM_RENDER_DATA) = (u64)rd_buf; rd_buf[0] = (u64)lodptrs; *(int *)((unsigned char *)rd_buf + 8) = 1; lodptrs[0] = (u64)ld;
    *(u64 *)(sm + SM_REF_BONE_INFO) = (u64)binfo; *(int *)(sm + SM_REF_BONE_INFO + 8) = NB;
    *(u64 *)(sm + SM_REF_BONE_POSE) = (u64)refpose; *(int *)(sm + SM_REF_BONE_POSE + 8) = NB;
    *(u64 *)(sm + SM_REF_BASES_INV) = (u64)refinv; *(int *)(sm + SM_REF_BASES_INV + 8) = NB;
    *(u64 *)(ld + LOD_SECTIONS) = (u64)secbuf; *(int *)(ld + LOD_SECTIONS + 8) = NSEC;
    ib_vt[0x58 / 8] = (u64)ib_num; ib_vt[0x68 / 8] = (u64)ib_get; ib_obj[0] = (u64)ib_vt;
    *(u64 *)(ld + LOD_INDICES) = (u64)ib_obj;
    *(u64 *)(ld + LOD_POSITIONS + 0x28) = (u64)pos; *(u32 *)(ld + LOD_POSITIONS + 0x30) = 12;
    *(int *)(ld + LOD_NUM_VERTICES) = NV;
    // ActiveBoneIndices: the sections' BoneMaps and their ancestors, as the engine builds it
    {
        unsigned char *on = calloc(NB, 1);
        for (int sc = 0; sc < NSEC; sc++) {
            int nm = *(int *)((unsigned char *)secbuf + sc * 0xe8 + SEC_BONE_MAP + 8);
            for (int j = 0; j < nm; j++) for (int b = bmaps[sc][j]; b >= 0 && !on[b]; b = bparent[b]) on[b] = 1;
        }
        act_base = malloc(2 * NB);
        for (int b = 0; b < NB; b++) if (on[b]) act_base[act_n++] = (u16)b;
        free(on);
        if (!env_on("NOACTIVE")) {
            act_buf = malloc(2 * act_n); memcpy(act_buf, act_base, 2 * act_n);
            *(u64 *)(ld + ACT_AT) = (u64)act_buf; *(int *)(ld + ACT_AT + 8) = act_n; *(int *)(ld + ACT_AT + 12) = act_n;
        }
    }
    sw[SW_VARIABLE] = 0; *(u32 *)(sw + SW_MAX_INFLUENCES) = 8; sw[SW_16BIT_INDEX] = 0; *(u64 *)(sw + SW_DATA) = (u64)wts; *(int *)(sw + SW_NUM_VERTICES) = NV;
    unsigned char *comps[2] = { comp_a, comp_b };
    for (int k = 0; k < 2; k++) {
        unsigned char *c = comps[k];
        *(u64 *)(c + SC_SKELETAL_MESH) = (u64)sm_buf;
        *(u64 *)(c + SC_SPACE_BASES) = (u64)space; *(int *)(c + SC_SPACE_BASES + 8) = NB;
        *(u64 *)(c + SC_SPACE_BASES + 0x10) = (u64)space; *(int *)(c + SC_SPACE_BASES + 0x18) = NB;
        float *tw = (float *)(c + SC_TO_WORLD); tw[3] = 1; tw[8] = tw[9] = tw[10] = 1;
    }

    int spine1 = bone("Bip001-Spine1"), pelvis = bone("Bip001-Pelvis"), head = bone("Bip001-Head");
    if (spine1 < 0 || pelvis < 0 || head < 0) { fprintf(stderr, "no Bip001 spine\n"); return 1; }
    // LIMB=1: a plain cut of the left upper arm (0.4 down it, square to it) on any mesh, an enemy's say: every vertex the
    // vanilla skin puts mostly on the forearm's subtree goes with the arm, none with no weight on the arm stays on it
    if (env_on("LIMB")) {
        int ua = bone("Bip001-L-UpperArm"), fa = bone("Bip001-L-Forearm");
        if (ua < 0 || fa < 0) { fprintf(stderr, "no left arm\n"); return 1; }
        float *a = space + ua * 12 + 4, *b2 = space + fa * 12 + 4, at2[3], nn[3], l = 0;
        float armat = getenv("ARMAT") ? (float)atof(getenv("ARMAT")) : 0.4f; // ARMAT: where down the upper arm (gore.lua PARTS at)
        for (int k = 0; k < 3; k++) { at2[k] = a[k] + (b2[k] - a[k]) * armat; nn[k] = b2[k] - a[k]; l += nn[k] * nn[k]; }
        for (int k = 0; k < 3; k++) nn[k] /= __builtin_sqrtf(l);
        set_nosink(); other_limbs_nosink(ua);
        limbs_comp = (u64)comp_a; ngone = nkeep = ndrop = nride = 0;
        skin_cut((u64)comp_a, 0, ua, at2, nn, MODE_CUT, 0, 0, -1);
        printf("limb: %.300s\n", lastres);
        if (!ov_a) { printf("FAIL: no override\n"); return 1; }
        unsigned char *fore = calloc(NB, 1), *armb = calloc(NB, 1);
        for (int i = 0; i < NB; i++) {
            fore[i] = i == fa || (bparent[i] >= 0 && fore[bparent[i]]);
            armb[i] = i == ua || (bparent[i] >= 0 && armb[bparent[i]]);
        }
        int nf = 0, fleft = 0, taken = 0;
        for (int v = 0; v < NV; v++) {
            skin_info vo; orig_info(v, &vo);
            int wf = 0, wa = 0, onarm = 0;
            for (int i = 0; i < 8; i++) if (vo.weights[i]) { if (fore[vo.bones[i]]) wf += vo.weights[i]; if (armb[vo.bones[i]]) wa += vo.weights[i]; }
            for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && armb[ov_a[v].bones[i]]) onarm = 1;
            if (wf > 127) { nf++; fleft += !onarm; }
            taken += !wa && onarm;
        }
        skin_collapse();
        skin_probe((u64)comp_a, 0);
        printf("limb probe: %.200s\n", lastres);
        int bad = fleft > nf / 200 || taken > 0;
        printf("limb: %d forearm vertices, %d stayed on the body; %d vertices off the arm went with it\n%s\n", nf, fleft, taken, bad ? "FAIL" : "PASS");
        return bad;
    }
    // MARK=1: a living hit's mark (skin_mark): rays out of the torso, an upper arm and a thigh, four ways round each,
    // must meet the skin within 3-20 cm of the axis, on a vertex carried by that part (its bone, a helper under it or
    // its parent), with the surface normal along the ray
    if (env_on("MARK")) {
        const char *seg[][2] = { { "Bip001-Spine1", "Bip001-Spine2" }, { "Bip001-L-UpperArm", "Bip001-L-Forearm" },
                                 { "Bip001-R-Thigh", "Bip001-R-Calf" } };
        int bad = 0, tried = 0;
        for (int k = 0; k < 3; k++) {
            int b0 = bone(seg[k][0]), b1 = bone(seg[k][1]);
            if (b0 < 0 || b1 < 0) continue;
            float *a = space + b0 * 12 + 4, *b2 = space + b1 * 12 + 4, ax[3], l = 0;
            for (int i = 0; i < 3; i++) { ax[i] = b2[i] - a[i]; l += ax[i] * ax[i]; }
            l = __builtin_sqrtf(l);
            for (int i = 0; i < 3; i++) ax[i] /= l;
            float side[3] = { 0, 0, 1 };
            if (ax[2] > 0.9f || ax[2] < -0.9f) { side[0] = 1; side[2] = 0; }
            float u[3] = { ax[1] * side[2] - ax[2] * side[1], ax[2] * side[0] - ax[0] * side[2], ax[0] * side[1] - ax[1] * side[0] }, ul = 0;
            for (int i = 0; i < 3; i++) ul += u[i] * u[i];
            for (int i = 0; i < 3; i++) u[i] /= __builtin_sqrtf(ul);
            float w[3] = { ax[1] * u[2] - ax[2] * u[1], ax[2] * u[0] - ax[0] * u[2], ax[0] * u[1] - ax[1] * u[0] };
            for (int r = 0; r < 4; r++) {
                float cs = r == 0 ? 1 : r == 2 ? -1 : 0, sn = r == 1 ? 1 : r == 3 ? -1 : 0, at[3], d[3];
                for (int i = 0; i < 3; i++) { at[i] = a[i] + ax[i] * l * 0.5f; d[i] = u[i] * cs + w[i] * sn; }
                skin_mark((u64)comp_a, 0, at, d, 25);
                tried++;
                float h[3], n[3], out = 0;
                int hb = -1, got = sscanf(lastres, "ok hit=%f,%f,%f n=%f,%f,%f bone=%d out=%f", h, h + 1, h + 2, n, n + 1, n + 2, &hb, &out);
                int on = 0;
                for (int x = hb; x >= 0 && !on; x = bparent[x]) on = x == b0 || x == bparent[b0];
                float nd = (n[0] * d[0] + n[1] * d[1] + n[2] * d[2]) / 100;
                int ok = got == 8 && out >= 3 && out <= 20 && on && nd > 0.3f;
                printf("mark %s way %d: %s %s\n", seg[k][0], r, lastres, ok ? "" : "<- bad");
                bad += !ok;
            }
        }
        printf("mark: %d of %d rays bad\n%s\n", bad, tried, bad || !tried ? "FAIL" : "PASS");
        return bad || !tried;
    }
    // HEAD=1: an enemy's beheading as gore.lua makes it with no face mesh: MODE_CUT on Bip001-Head, 0.7 of the way
    // from the neck to the head, square to the neck (MODE_PLANE vanishes the head: Eve's goes on her face mesh). Every vertex mostly on the head's subtree goes with
    // it, none with no weight on the head or the neck does
    if (env_on("HEAD")) {
        int neck = bone("Bip001-Neck");
        if (neck < 0) { fprintf(stderr, "no neck\n"); return 1; }
        float *a = space + neck * 12 + 4, *b2 = space + head * 12 + 4, at2[3], nn[3], l = 0;
        float t = getenv("HEADAT") ? (float)atof(getenv("HEADAT")) : 0.7f; // HEADAT: where between them (gore.lua's at)
        for (int k = 0; k < 3; k++) { at2[k] = a[k] + (b2[k] - a[k]) * t; nn[k] = b2[k] - a[k]; l += nn[k] * nn[k]; }
        for (int k = 0; k < 3; k++) nn[k] /= __builtin_sqrtf(l);
        set_nosink(); other_limbs_nosink(head);
        limbs_comp = (u64)comp_a; ngone = nkeep = ndrop = nride = 0;
        // FACESINK=1: Eve's face mesh, as gore.lua cuts it: its eyes, teeth and brows know only the head bone, so the
        // head side's seam closes on a borrowed bone no face vertex uses (Bip001-Spine1), made to follow the head
        int fsink = env_on("FACESINK") ? bone("Bip001-Spine1") : 0;
        skin_cut((u64)comp_a, 0, head, at2, nn, MODE_CUT, 0, fsink > 0 ? fsink : 0, fsink > 0 ? head : -1);
        printf("head: %.300s\n", lastres);
        if (!ov_a) { printf("FAIL: no override\n"); return 1; }
        unsigned char *hb = calloc(NB, 1), *nb2 = calloc(NB, 1);
        for (int i = 0; i < NB; i++) {
            hb[i] = i == head || (bparent[i] >= 0 && hb[bparent[i]]);
            nb2[i] = i == neck || (bparent[i] >= 0 && nb2[bparent[i]]);
        }
        int nh = 0, hleft = 0, taken = 0;
        for (int v = 0; v < NV; v++) {
            skin_info vo; orig_info(v, &vo);
            int wh = 0, wn = 0, on = 0;
            for (int i = 0; i < 8; i++) if (vo.weights[i]) { if (hb[vo.bones[i]]) wh += vo.weights[i]; if (nb2[vo.bones[i]]) wn += vo.weights[i]; }
            for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && (hb[ov_a[v].bones[i]] || (fsink > 0 && ov_a[v].bones[i] == fsink))) on = 1;
            // (one under the plane stays on the neck, as any cut leaves what is behind it)
            float x[3]; skin_v(&vo, v, x);
            float hd = (x[0] - at2[0]) * nn[0] + (x[1] - at2[1]) * nn[1] + (x[2] - at2[2]) * nn[2];
            if (wh > 200 && hd > 1) { nh++; hleft += !on; }
            taken += !wn && on;
        }
        // the borrowed bone follows the head (the master's, in game)
        if (fsink > 0) memcpy(space + fsink * 12, space + head * 12, 48);
        skin_collapse();
        skin_probe((u64)comp_a, 0);
        printf("head probe: %.200s\n", lastres);
        int st = 0, sth = 0;
        sscanf(lastres, "ok stretched=%d", &st);
        { char *h0 = strstr(lastres, "hidden="); if (h0) sscanf(h0, "hidden=%d", &sth); }
        // and flung: the head (with the bone that follows it) turned 60 degrees and 40 cm off; nothing may stretch
        // from the neck to it, nor any of the face's neck go with it
        int fl = 0, flh = 0;
        {
            float *saved = malloc(48 * NB); memcpy(saved, space, 48 * NB);
            float q[4] = { 0.5f, 0, 0, 0.8660254f };
            for (int i = 0; i < NB; i++) if (hb[i] || (fsink > 0 && i == fsink)) {
                float *t = space + i * 12, nq[4], r[3]; qmul(q, t, nq); memcpy(t, nq, 16);
                quat_rot(q, t + 4, r); t[4] = r[0] + 40; t[5] = r[1]; t[6] = r[2] - 20;
            }
            skin_probe((u64)comp_a, 0);
            printf("head probe flung: %.300s\n", lastres);
            sscanf(lastres, "ok stretched=%d", &fl);
            char *h0 = strstr(lastres, "hidden="); if (h0) sscanf(h0, "hidden=%d", &flh);
            memcpy(space, saved, 48 * NB); free(saved);
        }
        int bad = hleft > nh / 50 || taken > 0;
        // (more than with the head still: an enemy's bind pose stretches a few already)
        if (fl - flh > st - sth) { printf("FAIL: %d more triangles stretch, visible, with the head flung off\n", fl - flh - (st - sth)); bad = 1; }
        printf("head: %d head vertices over the plane, %d stayed on the body; %d vertices off the neck went with it\n%s\n", nh, hleft, taken, bad ? "FAIL" : "PASS");
        return bad;
    }
    // ARM=1: F9's cut of the left upper arm (0.4 down it, square to it), the cape's chain (Ab_CapeL01, hanging off the
    // arm's twist bone) named to stay on the body, as gore.lua does (NOKEEP=1: not named, it goes with the arm). Every
    // vertex the vanilla skin puts mostly on the cape must stay on the body, every one mostly on the forearm's subtree
    // must go with the arm
    if (env_on("ARM")) {
        int ua = bone(getenv("ARMBONE") ? getenv("ARMBONE") : "Bip001-L-UpperArm"), fa = bone(getenv("ARMEND") ? getenv("ARMEND") : "Bip001-L-Forearm");
        if (ua < 0 || fa < 0) { fprintf(stderr, "no left arm\n"); return 1; }
        // CAPE=<root,root...>: the chains named to stay on the body (CH_P_EVE_14's leg straps: Ab_LLA01,Ab_LLB01), the
        // cape by default
        int capes[8], ncape = 0;
        {
            char cl[256];
            snprintf(cl, sizeof cl, "%s", getenv("CAPE") ? getenv("CAPE") : "Ab_CapeL01");
            for (char *tk = strtok(cl, ","); tk && ncape < 8; tk = strtok(0, ",")) {
                int c = bone(tk);
                if (c >= 0) capes[ncape++] = c;
            }
        }
        int cape = ncape ? capes[0] : -1;
        // (an outfit with no cape, CH_P_EVE_30: the arm cut alone; it had been skipped, and its stump came out hollow)
        if (cape < 0) printf("arm: no %s on this mesh, the arm alone\n", getenv("CAPE") ? getenv("CAPE") : "Ab_CapeL01");
        // DOWN=1: her idle pose's arm, hanging down her side (the bind pose holds it out): the arm's subtree turned about
        // the shoulder until the elbow is under it, 12 degrees out from the body
        if (env_on("DOWN")) {
            float *pp = space + pelvis * 12 + 4, *hp = space + head * 12 + 4, up[3], d[3], o[3], lu = 0, ld = 0;
            for (int k = 0; k < 3; k++) { up[k] = hp[k] - pp[k]; lu += up[k] * up[k]; }
            for (int k = 0; k < 3; k++) { up[k] /= __builtin_sqrtf(lu); o[k] = space[ua * 12 + 4 + k]; d[k] = space[fa * 12 + 4 + k] - o[k]; }
            for (int k = 0; k < 3; k++) ld += d[k] * d[k];
            ld = __builtin_sqrtf(ld);
            for (int k = 0; k < 3; k++) d[k] /= ld;
            // out: the arm's direction off the up axis
            float du = d[0] * up[0] + d[1] * up[1] + d[2] * up[2], out[3], lo = 0, want[3], lw = 0;
            for (int k = 0; k < 3; k++) { out[k] = d[k] - up[k] * du; lo += out[k] * out[k]; }
            for (int k = 0; k < 3; k++) { out[k] /= __builtin_sqrtf(lo); want[k] = -up[k] * 0.978f + out[k] * 0.208f; lw += want[k] * want[k]; }
            for (int k = 0; k < 3; k++) want[k] /= __builtin_sqrtf(lw);
            float ax[3] = { d[1] * want[2] - d[2] * want[1], d[2] * want[0] - d[0] * want[2], d[0] * want[1] - d[1] * want[0] };
            float cs = d[0] * want[0] + d[1] * want[1] + d[2] * want[2], qa[4] = { ax[0], ax[1], ax[2], 1 + cs }, ql = 0;
            for (int k = 0; k < 4; k++) ql += qa[k] * qa[k];
            for (int k = 0; k < 4; k++) qa[k] /= __builtin_sqrtf(ql);
            unsigned char *sub = calloc(NB, 1);
            for (int i = 0; i < NB; i++) sub[i] = i == ua || (bparent[i] >= 0 && sub[bparent[i]]);
            for (int i = 0; i < NB; i++) if (sub[i]) {
                float *t = space + i * 12, nq[4], e[3] = { t[4] - o[0], t[5] - o[1], t[6] - o[2] }, r[3];
                qmul(qa, t, nq); memcpy(t, nq, 16);
                quat_rot(qa, e, r); t[4] = o[0] + r[0]; t[5] = o[1] + r[1]; t[6] = o[2] + r[2];
            }
            free(sub);
        }
        float *a = space + ua * 12 + 4, *b2 = space + fa * 12 + 4, at2[3], nn[3], l = 0;
        float armat = getenv("ARMAT") ? (float)atof(getenv("ARMAT")) : 0.4f; // ARMAT: where down the upper arm (gore.lua PARTS at)
        for (int k = 0; k < 3; k++) { at2[k] = a[k] + (b2[k] - a[k]) * armat; nn[k] = b2[k] - a[k]; l += nn[k] * nn[k]; }
        for (int k = 0; k < 3; k++) nn[k] /= __builtin_sqrtf(l);
        // ARMTILT=<deg>: the plane leans that far off square to the arm (a blade's cut along its swing, 52 degrees in
        // the playtest), ARMTILTDIR=0..7 which way round the arm, 45 degrees apart
        if (getenv("ARMTILT")) {
            float tilt = (float)atof(getenv("ARMTILT")) * 3.14159f / 180, way = (getenv("ARMTILTDIR") ? atoi(getenv("ARMTILTDIR")) : 0) * 0.7854f;
            float e1[3] = { __builtin_fabsf(nn[2]) < 0.9f ? 0.0f : 1.0f, 0, __builtin_fabsf(nn[2]) < 0.9f ? 1.0f : 0.0f }, t = e1[0] * nn[0] + e1[1] * nn[1] + e1[2] * nn[2], el = 0;
            for (int k = 0; k < 3; k++) { e1[k] -= t * nn[k]; el += e1[k] * e1[k]; }
            for (int k = 0; k < 3; k++) e1[k] /= __builtin_sqrtf(el);
            float e2[3] = { nn[1] * e1[2] - nn[2] * e1[1], nn[2] * e1[0] - nn[0] * e1[2], nn[0] * e1[1] - nn[1] * e1[0] };
            for (int k = 0; k < 3; k++) nn[k] = nn[k] * __builtin_cosf(tilt) + (e1[k] * __builtin_cosf(way) + e2[k] * __builtin_sinf(way)) * __builtin_sinf(tilt);
        }
        // ELBOWHIP=1 (a thigh cut, ARMBONE=Bip001-L-Thigh): her left arm moved so its elbow helper lies on the hip
        // joint, the hand resting by the hip in a fall. In game the hip's own helpers had moved off it (driven by the
        // bent thigh) and that helper was the best sink: the hip's seam went off with the flailing arm, a sheet from
        // the hip to the elbow (twenty-seventh playtest). No sink may be on another limb
        if (env_on("ELBOWHIP")) {
            int eb = bone("Ab-L-Elbow"), lu = bone("Bip001-L-UpperArm");
            if (eb < 0) eb = bone("Bip001-L-Forearm");
            if (eb < 0 || lu < 0) { fprintf(stderr, "no left elbow\n"); return 1; }
            float *jp = space + ua * 12 + 4, dl[3];
            for (int k = 0; k < 3; k++) dl[k] = jp[k] - space[eb * 12 + 4 + k];
            unsigned char *sub = calloc(NB, 1);
            for (int i = 0; i < NB; i++) sub[i] = i == lu || (bparent[i] >= 0 && sub[bparent[i]]);
            for (int i = 0; i < NB; i++) if (sub[i]) for (int k = 0; k < 3; k++) space[i * 12 + 4 + k] += dl[k];
            free(sub);
        }
        // DRIVEN=1: the helpers on the arm's parent swung 20 degrees off it once while she played (a corrective the
        // animation drives, as the spine's Ab-AX3 that flung a thigh's stub about, twenty-fifth playtest): none may
        // carry the stub
        int driven = env_on("DRIVEN") || env_on("UNWATCHED");
        if (env_on("DRIVEN")) {
            float q[4] = { 0, __builtin_sinf(0.1745f), 0, __builtin_cosf(0.1745f) };
            // (with the helpers under it, as the animation turns them: Ab-R-Side under the aim helper Dm-R-Side-Point
            // held still against it)
            for (int i = 0; i < NB; i++) if (bparent[i] == bparent[ua] && strncmp(bname[i], "Bip001", 6)) {
                float *keep = malloc(48 * NB), *o0 = space + i * 12 + 4, org[3] = { o0[0], o0[1], o0[2] };
                memcpy(keep, space, 48 * NB);
                for (int j = 0; j < NB; j++) {
                    int under = 0;
                    for (int a2 = j; a2 >= 0 && !under; a2 = bparent[a2]) under = a2 == i;
                    if (!under) continue;
                    float *t = space + j * 12, o[4], d[3] = { t[4] - org[0], t[5] - org[1], t[6] - org[2] }, r[3];
                    qmul(q, t, o); memcpy(t, o, 16);
                    quat_rot(q, d, r); t[4] = org[0] + r[0]; t[5] = org[1] + r[1]; t[6] = org[2] + r[2];
                }
                skin_watch((u64)comp_a);
                memcpy(space, keep, 48 * NB); free(keep);
            }
        }
        // LEGFIRST=<thigh>: that thigh came off first (0.4 down it, square to it, collapsed), as a killing swing through
        // both legs: the crotch between them stretched (twenty-ninth playtest)
        int lf = getenv("LEGFIRST") ? bone(getenv("LEGFIRST")) : -1, nfirst = 0;
        if (lf >= 0) {
            int lc = -1;
            for (int i = 0; i < NB; i++) if (bparent[i] == lf && strstr(bname[i], "Calf")) lc = i;
            if (lc < 0) { fprintf(stderr, "no calf under %s\n", bname[lf]); return 1; }
            float *ap = space + lf * 12 + 4, *bp = space + lc * 12 + 4, aat[3], an[3], al = 0;
            for (int k = 0; k < 3; k++) { aat[k] = ap[k] + (bp[k] - ap[k]) * 0.4f; an[k] = bp[k] - ap[k]; al += an[k] * an[k]; }
            for (int k = 0; k < 3; k++) an[k] /= __builtin_sqrtf(al);
            set_nosink(); other_limbs_nosink(lf);
            limbs_comp = (u64)comp_a; ngone = 0; nkeep = 0; nride = 0; ndrop = 0;
            skin_cut((u64)comp_a, 0, lf, aat, an, MODE_CUT, 0, 0, -1);
            printf("leg first: %.200s\n", lastres);
            if (strncmp(lastres, "ok", 2)) { printf("FAIL: the leg cut first failed\n"); return 1; }
            skin_collapse();
            const char *q = strstr(lastres, " sinks=");
            for (q = q ? q + 7 : 0, nfirst = q && *q != ' '; q && *q && *q != ' '; q++) nfirst += *q == ',';
        }
        set_nosink();
        other_limbs_nosink(ua);
        // the cape goes whole with the arm, as gore.lua sends it (the 4th group); KEEPCAPE=1 keeps it on the body
        // as gore.lua does by default: kept on the body by the arm's cut, then cut off at its root as a piece of its
        // own; KEEPCAPE=1 leaves it on the body (tune.gore.chains "body"), WITH=1 sends it whole with the arm
        int keep = cape >= 0 && !env_on("NOKEEP"), detach = keep && !env_on("KEEPCAPE") && !env_on("WITH");
        int onbody = keep && !env_on("WITH"), with = keep && env_on("WITH");
        limbs_comp = (u64)comp_a; ngone = 0; nkeep = onbody ? ncape : 0; nride = 0;
        ndrop = with ? ncape : 0;
        memcpy(keep_roots, capes, 4 * ncape); memcpy(drop_roots, capes, 4 * ncape);
        skin_cut((u64)comp_a, 0, ua, at2, nn, MODE_CUT, 0, 0, -1);
        printf("arm: %.300s\n", lastres);
        if (!ov_a) { printf("FAIL: no override\n"); return 1; }
        // every sink of the cut on the cut's own limb or off the limbs (the body), none on another arm or leg
        {
            const char *q = strstr(lastres, " sinks=");
            int own = limb_of(ua), wrong = 0, k = 0;
            for (q = q ? q + 7 : 0; q && *q && *q != ' '; k++) {
                int i = atoi(q);
                // (the first leg's own sinks are on that leg)
                if (k >= nfirst && i > 0 && i < NB && limb_of(i) >= 0 && limb_of(i) != own) { printf("arm: sink %s is on %s\n", bname[i], bname[limb_of(i)]); wrong++; }
                while (*q && *q != ',' && *q != ' ') q++;
                if (*q == ',') q++;
            }
            if (wrong) { printf("FAIL: %d sinks on another limb (the seam would ride it)\n", wrong); return 1; }
        }
        // every new sink rides its side's stump's body or the next one (gore.lua sends her bodies): further, the
        // seam's point moves against the opening as she bends
        if (nbodies) {
            short g[MAX_BONES];
            cut_ctx cc = { 0 }; cc.binfo = binfo; cc.nb = NB;
            for (int i = 0; i < NB; i++) g[i] = hasbody[i] ? i : bparent[i] >= 0 ? g[bparent[i]] : -1;
            int far = 0;
            for (int k = 0; k < nsinks; k++) {
                if (sinks[k].carry) continue;
                int sb = sinks[k].bone, sd = 0;
                for (int a2 = sb; a2 >= 0; a2 = bparent[a2]) if (a2 == ua) sd = 1;
                int h = body_hops(&cc, g, g[sb], sd ? g[ua] : g[bparent[ua]]);
                if (h > 1) { printf("arm: sink %s rides %s, %d bodies off its stump's %s\n", bname[sb], bname[g[sb]], h, bname[sd ? g[ua] : g[bparent[ua]]]); far++; }
            }
            if (far) { printf("FAIL: %d sinks ride a body away from their stump\n", far); return 1; }
        }
        if (driven) {
            if (strstr(lastres, " carried=")) { printf("FAIL: a helper that swung while she played (or was never watched) carries the stub\n"); return 1; }
            // nor may a sink hang under one: Ab-R-Side, still against Dm-R-Side-Point (the aim helper the animation
            // points at the arm), took the shoulder's seam, and in an animated death it chased the flying arm, a sheet
            // from the shoulder to it (playtest, CH_P_EVE_29)
            if (env_on("DRIVEN")) {
                const char *q = strstr(lastres, " sinks=");
                int under = 0;
                for (q = q ? q + 7 : 0; q && *q && *q != ' ';) {
                    int i = atoi(q);
                    // (one that swung itself may take it, the sink of last resort: it moves the point a few cm)
                    for (int a2 = bparent[i]; a2 >= 0 && strncmp(bname[a2], "Bip001", 6); a2 = bparent[a2])
                        if (bparent[a2] == bparent[ua]) { printf("arm: sink %s hangs under %s, which swung\n", bname[i], bname[a2]); under++; break; }
                    while (*q && *q != ',' && *q != ' ') q++;
                    if (*q == ',') q++;
                }
                if (under) { printf("FAIL: %d sinks under a helper that swung while she played\n", under); return 1; }
            }
            printf("arm: no carrier, as wanted\nPASS\n");
            return 0;
        }
        unsigned char *capeall = calloc(NB, 1);
        for (int i = 0; i < NB; i++) {
            for (int k = 0; k < ncape; k++) if (i == capes[k]) capeall[i] = 1;
            if (bparent[i] >= 0 && capeall[bparent[i]]) capeall[i] = 1;
        }
        for (int ck = 0; detach && ck < ncape; ck++) {
            int cape = capes[ck];
            // the cape's own cut: at its root joint, square to its first link, its bones allowed as sinks
            int c2 = -1;
            for (int i = 0; i < NB; i++) if (bparent[i] == cape) c2 = i;
            // the plane through the joint the cape hangs from (the arm's twist bone), facing down the cape: all of the
            // cape is in front of it (through the cape's own root, its top went to the twist bone, off with the arm)
            (void)c2;
            float *r0 = space + bparent[cape] * 12 + 4, *r1 = space + cape * 12 + 4, cn[3], cl = 0;
            for (int k = 0; k < 3; k++) { cn[k] = r1[k] - r0[k]; cl += cn[k] * cn[k]; }
            for (int k = 0; k < 3; k++) cn[k] /= __builtin_sqrtf(cl);
            // gore.lua's own list for it (nosink_list, not the arm cut's: other limbs allowed)
            base_nosink();
            // nor the arm's bones as the body side's sink: it is gone (an earlier cut's biceps sink pulled the
            // cape's seam off with the arm)
            for (int i = 0; i < NB; i++) {
                int arm = 0;
                for (int a = i; a >= 0 && !arm; a = bparent[a]) if (a == ua) arm = 1;
                if (capeall[i] && i != cape) nosink[i] = 0;
                else if (arm && !capeall[i]) nosink[i] = 1;
            }
            limbs_comp = (u64)comp_a; ngone = nkeep = ndrop = nride = 0;
            skin_cut((u64)comp_a, 0, cape, r0, cn, MODE_CUT, 0, 0, -1);
            printf("cape: %.300s\n", lastres);
            set_nosink();
        }
        unsigned char *capeb = calloc(NB, 1), *fore = calloc(NB, 1), *armb = calloc(NB, 1);
        for (int i = 0; i < NB; i++) {
            capeb[i] = capeall[i];
            fore[i] = i == fa || (bparent[i] >= 0 && fore[bparent[i]]);
            armb[i] = (i == ua || (bparent[i] >= 0 && armb[bparent[i]]));
        }
        for (int i = 0; i < NB; i++) if (capeb[i]) armb[i] = 0;
        int nc = 0, cgone = 0, nf = 0, fleft = 0;
        for (int v = 0; v < NV; v++) {
            skin_info vo; orig_info(v, &vo);
            int wc = 0, wf = 0;
            for (int i = 0; i < 8; i++) if (vo.weights[i]) { if (capeb[vo.bones[i]]) wc += vo.weights[i]; if (fore[vo.bones[i]]) wf += vo.weights[i]; }
            // gone with the arm: any weight on the arm's own bones now
            int onarm = 0;
            for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && armb[ov_a[v].bones[i]]) onarm = 1;
            // with the arm: every weight on the arm's subtree, the cape's included
            int whole = 1;
            for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && !armb[ov_a[v].bones[i]] && !capeb[ov_a[v].bones[i]]) whole = 0;
            int capeonly = 1;
            for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && !capeb[ov_a[v].bones[i]]) capeonly = 0;
            if (wc > 127) { nc++; cgone += detach ? !capeonly : with ? whole : onarm; }
            if (wc > 127 && detach && !capeonly && env_on("DBG")) {
                static int shown_n = 0;
                if (shown_n++ < 6) {
                    printf("dbg v%d:", v);
                    for (int i = 0; i < 8; i++) if (vo.weights[i]) printf(" %s=%d", bname[vo.bones[i]], vo.weights[i]);
                    printf(" ->");
                    for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i]) printf(" %s=%d", bname[ov_a[v].bones[i]], ov_a[v].weights[i]);
                    printf("\n");
                }
            }
            if (wf > 127) { nf++; fleft += !onarm; }
            if (wf > 127 && !onarm && getenv("DBGFORE")) {
                static int sf = 0;
                float x[3]; skin_v(&vo, v, x);
                if (sf++ < 12) { printf("fore v%d h=%.1f:", v, (x[0]-at2[0])*nn[0]+(x[1]-at2[1])*nn[1]+(x[2]-at2[2])*nn[2]);
                for (int i = 0; i < 8; i++) if (vo.weights[i]) printf(" %s=%d", bname[vo.bones[i]], vo.weights[i]);
                printf(" ->"); for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i]) printf(" %s=%d", bname[ov_a[v].bones[i]], ov_a[v].weights[i]); printf("\n"); }
            }
        }
        // what else goes with the arm, per section: vertices the vanilla skin puts mostly off the arm (an outfit piece
        // over the shoulder, a strap) that the cut takes along all the same
        for (int sc = 0; sc < NSEC; sc++) {
            unsigned char *sec = (unsigned char *)secbuf + sc * 0xe8;
            int b0 = *(int *)(sec + SEC_BASE_VERTEX), n0 = *(int *)(sec + SEC_NUM_VERTICES), gone = 0, off = 0;
            for (int v = b0; v < b0 + n0; v++) {
                int onarm = 0;
                for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && armb[ov_a[v].bones[i]]) onarm = 1;
                if (!onarm) continue;
                gone++;
                skin_info vo; orig_info(v, &vo);
                int wa = 0;
                for (int i = 0; i < 8; i++) if (vo.weights[i] && armb[vo.bones[i]]) wa += vo.weights[i];
                off += wa <= 127;
            }
            int sunk = 0;
            for (int v = b0; v < b0 + n0; v++) {
                int all = 1, any = 0;
                for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i]) { any = 1; if (!is_sink(&(cut_ctx){ .sm = (u64)sm_buf }, ov_a[v].bones[i])) all = 0; }
                sunk += any && all;
            }
            if (gone || sunk) printf("arm: section %d (%d vertices): %d go with the arm, %d of them mostly off it, %d sunk\n", sc, n0, gone, off, sunk);
            if (env_on("DBGARM")) { // where this section's skin lies against the plane: behind it and gone, in front and kept
                int behind_gone = 0, front_kept = 0, near_kept = 0; float minb = 1e9f, maxb = -1e9f;
                for (int v = b0; v < b0 + n0; v++) {
                    int onarm = 0;
                    for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && armb[ov_a[v].bones[i]]) onarm = 1;
                    skin_info vo; orig_info(v, &vo);
                    float x[3]; skin_v(&vo, v, x);
                    float hd = (x[0] - at2[0]) * nn[0] + (x[1] - at2[1]) * nn[1] + (x[2] - at2[2]) * nn[2];
                    int wa = 0;
                    for (int i = 0; i < 8; i++) if (vo.weights[i] && armb[vo.bones[i]]) wa += vo.weights[i];
                    if (onarm && hd < -1) behind_gone++;
                    if (!onarm && hd > 1 && wa > 127) front_kept++;
                    if (!onarm && wa > 127) { near_kept++; if (hd < minb) minb = hd; if (hd > maxb) maxb = hd; }
                }
                printf("arm dbg: section %d: %d gone from behind the plane, %d mostly-arm kept in front; mostly-arm kept %d, %.1f..%.1f cm off the plane\n",
                       sc, behind_gone, front_kept, near_kept, minb, maxb);
            }
        }
        // the body's rim (kept vertices of triangles the arm took part of), posed with the cut's weights once its sinks and
        // carriers are in: it must still go round the arm. Kept stub skin put on the clavicle snapped back towards the
        // bind pose and left a 3-of-16-direction sliver 4 cm off the cut, a hollow stump (twenty-second playtest)
        int rimdirs = 16;
        {
            unsigned char *gn = calloc(NV, 1), *rv = calloc(NV, 1);
            // gone (on the arm) or sunk (wholly on the cut's collapsing sinks, the seam): the rim is what is next to them
            for (int v = 0; v < NV; v++) {
                int all = 1, any = 0;
                for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i]) {
                    any = 1;
                    if (armb[ov_a[v].bones[i]]) gn[v] = 1;
                    int sk = 0;
                    for (int k = 0; k < nsinks; k++) if (sinks[k].bone == ov_a[v].bones[i] && !sinks[k].carry) sk = 1;
                    if (!sk) all = 0;
                }
                if (any && all) gn[v] = 2;
            }
            for (int t = 0; t + 2 < NIDX; t += 3) {
                int g = !!gn[idx[t]] + !!gn[idx[t + 1]] + !!gn[idx[t + 2]];
                if (g && g < 3) for (int k = 0; k < 3; k++) if (!gn[idx[t + k]]) rv[idx[t + k]] = 1;
            }
            float ax[3] = { __builtin_fabsf(nn[0]) < 0.9f ? 1.0f : 0.0f, __builtin_fabsf(nn[0]) < 0.9f ? 0.0f : 1.0f, 0 }, tt = ax[0] * nn[0] + ax[1] * nn[1];
            for (int k = 0; k < 3; k++) ax[k] -= tt * nn[k];
            float al = __builtin_sqrtf(ax[0] * ax[0] + ax[1] * ax[1] + ax[2] * ax[2]);
            for (int k = 0; k < 3; k++) ax[k] /= al;
            float ay[3] = { nn[1] * ax[2] - nn[2] * ax[1], nn[2] * ax[0] - nn[0] * ax[2], nn[0] * ax[1] - nn[1] * ax[0] };
            for (int pass = 0; pass < 2; pass++) {
                if (pass) skin_collapse(); // "k"
                int bins = 0, cnt = 0; float hs = 0, rs = 0;
                for (int v = 0; v < NV; v++) if (rv[v]) {
                    skin_info vo; if (pass) vo = ov_a[v]; else orig_info(v, &vo);
                    float x[3]; skin_v(&vo, v, x);
                    float d[3] = { x[0] - at2[0], x[1] - at2[1], x[2] - at2[2] }, h = d[0] * nn[0] + d[1] * nn[1] + d[2] * nn[2];
                    float u = d[0] * ax[0] + d[1] * ax[1] + d[2] * ax[2], w = d[0] * ay[0] + d[1] * ay[1] + d[2] * ay[2];
                    int bn = (int)((__builtin_atan2f(w, u) + 3.14159f) / 6.28319f * 16); if (bn > 15) bn = 15; if (bn < 0) bn = 0;
                    bins |= 1 << bn; cnt++; hs += h; rs += __builtin_sqrtf(u * u + w * w);
                }
                if (pass) rimdirs = __builtin_popcount(bins);
                if (env_on("DBGARM") || (pass && rimdirs < 12)) printf("arm: body rim %s: %d vertices, %d of 16 directions, mean %.1f cm off the plane, %.1f from the axis\n",
                       pass ? "cut weights" : "vanilla weights", cnt, __builtin_popcount(bins), cnt ? hs / cnt : 0, cnt ? rs / cnt : 0);
            }
            free(gn); free(rv);
        }
        // the stretch probe with the arm flung off (the arm's subtree turned 45 degrees and moved 40 cm out, 20 down): a
        // triangle stretched from the body to the dropped arm is the outfit hanging off the shoulder (sixteenth playtest)
        int still = -1, flung = -1, hid = 0, still_hid = 0;
        skin_collapse(); // "k", as in game a few frames after the cut
        // HEADAFTER=1: the killing swing's head cut right after the arm's (gore.lua's "one swing, then head"): MODE_PLANE
        // on Bip001-Head HEADAT (1.0) of the way from the neck, square to it, as for Eve (her head goes on the face mesh), then
        // collapsed. The arm must still come off clean (a sheet from the shoulder to the dropped arm, playtest)
        if (env_on("HEADAFTER")) {
            int neck = bone("Bip001-Neck");
            float *a = space + neck * 12 + 4, *b2 = space + head * 12 + 4, hat[3], hn[3], hl = 0;
            float hat_t = getenv("HEADAT") ? (float)atof(getenv("HEADAT")) : 1.0f; // tune.gore.headAt
            for (int k = 0; k < 3; k++) { hat[k] = a[k] + (b2[k] - a[k]) * hat_t; hn[k] = b2[k] - a[k]; hl += hn[k] * hn[k]; }
            for (int k = 0; k < 3; k++) hn[k] /= __builtin_sqrtf(hl);
            set_nosink(); other_limbs_nosink(head);
            limbs_comp = (u64)comp_a; ngone = nkeep = ndrop = nride = 0;
            skin_cut((u64)comp_a, 0, head, hat, hn, MODE_PLANE, 0, 0, -1);
            printf("head after: %.300s\n", lastres);
            skin_collapse();
            int gone_arm = 0, nfa = 0;
            for (int v = 0; v < NV; v++) {
                skin_info vo; orig_info(v, &vo);
                int wf = 0, onarm = 0;
                for (int i = 0; i < 8; i++) if (vo.weights[i] && fore[vo.bones[i]]) wf += vo.weights[i];
                for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && armb[ov_a[v].bones[i]]) onarm = 1;
                if (wf > 127) { nfa++; gone_arm += !onarm; }
            }
            printf("head after: %d of %d forearm vertices fell off the arm\n", gone_arm, nfa);
        }
        {
            float *saved = malloc(48 * NB);
            memcpy(saved, space, 48 * NB);
            skin_probe((u64)comp_a, 0);
            sscanf(lastres, "ok stretched=%d", &still);
            printf("arm probe still: %.300s\n", lastres);
            { char *h0 = strstr(lastres, "hidden="); if (h0) sscanf(h0, "hidden=%d", &still_hid); }
            still_hid = still - still_hid; // the visible ones
            float q[4] = { 0.3826834f, 0, 0, 0.9238795f };
            float ua0[3] = { space[ua * 12 + 4], space[ua * 12 + 5], space[ua * 12 + 6] };
            float fa0[3] = { space[fa * 12 + 4], space[fa * 12 + 5], space[fa * 12 + 6] };
            for (int i = 0; i < NB; i++) if (i == ua || armb[i]) {
                float *t = space + i * 12, nq[4]; qmul(q, t, nq); memcpy(t, nq, 16);
                float r[3]; quat_rot(q, t + 4, r); t[4] = r[0] + 40; t[5] = r[1]; t[6] = r[2] - 20;
            }
            // the first leg flies its own way: 40 cm the other side and 20 down
            if (lf >= 0) {
                unsigned char *ls = calloc(NB, 1);
                for (int i = 0; i < NB; i++) ls[i] = i == lf || (bparent[i] >= 0 && ls[bparent[i]]);
                for (int i = 0; i < NB; i++) if (ls[i]) { space[i * 12 + 4] -= 40; space[i * 12 + 6] -= 20; }
                free(ls);
            }
            // detached, the cape falls its own way: 30 cm back and 25 down, turned the other way
            if (detach) {
                float q2[4] = { -0.3826834f, 0, 0, 0.9238795f };
                for (int i = 0; i < NB; i++) if (capeall[i]) {
                    float *t = space + i * 12, nq[4]; qmul(q2, t, nq); memcpy(t, nq, 16);
                    float r[3]; quat_rot(q2, t + 4, r); t[4] = r[0] - 30; t[5] = r[1]; t[6] = r[2] - 25;
                }
            }
            // HIPMOVED=1: the hip's correctives go on moving after the cut (the death animation drives them): each
            // turns 20 degrees about its own origin, with the seam's point on it if it is a sink
            if (env_on("HIPMOVED")) for (int i = 0; i < NB; i++) if (strstr(bname[i], "Venter") || strstr(bname[i], "-AX2")) {
                float qv[4] = { 0, __builtin_sinf(0.1745f), 0, __builtin_cosf(0.1745f) }, *t = space + i * 12, nq[4];
                qmul(qv, t, nq); memcpy(t, nq, 16);
            }
            // HIPMOVED=1: the hip's correctives go on moving after the cut (the death animation drives them): each
            // turns 20 degrees about its own origin, with the seam's point on it if it is a sink
            if (env_on("HIPMOVED")) for (int i = 0; i < NB; i++) if (strstr(bname[i], "Venter") || strstr(bname[i], "-AX2")) {
                float qv[4] = { 0, __builtin_sinf(0.1745f), 0, __builtin_cosf(0.1745f) }, *t = space + i * 12, nq[4];
                qmul(qv, t, nq); memcpy(t, nq, 16);
            }
            // the game's aim helpers chase the arm (the anim graph points them at it): Dm-L-Side-Point off the
            // clavicle and Dm-L-Trape-Cnt off Spine2 turn, with everything under them, from where the elbow was to
            // where it is now
            // (the cut arm's side: the right arm's were never turned)
            int right = strstr(bname[ua], "-R-") != 0;
            const char *aims[2] = { right ? "Dm-R-Side-Point" : "Dm-L-Side-Point", right ? "Dm-R-Trape-Cnt" : "Dm-L-Trape-Cnt" };
            for (int k = 0; k < 2; k++) {
                int h = bone(aims[k]);
                if (h < 0) continue;
                float *o = space + h * 12 + 4, p0[3], p1[3];
                for (int j = 0; j < 3; j++) { p0[j] = fa0[j] - o[j]; p1[j] = space[fa * 12 + 4 + j] - o[j]; }
                (void)ua0;
                float l0 = __builtin_sqrtf(p0[0] * p0[0] + p0[1] * p0[1] + p0[2] * p0[2]), l1 = __builtin_sqrtf(p1[0] * p1[0] + p1[1] * p1[1] + p1[2] * p1[2]);
                for (int j = 0; j < 3; j++) { p0[j] /= l0; p1[j] /= l1; }
                float ax[3] = { p0[1] * p1[2] - p0[2] * p1[1], p0[2] * p1[0] - p0[0] * p1[2], p0[0] * p1[1] - p0[1] * p1[0] };
                float cs = p0[0] * p1[0] + p0[1] * p1[1] + p0[2] * p1[2];
                float qa[4] = { ax[0], ax[1], ax[2], 1 + cs }, ql = __builtin_sqrtf(qa[0] * qa[0] + qa[1] * qa[1] + qa[2] * qa[2] + qa[3] * qa[3]);
                for (int j = 0; j < 4; j++) qa[j] /= ql;
                float org[3] = { o[0], o[1], o[2] };
                unsigned char *under = calloc(NB, 1);
                for (int i = 0; i < NB; i++) under[i] = i == h || (bparent[i] >= 0 && under[bparent[i]]);
                for (int i = 0; i < NB; i++) if (under[i]) {
                    float *t = space + i * 12, nq[4], d[3] = { t[4] - org[0], t[5] - org[1], t[6] - org[2] }, r[3];
                    qmul(qa, t, nq); memcpy(t, nq, 16);
                    quat_rot(qa, d, r); t[4] = org[0] + r[0]; t[5] = org[1] + r[1]; t[6] = org[2] + r[2];
                }
                free(under);
            }
            skin_probe((u64)comp_a, 0);
            sscanf(lastres, "ok stretched=%d", &flung);
            printf("arm probe flung: %.400s\n", lastres);
            char *h = strstr(lastres, "hidden="); if (h) sscanf(h, "hidden=%d", &hid);
            memcpy(space, saved, 48 * NB); free(saved);
            hid = flung - hid;
        }
        // not named: part of it goes with the arm (the bug), the rest stays torn off on the body
        int bad = cape < 0 ? 0 : onbody ? cgone > nc / 200 : with ? cgone < nc - nc / 200 : cgone == 0;
        if (rimdirs < 12) { printf("FAIL: the stump's opening covers %d of 16 directions round the arm\n", rimdirs); bad = 1; }
        // the stub moves with the limb's parent: the parent's subtree (the limb left out) turned 30 degrees about its
        // joint, every vertex wholly on a carrier must turn with it. A calf's stub carried on the spine stayed behind as
        // the thigh swung (twenty-fourth playtest)
        {
            int pb = bparent[ua], left = 0, n = 0;
            unsigned char *ps = calloc(NB, 1);
            for (int i = 0; i < NB; i++) ps[i] = i == pb || (bparent[i] >= 0 && ps[bparent[i]]);
            for (int i = 0; i < NB; i++) if (armb[i] || i == ua) ps[i] = 0;
            float *saved2 = malloc(48 * NB), *x0 = malloc(12 * (size_t)NV);
            memcpy(saved2, space, 48 * NB);
            unsigned char *oncar = calloc(NV, 1);
            for (int v = 0; v < NV; v++) {
                for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] == 255) for (int k = 0; k < nsinks; k++)
                    if (sinks[k].carry && sinks[k].bone == ov_a[v].bones[i]) oncar[v] = 1;
                if (oncar[v]) { skin_v(&ov_a[v], v, x0 + 3 * (size_t)v); n++; }
            }
            float q[4] = { 0.258819f, 0, 0, 0.9659258f }, org[3] = { space[pb * 12 + 4], space[pb * 12 + 5], space[pb * 12 + 6] };
            for (int i = 0; i < NB; i++) if (ps[i]) {
                float *t = space + i * 12, nq[4], d[3] = { t[4] - org[0], t[5] - org[1], t[6] - org[2] }, r[3];
                qmul(q, t, nq); memcpy(t, nq, 16);
                quat_rot(q, d, r); t[4] = org[0] + r[0]; t[5] = org[1] + r[1]; t[6] = org[2] + r[2];
            }
            for (int v = 0; v < NV; v++) {
                if (!oncar[v]) continue;
                float x[3], *y = x0 + 3 * (size_t)v, d[3] = { y[0] - org[0], y[1] - org[1], y[2] - org[2] }, w[3];
                skin_v(&ov_a[v], v, x);
                quat_rot(q, d, w);
                float e0 = x[0] - org[0] - w[0], e1 = x[1] - org[1] - w[1], e2 = x[2] - org[2] - w[2];
                if (e0 * e0 + e1 * e1 + e2 * e2 > 1) left++;
            }
            memcpy(space, saved2, 48 * NB);
            free(saved2); free(x0); free(oncar); free(ps);
            if (env_on("DBGARM")) printf("arm: %d vertices on the carrier, %d left behind by the parent turning\n", n, left);
            if (left) { printf("FAIL: %d of the stub's %d carried vertices didn't turn with %s\n", left, n, bname[pb]); bad = 1; }
        }
        if (hid > still_hid) { printf("FAIL: the arm flung off stretches %d more triangles that stay visible\n", hid - still_hid); bad = 1; }
        // the second leg's seam stays at its own opening: on the first leg's sink it stretched to that stump
        if (lf >= 0 && still_hid > 0) { printf("FAIL: %d triangles stretch with both legs off, before either moves\n", still_hid); bad = 1; }
        printf("arm (cape %s): %d cape vertices, %d went with the arm; %d forearm vertices, %d stayed on the body\n%s\n",
            detach ? "detached, counted: not on its own bones" : onbody ? "kept on the body" : with ? "with the arm" : "not named",
            nc, cgone, nf, fleft, bad || fleft > nf / 200 ? "FAIL" : "PASS");
        return bad || fleft > nf / 200;
    }
    // WAIST=1: F9's torso cut instead (CUT at Spine1, halfway to Spine2, square to the spine). Her hands and the cape
    // hang below it (the bind pose's arms reach down to the hips): every vertex the vanilla skin puts mostly on an
    // arm (the clavicles' subtrees) must go with the upper body, not stay floating on the legs
    if (env_on("WAIST")) {
        float *wrefinv0 = malloc(64 * NB); memcpy(wrefinv0, refinv, 64 * NB); // the vanilla skin, for the tear check
        int spine2 = bone("Bip001-Spine2");
        float *a = space + spine1 * 12 + 4, *b2 = space + spine2 * 12 + 4, at2[3], nn[3], l = 0;
        // WAISTAT=<0-1>: where between Spine1 and Spine2 (default half way); WAISTTILT=<deg> WAISTTILTDIR=<0-7>: the
        // plane tilted off square to the spine, about an axis turned DIR x 45 degrees around it (a blade's cut, gore.lua
        // body_blade)
        float wat = getenv("WAISTAT") ? (float)atof(getenv("WAISTAT")) : 0.5f;
        for (int k = 0; k < 3; k++) { at2[k] = a[k] + (b2[k] - a[k]) * wat; nn[k] = b2[k] - a[k]; l += nn[k] * nn[k]; }
        for (int k = 0; k < 3; k++) nn[k] /= __builtin_sqrtf(l);
        if (getenv("WAISTTILT")) {
            float tl = (float)atof(getenv("WAISTTILT")) * 3.14159265f / 180, dr = (getenv("WAISTTILTDIR") ? atoi(getenv("WAISTTILTDIR")) : 0) * 3.14159265f / 4;
            float ref[3] = { 0, 0, 1 };
            if (__builtin_fabsf(nn[2]) > 0.9f) { ref[0] = 1; ref[2] = 0; }
            float u[3] = { nn[1] * ref[2] - nn[2] * ref[1], nn[2] * ref[0] - nn[0] * ref[2], nn[0] * ref[1] - nn[1] * ref[0] }, ul = 0;
            for (int k = 0; k < 3; k++) ul += u[k] * u[k];
            for (int k = 0; k < 3; k++) u[k] /= __builtin_sqrtf(ul);
            float w[3] = { nn[1] * u[2] - nn[2] * u[1], nn[2] * u[0] - nn[0] * u[2], nn[0] * u[1] - nn[1] * u[0] }, ax[3], c[3];
            for (int k = 0; k < 3; k++) ax[k] = u[k] * __builtin_cosf(dr) + w[k] * __builtin_sinf(dr);
            c[0] = ax[1] * nn[2] - ax[2] * nn[1]; c[1] = ax[2] * nn[0] - ax[0] * nn[2]; c[2] = ax[0] * nn[1] - ax[1] * nn[0];
            for (int k = 0; k < 3; k++) nn[k] = nn[k] * __builtin_cosf(tl) + c[k] * __builtin_sinf(tl);
        }
        // ARMFIRST=1: the left upper arm came off first, as a killing swing through her raised arm that goes on into
        // her body (multiCut's body follow-through): the arm cut and its collapse, then the waist cut as usual
        int ua = -1;
        float *armx = 0;
        unsigned char *armsub = 0;
        if (env_on("ARMFIRST")) {
            ua = bone("Bip001-L-UpperArm");
            int fa = bone("Bip001-L-Forearm");
            if (ua < 0 || fa < 0) { fprintf(stderr, "no left arm\n"); return 1; }
            float *ap = space + ua * 12 + 4, *bp = space + fa * 12 + 4, aat[3], an[3], al = 0;
            for (int k = 0; k < 3; k++) { aat[k] = ap[k] + (bp[k] - ap[k]) * 0.4f; an[k] = bp[k] - ap[k]; al += an[k] * an[k]; }
            for (int k = 0; k < 3; k++) an[k] /= __builtin_sqrtf(al);
            set_nosink(); other_limbs_nosink(ua);
            // ARMCAPE=1: as gore.lua: the cape kept on the body by the arm cut, then cut off at its top as a piece of
            // its own (tune.gore.chains "detach")
            int capeb = env_on("ARMCAPE") ? bone("Ab_CapeL01") : -1;
            if (env_on("ARMCAPE") && capeb < 0) { printf("FAIL: no Ab_CapeL01\n"); return 1; }
            limbs_comp = (u64)comp_a; ngone = 0; nkeep = 0; nride = 0; ndrop = 0;
            if (capeb >= 0) keep_roots[nkeep++] = capeb;
            skin_cut((u64)comp_a, 0, ua, aat, an, MODE_CUT, 0, 0, -1);
            printf("arm first: %.200s\n", lastres);
            if (strncmp(lastres, "ok", 2)) { printf("FAIL: the arm cut first failed\n"); return 1; }
            skin_collapse();
            if (capeb >= 0) {
                float *cp = space + bparent[capeb] * 12 + 4, *ct = space + capeb * 12 + 4, cn[3], cl = 0, cat[3];
                for (int k = 0; k < 3; k++) { cat[k] = cp[k]; cn[k] = ct[k] - cp[k]; cl += cn[k] * cn[k]; }
                for (int k = 0; k < 3; k++) cn[k] /= __builtin_sqrtf(cl);
                set_nosink();
                for (int i = 0; i < NB; i++) {
                    int inchain = 0, inlimb = 0;
                    for (int j = i; j >= 0; j = bparent[j]) { if (j == capeb) inchain = 1; if (j == ua) inlimb = 1; }
                    if (inchain && i != capeb) nosink[i] = 0;
                    else if (!inchain && inlimb) nosink[i] = 1;
                }
                limbs_comp = (u64)comp_a; ngone = nkeep = nride = ndrop = 0;
                skin_cut((u64)comp_a, 0, capeb, cat, cn, MODE_CUT, 0, 0, -1);
                printf("cape off: %.200s\n", lastres);
                if (strncmp(lastres, "ok", 2)) { printf("FAIL: the cape's cut failed\n"); return 1; }
                skin_collapse();
            }
            // ARMFLUNG=1: the arm flew off and lies across the waist plane when the body is cut (playtest 41: an arm,
            // then the chest; half the flying arm went to her spine, long sheets from her to the hand). gore.lua names
            // the cut-off arm a drop root of the body cut (NODROP=1: it doesn't, the bug)
            if (env_on("ARMFLUNG")) {
                armsub = calloc(NB, 1);
                for (int i = 0; i < NB; i++) armsub[i] = i == ua || (bparent[i] >= 0 && armsub[bparent[i]]);
                float *r0 = space + ua * 12 + 4, side[3] = { r0[0] - at2[0], r0[1] - at2[1], r0[2] - at2[2] };
                float sd = side[0] * nn[0] + side[1] * nn[1] + side[2] * nn[2], sl = 0;
                for (int k = 0; k < 3; k++) { side[k] -= nn[k] * sd; sl += side[k] * side[k]; }
                sl = __builtin_sqrtf(sl);
                float to[3], mv[3];
                float up = (float)atof(getenv("ARMFLUNG")); // ARMFLUNG=<cm>: its shoulder joint that far over the plane (under: < 0)
                if (up == 0 && strcmp(getenv("ARMFLUNG"), "0")) up = 15;
                for (int k = 0; k < 3; k++) { to[k] = at2[k] + nn[k] * up + side[k] / sl * 40; mv[k] = to[k] - r0[k]; }
                for (int i = 0; i < NB; i++) if (armsub[i]) for (int k = 0; k < 3; k++) space[i * 12 + 4 + k] += mv[k];
                // where the arm's skin is now: the body cut must not move any of it
                armx = malloc(12 * (size_t)NV);
                int over = 0, under = 0;
                for (int v = 0; v < NV; v++) {
                    skin_v(&ov_a[v], v, armx + 3 * (size_t)v);
                    int w = 0;
                    for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && armsub[ov_a[v].bones[i]]) w += ov_a[v].weights[i];
                    if (w <= 127) continue;
                    float *x = armx + 3 * (size_t)v;
                    if ((x[0] - at2[0]) * nn[0] + (x[1] - at2[1]) * nn[1] + (x[2] - at2[2]) * nn[2] > 0) over++; else under++;
                }
                printf("arm flung: %d of its vertices over the waist plane, %d under\n", over, under);
                if (!under) { printf("FAIL: the flung arm doesn't reach under the plane\n"); return 1; }
            }
        }
        set_nosink();
        // as gore.lua for a cut through the spine: nothing on an arm or a leg is a sink (it swings on its own, and
        // the bind pose's arms hang down at the waist: a strap's seam collapsed onto a triceps helper), no bodies
        nbodies = 0; memset(hasbody, 0, sizeof hasbody);
        for (int i = 0; i < NB; i++) if (limb_of(i) >= 0) nosink[i] = 1;
        // and what a Dm- driver moves only as a last resort (gore.lua's driven_list after fffd; OLDDM=1: as before)
        if (!env_on("OLDDM") && !env_on("ENEMY")) for (int i = 0; i < NB; i++) drivenb[i] = (unsigned char)under_driver(i);
        if (armsub && !env_on("NODROP")) { limbs_comp = (u64)comp_a; ngone = nkeep = nride = ndrop = 0; drop_roots[ndrop++] = ua; }
        skin_cut((u64)comp_a, 0, spine1, at2, nn, MODE_CUT, 0, 0, -1);
        printf("waist: %.300s\n", lastres);
        if (!strstr(lastres, " unsunk=0 ")) { printf("FAIL: seam vertices left with no sink\n"); return 1; }
        if (!env_on("OLDDM") && !env_on("ENEMY")) {
            // (the list holds the earlier cuts' sinks too, this one's "new=" last)
            const char *q = strstr(lastres, " sinks="), *nw = strstr(lastres, " new=");
            int all = 0, fresh = nw ? atoi(nw + 5) : 0, k = 0;
            for (const char *r = q ? q + 7 : 0; r && *r && *r != ' '; r++) if (*r == ',') all++;
            all += q != 0;
            for (q = q ? q + 7 : 0; q && *q && *q != ' '; k++) {
                int i = atoi(q);
                if (k >= all - fresh && i >= 0 && i < NB && under_driver(i)) { printf("FAIL: the waist's seam on %s, which a Dm- driver moves\n", bname[i]); return 1; }
                while (*q && *q != ',' && *q != ' ') q++;
                if (*q == ',') q++;
            }
        }
        if (!ov_a) { printf("FAIL: no override\n"); return 1; }
        unsigned char *arm = calloc(NB, 1), *upper = calloc(NB, 1);
        for (int i = 0; i < NB; i++) {
            arm[i] = !strcmp(bname[i], "Bip001-L-Clavicle") || !strcmp(bname[i], "Bip001-R-Clavicle") || (bparent[i] >= 0 && arm[bparent[i]]);
            upper[i] = i == spine1 || (bparent[i] >= 0 && upper[bparent[i]]);
        }
        int arms = 0, left = 0, below = 0, lv = -1;
        for (int v = 0; v < NV; v++) {
            skin_info vo; orig_info(v, &vo);
            int w = 0;
            for (int i = 0; i < 8; i++) if (vo.weights[i] && arm[vo.bones[i]]) w += vo.weights[i];
            if (w <= 127) continue;
            arms++;
            float x[3]; skin_v(&vo, v, x);
            int under = (x[0] - at2[0]) * nn[0] + (x[1] - at2[1]) * nn[1] + (x[2] - at2[2]) * nn[2] < 0;
            below += under;
            // on the upper body now: every weight on Spine1's subtree, or on a sink of it (the seam)
            int body = 0;
            for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && !upper[ov_a[v].bones[i]]) body = 1;
            if (body) { left++; if (lv < 0 || under) lv = v; }
        }
        printf("waist: %d arm vertices (%d below the cut), %d left on the legs", arms, below, left);
        if (lv >= 0) for (int i = 0; i < MAX_INF; i++) if (ov_a[lv].weights[i]) printf(" %s=%d", bname[ov_a[lv].bones[i]], ov_a[lv].weights[i]);
        printf("\n");
        // outfit pieces across the cut (belt straps, the harness down her hips) are cut, not sent whole to one side:
        // nothing mostly on the upper body and 6 cm over the cut stays on the legs (straps stood up off her hips),
        // nothing mostly off it and 6 cm under the cut goes with the upper body (a gap in her hips; seventeenth playtest)
        int horns = 0, gaps = 0;
        for (int v = 0; v < NV; v++) {
            skin_info vo; orig_info(v, &vo);
            int w = 0, t = 0;
            for (int i = 0; i < 8; i++) { t += vo.weights[i]; if (vo.weights[i] && upper[vo.bones[i]]) w += vo.weights[i]; }
            float x[3]; skin_v(&vo, v, x);
            float d = (x[0] - at2[0]) * nn[0] + (x[1] - at2[1]) * nn[1] + (x[2] - at2[2]) * nn[2];
            int now = 0;
            for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && upper[ov_a[v].bones[i]]) now += ov_a[v].weights[i];
            if (d > 6 && w * 2 > t && now * 2 < t) {
                horns++;
                if (env_on("HORNS")) {
                    int sec = 0;
                    for (int q = 0; q < NSEC; q++) { unsigned char *sc = (unsigned char *)secbuf + q * 0xe8; if (v >= *(int *)(sc + SEC_BASE_VERTEX)) sec = q; }
                    printf("horn v%d sec %d at %.1f cm over:", v, sec, d);
                    for (int i = 0; i < 8; i++) if (vo.weights[i]) printf(" %s=%d", bname[vo.bones[i]], vo.weights[i]);
                    printf(" ->");
                    for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i]) printf(" %s=%d", bname[ov_a[v].bones[i]], ov_a[v].weights[i]);
                    printf("\n");
                }
            }
            if (d < -6 && w * 2 < t && now * 2 > t) {
                int a2 = 0;
                for (int i = 0; i < 8; i++) if (vo.weights[i] && arm[vo.bones[i]]) a2 += vo.weights[i];
                if (a2 * 2 <= t) gaps++;
            }
        }
        printf("waist: %d upper body vertices over the cut stay on the legs, %d hip vertices under it go with the upper body\n", horns, gaps);
        // the stretch probe with the upper body fallen off (Spine1's subtree turned 45 degrees, 50 cm out and 30 down,
        // its arms swung): a cut strap must not stretch from the hips to it, nor its edge after an arm
        int still = -1, flung = -1, hs = 0, hf = 0;
        skin_collapse();
        // ARMSAFTER=1: both upper arms cut off the upper body after the waist (the playtest's death on CH_P_EVE_30:
        // Spine1 at 0.88 along a 10-degree blade, then the right upper arm at 0.44 and the left at 0.83): their seams
        // stay on the upper body, none of the legs' skin goes to a sink up there
        if (env_on("ARMSAFTER")) {
            unsigned char *legs0 = calloc(NV, 1);
            for (int v = 0; v < NV; v++) {
                legs0[v] = 1;
                for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && upper[ov_a[v].bones[i]]) legs0[v] = 0;
            }
            const char *ab[2][2] = { { "Bip001-R-UpperArm", "Bip001-R-Forearm" }, { "Bip001-L-UpperArm", "Bip001-L-Forearm" } };
            const float aat2[2] = { 0.44f, 0.83f };
            for (int k = 0; k < 2; k++) {
                int u = bone(ab[k][0]), f = bone(ab[k][1]);
                if (u < 0 || f < 0) { printf("FAIL: no %s\n", ab[k][0]); return 1; }
                float *ap = space + u * 12 + 4, *bp = space + f * 12 + 4, aat[3], an[3], al = 0;
                for (int j = 0; j < 3; j++) { aat[j] = ap[j] + (bp[j] - ap[j]) * aat2[k]; an[j] = bp[j] - ap[j]; al += an[j] * an[j]; }
                for (int j = 0; j < 3; j++) an[j] /= __builtin_sqrtf(al);
                set_nosink(); other_limbs_nosink(u);
                limbs_comp = (u64)comp_a; ngone = nkeep = nride = ndrop = 0;
                skin_cut((u64)comp_a, 0, u, aat, an, MODE_CUT, 0, 0, -1);
                printf("%s after the waist: %.200s\n", ab[k][0], lastres);
                if (strncmp(lastres, "ok", 2)) { printf("FAIL: the arm cut failed\n"); return 1; }
                skin_collapse();
            }
            // the legs' skin as the waist cut left it may not take any weight up there
            int took = 0, tv = -1;
            for (int v = 0; v < NV; v++) {
                if (!legs0[v]) continue;
                for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && upper[ov_a[v].bones[i]]) { took++; tv = v; break; }
            }
            printf("arms after the waist: %d of the legs' vertices took weight on the upper body", took);
            if (tv >= 0) for (int i = 0; i < MAX_INF; i++) if (ov_a[tv].weights[i]) printf(" %s=%d", bname[ov_a[tv].bones[i]], ov_a[tv].weights[i]);
            printf("\n");
            if (took) { printf("FAIL: an arm cut after the waist pulled the legs' skin onto the upper body\n"); return 1; }
            free(legs0);
        }
        int armmoved = 0;
        if (armx) {
            for (int v = 0; v < NV; v++) {
                float x[3], *y = armx + 3 * (size_t)v;
                skin_v(&ov_a[v], v, x);
                float d0 = x[0] - y[0], d1 = x[1] - y[1], d2 = x[2] - y[2];
                if (d0 * d0 + d1 * d1 + d2 * d2 > 4) {
                    skin_info vo; orig_info(v, &vo);
                    int w = 0;
                    for (int i = 0; i < 8; i++) if (vo.weights[i] && armsub[vo.bones[i]]) w += vo.weights[i];
                    if (w > 127) armmoved++;
                }
            }
            printf("waist after the flung arm: %d of the arm's vertices moved\n", armmoved);
            if (armmoved) printf("FAIL: the body cut pulled the cut-off arm's skin\n");
            free(armx); free(armsub);
        }
        float *saved = malloc(48 * NB);
        memcpy(saved, space, 48 * NB);
        // where the legs' skin lies now (none of its weight on the upper body): flinging the upper body must not move it
        float *legx = malloc(12 * (size_t)NV);
        unsigned char *onlegs = calloc(NV, 1);
        for (int v = 0; v < NV; v++) {
            onlegs[v] = 1;
            for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i] && upper[ov_a[v].bones[i]]) onlegs[v] = 0;
            if (onlegs[v]) skin_v(&ov_a[v], v, legx + 3 * (size_t)v);
        }
        float *xstill = malloc(12 * (size_t)NV);
        for (int v = 0; v < NV; v++) skin_v(&ov_a[v], v, xstill + 3 * (size_t)v);
        // the uncut skin in the same poses: the flail turns the arm without the elbow helpers that hang elsewhere
        // (an enemy's Ab-L-Elbow, Ab_ArmAX*), which stretches the vanilla skin too, and that is no tear of the cut's
        float *ustill = malloc(12 * (size_t)NV);
        float *cur = refinv; refinv = wrefinv0;
        for (int v = 0; v < NV; v++) { skin_info vo; orig_info(v, &vo); skin_v(&vo, v, ustill + 3 * (size_t)v); }
        refinv = cur;
        skin_probe((u64)comp_a, 0);
        sscanf(lastres, "ok stretched=%d", &still);
        char *hh = strstr(lastres, "hidden="); if (hh) sscanf(hh, "hidden=%d", &hs);
        printf("waist probe still: %.300s\n", lastres);
        float q[4] = { 0.3826834f, 0, 0, 0.9238795f };
        for (int i = 0; i < NB; i++) if (upper[i]) {
            float *t = space + i * 12, nq[4]; qmul(q, t, nq); memcpy(t, nq, 16);
            float r[3]; quat_rot(q, t + 4, r); t[4] = r[0] + 50; t[5] = r[1]; t[6] = r[2] - 30;
        }
        // the spine's blend driver goes half way after it, as the animation drives it (between Spine and Spine1): a
        // stub carried on it stretched the waist after the flying upper body (twenty-third playtest)
        {
            int dm = bone("Dm-Spine-bland");
            if (dm >= 0) {
                float qh[4] = { 0.1950903f, 0, 0, 0.9807853f }, *t = space + dm * 12, nq[4], r[3];
                qmul(qh, t, nq); memcpy(t, nq, 16);
                quat_rot(qh, t + 4, r); t[4] = r[0] + 25; t[5] = r[1]; t[6] = r[2] - 15;
            }
        }
        // and her arms flail on it: each upper arm's subtree turned 60 degrees about the shoulder
        const char *ua2[2] = { "Bip001-L-UpperArm", "Bip001-R-UpperArm" };
        for (int k = 0; k < 2; k++) {
            int h = bone(ua2[k]);
            if (h < 0) continue;
            float qa[4] = { 0, k ? -0.5f : 0.5f, 0, 0.8660254f }, org[3] = { space[h * 12 + 4], space[h * 12 + 5], space[h * 12 + 6] };
            unsigned char *under = calloc(NB, 1);
            // with the upper arm's helpers that hang off the clavicle (an enemy's Ab-L-UpperArm-Sub, -Twist1): the
            // animation turns those with the arm, so leaving them behind stretches skin no cut made
            const char *helper = k ? "-R-UpperArm" : "-L-UpperArm";
            for (int i = 0; i < NB; i++) under[i] = i == h || (!strncmp(bname[i], "Ab-", 3) && strstr(bname[i], helper)) || (bparent[i] >= 0 && under[bparent[i]]);
            for (int i = 0; i < NB; i++) if (under[i]) {
                float *t = space + i * 12, nq[4], d[3] = { t[4] - org[0], t[5] - org[1], t[6] - org[2] }, r[3];
                qmul(qa, t, nq); memcpy(t, nq, 16);
                quat_rot(qa, d, r); t[4] = org[0] + r[0]; t[5] = org[1] + r[1]; t[6] = org[2] + r[2];
            }
            free(under);
        }
        skin_probe((u64)comp_a, 0);
        sscanf(lastres, "ok stretched=%d", &flung);
        hh = strstr(lastres, "hidden="); if (hh) sscanf(hh, "hidden=%d", &hf);
        printf("waist probe flung: %.400s\n", lastres);
        // skin torn between the halves: a triangle whose longest edge grows more than 5 cm when the upper body falls
        // off, more than 5 cm past what the uncut skin's grows in the same poses, and still has area (the stretch
        // probe counts it once, when the cut has already stretched it in place)
        int torn = 0;
        {
            float *xfl = malloc(12 * (size_t)NV), *ufl = malloc(12 * (size_t)NV);
            for (int v = 0; v < NV; v++) skin_v(&ov_a[v], v, xfl + 3 * (size_t)v);
            float *cur = refinv; refinv = wrefinv0;
            for (int v = 0; v < NV; v++) { skin_info vo; orig_info(v, &vo); skin_v(&vo, v, ufl + 3 * (size_t)v); }
            refinv = cur;
            int shownt = 0;
            for (int t = 0; t + 2 < NIDX; t += 3) {
                float l0 = 0, l1 = 0, u0 = 0, u1 = 0;
                for (int e = 0; e < 3; e++) {
                    u32 i = idx[t + e], j = idx[t + (e + 1) % 3];
                    float d0 = dist3(xstill + 3 * (size_t)i, xstill + 3 * (size_t)j), d1 = dist3(xfl + 3 * (size_t)i, xfl + 3 * (size_t)j);
                    float e0 = dist3(ustill + 3 * (size_t)i, ustill + 3 * (size_t)j), e1 = dist3(ufl + 3 * (size_t)i, ufl + 3 * (size_t)j);
                    if (d0 > l0) l0 = d0;
                    if (d1 > l1) l1 = d1;
                    if (e0 > u0) u0 = e0;
                    if (e1 > u1) u1 = e1;
                }
                if (l1 <= l0 + 5 || l1 - l0 <= u1 - u0 + 5) continue;
                float *a0 = xfl + 3 * (size_t)idx[t], *a1 = xfl + 3 * (size_t)idx[t + 1], *a2 = xfl + 3 * (size_t)idx[t + 2];
                float e1[3] = { a1[0]-a0[0], a1[1]-a0[1], a1[2]-a0[2] }, e2[3] = { a2[0]-a0[0], a2[1]-a0[1], a2[2]-a0[2] };
                float cr[3] = { e1[1]*e2[2]-e1[2]*e2[1], e1[2]*e2[0]-e1[0]*e2[2], e1[0]*e2[1]-e1[1]*e2[0] };
                if (cr[0]*cr[0] + cr[1]*cr[1] + cr[2]*cr[2] <= 4.0f) continue;
                torn++;
                if (env_on("TORN") && shownt++ < 12) {
                    printf("torn t%d %.1f -> %.1f cm:", t / 3, l0, l1);
                    for (int e = 0; e < 3; e++) {
                        u32 v = idx[t + e];
                        skin_info vo; orig_info(v, &vo);
                        printf(" | v%u", v);
                        for (int i = 0; i < 8; i++) if (vo.weights[i]) printf(" %s=%d", bname[vo.bones[i]], vo.weights[i]);
                        printf(" ->");
                        for (int i = 0; i < MAX_INF; i++) if (ov_a[v].weights[i]) printf(" %s=%d", bname[ov_a[v].bones[i]], ov_a[v].weights[i]);
                    }
                    printf("\n");
                }
            }
            free(xfl); free(ufl);
        }
        free(xstill); free(ustill); free(wrefinv0);
        printf("waist: %d triangles torn between the halves\n", torn);
        if (torn) printf("FAIL: the upper body fallen off tears %d triangles that keep their area\n", torn);
        int legmoved = 0;
        for (int v = 0; v < NV; v++) {
            if (!onlegs[v]) continue;
            float x[3]; skin_v(&ov_a[v], v, x);
            float *y = legx + 3 * (size_t)v, d0 = x[0] - y[0], d1 = x[1] - y[1], d2 = x[2] - y[2];
            if (d0 * d0 + d1 * d1 + d2 * d2 > 4) legmoved++;
        }
        free(legx); free(onlegs);
        if (legmoved) printf("FAIL: %d vertices of the legs' skin moved with the upper body flung off\n", legmoved);
        memcpy(space, saved, 48 * NB); free(saved);
        int shown = (flung - hf) - (still - hs);
        if (shown > 0) printf("FAIL: the upper body fallen off stretches %d more triangles that stay visible\n", shown);
        int bad = left > arms / 200 || horns > 0 || gaps > 0 || shown > 0 || legmoved > 0 || armmoved > 0 || torn > 0;
        printf("%s\n", bad ? "FAIL" : "PASS");
        return bad;
    }

    // the split as gore.lua makes it: through Spine1, square to the spine, her left/right
    float *at = space + spine1 * 12 + 4, *pp = space + pelvis * 12 + 4, *hp = space + head * 12 + 4;
    float axis[3] = { hp[0] - pp[0], hp[1] - pp[1], hp[2] - pp[2] };
    float la = __builtin_sqrtf(axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]);
    for (int k = 0; k < 3; k++) axis[k] /= la;
    int lu = bone("Bip001-L-UpperArm"), ru = bone("Bip001-R-UpperArm");
    float *lp = space + lu * 12 + 4, *rp = space + ru * 12 + 4;
    float n[3] = { rp[0] - lp[0], rp[1] - lp[1], rp[2] - lp[2] }, d = n[0] * axis[0] + n[1] * axis[1] + n[2] * axis[2];
    for (int k = 0; k < 3; k++) n[k] -= axis[k] * d;
    float ln = __builtin_sqrtf(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
    for (int k = 0; k < 3; k++) n[k] /= ln;
    // ACROSS=1: the blade level through Spine1 (a cut across the waist; the half with the head keeps the front)
    if (env_on("ACROSS")) for (int k = 0; k < 3; k++) n[k] = axis[k];
    // LOW=<cm>: that far up the spine from the pelvis instead (with ACROSS: a waist split low enough to break her spine
    // at Bip001-Spine, her half letting the pelvis go, playtest 40)
    float atl[3];
    if (getenv("LOW")) {
        float lo = (float)atof(getenv("LOW"));
        for (int k = 0; k < 3; k++) atl[k] = pp[k] + axis[k] * lo;
        at = atl;
    }
    // BESIDE=<cm>: as gore.lua's splitBeside, leaned about her front-to-back axis from the pelvis to that far beside
    // her neck, the head on A's side
    float atb[3];
    if (getenv("BESIDE") && atof(getenv("BESIDE")) > 0) {
        float side = (float)atof(getenv("BESIDE")), *nk0 = space + bone("Bip001-Neck") * 12 + 4, t[3], dd[3], m[3];
        t[0] = axis[1] * n[2] - axis[2] * n[1]; t[1] = axis[2] * n[0] - axis[0] * n[2]; t[2] = axis[0] * n[1] - axis[1] * n[0];
        for (int k = 0; k < 3; k++) dd[k] = nk0[k] - n[k] * side - pp[k];
        m[0] = t[1] * dd[2] - t[2] * dd[1]; m[1] = t[2] * dd[0] - t[0] * dd[2]; m[2] = t[0] * dd[1] - t[1] * dd[0];
        float lm = __builtin_sqrtf(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]), sg = 0, hs = 0;
        for (int k = 0; k < 3; k++) { m[k] /= lm; sg += m[k] * n[k]; }
        for (int k = 0; k < 3; k++) { if (sg < 0) m[k] = -m[k]; hs += (hp[k] - pp[k]) * m[k]; }
        for (int k = 0; k < 3; k++) { n[k] = hs < 0 ? -m[k] : m[k]; atb[k] = pp[k]; }
        at = atb;
    }
    float neg[3] = { -n[0], -n[1], -n[2] };
    const char *roots[4] = { "Bip001-L-UpperArm", "Bip001-R-UpperArm", "Bip001-L-Thigh", "Bip001-R-Thigh" };
    int gone1[4], ng1 = 0, gone2[4], ng2 = 0;
    for (int r = 0; r < 4; r++) {
        // by the joint the limb hangs from, as gore.lua's limb_sides
        float *a = space + bone(roots[r]) * 12 + 4;
        float mid[3] = { a[0] - at[0], a[1] - at[1], a[2] - at[2] };
        if (mid[0] * n[0] + mid[1] * n[1] + mid[2] * n[2] < 0) gone1[ng1++] = bone(roots[r]); else gone2[ng2++] = bone(roots[r]);
    }
    printf("plane at %.1f %.1f %.1f normal %.2f %.2f %.2f, %d limbs each side\n", at[0], at[1], at[2], n[0], n[1], n[2], ng1);
    // where the spine breaks, as gore.lua's spine_break (SPINE_TOL 4 cm): the first bone up the chain past which every
    // bone is on A's side. Each half's ragdoll lets go of the other side of it (settle_half)
    int brk = -1;
    {
        static const char *chain[] = { "Bip001-Pelvis", "Bip001-Spine", "Bip001-Spine1", "Bip001-Spine2", "Bip001-Neck", "Bip001-Head" };
        float hs[6];
        int okc = 1;
        for (int i = 0; i < 6; i++) {
            int bi = bone(chain[i]);
            if (bi < 0) { okc = 0; break; }
            float *t = space + bi * 12 + 4;
            hs[i] = (t[0] - at[0]) * n[0] + (t[1] - at[1]) * n[1] + (t[2] - at[2]) * n[2];
        }
        if (okc && hs[0] < -4)
            for (int i = 1; i < 6 && brk < 0; i++) {
                int above = 1;
                for (int j = i; j < 6; j++) if (hs[j] < -4) above = 0;
                if (above) brk = bone(chain[i]);
            }
    }
    // the copy's break, as gore.lua's copy_break: one bone up when its own legs hang off it (Biped thighs: off Spine)
    int brk2 = brk;
    if (brk >= 0) {
        static const char *chain[] = { "Bip001-Pelvis", "Bip001-Spine", "Bip001-Spine1", "Bip001-Spine2", "Bip001-Neck", "Bip001-Head" };
        for (int r = 0; r < ng1 && brk2 == brk; r++)
            for (int j = gone1[r]; j >= 0; j = bparent[j])
                if (j == brk && j != gone1[r]) {
                    for (int i = 0; i < 5; i++) if (bone(chain[i]) == brk) brk2 = bone(chain[i + 1]);
                    break;
                }
    }
    printf("spine breaks at %s, the copy's at %s\n", brk >= 0 ? bname[brk] : "none", brk2 >= 0 ? bname[brk2] : "none");

    // the neck plane, as gore.lua sends it: at the neck's base, square to the neck. A keeps the head, B lets it go
    int neckb = bone("Bip001-Neck");
    float *nk = space + neckb * 12 + 4, p2[3], n2[3], l2 = 0;
    for (int k = 0; k < 3; k++) { p2[k] = nk[k]; n2[k] = hp[k] - nk[k]; l2 += n2[k] * n2[k]; }
    for (int k = 0; k < 3; k++) n2[k] /= __builtin_sqrtf(l2);
    hmid = __builtin_sqrtf(l2) * 0.5f;
    int heads = !env_on("NOHEAD");
    // accessory chains as gore.lua's split_chains (by name here: Ab_ tops off the torso or neck, 2+ bones): A keeps
    // those in front of the plane and drops the rest, B the other way round
    int chf[32], nchf = 0, chb[32], nchb = 0;
    unsigned char *chain = calloc(NB, 1);
    for (int i = 0; i < NB; i++) {
        if (strncmp(bname[i], "Ab_", 3) || (bparent[i] >= 0 && !strncmp(bname[bparent[i]], "Ab_", 3))) continue;
        int q = bparent[i];
        while (q >= 0 && strncmp(bname[q], "Bip001", 6)) q = bparent[q];
        int ok = q >= 0 && q != head;
        for (int r = 0; r < 4 && ok; r++) for (int j = q; j >= 0; j = bparent[j]) if (j == bone(roots[r])) ok = 0;
        if (!ok) continue;
        float sum = 0; int k = 0;
        for (int j = 0; j < NB; j++) {
            int in = 0;
            for (int t = j; t >= 0 && !in; t = bparent[t]) in = t == i;
            if (!in) continue;
            float *b3 = space + j * 12 + 4;
            sum += (b3[0] - at[0]) * n[0] + (b3[1] - at[1]) * n[1] + (b3[2] - at[2]) * n[2]; k++;
            chain[j] = sum >= 0 ? 1 : 2; // fixed below
        }
        if (k < 2) { for (int j = 0; j < NB; j++) { int in = 0; for (int t = j; t >= 0 && !in; t = bparent[t]) in = t == i; if (in) chain[j] = 0; } continue; }
        for (int j = 0; j < NB; j++) { int in = 0; for (int t = j; t >= 0 && !in; t = bparent[t]) in = t == i; if (in) chain[j] = sum >= 0 ? 1 : 2; }
        if (sum >= 0 && nchf < 32) chf[nchf++] = i; else if (sum < 0 && nchb < 32) chb[nchb++] = i;
    }
    printf("chains: %d in front, %d behind:", nchf, nchb);
    for (int i = 0; i < nchf; i++) printf(" +%s", bname[chf[i]]);
    for (int i = 0; i < nchb; i++) printf(" -%s", bname[chb[i]]);
    printf("\n");
    static char res_a[65536], res_b[65536];
    // DRIVEN=1: the spine's AX correctives (Ab-AX3 and its family, which the animation drives) turned 20 degrees once
    // while she played: none may be a sink (CH_P_EVE_10's split seam collapsed onto them and stood up in sheets in a
    // ragdoll death, twenty-sixth playtest)
    unsigned char *drv = calloc(NB, 1);
    if (env_on("DRIVEN")) {
        float q[4] = { 0, __builtin_sinf(0.1745f), 0, __builtin_cosf(0.1745f) }, *keep = malloc(48 * NB);
        memcpy(keep, space, 48 * NB);
        for (int i = 0; i < NB; i++) if (strstr(bname[i], "AX")) {
            float *t = space + i * 12, o[4];
            qmul(t, q, o); memcpy(t, o, 16);
            drv[i] = 1;
        }
        for (int i = 0; i < NB; i++) if (bparent[i] >= 0 && drv[bparent[i]]) drv[i] = 1; // their children turn against them too
        skin_watch((u64)comp_a);
        memcpy(space, keep, 48 * NB);
        free(keep);
    }
    // half A (her own mesh) keeps the front of the plane, B (the copy) the back
    set_nosink();
    limbs_comp = (u64)comp_a; ngone = ng1; nkeep = ng2; memcpy(gone_roots, gone1, 4 * ng1); memcpy(keep_roots, gone2, 4 * ng2); set_ride(0, brk);
    free_spine = env_on("NOFREE") ? -1 : brk; free_upper = 1; // NOFREE=1: the DLL not told (the bug, for a check)
    if (!env_on("NOCHAINS")) { memcpy(keep_roots + nkeep, chf, 4 * nchf); nkeep += nchf; memcpy(drop_roots, chb, 4 * nchb); ndrop = nchb; }
    // gore.lua's side_cut sends the bones a Dm- driver moves (OLDDM=1: it didn't): a point sink on them followed the
    // limbs the half lets go, cones out of both halves (playtest, CH_P_EVE_30)
    // and the drivers of a side whose limbs the half lets go, which its kept skin lets go of too (fffc; OLDDRV=1: not)
    if (!env_on("OLDDM") && !env_on("ENEMY")) for (int i = 0; i < NB; i++) drivenb[i] = (unsigned char)(!env_on("OLDDRV") && side_driver(i, gone_sides(gone1, ng1)) ? 2 : under_driver(i));
    if (heads) { head_comp = (u64)comp_a; head_mode = HEAD_KEEP; head_bone = head; memcpy(head_pw, p2, 12); memcpy(head_nw, n2, 12); }
    skin_cut((u64)comp_a, 0, spine1, at, n, MODE_SIDE, 0, 0, -1);
    strcpy(res_a, lastres);
    printf("A: %.300s\n", lastres);
    set_nosink();
    limbs_comp = (u64)comp_b; ngone = ng2; nkeep = ng1; memcpy(gone_roots, gone2, 4 * ng2); memcpy(keep_roots, gone1, 4 * ng1); set_ride(1, brk2);
    free_spine = env_on("NOFREE") ? -1 : brk2; free_upper = 0;
    ndrop = 0;
    if (!env_on("NOCHAINS")) { memcpy(keep_roots + nkeep, chb, 4 * nchb); nkeep += nchb; memcpy(drop_roots, chf, 4 * nchf); ndrop = nchf; }
    if (!env_on("OLDDM") && !env_on("ENEMY")) for (int i = 0; i < NB; i++) drivenb[i] = (unsigned char)(!env_on("OLDDRV") && side_driver(i, gone_sides(gone2, ng2)) ? 2 : under_driver(i));
    if (heads) { head_comp = (u64)comp_b; head_mode = HEAD_DROP; head_bone = head; memcpy(head_pw, p2, 12); memcpy(head_nw, n2, 12); }
    skin_cut((u64)comp_b, 0, spine1, at, neg, MODE_SIDE, 0, 0, -1);
    strcpy(res_b, lastres);
    printf("B: %.300s\n", lastres);
    for (int r = 0; r < ng1; r++) printf("half A lets go of %s\n", bname[gone1[r]]);
    for (int r = 0; r < ng2; r++) printf("half B lets go of %s\n", bname[gone2[r]]);
    if (!ov_a || !ov_b) { printf("FAIL: no override\n"); return 1; }
    int fail = 0;
    // the sinks a driver moves (a last resort: a split half keeps too few other helpers, each one point; OLDDM=1 for
    // as many as before, 11 to 15 a split here, against 7 to 9), never one of a side whose limbs the half lets go: the
    // animation moves it after them, as they fall free (cones, playtest)
    {
        int nd = 0, ns = 0;
        for (int h = 0; h < 2; h++) {
            // (the list holds A's sinks too on B's, this cut's "new=" last)
            const char *res = h ? res_b : res_a, *sk = strstr(res, " sinks="), *nw = strstr(res, " new=");
            int all = sk != 0, fresh = nw ? atoi(nw + 5) : 0, k = 0;
            for (const char *r = sk ? sk + 7 : 0; r && *r && *r != ' '; r++) if (*r == ',') all++;
            for (const char *q = sk ? sk + 7 : 0; q && *q && *q != ' '; k++) {
                int b = (int)strtol(q, (char **)&q, 10);
                if (k >= all - fresh && b >= 0 && b < NB && under_driver(b)) { printf("half %c: sink %s, which a Dm- driver moves (", h ? 'B' : 'A', bname[b]);
                    for (int j = bparent[b]; j >= 0; j = bparent[j]) { printf(" < %s", bname[j]); if (!strncmp(bname[j], "Bip001", 6)) break; }
                    printf(")%s\n", side_driver(b, h ? gone_sides(gone2, ng2) : gone_sides(gone1, ng1)) ? ", on the side it lets go" : "");
                    nd++; ns += side_driver(b, h ? gone_sides(gone2, ng2) : gone_sides(gone1, ng1)); }
                if (*q == ',') q++;
            }
        }
        printf("split: %d sinks a driver moves, %d of a side let go\n", nd, ns);
        if (ns && !env_on("OLDDM")) { printf("FAIL: a sink a let-go limb's driver moves\n"); fail = 1; }
    }
    if (env_on("DRIVEN")) {
        int bad = 0, any = 0;
        for (int h = 0; h < 2; h++) {
            const char *sk = strstr(h ? res_b : res_a, " sinks=");
            if (!sk) continue;
            for (const char *p = sk + 7; *p && *p != ' ';) {
                int b = (int)strtol(p, (char **)&p, 10);
                any |= drv[b] || 1;
                if (b >= 0 && b < NB && drv[b]) { printf("FAIL: a driven corrective is a sink: %s\n", bname[b]); bad = 1; }
                if (*p == ',') p++;
            }
        }
        int n = 0;
        for (int i = 0; i < NB; i++) n += drv[i];
        printf("driven: %d correctives watched turning, none a sink: %s\n", n, bad ? "no" : "yes");
        fail |= bad || !n || !any;
    }
    // every vertex mostly on a chain: whole on the half that keeps it (none of it on a sink), all on sinks on the other
    {
        cut_ctx cc = { .sm = (u64)sm_buf };
        int nch = 0, kept_bad = 0, drop_bad = 0;
        for (int v = 0; v < NV; v++) {
            skin_info vo; orig_info(v, &vo);
            int wf = 0, wb = 0;
            for (int i = 0; i < 8; i++) if (vo.weights[i]) { if (chain[vo.bones[i]] == 1) wf += vo.weights[i]; if (chain[vo.bones[i]] == 2) wb += vo.weights[i]; }
            if (wf <= 127 && wb <= 127) continue;
            nch++;
            skin_info *keep = wf > 127 ? &ov_a[v] : &ov_b[v], *drop = wf > 127 ? &ov_b[v] : &ov_a[v];
            int ks = 0, ds = 1, any = 0;
            for (int i = 0; i < MAX_INF; i++) {
                if (keep->weights[i] && is_sink(&cc, keep->bones[i])) ks = 1;
                if (drop->weights[i]) { any = 1; if (!is_sink(&cc, drop->bones[i])) ds = 0; }
            }
            kept_bad += ks; drop_bad += !(any && ds);
        }
        printf("chains: %d vertices, %d on a sink on the half that keeps them, %d not all sunk on the other\n", nch, kept_bad, drop_bad);
        if (!env_on("NOCHAINS")) fail |= kept_bad > nch / 100 || drop_bad > nch / 100;
    }
    // every vertex mostly on a limb a half drops collapses onto a point there, never flattened onto the plane: the
    // arm's sections had no point riding the neck (the arms' nearest spine bone) and the dropped arm lay pressed on
    // the plane, a flat hand (twenty-eighth playtest)
    for (int h = 0; h < 2; h++) {
        cut_ctx cc = { .sm = (u64)sm_buf };
        unsigned char *sub = calloc(NB, 1);
        const int *g = h ? gone2 : gone1;
        for (int i = 0; i < NB; i++) {
            for (int r = 0; r < (h ? ng2 : ng1); r++) if (g[r] == i) sub[i] = 1;
            if (!sub[i] && bparent[i] >= 0 && bparent[i] < i) sub[i] = sub[bparent[i]];
        }
        int nl = 0, flat = 0;
        for (int v = 0; v < NV; v++) {
            skin_info vo; orig_info(v, &vo);
            int w = 0;
            for (int i = 0; i < 8; i++) if (vo.weights[i] && sub[vo.bones[i]]) w += vo.weights[i];
            if (w <= 127) continue;
            nl++;
            const skin_info *o = h ? &ov_b[v] : &ov_a[v];
            for (int i = 0; i < MAX_INF; i++) if (o->weights[i] && is_proj_sink(&cc, o->bones[i])) { flat++; break; }
        }
        printf("half %c: %d vertices on the limbs it drops, %d flattened onto the plane\n", h ? 'B' : 'A', nl, flat);
        fail |= flat > 0;
        free(sub);
    }
    memcpy(hp2, p2, 12); memcpy(hn2, n2, 12);
    headbones = calloc(NB, 1);
    for (int i = 0; i < NB; i++) headbones[i] = i == head || (bparent[i] >= 0 && headbones[bparent[i]]);
    // each half's opening on the plane: one outline, not crossing itself, facing the side that went (counter-clockwise
    // seen from there: negative area seen along the kept side's normal)
    for (int h = 0; h < 2; h++) {
        static float uv[512][2];
        float area = 0, *nn = h ? neg : n;
        int m = outline_of(h ? res_b : res_a, "s0", uv, 512, nn, &area), cross = 0;
        for (int i = 0; i < m; i++)
            for (int j = i + 2; j < m; j++) {
                if (i == 0 && j == m - 1) continue;
                if (seg_cross(uv[i], uv[(i + 1) % m], uv[j], uv[(j + 1) % m])) cross++;
            }
        int lids = 0;
        for (const char *q = h ? res_b : res_a; (q = strstr(q, "p=")); q++) lids++;
        printf("half %c: outline %d points, %.0f cm2, %d crossings, %d lids%s\n", h ? 'B' : 'A', m, -area, cross, lids,
               heads && strstr(h ? res_b : res_a, " np=") ? " (neck lid)" : "");
        // her waist is about 270 cm2 across, the torso 1100 lengthwise; leaned past the neck, it leaves through a
        // shoulder (bent, CH_P_EVE_09's measured 487 and 557)
        fail |= m < 12 || cross > 0 || -area < (env_on("ACROSS") ? 200 : getenv("BESIDE") ? 400 : 800);
        // a plane up the spine reaches the neck: both halves get its lid (one leaned past the neck reaches none)
        if (heads && !env_on("ACROSS") && !getenv("BESIDE")) fail |= !strstr(h ? res_b : res_a, " np=");
        if (getenv("OUTLINE_OBJ")) {
            char fn[512]; snprintf(fn, sizeof fn, "%s_%c.txt", getenv("OUTLINE_OBJ"), h ? 'b' : 'a');
            FILE *f = fopen(fn, "w"); fprintf(f, "%s\n", h ? res_b : res_a); fclose(f);
        }
    }
    for (int h = 0; h < 2; h++) {
        int *gr = h ? gone2 : gone1, ng = h ? ng2 : ng1, *kr = h ? gone1 : gone2, nk = h ? ng1 : ng2;
        gone_sub[h] = calloc(NB, 1); keep_sub[h] = calloc(NB, 1);
        for (int i = 0; i < NB; i++) {
            for (int r = 0; r < ng; r++) if (gr[r] == i) gone_sub[h][i] = 1;
            if (!gone_sub[h][i] && bparent[i] >= 0 && gone_sub[h][bparent[i]]) gone_sub[h][i] = 1;
            for (int r = 0; r < nk; r++) if (kr[r] == i) keep_sub[h][i] = 1;
            if (!env_on("NOCHAINS") && chain[i] == (h ? 2 : 1)) keep_sub[h][i] = 1;
            if (!keep_sub[h][i] && bparent[i] >= 0 && keep_sub[h][bparent[i]]) keep_sub[h][i] = 1;
        }
    }

    // before the collapse: every vertex where it was (the new weights alone must not move anything kept)
    float *orig = malloc(12 * NV);
    for (int v = 0; v < NV; v++) { skin_info o; orig_info(v, &o); skin_v(&o, v, orig + v * 3); }
    float *refinv0 = malloc(64 * NB); memcpy(refinv0, refinv, 64 * NB); // the vanilla skin, for reference
    if (getenv("OUTLINE_OBJ")) {
        // each half's rim (kept vertices in a triangle with a vanished one), posed, for a look at the outlines
        for (int h = 0; h < 2; h++) {
            skin_info *o = h ? ov_b : ov_a;
            char fn[512]; snprintf(fn, sizeof fn, "%s_rim_%c.txt", getenv("OUTLINE_OBJ"), h ? 'b' : 'a');
            FILE *f = fopen(fn, "w");
            unsigned char *gone = calloc(NV, 1), *rimv = calloc(NV, 1);
            for (int v = 0; v < NV; v++) gone[v] = vanished_in(&o[v], h ? (u64)comp_b : (u64)comp_a);
            for (int t = 0; t < NIDX; t += 3) {
                int g = gone[idx[t]] + gone[idx[t + 1]] + gone[idx[t + 2]];
                if (g && g < 3) for (int k = 0; k < 3; k++) if (!gone[idx[t + k]]) rimv[idx[t + k]] = 1;
            }
            for (int v = 0; v < NV; v++) if (rimv[v]) { float x[3]; skin_v(&o[v], v, x); fprintf(f, "%f %f %f\n", x[0], x[1], x[2]); }
            fclose(f); free(gone); free(rimv);
        }
    }
    printf("collapsed %d sinks\n", skin_collapse());
    // each half: kept vertices (in front of its plane by more than 1 cm, not on a limb it lets go) must not move; the
    // rest must end on the plane or at a limb point, never off in space. With the neck plane, A keeps the head whole
    // (its other half may lie behind the plane) and B keeps none of it
    for (int h = 0; h < 2; h++) {
        skin_info *o = h ? ov_b : ov_a;
        float *nn = h ? neg : n;
        int kept = 0, kept_moved = 0, gone = 0, gone_off = 0, worst_v = -1, behind_kept = 0, head_kept = 0, head_all = 0;
        float worst = 0;
        // the other side of a broken spine (free in game): kept skin on it moves to a kept bone, which isn't posed as
        // it was, so that skin may shift a little at the cut (POP_CM), never stretch after the free bones
        unsigned char *fr = calloc(NB, 1);
        int fb = h ? brk2 : brk, popped = 0;
        float pop = 0;
        if (fb >= 0) {
            unsigned char *sp = calloc(NB, 1);
            for (int i = 0; i < NB; i++) sp[i] = i == fb || (bparent[i] >= 0 && sp[bparent[i]]);
            for (int i = 1; i < NB; i++) fr[i] = h ? sp[i] : !sp[i];
            free(sp);
        }
        for (int v = 0; v < NV; v++) {
            float x[3]; skin_v(&o[v], v, x);
            float *p0 = orig + v * 3;
            float hgt = (p0[0] - at[0]) * nn[0] + (p0[1] - at[1]) * nn[1] + (p0[2] - at[2]) * nn[2];
            float mv = dist3(x, p0);
            {   // the copy's neck skin as the vanilla skin with the head's weight on the neck (see fold_head)
                skin_info vo; orig_info(v, &vo);
                if (h && heads && fold_head(&vo, head)) { float y[3], *cur = refinv; refinv = refinv0; skin_v(&vo, v, y); refinv = cur; mv = dist3(x, y); }
            }
            // (not an accessory chain's: it goes whole with its side, a shoulder's gear reaching the neck too)
            int hd = heads && !tied_to_kept(h, v) && !tied_to_gone(h, v) && in_head(v, p0);
            if (hd) { skin_info vo; orig_info(v, &vo); int wc = 0; for (int i = 0; i < 8; i++) if (vo.weights[i] && chain[vo.bones[i]]) wc += vo.weights[i]; if (wc > 127) hd = 0; }
            head_all += hd;
            if (!vanished_in(&o[v], h ? (u64)comp_b : (u64)comp_a)) {
                if (tied_to_gone(h, v)) continue;
                head_kept += hd;
                if (hgt < -1.0f && !tied_to_kept(h, v) && !(hd && h == 0)) {
                    behind_kept++;
                    if (env_on("SPLIT_DEBUG")) {
                        static int hist[2][16][256];
                        int sc = 0; for (int k = 0; k < NSEC; k++) { unsigned char *sec = (unsigned char *)secbuf + k * 0xe8; if (v >= *(int *)(sec + SEC_BASE_VERTEX)) sc = k; }
                        int tb = 0, tw = 0; skin_info vo; orig_info(v, &vo);
                        for (int i = 0; i < 8; i++) if (vo.weights[i] > tw) { tw = vo.weights[i]; tb = vo.bones[i]; }
                        if (hist[h][sc][tb & 255]++ == 200) printf("  behind kept: half %c sec %d top %s\n", h ? 'B' : 'A', sc, bname[tb]);
                    }
                }
                kept++;
                int onfree = 0;
                { skin_info vo; orig_info(v, &vo); for (int i = 0; i < 8; i++) if (vo.weights[i] && fr[vo.bones[i]]) onfree = 1; }
                if (onfree && mv > 0.5f) { popped++; if (mv > pop) pop = mv; }
                else if (mv > 0.5f) { kept_moved++; if (mv > worst) { worst = mv; worst_v = v; } }
            } else {
                gone++;
                float hx = (x[0] - at[0]) * nn[0] + (x[1] - at[1]) * nn[1] + (x[2] - at[2]) * nn[2];
                // into the neck: within NECK_R of its axis, at most NECK_BAND + 1 cm under the neck plane
                float e[3] = { x[0] - p2[0], x[1] - p2[1], x[2] - p2[2] }, h2 = e[0] * n2[0] + e[1] * n2[1] + e[2] * n2[2];
                int necked = heads && h2 < 0.5f && h2 > -NECK_BAND - 1.0f && e[0] * e[0] + e[1] * e[1] + e[2] * e[2] - h2 * h2 < NECK_BASE_R * NECK_BASE_R;
                if (!necked && (hx < -0.5f || hx > 3.0f)) {
                    gone_off++;
                    if (env_on("SPLIT_DEBUG") && gone_off <= 4) {
                        int sc = 0; for (int k = 0; k < NSEC; k++) { unsigned char *sec = (unsigned char *)secbuf + k * 0xe8; if (v >= *(int *)(sec + SEC_BASE_VERTEX)) sc = k; }
                        printf("  off: v%d sec %d at %.1f:", v, sc, hx);
                        for (int i = 0; i < MAX_INF; i++) if (o[v].weights[i]) printf(" %s=%d", bname[o[v].bones[i]], o[v].weights[i]);
                        printf("\n");
                    }
                }
            }
        }
        printf("half %c: kept %d, moved %d (worst %.1f cm at v%d", h ? 'B' : 'A', kept, kept_moved, worst, worst_v);
        if (worst_v >= 0) {
            printf(":");
            for (int i = 0; i < MAX_INF; i++) if (o[worst_v].weights[i]) printf(" %s=%d", bname[o[worst_v].bones[i]], o[worst_v].weights[i]);
        }
        if (worst_v >= 0) { skin_info vo; orig_info(worst_v, &vo); printf(" was"); for (int i = 0; i < 8; i++) if (vo.weights[i]) printf(" %s=%d", bname[vo.bones[i]], vo.weights[i]); }
        printf("), let go %d, off the plane %d, of the other half left on it %d", gone, gone_off, behind_kept);
        if (heads) printf(", head kept %d of %d", head_kept, head_all);
        printf("\n");
        // the other half's skin left standing on this one (no sink found for it); A keeps all of the head, B none
        if (fb >= 0) printf("half %c: %d kept vertices on the free side of the spine shifted at the cut, %.1f cm at most\n", h ? 'B' : 'A', popped, pop);
        free(fr);
        fail |= kept_moved > kept / 200 || behind_kept > kept / 200 || pop > POP_CM;
        if (heads) fail |= h == 0 ? head_kept < head_all : head_kept > head_all / 200;
    }
    // posed: she keeps falling after the cut (the spine and head turn further): kept skin must still match the
    // vanilla skin in the new pose
    // the lid pieces ride the spine bone nearest to them (gore.lua's SPLIT_RIDE), rigidly: the flattened skin behind a
    // piece must stay behind it, not come out in front through it once she bends (SHEET_IN behind the plane, the lid
    // splitLidPush in front of it)
    static const char *ride[] = { "Bip001-Head", "Bip001-Neck", "Bip001-Spine2", "Bip001-Spine1", "Bip001-Spine", "Bip001-Pelvis" };
    float *xcut[2] = { 0, 0 }, *scut = 0;
    if (posed) {
        scut = malloc(48 * NB); memcpy(scut, space, 48 * NB);
        for (int h = 0; h < 2; h++) {
            skin_info *o = h ? ov_b : ov_a;
            xcut[h] = malloc(12 * NV);
            for (int v = 0; v < NV; v++) skin_v(&o[v], v, xcut[h] + v * 3);
        }
    }
    if (posed) {
        bend(local, "Bip001-Spine", 0, 1, 0, 30); bend(local, "Bip001-Spine2", 1, 0, 0, -20); bend(local, "Bip001-Head", 0, 0, 1, 40);
        bend(local, "Bip001-L-Clavicle", 1, 0, 0, 15);
        pose_from_local(space);
        for (int h = 0; h < 2; h++) {
            skin_info *o = h ? ov_b : ov_a;
            float *nn = h ? neg : n;
            int kept = 0, moved = 0, wv = -1; float worst = 0;
            for (int v = 0; v < NV; v++) {
                float *p0 = orig + v * 3;
                (void)p0; (void)nn;
                if (vanished_in(&o[v], h ? (u64)comp_b : (u64)comp_a) || tied_to_gone(h, v)) continue;
                skin_info vo; orig_info(v, &vo);
                // the copy's neck skin rides the neck alone: it must not follow the head's bend
                if (h && heads) fold_head(&vo, head);
                // nor the other side of a broken spine, free in game: A's pelvis weight rides the break bone, B's
                // weight above its break the bone under it
                int fb = h ? brk2 : brk;
                if (fb >= 0) for (int i = 0; i < 8; i++) if (vo.weights[i] && vo.bones[i] > 0) {
                    int in = 0;
                    for (int j = vo.bones[i]; j >= 0 && !in; j = bparent[j]) in = j == fb;
                    if (h ? in : !in) vo.bones[i] = h ? bparent[fb] : fb;
                }
                float a[3], b[3];
                float *cur = refinv; refinv = refinv0; skin_v(&vo, v, a); refinv = cur;
                skin_v(&o[v], v, b);
                kept++;
                float d = dist3(a, b);
                if (d > 0.5f) { moved++; if (d > worst) { worst = d; wv = v; } }
            }
            printf("half %c bent further: kept %d off the vanilla skin %d (worst %.1f cm", h ? 'B' : 'A', kept, moved, worst);
            if (wv >= 0) for (int i = 0; i < MAX_INF; i++) if (o[wv].weights[i]) printf(" %s=%d", bname[o[wv].bones[i]], o[wv].weights[i]);
            printf(")\n");
            fail |= moved > kept / 200;
            skin_probe(h ? (u64)comp_b : (u64)comp_a, 0);
            printf("half %c bent probe: %.300s\n", h ? 'B' : 'A', lastres);
            // out through the lid: a vanished vertex ahead of where the lid over it went. The lid as gore.lua's
            // skin_lid bends it (splitLidSkin, the default): each point between the two ride bones of the spine
            // segment nearest to it, blended along that segment; LIDRIGID=1 the rigid pieces (each on the nearest bone)
            int chain[6], nch = 0, rigid = env_on("LIDRIGID");
            for (int r = h ? 1 : 0; r < 6; r++) if (bone(ride[r]) >= 0) chain[nch++] = bone(ride[r]);
            int poke = 0, sheet = 0, pv = -1, p1 = 0, p2 = 0, p3 = 0; float pworst = 0;
            for (int v = 0; v < NV && nch; v++) {
                if (!vanished_in(&o[v], h ? (u64)comp_b : (u64)comp_a) || tied_to_gone(h, v)) continue;
                const float *x0 = xcut[h] + v * 3;
                // only the sheet on the opening: points deep in the half collapse far behind it
                float hh = (x0[0] - at[0]) * nn[0] + (x0[1] - at[1]) * nn[1] + (x0[2] - at[2]) * nn[2];
                if (hh < -1.0f || hh > SHEET_IN + 1.0f) continue;
                sheet++;
                int ja = 0, jb = 0; float bt = 0, bd = 1e30f;
                if (rigid) {
                    for (int j = 0; j < nch; j++) {
                        const float *t = scut + chain[j] * 12;
                        float d = (x0[0] - t[4]) * (x0[0] - t[4]) + (x0[1] - t[5]) * (x0[1] - t[5]) + (x0[2] - t[6]) * (x0[2] - t[6]);
                        if (d < bd) { bd = d; ja = jb = j; }
                    }
                } else for (int j = 0; j < (nch > 1 ? nch - 1 : 1); j++) {
                    int k = j + 1 < nch ? j + 1 : j;
                    const float *a0 = scut + chain[j] * 12 + 4, *b0 = scut + chain[k] * 12 + 4;
                    float ab[3] = { b0[0] - a0[0], b0[1] - a0[1], b0[2] - a0[2] }, ax[3] = { x0[0] - a0[0], x0[1] - a0[1], x0[2] - a0[2] };
                    float l2 = ab[0] * ab[0] + ab[1] * ab[1] + ab[2] * ab[2];
                    float t = l2 > 1e-6f ? (ax[0] * ab[0] + ax[1] * ab[1] + ax[2] * ab[2]) / l2 : 0;
                    t = t < 0 ? 0 : t > 1 ? 1 : t;
                    float d[3] = { ax[0] - ab[0] * t, ax[1] - ab[1] * t, ax[2] - ab[2] * t }, dd = d[0] * d[0] + d[1] * d[1] + d[2] * d[2];
                    if (dd < bd) { bd = dd; ja = j; jb = k; bt = t; }
                }
                // the lid point over the vertex and its normal, carried by each end of the segment, then blended
                float lp[3] = { 0, 0, 0 }, nw[3] = { 0, 0, 0 };
                for (int e2 = 0; e2 < 2; e2++) {
                    int rb = chain[e2 ? jb : ja];
                    float wgt = e2 ? bt : 1 - bt;
                    const float *t0 = scut + rb * 12, *t1 = space + rb * 12;
                    float d[3] = { x0[0] - t0[4], x0[1] - t0[5], x0[2] - t0[6] }, iq[4] = { -t0[0], -t0[1], -t0[2], t0[3] }, l[3], e[3], nl[3], ne[3];
                    quat_rot(iq, d, l); quat_rot(t1, l, e);
                    quat_rot(iq, nn, nl); quat_rot(t1, nl, ne);
                    for (int k = 0; k < 3; k++) { lp[k] += (t1[4 + k] + e[k]) * wgt; nw[k] += ne[k] * wgt; }
                }
                float nl2 = __builtin_sqrtf(nw[0] * nw[0] + nw[1] * nw[1] + nw[2] * nw[2]);
                if (nl2 > 1e-6f) for (int k = 0; k < 3; k++) nw[k] /= nl2;
                float x1[3]; skin_v(&o[v], v, x1);
                // ahead of the lid: towards the gone side (-n) past the lid's push
                float ahead = -((x1[0] - lp[0]) * nw[0] + (x1[1] - lp[1]) * nw[1] + (x1[2] - lp[2]) * nw[2]) - (SHEET_IN + 0.2f);
                if (ahead > 0.5f) { poke++; if (ahead > pworst) { pworst = ahead; pv = v; } }
                p1 += ahead > 1; p2 += ahead > 2; p3 += ahead > 3;
            }
            printf("half %c bent: %d of %d sheet verts out through the lid (%d / %d / %d over 1 / 2 / 3 cm, worst %.1f cm", h ? 'B' : 'A', poke, sheet, p1, p2, p3, pworst);
            if (pv >= 0) for (int i = 0; i < MAX_INF; i++) if (o[pv].weights[i]) printf(" %s=%d", bname[o[pv].bones[i]], o[pv].weights[i]);
            printf(")\n");
            fail |= p3 > sheet / 200;
        }
    }
    free(xcut[0]); free(xcut[1]); free(scut);
    // in game each half's dropped limbs fall free (constraint broken, at their own mass): they end anywhere. Move them
    // 40 cm away and turn them; nothing the half shows may follow
    for (int h = 0; h < 2; h++) {
        skin_info *o = h ? ov_b : ov_a;
        int *gr = h ? gone2 : gone1, ng = h ? ng2 : ng1;
        float *saved = malloc(48 * NB); memcpy(saved, space, 48 * NB);
        unsigned char *sub = calloc(NB, 1);
        // the copy (B) lets its head go too (settle_half), free and spinning
        for (int i = 0; i < NB; i++) {
            for (int r = 0; r < ng; r++) if (gr[r] == i) sub[i] = 1;
            if (h && i == bone("Bip001-Head")) sub[i] = 1;
            // and the drivers of their side, which the animation moves after them (cones, playtest)
            if (side_driver(i, gone_sides(gr, ng))) sub[i] = 1;
            if (!sub[i] && bparent[i] >= 0 && sub[bparent[i]]) sub[i] = 1;
        }
        // and with the spine broken, the other side of the break: A lets go of all but the break bone's subtree (the
        // pelvis and its hip helpers), B of that subtree. Not a chain the half keeps (it isn't let go of)
        if ((h ? brk2 : brk) >= 0) {
            unsigned char *sp = calloc(NB, 1);
            for (int i = 0; i < NB; i++) sp[i] = i == (h ? brk2 : brk) || (bparent[i] >= 0 && sp[bparent[i]]);
            for (int i = 1; i < NB; i++) if ((h ? sp[i] : !sp[i]) && chain[i] != (h ? 2 : 1)) sub[i] = 1;
            free(sp);
        }
        float before[3], *bx = malloc(12 * NV);
        for (int v = 0; v < NV; v++) skin_v(&o[v], v, bx + v * 3);
        float q[4] = { 0.3826834f, 0, 0, 0.9238795f }; // 45 degrees about x
        for (int i = 0; i < NB; i++) if (sub[i]) {
            float *t = space + i * 12, nq[4]; qmul(q, t, nq); memcpy(t, nq, 16);
            float r[3]; quat_rot(q, t + 4, r); t[4] = r[0] + 40; t[5] = r[1]; t[6] = r[2] - 20;
        }
        int follow = 0, wv = -1; float worst = 0;
        for (int v = 0; v < NV; v++) {
            float x[3]; skin_v(&o[v], v, x);
            float mv = dist3(x, bx + v * 3);
            if (mv > 0.5f) { follow++; if (mv > worst) { worst = mv; wv = v; } }
        }
        (void)before;
        printf("half %c with its dropped limbs flung: %d verts follow them (worst %.1f cm", h ? 'B' : 'A', follow, worst);
        if (wv >= 0) for (int i = 0; i < MAX_INF; i++) if (o[wv].weights[i]) printf(" %s%s=%d", bname[o[wv].bones[i]], sub[o[wv].bones[i]] ? "*" : "", o[wv].weights[i]);
        printf(")\n");
        fail |= follow > 0;
        // the stretch probe ("s"), on the half's override as the GPU skins it: what the half shows of the flung limbs
        // is on its sinks, so flinging them must not stretch one more triangle
        skin_probe(h ? (u64)comp_b : (u64)comp_a, 0);
        int flung_bad = -1, still_bad = -1;
        sscanf(lastres, "ok stretched=%d", &flung_bad);
        printf("half %c probe flung: %.160s\n", h ? 'B' : 'A', lastres);
        memcpy(space, saved, 48 * NB);
        skin_probe(h ? (u64)comp_b : (u64)comp_a, 0);
        sscanf(lastres, "ok stretched=%d", &still_bad);
        printf("half %c probe: %.160s\n", h ? 'B' : 'A', lastres);
        fail |= flung_bad < 0 || flung_bad != still_bad;
        memcpy(space, saved, 48 * NB); free(saved); free(sub); free(bx);
    }
    for (int i = 0; i < nsinks; i++) printf("sink %s %s%s\n", bname[sinks[i].bone], sinks[i].proj ? "proj" : "point", sinks[i].down ? "" : " (open)");
    if (argc > 2) {
        char fn[512];
        snprintf(fn, sizeof fn, "%s_a.obj", argv[2]); write_obj(fn, ov_a);
        snprintf(fn, sizeof fn, "%s_b.obj", argv[2]); write_obj(fn, ov_b);
    }
    printf("%s\n", fail ? "FAIL" : "PASS");
    return fail;
}
