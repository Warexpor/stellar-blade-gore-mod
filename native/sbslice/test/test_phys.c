// Linux harness for the outfit physics commands (sbslice.c "b", "t" and "j", physfix.lua's runtime fix): a bone chain's
// bind pose against a matrix composition of its own, and CollisionDisableTable rewritten in a made-up physics asset
// laid out as the engine's TMap<FRigidBodyIndexPair, bool>, then looked up the engine's way. Run: ./test/run.sh phys
#include "host.h"
#define sqrt __builtin_sqrt
#define fabs __builtin_fabs
static double fmax(double a, double b) { return a > b ? a : b; }

// what mem_readable may say yes to: the made-up asset and the arrays given out
static struct { u64 p, n; } rd[64]; static int nrd;
static void readable_add(const void *p, u64 n) { rd[nrd].p = (u64)p; rd[nrd++].n = n; }
int mem_readable(u64 p, u64 n)
{
    for (int i = 0; i < nrd; i++) if (p >= rd[i].p && p + n <= rd[i].p + rd[i].n) return 1;
    return 0;
}
// (the memory scans of stats.c, for the Y and M commands: nothing to scan here)
int mem_scan(u64 v, u64 *h, int m) { (void)v; (void)h; (void)m; return 0; }
int mem_scan32(u32 v, u64 *h, int m) { (void)v; (void)h; (void)m; return 0; }
int mem_scan_set(u64 a, int e, u64 *h, int m) { (void)a; (void)e; (void)h; (void)m; return 0; }
static void *gm_out[256]; static int ngm, nfreed;
static void *gm_malloc(u64 self, u64 n, u32 al) { (void)self; (void)al; void *p = calloc(1, n); gm_out[ngm++] = p; readable_add(p, n); return p; }
static void gm_free(u64 self, void *p) { (void)self; for (int i = 0; i < ngm; i++) if (gm_out[i] == p) { gm_out[i] = 0; nfreed++; return; } fprintf(stderr, "FAIL: GMalloc freed %p it never gave\n", p); _exit(1); }
static u64 gm_vt[16], gm_obj[2];
static int fails;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL: " __VA_ARGS__); printf("\n"); fails++; } } while (0)
static void cmd(const char *s)
{
    static u16 w[16384]; int n = 0;
    while (s[n]) { w[n] = (u16)s[n]; n++; }
    w[n] = 0; // an FString counts its terminator
    unsigned char p[0x40] = { 0 }, stack[0x40] = { 0 };
    *(u16 **)(p + 0x18) = w; *(int *)(p + 0x20) = n + 1;
    *(unsigned char **)(stack + 0x28) = p;
    lastres[0] = 0;
    exec_slice(0, stack, 0);
}

