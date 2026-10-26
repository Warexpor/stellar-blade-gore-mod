// Linux harness for the weapon split ("e", weapon_split in sbslice.c) on a synthetic sword: a 100 cm square tube along
// x, its grip (0-30 cm) on GRIP, the blade on BLADE, a guard piece of its own on GRIP, and helper bones no vertex uses.
// The sword is posed turned and moved off its bind pose; a tilted plane through the blade splits it. Checks: each half
// keeps its side where it was, gives up the other (the blade's far side slid along the sword onto the plane, the grip
// and guard past it collapsed onto the plane point), stays whole when the sword moves on, and "x" puts the
// asset's matrices back. Run: ./test/run.sh weapon
#include "host.h"
static u64 ld_buf[0x900 / 8];
static unsigned short act_buf[64]; static int act_n;
int mem_readable(u64 p, u64 n)
{
    return (p >= (u64)ld_buf && p + n <= (u64)ld_buf + sizeof ld_buf) || (p >= (u64)act_buf && p + n <= (u64)(act_buf + act_n));
}
enum { ROOT, GRIP, BLADE, H1, H2, H3, H4, H5, H6, NB };
static int parent[NB] = { -1, ROOT, GRIP, BLADE, BLADE, GRIP, ROOT, BLADE, ROOT };
static float bonex[NB] = { 0, 0, 30, 60, 90, 10, 0, 50, 0 };
#define RINGS 21
#define NV (RINGS * 4 + 8)
static float vpos[NV][3];
static unsigned char vw[NV][8];
static u32 idx[RINGS * 24 + 36]; static int nidx;
static u64 sw_buf[32], sm_buf[128], rd_buf[4], lodptrs[1], ib_obj[1], ib_vt[16], sec_buf[0x200 / 8];
static u16 bonemap[NB];
static float space[NB * 12], refpose[NB * 12], refinv[NB * 16], refinv0[NB * 16];
static unsigned char binfo[NB * 0xc];
static unsigned char comp_a[0x2000], comp_b[0x2000];
static skin_info *ov[2]; static u64 ov_comp[2];
static int ib_num(u64 s) { (void)s; return nidx; }
static u32 ib_get(u64 s, u32 i) { (void)s; return idx[i]; }
static u64 st_get_buffer(u64 c, int l) { (void)c; (void)l; return (u64)sw_buf; }
static void st_set_override(u64 c, int l, const tarray *a)
{
    (void)l;
    int k = c == (u64)comp_a ? 0 : 1;
    free(ov[k]); ov[k] = malloc(sizeof(skin_info) * a->num); memcpy(ov[k], a->data, sizeof(skin_info) * a->num); ov_comp[k] = c;
}
static void st_release(u64 info) { (void)info; }
static void st_noop(u64 c) { (void)c; }
static u64 st_weak(u64 w) { (void)w; return 0; }
static void tramp(u64 at, void *fn) { unsigned char *p = (unsigned char *)at; p[0] = 0x48; p[1] = 0xb8; memcpy(p + 2, &fn, 8); p[10] = 0xff; p[11] = 0xe0; }
static void *gm_malloc(u64 self, u64 n, u32 al) { (void)self; (void)al; return calloc(1, n); }
static void gm_free(u64 self, void *p) { (void)self; free(p); }
static u64 gm_vt[16], gm_obj[2];

// the pose: every bone at its bind offset, the whole sword turned q about z and moved by off
static float q[4], off[3];
static void pose(void)
{
    for (int i = 0; i < NB; i++) {
        float *t = space + i * 12; memset(t, 0, 48);
        float b[3] = { bonex[i], 0, 0 }, r[3];
        quat_rot(q, b, r);
        memcpy(t, q, 16); t[4] = r[0] + off[0]; t[5] = r[1] + off[1]; t[6] = r[2] + off[2]; t[8] = t[9] = t[10] = 1;
    }
}
static void skin(const skin_info *o, const float *vp, float *x)
{
    cut_ctx c = { 0 }; c.nb = NB; c.binfo = binfo; c.refinv = refinv; c.space = space; c.nspace = NB;
    skin_point(&c, o, vp, x);
}
static float sd(const float *x, const float *p, const float *n) { return (x[0] - p[0]) * n[0] + (x[1] - p[1]) * n[1] + (x[2] - p[2]) * n[2]; }

