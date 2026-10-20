// Linux harness for the skin cut (sbslice.c) on a synthetic body + leg tube: cuts the leg, moves it 40 cm and
// checks that no triangle spans the gap, every weight sums to 255 and the collapsed matrices come back.
// Engine calls go to stubs through trampolines at exe + RVA. Run: ./test/run.sh
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#define __declspec(x)
#define __stdcall
#define u64 U64_
#define u32 U32_
#define u16 U16_
typedef unsigned long long U64_; typedef unsigned int U32_; typedef unsigned short U16_;
#undef u64
#undef u32
#undef u16
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
#include "../sbslice.c"
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
static char lastres[8192];
HANDLE CreateThread_(void *a, u64 b, u32(WINAPI *c)(void *), void *d, u32 e, u32 *f) { (void)a;(void)b;(void)c;(void)d;(void)e;(void)f; return 0; }
void Sleep_(u32 x) { (void)x; }
HANDLE CreateFileW_(const u16 *p, u32 a, u32 b, void *c, u32 d, u32 e, HANDLE f) { (void)p;(void)a;(void)b;(void)c;(void)d;(void)e;(void)f; return (HANDLE)1; }
int ReadFile_(HANDLE h, void *b, u32 n, u32 *g, void *o) { (void)h;(void)b;(void)n;(void)o; *g = 0; return 1; }
int WriteFile_(HANDLE h, const void *b, u32 n, u32 *w, void *o) { (void)h;(void)o; memcpy(lastres, b, n); lastres[n] = 0; *w = n; return 1; }
int CloseHandle_(HANDLE h) { (void)h; return 1; }
int DeleteFileW_(const u16 *p) { (void)p; return 1; }
void *GetModuleHandleW_(const u16 *p) { (void)p; return 0; }
int GetModuleHandleExW_(u32 a, const void *b, void **c) { (void)a;(void)b;(void)c; return 1; }
int DisableThreadLibraryCalls_(void *a) { (void)a; return 1; }
void *VirtualAlloc_(void *a, u64 n, u32 t, u32 p) { (void)a;(void)t;(void)p; void *m = mmap(0, n, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0); return m == MAP_FAILED ? 0 : m; }
int VirtualFree_(void *a, u64 n, u32 t) { (void)a;(void)n;(void)t; return 1; } // leak, fine

// ---- synthetic mesh -----
enum { ROOT, SPINE, THIGH, CALF, THIGH_HELP, SPINE_HELP, NB };
static int parent[NB] = { -1, ROOT, SPINE, THIGH, THIGH, SPINE };
static float bonez[NB] = { 0, 100, 60, 30, 55, 65 };   // global ref positions on the z axis
#define RINGS 21
#define SEG 12
#define NV (RINGS * SEG)
static float vpos[NV][3];
static unsigned char vw[NV][4 * 2]; // 4 indices then 4 weights (section-local == mesh, BoneMap identity)
static u32 idx[(RINGS - 1) * SEG * 6]; static int nidx;
static u64 sw_buf[32], ld_buf[64], sm_buf[128], rd_buf[4], lodptrs[1], ib_obj[1], ib_vt[16], sec_buf[0x100/8];
static u16 bonemap[NB];
static float space[NB * 12], refpose[NB * 12], refinv[NB * 16];
static unsigned char binfo[NB * 0xc];
static unsigned char comp_buf[0x2000];
static skin_info *override_w; static int override_n;
static int ib_num(u64 s) { (void)s; return nidx; }
static u32 ib_get(u64 s, u32 i) { (void)s; return idx[i]; }
static u64 st_get_buffer(u64 c, int l) { (void)c;(void)l; return (u64)sw_buf; }
static void st_set_override(u64 c, int l, const tarray *a) { (void)c;(void)l; override_n = a->num; override_w = malloc(sizeof(skin_info) * a->num); memcpy(override_w, a->data, sizeof(skin_info) * a->num); }
static void st_noop(u64 c) { (void)c; }
static u64 st_weak(u64 w) { (void)w; return 0; }
static void tramp(u64 at, void *fn) { unsigned char *p = (unsigned char *)at; p[0] = 0x48; p[1] = 0xb8; memcpy(p + 2, &fn, 8); p[10] = 0xff; p[11] = 0xe0; }

