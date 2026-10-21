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
#define DllMain DllMain_
#define SBSLICE_HOSTED
#include "../../sbslice.c"
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

static int NB, NV, NSEC, NIDX;
static int *bparent; static char (*bname)[32];
static float *local, *space, *refinv, *refpose, *pos;
static unsigned char *wts, *binfo;
static u32 *idx;
static u64 *secbuf; static u16 **bmaps;
static u64 sw_buf[32], ld_buf[64], sm_buf[128], rd_buf[4], lodptrs[1], ib_obj[1], ib_vt[16];
static unsigned char comp_a[0x2000], comp_b[0x2000];
static skin_info *ov_a, *ov_b;
static int ib_num(u64 s) { (void)s; return NIDX; }
static u32 ib_get(u64 s, u32 i) { (void)s; return idx[i]; }
static u64 st_get_buffer(u64 c, int l) { (void)c;(void)l; return (u64)sw_buf; }
static void st_set_override(u64 c, int l, const tarray *a)
{
    (void)l;
    skin_info **o = c == (u64)comp_a ? &ov_a : &ov_b;
    free(*o); *o = malloc(sizeof(skin_info) * a->num); memcpy(*o, a->data, sizeof(skin_info) * a->num);
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

// a vertex the vanilla skin ties to a limb this half lets go (hip skin on the other half's thigh twist): it has to
// stay with the body, so it may shift; not counted
static unsigned char *gone_sub[2], *keep_sub[2];
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

// the kept head (gore.lua's neck plane): above the plane within NECK_R of the neck axis, or mostly on the head's bones
static float hp2[3], hn2[3];
static unsigned char *headbones;
static int in_head(int v, const float *x)
{
    float e[3] = { x[0] - hp2[0], x[1] - hp2[1], x[2] - hp2[2] }, h2 = e[0] * hn2[0] + e[1] * hn2[1] + e[2] * hn2[2];
    if (h2 > 0 && e[0] * e[0] + e[1] * e[1] + e[2] * e[2] - h2 * h2 < NECK_R * NECK_R) return 1;
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
    if (o->weights[0] != 255) return 0;
    for (int i = 0; i < nsinks; i++) if (sinks[i].comp == comp && sinks[i].bone == o->bones[0]) return 1;
    return 0;
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
static void set_nosink(void)
{
    nosink_mesh = (u64)sm_buf;
    for (int i = 0; i < MAX_BONES; i++) nosink[i] = 0;
    for (int i = 0; i < NB; i++) {
        int bad = !strcmp(bname[i], "Root");
        for (int k = 0; k < 3; k++) if (!strncmp(bname[i], NOSINK_PRE[k], strlen(NOSINK_PRE[k]))) bad = 1;
        for (int k = 0; k < 4; k++) if (strstr(bname[i], NOSINK_PART[k])) bad = 1;
        nosink[i] = bad;
    }
}

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "usage: real_split <mesh.bin> [obj prefix]\n"); return 2; }
    load(argv[1]);
    void *m = mmap(0, 0x4200000, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    exe = (u64)m;
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
    // WAIST=1: F9's torso cut instead (CUT at Spine1, halfway to Spine2, square to the spine). Her hands and the cape
    // hang below it (the bind pose's arms reach down to the hips): every vertex the vanilla skin puts mostly on an
    // arm (the clavicles' subtrees) must go with the upper body, not stay floating on the legs
    if (env_on("WAIST")) {
        int spine2 = bone("Bip001-Spine2");
        float *a = space + spine1 * 12 + 4, *b2 = space + spine2 * 12 + 4, at2[3], nn[3], l = 0;
        for (int k = 0; k < 3; k++) { at2[k] = (a[k] + b2[k]) * 0.5f; nn[k] = b2[k] - a[k]; l += nn[k] * nn[k]; }
        for (int k = 0; k < 3; k++) nn[k] /= __builtin_sqrtf(l);
        set_nosink();
        skin_cut((u64)comp_a, 0, spine1, at2, nn, MODE_CUT, 0, 0, -1, 0);
        printf("waist: %.300s\n", lastres);
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
        printf("\n%s\n", left > arms / 200 ? "FAIL" : "PASS");
        return left > arms / 200;
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

    // the neck plane, as gore.lua sends it: halfway up the neck, square to it. A keeps the head, B lets it go
    int neckb = bone("Bip001-Neck");
    float *nk = space + neckb * 12 + 4, p2[3], n2[3], l2 = 0;
    for (int k = 0; k < 3; k++) { p2[k] = (nk[k] + hp[k]) * 0.5f; n2[k] = hp[k] - nk[k]; l2 += n2[k] * n2[k]; }
    for (int k = 0; k < 3; k++) n2[k] /= __builtin_sqrtf(l2);
    int heads = !env_on("NOHEAD");
    static char res_a[65536], res_b[65536];
    // half A (her own mesh) keeps the front of the plane, B (the copy) the back
    set_nosink();
    limbs_comp = (u64)comp_a; ngone = ng1; nkeep = ng2; memcpy(gone_roots, gone1, 4 * ng1); memcpy(keep_roots, gone2, 4 * ng2);
    if (heads) { head_comp = (u64)comp_a; head_mode = HEAD_KEEP; head_bone = head; memcpy(head_pw, p2, 12); memcpy(head_nw, n2, 12); }
    skin_cut((u64)comp_a, 0, spine1, at, n, MODE_SIDE, 0, 0, -1, 0);
    strcpy(res_a, lastres);
    printf("A: %.300s\n", lastres);
    set_nosink();
    limbs_comp = (u64)comp_b; ngone = ng2; nkeep = ng1; memcpy(gone_roots, gone2, 4 * ng2); memcpy(keep_roots, gone1, 4 * ng1);
    if (heads) { head_comp = (u64)comp_b; head_mode = HEAD_DROP; head_bone = head; memcpy(head_pw, p2, 12); memcpy(head_nw, n2, 12); }
    skin_cut((u64)comp_b, 0, spine1, at, neg, MODE_SIDE, 0, 0, -1, 0);
    strcpy(res_b, lastres);
    printf("B: %.300s\n", lastres);
    if (!ov_a || !ov_b) { printf("FAIL: no override\n"); return 1; }
    int fail = 0;
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
        fail |= m < 12 || cross > 0 || -area < (env_on("ACROSS") ? 200 : 800); // her waist is about 270 cm2 across, the torso 1100 lengthwise
        // a plane up the spine reaches the neck: both halves get its lid
        if (heads && !env_on("ACROSS")) fail |= !strstr(h ? res_b : res_a, " np=");
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
        for (int v = 0; v < NV; v++) {
            float x[3]; skin_v(&o[v], v, x);
            float *p0 = orig + v * 3;
            float hgt = (p0[0] - at[0]) * nn[0] + (p0[1] - at[1]) * nn[1] + (p0[2] - at[2]) * nn[2];
            float mv = dist3(x, p0);
            int hd = heads && !tied_to_kept(h, v) && !tied_to_gone(h, v) && in_head(v, p0);
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
                if (mv > 0.5f) { kept_moved++; if (mv > worst) { worst = mv; worst_v = v; } }
            } else {
                gone++;
                float hx = (x[0] - at[0]) * nn[0] + (x[1] - at[1]) * nn[1] + (x[2] - at[2]) * nn[2];
                // into the neck: within NECK_R of its axis, at most NECK_BAND + 1 cm under the neck plane
                float e[3] = { x[0] - p2[0], x[1] - p2[1], x[2] - p2[2] }, h2 = e[0] * n2[0] + e[1] * n2[1] + e[2] * n2[2];
                int necked = heads && h2 < 0.5f && h2 > -NECK_BAND - 1.0f && e[0] * e[0] + e[1] * e[1] + e[2] * e[2] - h2 * h2 < NECK_R * NECK_R;
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
        fail |= kept_moved > kept / 200 || behind_kept > kept / 200;
        if (heads) fail |= h == 0 ? head_kept < head_all : head_kept > head_all / 200;
    }
    // posed: she keeps falling after the cut (the spine and head turn further): kept skin must still match the
    // vanilla skin in the new pose
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
        }
    }
    // in game each half's dropped limbs keep simulating (constraint broken, 0.02 kg): they flop anywhere. Move them
    // 40 cm away and turn them; nothing the half shows may follow
    for (int h = 0; h < 2; h++) {
        skin_info *o = h ? ov_b : ov_a;
        int *gr = h ? gone2 : gone1, ng = h ? ng2 : ng1;
        float *saved = malloc(48 * NB); memcpy(saved, space, 48 * NB);
        unsigned char *sub = calloc(NB, 1);
        for (int i = 0; i < NB; i++) {
            for (int r = 0; r < ng; r++) if (gr[r] == i) sub[i] = 1;
            if (!sub[i] && bparent[i] >= 0 && sub[bparent[i]]) sub[i] = 1;
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
