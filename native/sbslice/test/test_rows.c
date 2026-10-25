// Linux harness for the data table row commands (D, N, A in sbslice.c) on a made-up UDataTable: a row map of four
// rows (TSet layout and FName hash as UE 4.26's, hash size 8), rows with an FString, a TArray<FName> and a TArray of structs holding
// an FString. Checks: A adds a copy of a row (its heap fields in buffers of its own) that the hash finds, into a full
// sparse array and into a free slot; A on a name already there answers exists; D sets an FString; N swaps names in a
// TArray<FName>; M adds a new row to the game's alias -> ID and ID -> alias maps (int keys hashed by value), checked
// against the table first. Run: ./test/run.sh rows
#include "host.h"
int mem_readable(u64 p, u64 n) { (void)n; return p >= 0x10000; }
int mem_scan(u64 v, u64 *h, int m) { (void)v; (void)h; (void)m; return 0; }
int mem_scan32(u32 v, u64 *h, int m) { (void)v; (void)h; (void)m; return 0; }
int mem_scan_set(u64 a, int e, u64 *h, int m) { (void)a; (void)e; (void)h; (void)m; return 0; }
static void *gm_malloc(u64 self, u64 n, u32 al) { (void)self; (void)al; return calloc(1, n); }
static void gm_free(u64 self, void *p) { (void)self; free(p); }
static u64 gm_vt[16], gm_obj[2];

#define RS_SIZE 0x40
typedef struct { u64 vt; u16 *str; int sn, sm; u32 *names; int nn, nm; float life; u32 id; unsigned char *ends; int en, em; } row_t;
typedef struct { u32 idx, num; u64 row; int next, hidx; } elem_t;
static unsigned char table[0x100], rs[0xa0];
static int fails;
static void check(int ok, const char *what) { if (!ok) { printf("FAIL %s\n", what); fails++; } }
static void send(void (*fn)(const u16 *, int), const char *s)
{
    static u16 w[512];
    int n = 0;
    for (; s[n]; n++) w[n] = (u16)s[n];
    fn(w, n);
}
static u16 *wstr(const char *s) { int n = (int)strlen(s); u16 *w = calloc(n + 1, 2); for (int i = 0; i < n; i++) w[i] = (u16)s[i]; return w; }
static int weq(const u16 *w, const char *s) { for (int i = 0; s[i]; i++) if (w[i] != (u16)s[i]) return 0; return w[strlen(s)] == 0; }
static row_t *mkrow(u32 id, const char *str, u32 nm)
{
    row_t *r = calloc(1, RS_SIZE);
    r->vt = 0x1234; r->id = id; r->life = 1.0f;
    r->str = wstr(str); r->sn = r->sm = (int)strlen(str) + 1;
    r->names = calloc(2, 8); r->names[0] = nm; r->names[2] = 77; r->nn = r->nm = 2;
    r->ends = calloc(1, 0x18); *(u16 **)(r->ends + 8) = wstr("end"); *(int *)(r->ends + 16) = *(int *)(r->ends + 20) = 4;
    r->en = r->em = 1;
    return r;
}
static u64 *S64(int o) { return (u64 *)(table + 0x30 + o); }
static int *S32(int o) { return (int *)(table + 0x30 + o); }
// the row the hash finds for a name, as TSet::FindId walks it
static row_t *find(u32 idx, u32 num)
{
    int *hash = *S64(64) ? (int *)*S64(64) : S32(56);
    elem_t *e = (elem_t *)*S64(0);
    for (int i = hash[fname_hash(idx, num) & (*S32(72) - 1)]; i >= 0; i = e[i].next)
        if (e[i].idx == idx && e[i].num == num) return (row_t *)e[i].row;
    return 0;
}