static void skin(const skin_info *o, const float *vp, float *x)
{
    cut_ctx c = { 0 }; c.nb = NB; c.binfo = binfo; c.refinv = refinv; c.space = space; c.nspace = NB;
    skin_point(&c, o, vp, x);
}

int main(void)
{
    void *m = mmap(0, 0x4200000, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) { perror("mmap"); return 1; }
    exe = (u64)m;
    tramp(exe + RVA_GET_SKIN_WEIGHT_BUFFER, (void *)st_get_buffer);
    tramp(exe + RVA_SET_SKIN_WEIGHT_OVERRIDE, (void *)st_set_override);
    tramp(exe + RVA_MARK_RENDER_STATE_DIRTY, (void *)st_noop);
    tramp(exe + RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS, (void *)st_noop);
    tramp(exe + RVA_WEAK_PTR_GET, (void *)st_weak);
    // bones: identity rotations, global positions on z; local = global - parent global
    for (int i = 0; i < NB; i++) {
        float *t = space + i * 12; memset(t, 0, 48); t[3] = 1; t[6] = bonez[i]; t[8] = t[9] = t[10] = 1;
        float *r = refpose + i * 12; memset(r, 0, 48); r[3] = 1; r[6] = bonez[i] - (parent[i] >= 0 ? bonez[parent[i]] : 0); r[8] = r[9] = r[10] = 1;
        float *iv = refinv + i * 16; memset(iv, 0, 64); iv[0] = iv[5] = iv[10] = iv[15] = 1; iv[14] = -bonez[i];
        *(int *)(binfo + i * 0xc + 8) = parent[i];
        bonemap[i] = i;
    }
    // a tube from z=100 (body) down to z=0 (leg); weights: body above 62, blend 62..58, thigh below, calf below 32
    for (int r = 0; r < RINGS; r++) for (int s = 0; s < SEG; s++) {
        int v = r * SEG + s; float z = 100 - r * 5, a = s * 6.2831853f / SEG;
        vpos[v][0] = 8 * __builtin_cosf(a); vpos[v][1] = 8 * __builtin_sinf(a); vpos[v][2] = z;
        unsigned char *w = vw[v];
        memset(w, 0, 8);
        if (z > 64) { w[0] = SPINE; w[4] = 255; if (z < 76) { w[1] = SPINE_HELP; w[4] = 200; w[5] = 55; } }
        else if (z > 56) { w[0] = SPINE; w[1] = THIGH; w[2] = THIGH_HELP; w[4] = 100; w[5] = 120; w[6] = 35; }
        else if (z > 32) { w[0] = THIGH; w[4] = 255; if (z > 44) { w[1] = THIGH_HELP; w[4] = 215; w[5] = 40; } }
        else { w[0] = CALF; w[4] = 255; }
    }
    for (int r = 0; r + 1 < RINGS; r++) for (int s = 0; s < SEG; s++) {
        u32 a = r * SEG + s, b = r * SEG + (s + 1) % SEG, c = (r + 1) * SEG + s, d = (r + 1) * SEG + (s + 1) % SEG;
        idx[nidx++] = a; idx[nidx++] = c; idx[nidx++] = b; idx[nidx++] = b; idx[nidx++] = c; idx[nidx++] = d;
    }
    // engine structures
    *(u64 *)(comp_buf + SC_SKELETAL_MESH) = (u64)sm_buf;
    *(u64 *)(comp_buf + SC_SPACE_BASES) = (u64)space; *(int *)(comp_buf + SC_SPACE_BASES + 8) = NB;
    *(int *)(comp_buf + SC_SPACE_READ) = 0;
    float *tw = (float *)(comp_buf + SC_TO_WORLD); tw[3] = 1; tw[8] = tw[9] = tw[10] = 1;
    unsigned char *sm = (unsigned char *)sm_buf, *ld = (unsigned char *)ld_buf, *sw = (unsigned char *)sw_buf, *sec = (unsigned char *)sec_buf;
    *(u64 *)(sm + SM_RENDER_DATA) = (u64)rd_buf; rd_buf[0] = (u64)lodptrs; *(int *)((unsigned char *)rd_buf + 8) = 1; lodptrs[0] = (u64)ld;
    *(u64 *)(sm + SM_REF_BONE_INFO) = (u64)binfo; *(int *)(sm + SM_REF_BONE_INFO + 8) = NB;
    *(u64 *)(sm + SM_REF_BONE_POSE) = (u64)refpose; *(int *)(sm + SM_REF_BONE_POSE + 8) = NB;
    *(u64 *)(sm + SM_REF_BASES_INV) = (u64)refinv; *(int *)(sm + SM_REF_BASES_INV + 8) = NB;
    *(u64 *)(ld + LOD_SECTIONS) = (u64)sec; *(int *)(ld + LOD_SECTIONS + 8) = 1;
    ib_vt[0x58 / 8] = (u64)ib_num; ib_vt[0x68 / 8] = (u64)ib_get; ib_obj[0] = (u64)ib_vt;
    *(u64 *)(ld + LOD_INDICES) = (u64)ib_obj;
    *(u64 *)(ld + LOD_POSITIONS + 0x28) = (u64)vpos; *(u32 *)(ld + LOD_POSITIONS + 0x30) = 12;
    *(int *)(ld + LOD_NUM_VERTICES) = NV;
    *(int *)(sec + SEC_BASE_VERTEX) = 0; *(u64 *)(sec + SEC_BONE_MAP) = (u64)bonemap; *(int *)(sec + SEC_BONE_MAP + 8) = NB; *(int *)(sec + SEC_NUM_VERTICES) = NV;
    sw[SW_VARIABLE] = 0; *(u32 *)(sw + SW_MAX_INFLUENCES) = 4; sw[SW_16BIT_INDEX] = 0; *(u64 *)(sw + SW_DATA) = (u64)vw; *(int *)(sw + SW_NUM_VERTICES) = NV;

    float pw[3] = { 0, 0, 57 }, nw[3] = { 0, 0, -1 };
    skin_cut((u64)comp_buf, 0, THIGH, pw, nw);
    printf("%s\n", lastres);
    int pending = refinv[THIGH_HELP * 16] == 1;
    printf("collapsed %d (sinks untouched before: %d)\n", skin_collapse(), pending);
    if (!override_w) return 1;
    printf("refinv thigh_help zeroed: %d, spine_help zeroed: %d\n", refinv[THIGH_HELP * 16] == 0 && refinv[THIGH_HELP * 16 + 15] == 1, refinv[SPINE_HELP * 16] == 0);
    // move the limb 40 cm sideways and tilt nothing: thigh, calf, helper follow
    float before[NV][3], after[NV][3];
    for (int v = 0; v < NV; v++) skin(&override_w[v], vpos[v], before[v]);
    for (int i = 0; i < NB; i++) if (i == THIGH || i == CALF || i == THIGH_HELP) space[i * 12 + 4] += 40;
    for (int v = 0; v < NV; v++) skin(&override_w[v], vpos[v], after[v]);
    int bad = 0, spanning = 0;
    for (int t = 0; t < nidx; t += 3) {
        int moved = 0, still = 0;
        for (int k = 0; k < 3; k++) { float dx = after[idx[t + k]][0] - before[idx[t + k]][0]; if (dx > 39) moved++; else if (fabsf_(dx) < 1) still++; else bad++; }
        if (moved && still) {
            float *a = after[idx[t]], *b = after[idx[t + 1]], *c = after[idx[t + 2]];
            float u[3] = { b[0] - a[0], b[1] - a[1], b[2] - a[2] }, w[3] = { c[0] - a[0], c[1] - a[1], c[2] - a[2] };
            float cx = u[1] * w[2] - u[2] * w[1], cy = u[2] * w[0] - u[0] * w[2], cz = u[0] * w[1] - u[1] * w[0];
            float area = 0.5f * __builtin_sqrtf(cx * cx + cy * cy + cz * cz);
            if (area > 0.01f) { spanning++; if (spanning < 5) printf("spanning tri %d area %.2f\n", t / 3, area); }
        }
    }
    // weights sum check
    int badsum = 0;
    for (int v = 0; v < NV; v++) { int s = 0; for (int i = 0; i < MAX_INF; i++) s += override_w[v].weights[i]; if (s != 255) badsum++; }
    int r1 = skin_restore(0);
    printf("restored %d, thigh_help refinv[0]=%.0f [14]=%.0f, spine_help [14]=%.0f, nsinks=%d\n", r1, refinv[THIGH_HELP*16], refinv[THIGH_HELP*16+14], refinv[SPINE_HELP*16+14], nsinks);
    // a tilted plane on the already moved pose (exercises a second cut over a posed limb)
    float pw2[3] = { 0, 0, 57 }, nw2[3] = { 0.3f, 0, 0.95f };
    skin_cut((u64)comp_buf, 0, THIGH, pw2, nw2);
    skin_collapse();
    printf("second plane: %s\n", lastres);
    skin_restore(0);
    printf("partially moved verts: %d, spanning triangles: %d, weight sums != 255: %d\n", bad, spanning, badsum);
    // the fit on its own: an elliptic ring 6 x 4 cm plus a strap standing 15 cm off it must give 6 x 4
    float ring[60 * 3], pp[3] = { 0, 0, 0 }, up[3] = { 0, 0, 1 }, idt[12] = { 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 0 };
    for (int i = 0; i < 50; i++) { float a = i * 6.2831853f / 50; ring[i * 3] = 6 * __builtin_cosf(a) + 1; ring[i * 3 + 1] = 4 * __builtin_sinf(a); ring[i * 3 + 2] = 0.3f; }
    for (int i = 50; i < 60; i++) { ring[i * 3] = 15 + (i - 50); ring[i * 3 + 1] = 2; ring[i * 3 + 2] = 0; }
    char fit[4096]; *put_fit(fit, "t", ring, 60, pp, up, idt) = 0;
    printf("fit:%s\n", fit);
    float fa = 0, fb = 0, fcx = 0;
    sscanf(strstr(fit, "te=") + 3, "%f,%f", &fa, &fb);
    sscanf(strstr(fit, "tc=") + 3, "%f", &fcx);
    // the outline: the ring's points in order, none of the strap
    int np = 0, strap = 0;
    for (char *q = strstr(fit, "tp="); q && *q && *q != ' '; q++) if (*q == ';') np++;
    { char *q = strstr(fit, "tp="); float x; while (q && sscanf(q + (*q == 't' ? 3 : 1), "%f", &x) == 1) { if (x > 10) strap++; q = strchr(q + 1, ';'); } }
    printf("outline points %d, on the strap %d\n", np + 1, strap);
    int fitbad = np + 1 < 20 || strap || fa < 5.7f || fa > 6.3f || fb < 3.7f || fb > 4.3f || fcx < 0.8f || fcx > 1.2f;
    int fail = fitbad || !pending || bad || spanning || badsum || r1 != 2 || refinv[THIGH_HELP * 16] != 1;
    printf("%s\n", fail ? "FAIL" : "PASS");
    return fail;
}