// ---- bind pose ----
static void qmul_d(const double *a, const double *b, double *o)
{
    o[0] = a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1];
    o[1] = a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0];
    o[2] = a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3];
    o[3] = a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2];
}
static void qmat(const double *q, double m[3][3]) // rotation matrix of a unit quaternion
{
    double x = q[0], y = q[1], z = q[2], w = q[3];
    m[0][0] = 1 - 2 * (y * y + z * z); m[0][1] = 2 * (x * y - z * w); m[0][2] = 2 * (x * z + y * w);
    m[1][0] = 2 * (x * y + z * w); m[1][1] = 1 - 2 * (x * x + z * z); m[1][2] = 2 * (y * z - x * w);
    m[2][0] = 2 * (x * z - y * w); m[2][1] = 2 * (y * z + x * w); m[2][2] = 1 - 2 * (x * x + y * y);
}
static void test_bind(void)
{
    enum { NB = 4 };
    static int par[NB] = { -1, 0, 1, 1 };
    static double lq[NB][4] = { { 0, 0, 0.7071068, 0.7071068 }, { 0.1, -0.2, 0.3, 0 }, { -0.4, 0.1, 0.05, 0 }, { 0, 0.6, 0, 0.8 } };
    static double lt[NB][3] = { { 1, 2, 3 }, { 10, 0, 0 }, { 0, 25, -4 }, { 3, -7, 12 } };
    static unsigned char info[NB * 0xc]; static float pose[NB * 12]; static u64 sm[0x400 / 8];
    for (int i = 0; i < NB; i++) {
        double *q = lq[i];
        if (q[3] == 0) q[3] = sqrt(1 - q[0] * q[0] - q[1] * q[1] - q[2] * q[2]);
        *(int *)(info + i * 0xc + 8) = par[i];
        for (int k = 0; k < 4; k++) pose[i * 12 + k] = (float)q[k];
        for (int k = 0; k < 3; k++) pose[i * 12 + 4 + k] = (float)lt[i][k];
        pose[i * 12 + 8] = pose[i * 12 + 9] = pose[i * 12 + 10] = 1;
    }
    unsigned char *s = (unsigned char *)sm;
    *(u64 *)(s + SM_REF_BONE_INFO) = (u64)info; *(int *)(s + SM_REF_BONE_INFO + 8) = NB;
    *(u64 *)(s + SM_REF_BONE_POSE) = (u64)pose; *(int *)(s + SM_REF_BONE_POSE + 8) = NB;
    char c[64]; snprintf(c, sizeof c, "b%llx,2,3,0,9", (unsigned long long)(u64)sm);
    cmd(c);
    // the reference: matrices, from the floats the DLL reads
    double R[NB][4], T[NB][3];
    for (int i = 0; i < NB; i++) {
        double q[4] = { pose[i * 12], pose[i * 12 + 1], pose[i * 12 + 2], pose[i * 12 + 3] }, t[3] = { pose[i * 12 + 4], pose[i * 12 + 5], pose[i * 12 + 6] };
        if (par[i] < 0) { memcpy(R[i], q, sizeof q); memcpy(T[i], t, sizeof t); continue; }
        double m[3][3]; qmat(R[par[i]], m);
        qmul_d(R[par[i]], q, R[i]);
        for (int k = 0; k < 3; k++) T[i][k] = T[par[i]][k] + m[k][0] * t[0] + m[k][1] * t[1] + m[k][2] * t[2];
    }
    const char *p = lastres;
    CHECK(!strncmp(p, "ok ", 3), "bind: %s", lastres);
    int want[4] = { 2, 3, 0, 9 };
    for (int j = 0; j < 4 && !strncmp(lastres, "ok ", 3); j++) {
        p += j ? 1 : 3;
        int b = (int)strtol(p, (char **)&p, 10);
        CHECK(b == want[j], "bind: bone %d answered as %d", want[j], b);
        if (want[j] >= NB) { CHECK(!strncmp(p, " -", 2), "bind: bone %d isn't there but got %s", b, p); p += 2; continue; }
        double v[7], e = 0;
        for (int k = 0; k < 7; k++) v[k] = strtod(p, (char **)&p);
        for (int k = 0; k < 4; k++) e = fmax(e, fabs(v[k] - R[b][k]));
        for (int k = 0; k < 3; k++) e = fmax(e, fabs(v[4 + k] - T[b][k]) / 100);
        CHECK(e < 2e-6, "bind: bone %d off by %g", b, e);
    }
    printf("bind: %s\n", fails ? lastres : "4 bones as composed");
}

