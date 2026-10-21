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
#define SBSLICE_HOSTED
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
// SPINE_HELP2 and PELVIS_HELP are helpers no vertex uses: free sinks for the split (bands, the leg's point)
enum { ROOT, SPINE, THIGH, CALF, THIGH_HELP, SPINE_HELP, SPINE_HELP2, PELVIS_HELP, NB };
static int parent[NB] = { -1, ROOT, SPINE, THIGH, THIGH, SPINE, SPINE, SPINE };
static float bonez[NB] = { 0, 100, 60, 30, 55, 65, 85, 58 };   // global ref positions on the z axis
#define RINGS 21
#define SEG 12
#define NV (RINGS * SEG)
static float vpos[NV][3];
static unsigned char vw[NV][4 * 2]; // 4 indices then 4 weights (section-local == mesh, BoneMap identity)
static u32 idx[(RINGS - 1) * SEG * 6]; static int nidx;
static u64 sw_buf[32], ld_buf[64], sm_buf[128], rd_buf[4], lodptrs[1], ib_obj[1], ib_vt[16], sec_buf[0x200/8];
static u16 bonemap[NB];
static float space[NB * 12], refpose[NB * 12], refinv[NB * 16];
static unsigned char binfo[NB * 0xc];
static unsigned char comp_buf[0x2000];
static skin_info *override_w; static int override_n;
static u32 *cur_idx = idx; static int *cur_nidx = &nidx;
static int ib_num(u64 s) { (void)s; return *cur_nidx; }
static u32 ib_get(u64 s, u32 i) { (void)s; return cur_idx[i]; }
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
// the same through a bone map (a remapped borrowed bone poses like the bone it follows)
static void skin_mapped(const skin_info *o, const float *vp, float *x, int *map)
{
    cut_ctx c = { 0 }; c.nb = NB; c.binfo = binfo; c.refinv = refinv; c.space = space; c.nspace = NB; c.mmap = map;
    skin_point(&c, o, vp, x);
}
static float dist3(const float *a, const float *b) { float d0 = a[0] - b[0], d1 = a[1] - b[1], d2 = a[2] - b[2]; return __builtin_sqrtf(d0 * d0 + d1 * d1 + d2 * d2); }