int main(void)
{
    void *m = mmap(0, 0x7100000, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) { perror("mmap"); return 1; }
    exe = (u64)m;
    gm_vt[2] = (u64)gm_malloc; gm_vt[6] = (u64)gm_free; gm_obj[0] = (u64)gm_vt; *(u64 *)(exe + RVA_GMALLOC) = (u64)gm_obj;
    tramp(exe + RVA_GET_SKIN_WEIGHT_BUFFER, (void *)st_get_buffer);
    tramp(exe + RVA_SET_SKIN_WEIGHT_OVERRIDE, (void *)st_set_override);
    tramp(exe + RVA_MARK_RENDER_STATE_DIRTY, (void *)st_noop);
    tramp(exe + RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS, (void *)st_release);
    tramp(exe + RVA_WEAK_PTR_GET, (void *)st_weak);
    for (int i = 0; i < NB; i++) {
        float *r = refpose + i * 12; memset(r, 0, 48); r[3] = 1; r[4] = bonex[i] - (parent[i] >= 0 ? bonex[parent[i]] : 0); r[8] = r[9] = r[10] = 1;
        float *iv = refinv + i * 16; memset(iv, 0, 64); iv[0] = iv[5] = iv[10] = iv[15] = 1; iv[12] = -bonex[i];
        *(int *)(binfo + i * 0xc + 8) = parent[i];
        bonemap[i] = i;
    }
    // only ROOT, GRIP and BLADE in the section's map: the sinks must be borrowed
    int nmap = 3;
    memcpy(refinv0, refinv, sizeof refinv);
    // the tube: 4 vertices a ring (2 x 0.5 cm), rings every 5 cm; the guard: a box at x 25-28 on GRIP
    for (int r = 0; r < RINGS; r++) for (int s = 0; s < 4; s++) {
        int v = r * 4 + s; float x = r * 5.0f;
        vpos[v][0] = x; vpos[v][1] = s & 1 ? 1 : -1; vpos[v][2] = s & 2 ? 0.25f : -0.25f;
        memset(vw[v], 0, 8); vw[v][0] = x < 30 ? GRIP : BLADE; vw[v][4] = 255;
    }
    for (int r = 0; r + 1 < RINGS; r++) for (int s = 0; s < 4; s++) {
        static const int ring[4] = { 0, 1, 3, 2 };
        u32 a = r * 4 + ring[s], b = r * 4 + ring[(s + 1) % 4], c = a + 4, d = b + 4;
        idx[nidx++] = a; idx[nidx++] = c; idx[nidx++] = b; idx[nidx++] = b; idx[nidx++] = c; idx[nidx++] = d;
    }
    int gb = RINGS * 4;
    for (int k = 0; k < 8; k++) {
        vpos[gb + k][0] = k & 1 ? 28 : 25; vpos[gb + k][1] = k & 2 ? 4 : -4; vpos[gb + k][2] = k & 4 ? 1 : -1;
        memset(vw[gb + k], 0, 8); vw[gb + k][0] = GRIP; vw[gb + k][4] = 255;
    }
    for (int k = 0; k < 6; k++) { idx[nidx++] = gb; idx[nidx++] = gb + 1 + k % 7; idx[nidx++] = gb + 2 + k % 6; }
    unsigned char *sm = (unsigned char *)sm_buf, *ld = (unsigned char *)ld_buf, *sw = (unsigned char *)sw_buf, *sec = (unsigned char *)sec_buf;
    for (int k = 0; k < 2; k++) {
        unsigned char *c = k ? comp_b : comp_a;
        *(u64 *)(c + SC_SKELETAL_MESH) = (u64)sm_buf;
        *(u64 *)(c + SC_SPACE_BASES) = (u64)space; *(int *)(c + SC_SPACE_BASES + 8) = NB; *(int *)(c + SC_SPACE_READ) = 0;
        float *tw = (float *)(c + SC_TO_WORLD); tw[3] = 1; tw[8] = tw[9] = tw[10] = 1;
        static u64 lodinfo[2][0x48 / 8];
        *(u64 *)(c + SC_LOD_INFO) = (u64)lodinfo[k]; *(int *)(c + SC_LOD_INFO + 8) = 1; lodinfo[k][3] = 1;
    }
    *(u64 *)(sm + SM_RENDER_DATA) = (u64)rd_buf; rd_buf[0] = (u64)lodptrs; *(int *)((unsigned char *)rd_buf + 8) = 1; lodptrs[0] = (u64)ld;
    *(u64 *)(sm + SM_REF_BONE_INFO) = (u64)binfo; *(int *)(sm + SM_REF_BONE_INFO + 8) = NB;
    *(u64 *)(sm + SM_REF_BONE_POSE) = (u64)refpose; *(int *)(sm + SM_REF_BONE_POSE + 8) = NB;
    *(u64 *)(sm + SM_REF_BASES_INV) = (u64)refinv; *(int *)(sm + SM_REF_BASES_INV + 8) = NB;
    *(u64 *)(ld + LOD_SECTIONS) = (u64)sec; *(int *)(ld + LOD_SECTIONS + 8) = 1;
    ib_vt[0x58 / 8] = (u64)ib_num; ib_vt[0x68 / 8] = (u64)ib_get; ib_obj[0] = (u64)ib_vt;
    *(u64 *)(ld + LOD_INDICES) = (u64)ib_obj;
    *(u64 *)(ld + LOD_POSITIONS + 0x28) = (u64)vpos; *(u32 *)(ld + LOD_POSITIONS + 0x30) = 12;
    *(int *)(ld + LOD_NUM_VERTICES) = NV;
    // (the engine's BoneMap array: GMalloc'd, so a borrow may swap it)
    u16 *bm = gm_malloc(0, 64 * 2, 0); memcpy(bm, bonemap, nmap * 2);
    *(int *)(sec + SEC_BASE_VERTEX) = 0; *(u64 *)(sec + SEC_BONE_MAP) = (u64)bm; *(int *)(sec + SEC_BONE_MAP + 8) = nmap;
    *(int *)(sec + SEC_BONE_MAP + 12) = 64; *(int *)(sec + SEC_NUM_VERTICES) = NV;
    for (int i = 0; i < 3; i++) act_buf[act_n++] = (unsigned short)i;
    *(u64 *)(ld + 0x3a8) = (u64)act_buf; *(int *)(ld + 0x3a8 + 8) = act_n; *(int *)(ld + 0x3a8 + 12) = 64;
    sw[SW_VARIABLE] = 0; *(u32 *)(sw + SW_MAX_INFLUENCES) = 4; sw[SW_16BIT_INDEX] = 0; *(u64 *)(sw + SW_DATA) = (u64)vw; *(int *)(sw + SW_NUM_VERTICES) = NV;

    // the sword turned 30 degrees about z and moved; the plane through the blade at 60 cm, tilted 25 degrees
    q[2] = __builtin_sinf(0.2617994f); q[3] = __builtin_cosf(0.2617994f);
    off[0] = 10; off[1] = 20; off[2] = 5;
    pose();
    float p0[3] = { 60, 0, 0 }, n0[3] = { __builtin_cosf(0.4363323f), 0, __builtin_sinf(0.4363323f) }, pw[3], nw[3];
    quat_rot(q, p0, pw); pw[0] += off[0]; pw[1] += off[1]; pw[2] += off[2];
    quat_rot(q, n0, nw);
    float before[NV][3];
    skin_info orig[NV];
    for (int v = 0; v < NV; v++) {
        memset(&orig[v], 0, sizeof orig[v]);
        for (int i = 0; i < 4; i++) { orig[v].bones[i] = vw[v][i]; orig[v].weights[i] = vw[v][4 + i]; }
        skin(&orig[v], vpos[v], before[v]);
    }
    weapon_split((u64)comp_a, (u64)comp_b, 0, pw, nw);
    printf("%s\n", lastres);
    if (!ov[0] || !ov[1]) { printf("FAIL\n"); return 1; }
    printf("collapsed %d\n", skin_collapse());
    int bad = 0, flatbad = 0, gonebad = 0, nflat = 0, ngone = 0;
    for (int h = 0; h < 2; h++) {
        for (int v = 0; v < NV; v++) {
            float x[3]; skin(&ov[h][v], vpos[v], x);
            float d0 = sd(before[v], pw, nw), d = sd(x, pw, nw);
            int keep = h == 0 ? d0 >= 0 : d0 < 0;
            if (keep) { for (int k = 0; k < 3; k++) if (fabsf_(x[k] - before[v][k]) > 0.01f) { bad++; break; } continue; }
            if (fabsf_(d) > 0.01f) { bad++; continue; }
            // the blade's far side: slid along the sword onto the plane; the grip and guard: the plane point
            if (vw[v][0] == BLADE) {
                nflat++;
                float ux[3] = { 1, 0, 0 }, u[3]; quat_rot(q, ux, u);
                float un = u[0] * nw[0] + u[1] * nw[1] + u[2] * nw[2];
                for (int k = 0; k < 3; k++) if (fabsf_(x[k] - (before[v][k] - d0 / un * u[k])) > 0.01f) { flatbad++; break; }
            } else {
                ngone++;
                for (int k = 0; k < 3; k++) if (fabsf_(x[k] - pw[k]) > 0.01f) { gonebad++; break; }
            }
        }
    }
    printf("halves: %d off their side or moved, %d of %d flattened off their projection, %d of %d collapsed off the plane point\n",
           bad, flatbad, nflat, gonebad, ngone);
    // the sword moves on (turned and carried): each half's skin goes with it rigidly
    float q2[4] = { 0, __builtin_sinf(0.5f), 0, __builtin_cosf(0.5f) }, o2[3] = { 30, -40, 70 };
    int rigidbad = 0;
    for (int h = 0; h < 2; h++) {
        float x0[NV][3];
        for (int v = 0; v < NV; v++) skin(&ov[h][v], vpos[v], x0[v]);
        float qs[4], os[3]; memcpy(qs, q, 16); memcpy(os, off, 12);
        // compose: new = q2 * q, off rotated by q2 then + o2
        float nq[4] = { q2[3] * q[0] + q2[0] * q[3] + q2[1] * q[2] - q2[2] * q[1],
                        q2[3] * q[1] - q2[0] * q[2] + q2[1] * q[3] + q2[2] * q[0],
                        q2[3] * q[2] + q2[0] * q[1] - q2[1] * q[0] + q2[2] * q[3],
                        q2[3] * q[3] - q2[0] * q[0] - q2[1] * q[1] - q2[2] * q[2] }, ro[3];
        quat_rot(q2, off, ro);
        memcpy(q, nq, 16); off[0] = ro[0] + o2[0]; off[1] = ro[1] + o2[1]; off[2] = ro[2] + o2[2];
        pose();
        for (int v = 0; v < NV; v++) {
            float x[3], e[3]; skin(&ov[h][v], vpos[v], x);
            quat_rot(q2, x0[v], e); e[0] += o2[0]; e[1] += o2[1]; e[2] += o2[2];
            for (int k = 0; k < 3; k++) if (fabsf_(x[k] - e[k]) > 0.02f) { rigidbad++; break; }
        }
        memcpy(q, qs, 16); memcpy(off, os, 12); pose();
    }
    printf("moved on: %d vertices not carried rigidly\n", rigidbad);
    // a plane past the sword: nothing to split
    float far[3] = { pw[0] + 500 * nw[0], pw[1] + 500 * nw[1], pw[2] + 500 * nw[2] };
    weapon_split((u64)comp_a, (u64)comp_b, 0, far, nw);
    int missed = strstr(lastres, "err the plane misses it") != 0;
    printf("past it: %s\n", lastres);
    skin_clear((u64)comp_a, 0, 0);
    skin_clear((u64)comp_b, 0, 0);
    skin_restore(0);
    int restored = !memcmp(refinv, refinv0, sizeof refinv) && *(int *)(sec + SEC_BONE_MAP + 8) == nmap;
    printf("restored: %d\n", restored);
    // her grip eased (relax_hand, "F"): GRIP stands for the hand, BLADE bent 60 degrees about y off it. Fully eased
    // the blade's vertices sit as the bind pose has them against the grip; not eased, where the pose has them; "F"
    // alone puts the matrices back
    nsinks = 0;
    pose();
    {
        float bq[4] = { 0, __builtin_sinf(0.5235988f), 0, __builtin_cosf(0.5235988f) }, *tg = space + GRIP * 12, *tb = space + BLADE * 12;
        float wq[4], d[3] = { bonex[BLADE] - bonex[GRIP], 0, 0 }, rd[3];
        quat_mul(tg, bq, wq);
        quat_rot(tg, d, rd);
        memcpy(tb, wq, 16); tb[4] = tg[4] + rd[0]; tb[5] = tg[5] + rd[1]; tb[6] = tg[6] + rd[2];
        // (BLADE's children ride it)
        for (int i = 0; i < NB; i++) if (parent[i] == BLADE) {
            float *t = space + i * 12, dd[3] = { bonex[i] - bonex[BLADE], 0, 0 }, r[3];
            quat_rot(wq, dd, r);
            memcpy(t, wq, 16); t[4] = tb[4] + r[0]; t[5] = tb[5] + r[1]; t[6] = tb[6] + r[2];
        }
    }
    int relaxbad = 0;
    for (int pass = 0; pass < 2; pass++) {
        u64 f[3] = { (u64)comp_a, GRIP, pass ? 1000 : 0 };
        relax_cmd(f, 3);
        for (int v = 0; v < RINGS * 4; v++) {
            if (vw[v][0] != BLADE) continue;
            float x[3], e[3];
            skin(&orig[v], vpos[v], x);
            if (pass) {
                // rigid with the grip, as bound
                float l[3] = { vpos[v][0] - bonex[GRIP], vpos[v][1], vpos[v][2] }, r[3], *tg = space + GRIP * 12;
                quat_rot(tg, l, r); e[0] = tg[4] + r[0]; e[1] = tg[5] + r[1]; e[2] = tg[6] + r[2];
            } else {
                float l[3] = { vpos[v][0] - bonex[BLADE], vpos[v][1], vpos[v][2] }, r[3], *tb = space + BLADE * 12;
                quat_rot(tb, l, r); e[0] = tb[4] + r[0]; e[1] = tb[5] + r[1]; e[2] = tb[6] + r[2];
            }
            for (int k = 0; k < 3; k++) if (fabsf_(x[k] - e[k]) > 0.02f) { relaxbad++; break; }
        }
    }
    u64 none[1] = { 0 };
    relax_cmd(none, 1);
    int unrelaxed = !memcmp(refinv, refinv0, sizeof refinv);
    printf("grip eased: %d vertices off, put back %d\n", relaxbad, unrelaxed);
    // an arm grown back (regrow_limb, "Z"): GRIP stands for the upper arm, BLADE for the forearm, the sword posed as
    // above. At the start every vertex of theirs sits within REGROW_MIN of its reach from the grip's joint; halfway the
    // grip is grown further than the blade; at the end each sits where the pose has it; "Z" alone puts the matrices back
    int growbad = 0;
    float gp[3] = { space[GRIP * 12 + 4], space[GRIP * 12 + 5], space[GRIP * 12 + 6] };
    for (int pass = 0; pass < 3; pass++) {
        u64 f[5] = { (u64)comp_a, GRIP, BLADE, 0xffff, pass == 0 ? 0 : pass == 1 ? 500 : 1000 };
        regrow_cmd(f, 5);
        for (int v = 0; v < RINGS * 4; v++) {
            if (vw[v][0] != BLADE && vw[v][0] != GRIP) continue;
            float x[3], e[3], *tb = space + vw[v][0] * 12;
            float l[3] = { vpos[v][0] - bonex[vw[v][0]], vpos[v][1], vpos[v][2] }, r[3];
            skin(&orig[v], vpos[v], x);
            quat_rot(tb, l, r); e[0] = tb[4] + r[0]; e[1] = tb[5] + r[1]; e[2] = tb[6] + r[2];
            float dx = 0, de = 0;
            for (int k = 0; k < 3; k++) { dx += (x[k] - gp[k]) * (x[k] - gp[k]); de += (e[k] - gp[k]) * (e[k] - gp[k]); }
            dx = __builtin_sqrtf(dx); de = __builtin_sqrtf(de);
            if (pass == 0 && dx > de * REGROW_MIN + 0.02f) growbad++;
            // (halfway: the grip's own vertices out to 0.5 + of their reach, the blade's less far than the pose has them)
            if (pass == 1 && vw[v][0] == GRIP && (dx < de * 0.5f - 0.02f || dx > de + 0.02f)) growbad++;
            if (pass == 1 && vw[v][0] == BLADE && dx > de - 0.5f) growbad++;
            if (pass == 2) for (int k = 0; k < 3; k++) if (fabsf_(x[k] - e[k]) > 0.02f) { growbad++; break; }
        }
    }
    regrow_cmd(none, 1);
    int ungrown = !memcmp(refinv, refinv0, sizeof refinv);
    printf("arm grown back: %d vertices off, put back %d\n", growbad, ungrown);
    int fail = bad || flatbad || gonebad || !nflat || !ngone || rigidbad || !missed || !restored || relaxbad || !unrelaxed
        || growbad || !ungrown;
    printf("%s\n", fail ? "FAIL" : "PASS");
    return fail;
}