// ---- collision table ----
#define AT 0x1a8       // where the made-up asset keeps its table
#define DECOY 0x150    // a TMap<FName, int32> before it (BodySetupIndexMap): 20 byte elements too
#define AFTER 0x300    // a table past its end, in the next asset in memory
typedef struct { int a, b, v, next, hidx; } elem;
static void make_set(unsigned char *s, const int (*pairs)[2], int n, int variant, int nbodies, int namemap)
{
    u32 hs = hash_buckets((u32)n), words = ((u32)n + 31) / 32;
    // from GMalloc, as the engine's own: the rewrite gives them back to it
    elem *e = gm_malloc(0, (u64)n * sizeof *e, 0); int *h = hs > 1 ? gm_malloc(0, hs * 4, 0) : calloc(1, 4);
    u32 *bits = words > 4 ? gm_malloc(0, words * 4, 0) : calloc(4, 4);
    for (u32 i = 0; i < hs; i++) h[i] = -1;
    for (int i = 0; i < n; i++) {
        e[i].a = namemap ? 4000 + i * 7 : pairs[i][0]; e[i].b = namemap ? 0 : pairs[i][1]; e[i].v = namemap ? i : 0;
        u32 hh = namemap ? (u32)e[i].a : pair_hash(variant, e[i].a, e[i].b);
        e[i].hidx = (int)(hh & (hs - 1)); e[i].next = h[e[i].hidx]; h[e[i].hidx] = i;
        bits[i >> 5] |= 1u << (i & 31);
    }
    (void)nbodies;
    *(u64 *)s = (u64)e; *(int *)(s + 8) = n; *(int *)(s + 12) = n;
    if (words <= 4) { memcpy(s + 16, bits, 16); free(bits); } else *(u64 *)(s + 32) = (u64)bits;
    *(int *)(s + 40) = n; *(int *)(s + 44) = (int)((words <= 4 ? 4 : words) * 32);
    *(int *)(s + 48) = -1; *(int *)(s + 52) = 0;
    if (hs > 1) *(u64 *)(s + 64) = (u64)h; else { *(int *)(s + 56) = h[0]; free(h); }
    *(int *)(s + 72) = (int)hs;
}
// TSet::FindId as the engine does it
static int find(const unsigned char *s, int variant, int a, int b)
{
    int hs = *(int *)(s + 72);
    const int *h = hs > 1 ? *(int **)(s + 64) : (const int *)(s + 56);
    const elem *e = *(elem **)s;
    for (int id = h[pair_hash(variant, a, b) & (u32)(hs - 1)]; id != -1; id = e[id].next)
        if (e[id].a == a && e[id].b == b) return id;
    return -1;
}
static void test_table(int variant, int nbodies, int corrupt)
{
    static unsigned char asset[0x400 + 80];
    memset(asset, 0, sizeof asset); nrd = 0; readable_add(asset, sizeof asset);
    int (*pairs)[2] = calloc(nbodies * 2, sizeof *pairs), n = 0;
    for (int i = 0; i + 1 < nbodies; i++) { pairs[n][0] = i; pairs[n++][1] = i + 1; }        // neighbours, as PhAT has them
    for (int i = 0; i + 3 < nbodies; i += 3) { pairs[n][0] = i; pairs[n++][1] = i + 3; }
    make_set(asset + DECOY, 0, 12, 0, nbodies, 1);
    make_set(asset + AT, (const int (*)[2])pairs, n, variant, nbodies, 0);
    make_set(asset + AFTER, (const int (*)[2])pairs, n / 2, variant, nbodies, 0); // the next asset's, past this one's end
    if (corrupt) ((elem *)*(u64 *)(asset + AT))[1].hidx ^= 1;
    u64 olddata = *(u64 *)(asset + AT);
    int ngm0 = ngm, nf0 = nfreed, owned = 1 + (*(u64 *)(asset + AT + 32) != 0) + (*(int *)(asset + AT + 72) > 1);
    if (!corrupt) {
        // the pairs it lets collide, read before it is rewritten: every pair not in it, nothing changed
        char l[64]; snprintf(l, sizeof l, "L%llx,%x", (unsigned long long)(u64)asset, nbodies);
        cmd(l);
        int want = nbodies * (nbodies - 1) / 2 - n, got = 0, wrong = 0;
        CHECK(!strncmp(lastres, "ok colliding ", 13) && atoi(lastres + 13) == want, "colliding: %.80s, want %d", lastres, want);
        for (const char *q = strchr(lastres + 13, ' '); q; q = strchr(q + 1, ' ')) {
            int a = (int)strtol(q + 1, 0, 16), b = (int)strtol(strchr(q, ',') + 1, 0, 16);
            got++;
            if (!(a < b && b < nbodies) || find(asset + AT, variant, a, b) >= 0) wrong++;
        }
        CHECK(got == want && !wrong && *(u64 *)(asset + AT) == olddata, "colliding: %d pairs listed, %d wrong, want %d", got, wrong, want);
        printf("colliding (%d bodies): %d pairs listed, none in the table\n", nbodies, got);
    }
    char c[64]; snprintf(c, sizeof c, "t%llx,%x", (unsigned long long)(u64)asset, nbodies);
    cmd(c);
    int m = nbodies * (nbodies - 1) / 2;
    if (corrupt) {
        CHECK(!strncmp(lastres, "err no table", 12) && *(u64 *)(asset + AT) == olddata, "a table out of its buckets was taken: %s", lastres);
        printf("table (an element out of its bucket): %s, left alone\n", lastres);
        return;
    }
    CHECK(!strncmp(lastres, "ok table +", 10), "table: %s", lastres);
    CHECK(strtol(lastres + 10, 0, 10) == AT, "table found at the wrong place: %s", lastres);
    if (strncmp(lastres, "ok table +", 10)) return;
    int missing = 0, extra = *(int *)(asset + AT + 8) != m;
    for (int a = 0; a < nbodies; a++) for (int b = a + 1; b < nbodies; b++) missing += find(asset + AT, variant, a, b) < 0;
    u64 bits = *(u64 *)(asset + AT + 32);
    for (int i = 0; i < m; i++) missing += !(((u32 *)bits)[i >> 5] >> (i & 31) & 1);
    CHECK(!missing && !extra, "table: %d pairs not found, size %d of %d", missing, *(int *)(asset + AT + 8), m);
    CHECK(*(int *)(asset + AT + 72) == (int)hash_buckets((u32)m), "hash size %d", *(int *)(asset + AT + 72));
    CHECK(ngm - ngm0 == 3, "table: %d arrays from GMalloc, want 3", ngm - ngm0);
    CHECK(*(int *)(asset + DECOY + 8) == 12, "the decoy map changed");
    CHECK(nfreed - nf0 == owned, "table: %d old arrays given back, want %d", nfreed - nf0, owned);
    printf("table (%d bodies, hash variant %d): %s; every one of %d pairs found\n", nbodies, variant, lastres, m);
    cmd(c);
    CHECK(strstr(lastres, " already") != 0 && ngm - ngm0 == 3, "table again: %s", lastres);
    // pairs left colliding (her arms and her chest): out of the table, every other pair in it, rewritten each time
    // (a repeat, an out-of-range and a reversed pair don't count)
    if (!variant && nbodies >= 20) {
        char k[160];
        snprintf(k, sizeof k, "t%llx,%x,3,11,5,12,3,11,0,%x,9,2", (unsigned long long)(u64)asset, nbodies, nbodies);
        cmd(k);
        CHECK(strstr(lastres, " colliding 2") != 0 && *(int *)(asset + AT + 8) == m - 2, "table, two pairs colliding: %s", lastres);
        int bad = 0;
        for (int a = 0; a < nbodies; a++) for (int b = a + 1; b < nbodies; b++)
            bad += (find(asset + AT, variant, a, b) < 0) != ((a == 3 && b == 17) || (a == 5 && b == 18));
        CHECK(!bad, "table, two pairs colliding: %d pairs wrong", bad);
        cmd(k);
        CHECK(strstr(lastres, " already") == 0 && *(int *)(asset + AT + 8) == m - 2, "table, colliding again: %s", lastres);
        cmd(c);
        CHECK(*(int *)(asset + AT + 8) == m, "table, every pair back: %s", lastres);
        printf("table, two pairs left colliding: %s\n", lastres);
        // more pairs than the first limit (64): every pair of body 0 and of body 1 with the rest (a cut piece's)
        int np = 0;
        char *big = malloc(16 * 1024), *o = big + sprintf(big, "t%llx,%x", (unsigned long long)(u64)asset, nbodies);
        for (int a = 0; a < 2; a++) for (int b = a + 1; b < nbodies && np < 120; b++, np++) o += sprintf(o, ",%x,%x", a, b);
        cmd(big);
        CHECK(*(int *)(asset + AT + 8) == m - np, "table, %d pairs colliding: %s", np, lastres);
        bad = 0;
        for (int a = 0; a < nbodies; a++) for (int b = a + 1; b < nbodies; b++) bad += (find(asset + AT, variant, a, b) < 0) != (a < 2);
        CHECK(!bad || np < 2 * nbodies - 3, "table, %d pairs colliding: %d pairs wrong", np, bad);
        cmd(c);
        CHECK(*(int *)(asset + AT + 8) == m, "table, every pair back after %d: %s", np, lastres);
        printf("table, %d pairs left colliding: ok\n", np);
        free(big);
    }
    free(pairs);
}