// the tube plus a second section of hanging pieces: strap A (x 9, body above the cut, leg below: tied to both), strap B
// (x -9, all leg) and a plate (x 9.5 over the skin at z 80, body)
#define XV (NV + 33)
static float xpos[XV][3];
static unsigned char xw[XV][8];
static u32 xidx[(RINGS - 1) * SEG * 6 + 64 * 3]; static int nxidx;
static u64 xsec[0x200 / 8];

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
    skin_cut((u64)comp_buf, 0, THIGH, pw, nw, MODE_CUT, 0, 0, -1, 0);
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
    skin_cut((u64)comp_buf, 0, THIGH, pw2, nw2, MODE_CUT, 0, 0, -1, 0);
    skin_collapse();
    printf("second plane: %s\n", lastres);
    skin_restore(0);
    printf("partially moved verts: %d, spanning triangles: %d, weight sums != 255: %d\n", bad, spanning, badsum);
    // the fit on its own: an elliptic ring 6 x 4 cm plus a strap standing 15 cm off it must give 6 x 4
    float ring[60 * 3], pp[3] = { 0, 0, 0 }, up[3] = { 0, 0, 1 }, idt[12] = { 0, 0, 0, 1, 0, 0, 0, 0, 1, 1, 1, 0 };
    for (int i = 0; i < 50; i++) { float a = i * 6.2831853f / 50; ring[i * 3] = 6 * __builtin_cosf(a) + 1; ring[i * 3 + 1] = 4 * __builtin_sinf(a); ring[i * 3 + 2] = 0.3f; }
    for (int i = 50; i < 60; i++) { ring[i * 3] = 15 + (i - 50); ring[i * 3 + 1] = 2; ring[i * 3 + 2] = 0; }
    char fit[4096]; *put_fit(fit, "t", ring, 60, pp, up, idt, 1) = 0;
    printf("fit:%s\n", fit);
    float fa = 0, fb = 0, fcx = 0;
    sscanf(strstr(fit, "te=") + 3, "%f,%f", &fa, &fb);
    sscanf(strstr(fit, "tc=") + 3, "%f", &fcx);
    // the outline: the ring's points in order, none of the strap
    int np = 0, strap = 0;
    for (char *q = strstr(fit, "tp="); q && *q && *q != ' '; q++) if (*q == ';') np++;
    { char *q = strstr(fit, "tp="); float x; while (q && sscanf(q + (*q == 't' ? 3 : 1), "%f", &x) == 1) { if (x > 10) strap++; q = strchr(q + 1, ';'); } }
    printf("outline points %d, on the strap %d\n", np + 1, strap);
    // the core filter: skin ring (section 0, r 6) and a tight suit over it (3, r 6.5) stay; a strap (1) on one side,
    // a loose sleeve (2, r 12) and their points go
    float lay[200 * 3]; u16 lsec[200]; int ln = 0;
    for (int i = 0; i < 40; i++) { float a = i * 6.2831853f / 40; lay[ln * 3] = 6 * __builtin_cosf(a); lay[ln * 3 + 1] = 6 * __builtin_sinf(a); lay[ln * 3 + 2] = 0; lsec[ln++] = 0; }
    for (int i = 0; i < 12; i++) { lay[ln * 3] = 7 + i * 0.2f; lay[ln * 3 + 1] = -1 + i * 0.2f; lay[ln * 3 + 2] = 0; lsec[ln++] = 1; }
    for (int i = 0; i < 40; i++) { float a = i * 6.2831853f / 40; lay[ln * 3] = 12 * __builtin_cosf(a); lay[ln * 3 + 1] = 12 * __builtin_sinf(a); lay[ln * 3 + 2] = 0; lsec[ln++] = 2; }
    for (int i = 0; i < 40; i++) { float a = i * 6.2831853f / 40 + 0.05f; lay[ln * 3] = 6.5f * __builtin_cosf(a); lay[ln * 3 + 1] = 6.5f * __builtin_sinf(a); lay[ln * 3 + 2] = 0; lsec[ln++] = 3; }
    char corelog[1024]; int kept = ln; *core_rim(corelog, "t", lay, lsec, &kept, pp, up) = 0;
    int corebad = kept != 80;
    for (int i = 0; i < kept; i++) if (lsec[i] != 0 && lsec[i] != 3) corebad = 1;
    // nothing goes round the axis (a cut through a strap only): everything stays
    float sp[12 * 3]; u16 ssec[12];
    for (int i = 0; i < 12; i++) { sp[i * 3] = 7 + i * 0.2f; sp[i * 3 + 1] = -1 + i * 0.2f; sp[i * 3 + 2] = 0; ssec[i] = 1; }
    int k2 = 12; char log2[256]; *core_rim(log2, "s", sp, ssec, &k2, pp, up) = 0;
    corebad |= k2 != 12;
    printf("core:%s (kept %d) /%s (kept %d)\n", corelog, kept, log2, k2);
    // ---- the other modes, on the rest pose again ----
    for (int i = 0; i < NB; i++) space[i * 12 + 4] = 0;
    int modebad = 0;
    // HOLE: a ray from inside the body along +x meets the skin at x=8; a 4 cm ball there collapses onto a sink
    // behind it, nothing else moves, and the answer names the surface point and a bone to ride on
    float hp[3] = { 0, 0, 80 }, hn[3] = { 1, 0, 0 };
    free(override_w); override_w = 0;
    skin_cut((u64)comp_buf, 0, SPINE, hp, hn, MODE_HOLE, 4, 0, -1, 0);
    skin_collapse();
    printf("hole: %.300s\n", lastres);
    {
        int holed = 0, other = 0, sums = 0;
        for (int v = 0; v < NV; v++) {
            float d0 = vpos[v][0] - 8, d1 = vpos[v][1], d2 = vpos[v][2] - 80;
            int in = d0 * d0 + d1 * d1 + d2 * d2 < 16;
            int onsink = override_w[v].weights[0] == 255 && is_sink(&(cut_ctx){ .sm = (u64)sm_buf }, override_w[v].bones[0]);
            if (in) holed += onsink; else other += onsink;
            int t = 0; for (int i = 0; i < MAX_INF; i++) t += override_w[v].weights[i];
            sums += t != 255;
        }
        float hx = 0; sscanf(strstr(lastres, " hit=") + 5, "%f", &hx);
        int sink_inside = 1;
        for (int i = 0; i < nsinks; i++) if (bonez[sinks[i].bone] == 0 && sinks[i].bone != ROOT) sink_inside = 0;
        printf("hole: %d in the ball on a sink, %d outside, sums %d, hit x %.1f, wb %d\n", holed, other, sums, hx, !!strstr(lastres, " wb="));
        modebad |= !holed || other || sums || hx < 7.5f || hx > 8.5f || !strstr(lastres, " bc=") || !sink_inside;
    }
    skin_restore(0);
    // DENT: a blunt blow at x 8, z 80 along +x, 5 cm wide, 2 deep: the skin at the ray goes 2 cm in, the dent fades
    // out to nothing at 5 cm across the ray, nothing behind it or past the radius moves, the skin stays closed
    {
        free(override_w); override_w = 0;
        skin_cut((u64)comp_buf, 0, SPINE, hp, hn, MODE_DENT, 5, 0, -1, 2);
        printf("dent: %.160s\n", lastres);
        skin_collapse();
        float cx = 0; int far_moved = 0, sums = 0, outward = 0, inner = 0;
        for (int v = 0; v < NV; v++) {
            float x[3]; skin(&override_w[v], vpos[v], x);
            int t2 = 0; for (int i = 0; i < MAX_INF; i++) t2 += override_w[v].weights[i];
            sums += t2 != 255;
            float dy = vpos[v][1], dz = vpos[v][2] - 80, q2 = dy * dy + dz * dz;
            if (vpos[v][0] > 7.9f && q2 < 0.01f) cx = x[0];
            if ((q2 >= 25 || vpos[v][0] < 0) && dist3(x, vpos[v]) > 0.01f) far_moved++;
            if (x[0] > vpos[v][0] + 0.01f) outward++;
            if (q2 < 25 && vpos[v][0] > 0 && x[0] < vpos[v][0] - 0.01f) inner++;
        }
        printf("dent: centre at x %.2f (8 - 2), %d moved outside it, %d pushed outward, %d pressed in, sums %d\n", cx, far_moved, outward, inner, sums);
        modebad |= cx < 5.9f || cx > 6.1f || far_moved || outward || inner < 3 || sums || !strstr(lastres, " dented=");
        skin_restore(0);
    }
    // RUPTURE: the same blow as a burst: every front vertex within the radius goes all the way to the floor (x 6),
    // with no falloff; nothing outside it moves
    {
        free(override_w); override_w = 0;
        skin_cut((u64)comp_buf, 0, SPINE, hp, hn, MODE_RUPTURE, 5, 0, -1, 2);
        printf("rupture: %.160s\n", lastres);
        skin_collapse();
        int far_moved = 0, sums = 0, off_floor = 0, floored = 0;
        for (int v = 0; v < NV; v++) {
            float x[3]; skin(&override_w[v], vpos[v], x);
            int t2 = 0; for (int i = 0; i < MAX_INF; i++) t2 += override_w[v].weights[i];
            sums += t2 != 255;
            float dy = vpos[v][1], dz = vpos[v][2] - 80, q2 = dy * dy + dz * dz;
            if ((q2 >= 25 || vpos[v][0] < 0) && dist3(x, vpos[v]) > 0.01f) far_moved++;
            if (q2 < 20 && vpos[v][0] > 6.5f) { if (x[0] > 6.2f) off_floor++; else floored++; }
        }
        printf("rupture: %d on the floor, %d left above it, %d moved outside it, sums %d\n", floored, off_floor, far_moved, sums);
        modebad |= off_floor || floored < 3 || far_moved || sums || !strstr(lastres, " dented=");
        skin_restore(0);
    }
    // PLANE through the knee region for the calf alone: the calf has no helper to collapse its side onto, so its
    // side of the seam vanishes into the body's sink instead of stretching when the calf flies off
    float pp2[3] = { 0, 0, 40 }, pn2[3] = { 0, 0, -1 };
    free(override_w); override_w = 0;
    skin_cut((u64)comp_buf, 0, CALF, pp2, pn2, MODE_PLANE, 10, 0, -1, 0);
    skin_collapse();
    printf("plane: %.200s\n", lastres);
    {
        float bf[NV][3], af[NV][3];
        for (int v = 0; v < NV; v++) skin(&override_w[v], vpos[v], bf[v]);
        space[CALF * 12 + 4] += 40;
        for (int v = 0; v < NV; v++) skin(&override_w[v], vpos[v], af[v]);
        space[CALF * 12 + 4] -= 40;
        int movers = 0, below_kept = 0;
        for (int v = 0; v < NV; v++) {
            if (af[v][0] - bf[v][0] > 1) movers++;
            if (vpos[v][2] < 40 && !(override_w[v].weights[0] == 255)) below_kept++;
        }
        int van = 0; sscanf(strstr(lastres, "vanished=") + 9, "%d", &van);
        printf("plane: %d verts follow the calf, %d below the plane not collapsed, vanished %d\n", movers, below_kept, van);
        modebad |= movers || below_kept || van < SEG * 7;
    }
    skin_restore(0);
    // WHOLE: everything follows the thigh, its opening is the band at the top of what is near the axis
    free(override_w); override_w = 0;
    float wp[3] = { 0, 0, 200 }, wn[3] = { 0, 0, -1 };
    skin_cut((u64)comp_buf, 0, THIGH, wp, wn, MODE_WHOLE, 0, 0, -1, 0);
    printf("whole: %.200s\n", lastres);
    {
        int follow = 0;
        for (int v = 0; v < NV; v++) for (int i = 0; i < MAX_INF; i++)
            if (override_w[v].weights[i] == 255 && (override_w[v].bones[i] == THIGH || override_w[v].bones[i] == CALF || override_w[v].bones[i] == THIGH_HELP)) follow++;
        int all255 = 1;
        for (int v = 0; v < NV; v++) { int t = 0, limbw = 0; for (int i = 0; i < MAX_INF; i++) { t += override_w[v].weights[i]; int bb = override_w[v].bones[i]; if (override_w[v].weights[i] && (bb == THIGH || bb == CALF || bb == THIGH_HELP)) limbw += override_w[v].weights[i]; } if (t != 255 || limbw != 255) all255 = 0; }
        float lcz = 0; char *lc = strstr(lastres, " lc="); if (lc) sscanf(lc + 4, "%*f,%*f,%f", &lcz);
        printf("whole: every vertex on limb bones %d, opening at z %.1f\n", all255, lcz);
        modebad |= !all255 || !lc || lcz < 97 || strstr(lastres, " bc=") != 0;
    }
    skin_restore(0);
    // a limb sink on the wrong side of the plane (THIGH_HELP at z 55, cut at 52): its collapse point is moved inside
    // the limb, so the limb's seam doesn't stick out past the cut as a cone
    {
        free(override_w); override_w = 0;
        float cp[3] = { 0, 0, 52 }, cn[3] = { 0, 0, -1 };
        skin_cut((u64)comp_buf, 0, THIGH, cp, cn, MODE_CUT, 0, 0, -1, 0);
        int moved = 0; char *sm = strstr(lastres, "sinkmoved="); if (sm) sscanf(sm + 10, "%d", &moved);
        skin_collapse();
        float top = -1e9f; int on = 0;
        for (int v = 0; v < NV; v++) {
            if (!(override_w[v].weights[0] == 255 && override_w[v].bones[0] == THIGH_HELP)) continue;
            float x[3]; skin(&override_w[v], vpos[v], x);
            if (x[2] > top) top = x[2];
            on++;
        }
        printf("sink side: moved %d, %d limb seam verts collapse to z %.1f (cut at 52)\n", moved, on, top);
        modebad |= moved < 1 || !on || top > 52 - 1.5f;
        skin_restore(0);
    }
    // SIDE: half a vertical split, x > 0 stays, the rest flattens onto the plane. The section is made to lack
    // SPINE_HELP (its vertices moved to SPINE) so the forced sink has to be borrowed into the BoneMap and remapped
    {
        unsigned char vsave[NV][8];
        memcpy(vsave, vw, sizeof vw);
        for (int v = 0; v < NV; v++) for (int i = 0; i < 4; i++) if (vw[v][i] == SPINE_HELP) { vw[v][i] = SPINE; }
        static u16 bm8[8];
        int nbm = 0;
        for (int i = 0; i < NB; i++) if (i != SPINE_HELP) bm8[nbm++] = i; // the weighted bones keep their index
        unsigned char *sec = (unsigned char *)sec_buf;
        *(u64 *)(sec + SEC_BONE_MAP) = (u64)bm8; *(int *)(sec + SEC_BONE_MAP + 8) = nbm; *(int *)(sec + SEC_BONE_MAP + 12) = nbm;
        static int mmap6[NB];
        for (int i = 0; i < NB; i++) mmap6[i] = i;
        *(u64 *)(comp_buf + SC_MASTER_BONE_MAP) = (u64)mmap6; *(int *)(comp_buf + SC_MASTER_BONE_MAP + 8) = NB;
        free(override_w); override_w = 0;
        float sp[3] = { 0, 0, 50 }, sn[3] = { 1, 0, 0 };
        skin_cut((u64)comp_buf, 0, SPINE, sp, sn, MODE_SIDE, 0, SPINE_HELP, SPINE, 0);
        printf("side: %.300s\n", lastres);
        int gone = 0, kept_bad = 0, nb8 = *(int *)(sec + SEC_BONE_MAP + 8), bands = 0;
        for (int v = 0; v < NV; v++) {
            int on_sink = override_w[v].weights[0] == 255 && override_w[v].bones[0] == SPINE_HELP;
            if (vpos[v][0] <= 0) gone += on_sink;
            else if (on_sink) kept_bad++;
        }
        int expect = 0;
        for (int v = 0; v < NV; v++) expect += vpos[v][0] <= 0;
        // one traced opening over the whole cut (bands only pick sinks now)
        bands = !!strstr(lastres, " s0c=") + !!strstr(lastres, " s0p=");
        int early = mmap6[SPINE_HELP] != SPINE_HELP;
        skin_collapse();
        int remapped = mmap6[SPINE_HELP] == SPINE && !early;
        // flattened, not collapsed: every vanished vertex on the plane (SHEET_IN inside) where it was, the rest unmoved
        int off = 0, moved = 0;
        for (int v = 0; v < NV; v++) {
            float x[3]; skin_mapped(&override_w[v], vpos[v], x, mmap6);
            if (vpos[v][0] <= 0) off += fabsf_(x[0] - SHEET_IN) > 0.01f || fabsf_(x[1] - vpos[v][1]) > 0.01f || fabsf_(x[2] - vpos[v][2]) > 0.01f;
            else moved += dist3(x, vpos[v]) > 0.01f;
        }
        skin_restore(0);
        int nb_back = *(int *)(sec + SEC_BONE_MAP + 8);
        unremap((u64)comp_buf);
        printf("side: %d/%d gone onto the borrowed sink, %d kept wrongly, bonemap %d -> %d, remapped %d -> %d, lid parts %d, off the plane %d, kept moved %d\n",
               gone, expect, kept_bad, nbm, nb8, remapped, mmap6[SPINE_HELP], bands, off, moved);
        modebad |= gone != expect || kept_bad || nb8 != nbm + 1 || nb_back != nbm || !remapped || mmap6[SPINE_HELP] != SPINE_HELP || bands < 2 || off || moved;
        // pose copy
        static float dst[NB * 12];
        static unsigned char comp2[0x2000];
        *(u64 *)(comp2 + SC_SPACE_BASES) = (u64)dst; *(int *)(comp2 + SC_SPACE_BASES + 8) = NB;
        *(u64 *)(comp2 + SC_SPACE_BASES + 0x10) = (u64)dst; *(int *)(comp2 + SC_SPACE_BASES + 0x18) = NB;
        *(u64 *)(comp_buf + SC_SPACE_BASES + 0x10) = (u64)space; *(int *)(comp_buf + SC_SPACE_BASES + 0x18) = NB;
        copy_pose((u64)comp_buf, (u64)comp2);
        printf("pose: %s, calf z %.1f\n", lastres, dst[CALF * 12 + 6]);
        char want[32]; sprintf(want, "ok copied %d", NB);
        modebad |= strncmp(lastres, want, strlen(want)) || dst[CALF * 12 + 6] != bonez[CALF];
        *(u64 *)(comp_buf + SC_MASTER_BONE_MAP) = 0; *(int *)(comp_buf + SC_MASTER_BONE_MAP + 8) = 0;
        *(u64 *)(sec + SEC_BONE_MAP) = (u64)bonemap; *(int *)(sec + SEC_BONE_MAP + 8) = NB;
        memcpy(vw, vsave, sizeof vw);
    }
    // SIDE with the leg gone to the other half: the torso behind the plane flattens through band sinks (helpers of the
    // kept side, never the spine), the leg collapses to one point on the plane where it joined, the rest stays
    {
        free(override_w); override_w = 0;
        limbs_comp = (u64)comp_buf; ngone = 1; gone_roots[0] = THIGH; nkeep = 0;
        float sp[3] = { 0, 0, 50 }, sn[3] = { 1, 0, 0 };
        skin_cut((u64)comp_buf, 0, SPINE, sp, sn, MODE_SIDE, 0, 0, -1, 0);
        printf("bands: %.200s\n", lastres);
        int proj = 0, point = 0; char *q;
        if ((q = strstr(lastres, " proj="))) sscanf(q + 6, "%d", &proj);
        if ((q = strstr(lastres, " point="))) sscanf(q + 7, "%d", &point);
        int badsink = 0;
        for (int i = 0; i < nsinks; i++) if (sinks[i].bone == SPINE || sinks[i].bone == THIGH || sinks[i].bone == CALF || sinks[i].bone == THIGH_HELP) badsink++;
        skin_collapse();
        int off = 0, leg_off = 0, moved = 0, legs = 0;
        float lp[3] = { SHEET_IN, 0, bonez[THIGH] };
        for (int v = 0; v < NV; v++) {
            float x[3]; skin(&override_w[v], vpos[v], x);
            if (vpos[v][2] <= 60) { legs++; leg_off += dist3(x, lp) > 0.01f; }
            else if (vpos[v][0] <= 0) {
                // near the plane: flattened where it was; deeper: anywhere on the plane (a band's point, or flattened)
                int deep = vpos[v][0] <= -SHEET_FAR;
                off += fabsf_(x[0] - SHEET_IN) > 0.01f || (!deep && (fabsf_(x[1] - vpos[v][1]) > 0.01f || fabsf_(x[2] - vpos[v][2]) > 0.01f));
            }
            else moved += dist3(x, vpos[v]) > 0.01f;
        }
        printf("bands: %d flattening and %d point sinks (%d on limbs or the spine), torso off the plane %d, leg verts off the point %d/%d, kept moved %d\n",
               proj, point, badsink, off, leg_off, legs, moved);
        modebad |= proj < 2 || point != 1 || badsink || off || leg_off || moved;
        skin_restore(0);
        // the same with the whole body turned 90 degrees about z: the sinks flatten in their bones' frames as posed
        free(override_w); override_w = 0;
        float qz[4] = { 0, 0, 0.70710678f, 0.70710678f };
        for (int i = 0; i < NB; i++) for (int k = 0; k < 4; k++) space[i * 12 + k] = qz[k];
        float sn2[3] = { 0, 1, 0 };
        skin_cut((u64)comp_buf, 0, SPINE, sp, sn2, MODE_SIDE, 0, 0, -1, 0);
        skin_collapse();
        int off2 = 0;
        for (int v = 0; v < NV; v++) {
            if (vpos[v][2] <= 60 || vpos[v][0] > 0) continue;
            float x[3]; skin(&override_w[v], vpos[v], x);
            // turned: (x, y, z) -> (-y, x, z), then onto y = SHEET_IN
            int deep = vpos[v][0] <= -SHEET_FAR;
            off2 += fabsf_(x[1] - SHEET_IN) > 0.01f || (!deep && (fabsf_(x[0] + vpos[v][1]) > 0.01f || fabsf_(x[2] - vpos[v][2]) > 0.01f));
        }
        printf("bands turned: torso off the plane %d\n", off2);
        modebad |= off2;
        skin_restore(0);
        for (int i = 0; i < NB; i++) { for (int k = 0; k < 3; k++) space[i * 12 + k] = 0; space[i * 12 + 3] = 1; }
        // across the body (the blade level at z 80, the top kept): everything below ends on the plane, inside the opening
        free(override_w); override_w = 0;
        float hp3[3] = { 0, 0, 80 }, hn3[3] = { 0, 0, 1 };
        skin_cut((u64)comp_buf, 0, SPINE, hp3, hn3, MODE_SIDE, 0, 0, -1, 0);
        printf("across: %.140s\n", lastres);
        skin_collapse();
        int off3 = 0, out3 = 0, moved3 = 0;
        for (int v = 0; v < NV; v++) {
            float x[3]; skin(&override_w[v], vpos[v], x);
            if (vpos[v][2] > 80) { moved3 += dist3(x, vpos[v]) > 0.01f; continue; }
            off3 += fabsf_(x[2] - 80 - SHEET_IN) > 0.01f;
            out3 += x[0] * x[0] + x[1] * x[1] > 8.05f * 8.05f;
        }
        printf("across: below off the plane %d, outside the opening %d, kept moved %d\n", off3, out3, moved3);
        modebad |= off3 || out3 || moved3 || strncmp(lastres, "ok", 2);
        skin_restore(0);
        for (int i = 0; i < NB; i++) { for (int k = 0; k < 3; k++) space[i * 12 + k] = 0; space[i * 12 + 3] = 1; }
        limbs_comp = 0; ngone = 0;
    }
    // no sink on a bone Lua forbids (the main skeleton, hair, capes)
    {
        free(override_w); override_w = 0;
        nosink_mesh = (u64)sm_buf; nosink[THIGH_HELP] = nosink[PELVIS_HELP] = 1;
        float cp[3] = { 0, 0, 57 }, cn[3] = { 0, 0, -1 };
        skin_cut((u64)comp_buf, 0, THIGH, cp, cn, MODE_CUT, 0, 0, -1, 0);
        int bad_ns = 0;
        for (int i = 0; i < nsinks; i++) bad_ns += nosink[sinks[i].bone];
        printf("nosink: %.120s -> %d forbidden sinks\n", lastres, bad_ns);
        modebad |= bad_ns || strncmp(lastres, "ok", 2);
        skin_restore(0);
        nosink_mesh = 0; nosink[THIGH_HELP] = nosink[PELVIS_HELP] = 0;
    }
    // hanging pieces and a plate, in a second section
    {
        memcpy(xpos, vpos, sizeof vpos); memcpy(xw, vw, sizeof vw);
        memcpy(xidx, idx, sizeof(u32) * nidx); nxidx = nidx;
        int base = NV;
        for (int st = 0; st < 2; st++)          // straps: 6 rows of 2
            for (int r = 0; r < 6; r++) for (int c2 = 0; c2 < 2; c2++) {
                int v = base + st * 12 + r * 2 + c2; float z = 70 - r * 5;
                xpos[v][0] = st ? -9 : 9; xpos[v][1] = c2 ? 1 : -1; xpos[v][2] = z;
                memset(xw[v], 0, 8); xw[v][4] = 255;
                xw[v][0] = st ? THIGH : (z > 57 ? SPINE : THIGH);
            }
        for (int st = 0; st < 2; st++) for (int r = 0; r + 1 < 6; r++) {
            u32 a = base + st * 12 + r * 2, b2 = a + 1, c3 = a + 2, d = a + 3;
            xidx[nxidx++] = a; xidx[nxidx++] = c3; xidx[nxidx++] = b2; xidx[nxidx++] = b2; xidx[nxidx++] = c3; xidx[nxidx++] = d;
        }
        int pb = base + 24;                      // plate: 3 x 3
        for (int r = 0; r < 3; r++) for (int c2 = 0; c2 < 3; c2++) {
            int v = pb + r * 3 + c2;
            xpos[v][0] = 9.5f; xpos[v][1] = -2 + 2 * c2; xpos[v][2] = 78 + 2 * r;
            memset(xw[v], 0, 8); xw[v][0] = SPINE; xw[v][4] = 255;
        }
        for (int r = 0; r + 1 < 3; r++) for (int c2 = 0; c2 + 1 < 3; c2++) {
            u32 a = pb + r * 3 + c2, b2 = a + 1, c3 = a + 3, d = a + 4;
            xidx[nxidx++] = a; xidx[nxidx++] = c3; xidx[nxidx++] = b2; xidx[nxidx++] = b2; xidx[nxidx++] = c3; xidx[nxidx++] = d;
        }
        unsigned char *ld = (unsigned char *)ld_buf, *sw = (unsigned char *)sw_buf, *xs2 = (unsigned char *)xsec;
        memcpy(xs2, sec_buf, 0xe8);
        memcpy(xs2 + 0xe8, sec_buf, 0xe8);
        *(int *)(xs2 + 0xe8 + SEC_BASE_VERTEX) = NV; *(int *)(xs2 + 0xe8 + SEC_NUM_VERTICES) = XV - NV;
        *(u64 *)(ld + LOD_SECTIONS) = (u64)xs2; *(int *)(ld + LOD_SECTIONS + 8) = 2;
        *(u64 *)(ld + LOD_POSITIONS + 0x28) = (u64)xpos; *(int *)(ld + LOD_NUM_VERTICES) = XV;
        *(u64 *)(sw + SW_DATA) = (u64)xw; *(int *)(sw + SW_NUM_VERTICES) = XV;
        cur_idx = xidx; cur_nidx = &nxidx;
        cut_ctx sc = { .sm = (u64)sm_buf };

        free(override_w); override_w = 0;
        float cp[3] = { 0, 0, 57 }, cn[3] = { 0, 0, -1 };
        skin_cut((u64)comp_buf, 0, THIGH, cp, cn, MODE_CUT, 0, 0, -1, 0);
        printf("pieces: %.160s\n", strstr(lastres, " pieces=") ? strstr(lastres, " pieces=") : lastres);
        skin_collapse();
        int a_sink = -1, a_bad = 0, b_bad = 0, b_off = 0;
        for (int v = base; v < base + 12; v++) {
            int ok = override_w[v].weights[0] == 255 && is_sink(&sc, override_w[v].bones[0]);
            if (!ok || (a_sink >= 0 && override_w[v].bones[0] != a_sink)) a_bad++;
            a_sink = override_w[v].bones[0];
        }
        for (int i = 0; i < NB; i++) if (i == THIGH || i == CALF || i == THIGH_HELP) space[i * 12 + 4] += 40;
        for (int v = base + 12; v < base + 24; v++) {
            float x[3]; skin(&override_w[v], xpos[v], x);
            for (int i = 0; i < MAX_INF; i++) {
                int bb = override_w[v].bones[i];
                if (override_w[v].weights[i] && bb != THIGH && bb != CALF && bb != THIGH_HELP) b_bad++;
            }
            b_off += fabsf_(x[0] - xpos[v][0] - 40) > 0.01f;
        }
        for (int i = 0; i < NB; i++) space[i * 12 + 4] = 0;
        printf("pieces: strap A %s (%d off one sink), strap B along with the leg (%d not on leg bones, %d not moved)\n",
               a_bad ? "not gone" : "gone into one sink", a_bad, b_bad, b_off);
        modebad |= a_bad || b_bad || b_off || !strstr(lastres, " pieces=1/1");
        skin_restore(0);

        // a hole where the ray comes out through the plate: the plate stays, the skin under it gets the hole
        free(override_w); override_w = 0;
        float hp[3] = { 0, 0, 80 }, hn[3] = { 1, 0, 0 };
        skin_cut((u64)comp_buf, 0, SPINE, hp, hn, MODE_HOLE, 4, 0, -1, 0);
        skin_collapse();
        int plate_hit = 0, skin_hit = 0;
        for (int v = pb; v < pb + 9; v++) plate_hit += override_w[v].weights[0] == 255 && is_sink(&sc, override_w[v].bones[0]);
        for (int v = 0; v < NV; v++) skin_hit += override_w[v].weights[0] == 255 && is_sink(&sc, override_w[v].bones[0]);
        float hx = 0; char *q = strstr(lastres, " hit="); if (q) sscanf(q + 5, "%f", &hx);
        printf("layers: plate verts holed %d, skin verts holed %d, hit x %.1f, %s\n", plate_hit, skin_hit, hx,
               strstr(lastres, " layersoff=") ? strstr(lastres, " layersoff=") + 1 : "?");
        modebad |= plate_hit || !skin_hit || hx < 7.5f || hx > 8.5f || !strstr(lastres, " layersoff=1");
        skin_restore(0);

        // a dent there: the plate stays as it is, the skin under it is pressed in
        free(override_w); override_w = 0;
        skin_cut((u64)comp_buf, 0, SPINE, hp, hn, MODE_DENT, 5, 0, -1, 2);
        skin_collapse();
        int plate_moved = 0, skin_in = 0;
        for (int v = pb; v < pb + 9; v++) { float x[3]; skin(&override_w[v], xpos[v], x); plate_moved += dist3(x, xpos[v]) > 0.01f; }
        for (int v = 0; v < NV; v++) { float x[3]; skin(&override_w[v], xpos[v], x); skin_in += x[0] < xpos[v][0] - 0.01f; }
        printf("dent layers: plate verts moved %d, skin verts pressed in %d\n", plate_moved, skin_in);
        modebad |= plate_moved || !skin_in;
        skin_restore(0);

        *(u64 *)(ld + LOD_SECTIONS) = (u64)sec_buf; *(int *)(ld + LOD_SECTIONS + 8) = 1;
        *(u64 *)(ld + LOD_POSITIONS + 0x28) = (u64)vpos; *(int *)(ld + LOD_NUM_VERTICES) = NV;
        *(u64 *)(sw + SW_DATA) = (u64)vw; *(int *)(sw + SW_NUM_VERTICES) = NV;
        cur_idx = idx; cur_nidx = &nidx;
    }
    int fitbad = modebad || corebad || np + 1 < 20 || strap || fa < 5.7f || fa > 6.3f || fb < 3.7f || fb > 4.3f || fcx < 0.8f || fcx > 1.2f;
    int fail = fitbad || !pending || bad || spanning || badsum || r1 != 2 || refinv[THIGH_HELP * 16] != 1;
    printf("%s\n", fail ? "FAIL" : "PASS");
    return fail;
}