int main(void)
{
    void *m = mmap(0, 0x7100000, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) { perror("mmap"); return 1; }
    exe = (u64)m;
    gm_vt[2] = (u64)gm_malloc; gm_vt[6] = (u64)gm_free; gm_obj[0] = (u64)gm_vt; *(u64 *)(exe + RVA_GMALLOC) = (u64)gm_obj;
    // the row struct: PropertiesSize at +0x58, alignment after it (and a decoy int far off the size)
    *(int *)(rs + 0x50) = 7; *(int *)(rs + 0x58) = RS_SIZE; *(int *)(rs + 0x5c) = 8;
    *(u64 *)(table + DT_ROWSTRUCT) = (u64)rs;
    // four rows, names 10..13 (number 0), packed full (num == max), heap bits
    int n = 4;
    elem_t *e = calloc(n, sizeof(elem_t));
    u32 *bits = calloc(1, 4);
    int *hash = calloc(8, 4);
    for (int i = 0; i < 8; i++) hash[i] = -1;
    for (int i = 0; i < n; i++) {
        e[i].idx = 10 + i; e[i].num = 0; e[i].row = (u64)mkrow(100 + i, "Show/A", 50 + i);
        e[i].hidx = (int)(fname_hash(e[i].idx, e[i].num) & 7); e[i].next = hash[e[i].hidx]; hash[e[i].hidx] = i;
        bits[0] |= 1u << i;
    }
    *S64(0) = (u64)e; *S32(8) = n; *S32(12) = n;
    *S64(32) = (u64)bits; *S32(40) = n; *S32(44) = 32;
    *S32(48) = -1; *S32(52) = 0;
    *S64(64) = (u64)hash; *S32(72) = 8;
    char cmd[256];
    // a copy of row 11 as name 20 (number 0): heap fields FString @8, TArray<FName> @0x18, TArray<struct> @0x30 with
    // an FString at +8 in each 0x18-byte element
    snprintf(cmd, sizeof cmd, "%llx,%llx,b,0,14,0,3c;8:2,18:8,30:18:8", (unsigned long long)(u64)table, (unsigned long long)(u64)rs);
    send(row_add_cmd, cmd);
    check(!strncmp(lastres, "ok row added ", 13), lastres);
    row_t *src = find(11, 0), *nr = find(0x14, 0);
    check(src && nr && nr != src, "the new row is found by its name");
    if (nr && src) {
        check(nr->id == 101 && nr->vt == 0x1234 && nr->life == 1.0f, "the copy has the source's plain fields");
        check(nr->str != src->str && weq(nr->str, "Show/A"), "FString copied into a buffer of its own");
        check(nr->names != src->names && nr->names[0] == 51 && nr->names[2] == 77 && nr->nn == 2, "TArray<FName> copied");
        check(nr->ends != src->ends && *(u16 **)(nr->ends + 8) != *(u16 **)(src->ends + 8) && weq(*(u16 **)(nr->ends + 8), "end"), "FStrings in array elements copied");
    }
    for (int i = 0; i < n; i++) check(find(10 + i, 0) != 0, "the old rows still found");
    check(*S32(8) == 5 && *S32(40) == 5, "sparse array and bits grown by one");
    // again: exists
    send(row_add_cmd, cmd);
    check(!strncmp(lastres, "ok row exists ", 14), lastres);
    // a free slot: element 2 freed (as TSparseArray::RemoveAt leaves it), then name 21 added into it
    elem_t *ed = (elem_t *)*S64(0);
    u32 *bd = (u32 *)*S64(32);
    int h2 = ed[2].hidx;
    // unlink 12 from its bucket
    { int *hh = (int *)*S64(64); int *pp = &hh[h2]; while (*pp != 2) pp = &ed[*pp].next; *pp = ed[2].next; }
    bd[0] &= ~(1u << 2);
    *(int *)&ed[2] = -1; *((int *)&ed[2] + 1) = -1;
    *S32(48) = 2; *S32(52) = 1;
    snprintf(cmd, sizeof cmd, "%llx,%llx,a,0,15,0,3c;8:2,18:8,30:18:8", (unsigned long long)(u64)table, (unsigned long long)(u64)rs);
    send(row_add_cmd, cmd);
    check(!strncmp(lastres, "ok row added ", 13), lastres);
    check(*S32(8) == 5 && *S32(52) == 0 && *S32(48) == -1, "the free slot taken");
    check(find(0x15, 0) && find(0x15, 0)->id == 100, "the row in the free slot found");
    check(find(12, 0) == 0, "the freed row gone");
    // a row map whose hash isn't index + number: refused
    int keep = ed[0].hidx;
    ed[0].hidx = (keep + 1) & 7;
    snprintf(cmd, sizeof cmd, "%llx,%llx,a,0,16,0,3c;8:2", (unsigned long long)(u64)table, (unsigned long long)(u64)rs);
    send(row_add_cmd, cmd);
    check(!strncmp(lastres, "err row map hash differs", 24), lastres);
    ed[0].hidx = keep;
    // D: the FString of row 13 set, then set again (same)
    snprintf(cmd, sizeof cmd, "%llx,%llx,d,0,8;CH_P_EVE_01/Ragdoll/EveRD_Step2", (unsigned long long)(u64)table, (unsigned long long)(u64)rs);
    send(row_str_cmd, cmd);
    check(!strcmp(lastres, "ok str set") && weq(find(13, 0)->str, "CH_P_EVE_01/Ragdoll/EveRD_Step2") && find(13, 0)->sn == 32, lastres);
    send(row_str_cmd, cmd);
    check(!strcmp(lastres, "ok str same"), lastres);
    // N: name 53 in row 13's array becomes 0x14
    snprintf(cmd, sizeof cmd, "%llx,%llx,d,0,18,35,0,14,0", (unsigned long long)(u64)table, (unsigned long long)(u64)rs);
    send(row_names_cmd, cmd);
    check(!strcmp(lastres, "ok names 1 of 2") && find(13, 0)->names[0] == 0x14 && find(13, 0)->names[2] == 77, lastres);
    // a row struct that isn't the table's
    snprintf(cmd, sizeof cmd, "%llx,%llx,d,0,8;x", (unsigned long long)(u64)table, (unsigned long long)(u64)rs + 8);
    send(row_str_cmd, cmd);
    check(!strcmp(lastres, "err not its row struct"), lastres);
    // M: the game's alias -> ID (FName key, int) and ID -> alias (int key, FName) maps, elements of 20, hash size 8
    {
        typedef struct __attribute__((packed)) { u32 idx, num; int id, next, hidx; } aelem_t;
        typedef struct __attribute__((packed)) { int id; u32 idx, num; int next, hidx; } ielem_t;
        static unsigned char am[80], im[80];
        aelem_t *ae = calloc(4, sizeof *ae);
        ielem_t *ie = calloc(4, sizeof *ie);
        int *ah = calloc(8, 4), *ih = calloc(8, 4);
        u32 *ab = calloc(1, 4), *ib = calloc(1, 4);
        for (int i = 0; i < 8; i++) ah[i] = ih[i] = -1;
        u32 nm4[4] = { 10, 11, 13, 0x15 };
        for (int i = 0; i < 4; i++) {
            int id = (int)find(nm4[i], 0)->id;
            ae[i].idx = nm4[i]; ae[i].id = id; ae[i].hidx = (int)(fname_hash(nm4[i], 0) & 7); ae[i].next = ah[ae[i].hidx]; ah[ae[i].hidx] = i;
            ie[i].id = id; ie[i].idx = nm4[i]; ie[i].hidx = id & 7; ie[i].next = ih[ie[i].hidx]; ih[ie[i].hidx] = i;
            ab[0] |= 1u << i; ib[0] |= 1u << i;
        }
        unsigned char *ms[2] = { am, im };
        void *ds[2] = { ae, ie }; u32 *bs[2] = { ab, ib }; int *hs[2] = { ah, ih };
        for (int k = 0; k < 2; k++) {
            *(u64 *)ms[k] = (u64)ds[k]; *(int *)(ms[k] + 8) = 4; *(int *)(ms[k] + 12) = 4;
            *(u64 *)(ms[k] + 32) = (u64)bs[k]; *(int *)(ms[k] + 40) = 4; *(int *)(ms[k] + 44) = 32;
            *(int *)(ms[k] + 48) = -1; *(int *)(ms[k] + 52) = 0;
            *(u64 *)(ms[k] + 64) = (u64)hs[k]; *(int *)(ms[k] + 72) = 8;
        }
        find(0x14, 0)->id = 300;
        // ID at row offset 0x2c (row_t.id)
        snprintf(cmd, sizeof cmd, "%llx,%llx,%llx,%llx,b,14,2c", (unsigned long long)(u64)am, (unsigned long long)(u64)im,
            (unsigned long long)(u64)table, (unsigned long long)(u64)rs);
        send(game_cmd, cmd);
        check(!strcmp(lastres, "ok ids added 300"), lastres);
        const char *err;
        u64 a = tset_find((u64)am, 20, 0, 0x14, 0), b = tset_find((u64)im, 20, 1, 300, 0);
        check(a && *(int *)(a + 8) == 300, "the alias map has it");
        check(b && *(u32 *)(b + 4) == 0x14, "the ID map has it");
        check(tset_ok((u64)am, 20, 0, &err) && tset_ok((u64)im, 20, 1, &err), "both maps hash as before");
        for (int i = 0; i < 4; i++) check(tset_find((u64)am, 20, 0, nm4[i], 0) != 0, "the old aliases still found");
        send(game_cmd, cmd);
        check(!strcmp(lastres, "ok ids exists 300"), lastres);
        // a source whose ID in the map isn't its row's: refused
        // (through the map: the add grew it into a new array)
        *(int *)(tset_find((u64)am, 20, 0, 11, 0) + 8) = 999;
        snprintf(cmd, sizeof cmd, "%llx,%llx,%llx,%llx,b,15,2c", (unsigned long long)(u64)am, (unsigned long long)(u64)im,
            (unsigned long long)(u64)table, (unsigned long long)(u64)rs);
        send(game_cmd, cmd);
        check(!strncmp(lastres, "err the alias map's ID", 22), lastres);
    }
    printf(fails ? "FAIL\n" : "PASS\n");
    return fails != 0;
}