// ---- joints appended to ConstraintSetup: the TArray found by its length and first element, a decoy of the same
// length beside it ----
static void test_joints(void)
{
    static unsigned char asset[0x200];
    memset(asset, 0, sizeof asset); nrd = 0; readable_add(asset, sizeof asset);
    u64 *decoy = gm_malloc(0, 3 * 8, 0), *have = gm_malloc(0, 3 * 8, 0);
    for (int i = 0; i < 3; i++) { decoy[i] = 0x7000 + i * 8; have[i] = 0x50000 + i * 0x100; }
    *(u64 **)(asset + 0x48) = decoy; *(int *)(asset + 0x50) = 3; *(int *)(asset + 0x54) = 3;
    *(u64 **)(asset + 0x68) = have; *(int *)(asset + 0x70) = 3; *(int *)(asset + 0x74) = 4;
    int ngm0 = ngm, nf0 = nfreed;
    char c[128]; snprintf(c, sizeof c, "j%llx,3,50000,90000,90100", (unsigned long long)(u64)asset);
    cmd(c);
    CHECK(!strcmp(lastres, "ok joints +104 3 -> 5"), "joints: %s", lastres);
    u64 *now = *(u64 **)(asset + 0x68);
    CHECK(*(int *)(asset + 0x70) == 5 && *(int *)(asset + 0x74) == 5 && now != have && now[0] == 0x50000 && now[2] == 0x50200
          && now[3] == 0x90000 && now[4] == 0x90100, "joints: the array reads %d of %d", *(int *)(asset + 0x70), *(int *)(asset + 0x74));
    CHECK(*(u64 **)(asset + 0x48) == decoy && *(int *)(asset + 0x50) == 3, "joints: the decoy changed");
    CHECK(ngm - ngm0 == 1 && nfreed - nf0 == 1, "joints: %d arrays from GMalloc, %d given back", ngm - ngm0, nfreed - nf0);
    printf("joints: %s\n", lastres);
    snprintf(c, sizeof c, "j%llx,4,50000,90000", (unsigned long long)(u64)asset); // a count it doesn't have
    cmd(c);
    CHECK(!strncmp(lastres, "err no joint array", 18) && *(int *)(asset + 0x70) == 5, "joints, wrong count: %s", lastres);
}

// ---- a data table row's field ("d"): a made-up UDataTable, its RowMap's third slot free ----
static void test_rows(void)
{
    static u64 dt[0x80 / 8], rowstruct[4];
    static unsigned char rows[3][0x200];
    static u32 elems[4][6]; // FName (index, number), row pointer, hash links
    static u32 flags[1] = { 0xb }; // slots 0, 1, 3 in use
    u32 names[4][2] = { { 11, 0 }, { 22, 0 }, { 99, 0 }, { 22, 3 } };
    for (int i = 0; i < 4; i++) {
        elems[i][0] = names[i][0]; elems[i][1] = names[i][1];
        *(u64 *)&elems[i][2] = i == 2 ? 0 : (u64)rows[i == 3 ? 2 : i];
    }
    for (int i = 0; i < 3; i++) *(float *)(rows[i] + 0x10c) = 1.0f + i;
    dt[0x28 / 8] = (u64)rowstruct;
    unsigned char *s = (unsigned char *)dt + 0x30;
    *(u64 *)s = (u64)elems; *(int *)(s + 8) = 4; *(int *)(s + 12) = 4;
    *(u32 *)(s + 16) = flags[0]; *(int *)(s + 40) = 4; *(int *)(s + 44) = 128;
    readable_add(dt, sizeof dt); readable_add(elems, sizeof elems); readable_add(rows, sizeof rows);
    char c[128];
    float v = 100000.0f; u32 bits; memcpy(&bits, &v, 4);
    snprintf(c, sizeof c, "d%llx,%llx,16,3,10c,%x", (unsigned long long)(u64)dt, (unsigned long long)(u64)rowstruct, bits);
    cmd(c);
    CHECK(!strncmp(lastres, "ok row ", 7) && *(float *)(rows[2] + 0x10c) == 100000.0f && *(float *)(rows[1] + 0x10c) == 2.0f,
          "rows: write: %s", lastres);
    printf("rows: %s\n", lastres);
    snprintf(c, sizeof c, "d%llx,%llx,16,0,10c", (unsigned long long)(u64)dt, (unsigned long long)(u64)rowstruct); // read only
    cmd(c);
    CHECK(!strncmp(lastres, "ok row ", 7) && *(float *)(rows[1] + 0x10c) == 2.0f && strstr(lastres, "0000000040000000 0000000040000000"),
          "rows: read: %s", lastres);
    snprintf(c, sizeof c, "d%llx,%llx,63,0,10c,0", (unsigned long long)(u64)dt, (unsigned long long)(u64)rowstruct); // a freed slot's name
    cmd(c);
    CHECK(!strcmp(lastres, "err no such row"), "rows: free slot: %s", lastres);
    snprintf(c, sizeof c, "d%llx,%llx,b,0,10c,0", (unsigned long long)(u64)dt, (unsigned long long)(u64)rows); // another struct
    cmd(c);
    CHECK(!strcmp(lastres, "err not its row struct") && *(float *)(rows[0] + 0x10c) == 1.0f, "rows: wrong struct: %s", lastres);
}

int main(void)
{
    void *m = mmap(0, 0x7100000, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) { perror("mmap"); return 1; }
    exe = (u64)m;
    gm_vt[2] = (u64)gm_malloc; gm_vt[6] = (u64)gm_free; gm_obj[0] = (u64)gm_vt; *(u64 *)(exe + RVA_GMALLOC) = (u64)gm_obj;
    test_bind();
    test_table(0, 60, 0);
    test_table(0, 33, 0);   // another asset: at the offset learned
    known_at = -1;          // (a game with the other hash, from scratch)
    test_table(1, 23, 0);
    test_table(0, 40, 1);
    test_joints();
    test_rows();
    printf("%s\n", fails ? "FAIL" : "PASS");
    return fails != 0;
}
