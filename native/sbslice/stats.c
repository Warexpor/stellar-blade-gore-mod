// Actor stats (HP, shield) for the glass cannon mode (glass.lua). The game keeps them in native memory only: no
// reflected property or working cheat reads or writes them in the shipping build. They are an array of floats
// indexed by ESBActorStatType (None 0, HP 1, MaxHP 2, ..., Shield 7, MaxShield 8), so the first find scans the
// player's actor (and the objects it points to, two levels deep) for HP, MaxHP, Shield and MaxShield at those
// places, anchored on the values her HUD shows (WB_MainHUD_PlayerInfo's HpValue etc.). The pointer path found is
// kept and followed again on every read, so a reallocated array is still found; enemies are ASBCharacters too and
// are checked against the same path.
// Commands (from exec_slice, fields in hex, floats in its LocX/Y/Z and DirX):
//   vf<actor>            find the stats: HP, MaxHP, Shield in LocX/Y/Z, MaxShield in DirX (her HUD's; MaxHP 0: refused)
//   vr<actor>            read HP, MaxHP, Shield, MaxShield
//   vw<actor>,<index>    write LocX to stat <index> on every copy found
//   vy<actor>,<guard>    follow her: HP lost while her shield was up is given back (guard 1); 0 stops
//   ve<actor>,<x100>     follow an enemy: HP and shield it loses are multiplied (x100 = 100 * the factor)
//   vs<actor>            no HUD numbers: note every stats-shaped array (candidates) for the search by hits
//   vd<actor>,<hit>      the search by hits: hit 1, a hit just landed: candidates whose HP is under what it was at the
//                        note stay; hit 0, quiet: candidates whose MaxHP changed, whose HP rose, or whose HP changed on
//                        two checks running (a timer, not hits) go. A hit the script missed only drops HP once, so it
//                        doesn't lose her array. Found once a hit leaves what reads as one array (its copies)
//                        hit 2: her death (HP 0); hit 3: her HUD's HP bar reads LocX (ProgressBar_HP.Percent, the one
//                        HUD value the game keeps live): candidates whose HP / MaxHP is within RATIO_TOL of it stay,
//                        and one array left after RATIO_READS readings is found as after a hit
//   vz                   follow nothing
//   vt                   one tick of following: what happened goes to sbslice.evt (nothing when nothing did)
typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned short u16;

#ifndef STATS_TEST
typedef void *HANDLE;
#define WINAPI __stdcall
typedef struct { void *base, *alloc; u32 aprot; u16 part; u64 size; u32 state, prot, type; } MBI;
__declspec(dllimport) u64 WINAPI VirtualQuery(const void *, MBI *, u64);
__declspec(dllimport) HANDLE WINAPI CreateFileW(const u16 *, u32, u32, void *, u32, u32, HANDLE);
__declspec(dllimport) int WINAPI WriteFile(HANDLE, const void *, u32, u32 *, void *);
__declspec(dllimport) int WINAPI CloseHandle(HANDLE);

// readable for n bytes from p (committed, readable, not a guard page); the last region asked about is kept, for the
// first thread to ask alone (the game thread: tables.lua's scans run on one of their own, and a pair written by one
// thread as the other read it would pass a region neither asked about)
static u64 rd_lo, rd_hi;
static volatile u32 rd_tid;
__declspec(dllimport) u32 WINAPI GetCurrentThreadId(void);
static int readable_to(u64 p, u64 n, u64 *end)
{
    if (p < 0x10000 || p > 0x7ffffffeffffull || (p & 3)) return 0;
    u32 tid = GetCurrentThreadId();
    if (!rd_tid) __atomic_compare_exchange_n(&rd_tid, &(u32){ 0 }, tid, 0, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    int mine = rd_tid == tid;
    if (mine && p >= rd_lo && p + n <= rd_hi) { *end = rd_hi; return 1; }
    MBI m;
    if (!VirtualQuery((const void *)p, &m, sizeof m)) return 0;
    if (m.state != 0x1000 || (m.prot & 0x101) || !(m.prot & 0xee)) return 0;
    u64 lo = (u64)m.base, hi = lo + m.size;
    if (mine) { rd_lo = lo; rd_hi = hi; }
    *end = hi;
    return p + n <= hi;
}
static int readable(u64 p, u64 n) { u64 end; return readable_to(p, n, &end); }
// for sbslice.c (its "o" command)
int mem_readable(u64 p, u64 n) { return readable(p, n); }
// every 8-aligned place in the process's private read-write memory holding needle, up to max of them (a probe: what
// else points at a data table's row). Returns how many were found
int mem_scan(u64 needle, u64 *hits, int max)
{
    int n = 0;
    u64 p = 0x10000;
    MBI m;
    while (p < 0x7ffffffeffffull && n < max && VirtualQuery((const void *)p, &m, sizeof m)) {
        u64 base = (u64)m.base, size = m.size;
        if (m.state == 0x1000 && m.type == 0x20000 && (m.prot == 0x04) && size) {
            const u64 *q = (const u64 *)base, *e = (const u64 *)(base + size);
            for (; q < e && n < max; q++) if (*q == needle) hits[n++] = (u64)q;
        }
        if (base + size <= p) break;
        p = base + size;
    }
    return n;
}
// the same for a 4-byte value, 4-aligned
int mem_scan32(u32 needle, u64 *hits, int max)
{
    int n = 0;
    u64 p = 0x10000;
    MBI m;
    while (p < 0x7ffffffeffffull && n < max && VirtualQuery((const void *)p, &m, sizeof m)) {
        u64 base = (u64)m.base, size = m.size;
        if (m.state == 0x1000 && m.type == 0x20000 && (m.prot == 0x04) && size) {
            const u32 *q = (const u32 *)base, *e = (const u32 *)(base + size);
            for (; q < e && n < max; q++) if (*q == needle) hits[n++] = (u64)q;
        }
        if (base + size <= p) break;
        p = base + size;
    }
    return n;
}
// the same for a TSet's header holding an element at addr: a qword p <= addr, addr - p a multiple of esz, followed
// by Num <= Max with addr inside Max elements, as many allocation bits as elements and a hash size a power of two
int mem_scan_set(u64 addr, int esz, u64 *hits, int max)
{
    int n = 0;
    u64 p = 0x10000;
    MBI m;
    while (p < 0x7ffffffeffffull && n < max && VirtualQuery((const void *)p, &m, sizeof m)) {
        u64 base = (u64)m.base, size = m.size;
        if (m.state == 0x1000 && m.type == 0x20000 && (m.prot == 0x04) && size >= 80) {
            const u64 *q = (const u64 *)base, *e = (const u64 *)(base + size - 80);
            for (; q < e && n < max; q++) {
                u64 v = *q;
                if (v > addr || addr - v > (u64)esz * 0x100000 || (addr - v) % (u64)esz) continue;
                int num = ((const int *)q)[2], mx = ((const int *)q)[3];
                if (num <= 0 || mx < num || (u64)mx * esz <= addr - v) continue;
                int nbits = ((const int *)q)[10], maxbits = ((const int *)q)[11], hsize = ((const int *)q)[18];
                if (nbits != num || maxbits < nbits || hsize <= 0 || (hsize & (hsize - 1))) continue;
                hits[n++] = (u64)q;
            }
        }
        if (base + size <= p) break;
        p = base + size;
    }
    return n;
}
// how many bytes from p are readable, up to max
static u64 readable_len(u64 p, u64 max)
{
    u64 end;
    if (!readable_to(p, 4, &end)) return 0;
    return end - p < max ? end - p : max;
}
static void stats_write_file(const u16 *path, const char *s)
{
    HANDLE h = CreateFileW(path, 0x40000000 /*GENERIC_WRITE*/, 1, 0, 2 /*CREATE_ALWAYS*/, 0x80, 0);
    if (h == (HANDLE)(long long)-1) return;
    u32 n = 0, w;
    while (s[n]) n++;
    WriteFile(h, s, n, &w, 0);
    CloseHandle(h);
}
static const u16 STATRES[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.cut";
static const u16 STATEVT[] = u"ue4ss\\Mods\\StellarBladeGore\\sbslice.evt";
static void stats_result(const char *s) { stats_write_file(STATRES, s); }
static void stats_event(const char *s) { stats_write_file(STATEVT, s); }
#else
int readable(u64 p, u64 n);
u64 readable_len(u64 p, u64 max);
void stats_result(const char *s);
void stats_event(const char *s);
#endif

#define S_HP 1
#define S_MAXHP 2
#define S_SHIELD 7
#define S_MAXSHIELD 8
#define S_COUNT 131 // ActorStatType_Num
#define MAX_PATHS 4
#define MAX_FOLLOW 32

static int npaths;
static int path_len[MAX_PATHS];
static u32 path_off[MAX_PATHS][3]; // pointer offsets, the last one is where the array (stat 0) starts in its object

static float fabs_(float x) { return x < 0 ? -x : x; }
static int finite_(float x) { return x == x && x < 1e30f && x > -1e30f; }

static char *s_put(char *o, const char *s) { while (*s) *o++ = *s++; return o; }
static char *s_hex(char *o, u64 v)
{
    char t[17]; int n = 0;
    do { t[n++] = "0123456789abcdef"[v & 15]; v >>= 4; } while (v);
    while (n) *o++ = t[--n];
    return o;
}
static char *s_int(char *o, long long v)
{
    char t[24]; int n = 0;
    if (v < 0) { *o++ = '-'; v = -v; }
    do { t[n++] = (char)('0' + v % 10); v /= 10; } while (v);
    while (n) *o++ = t[--n];
    return o;
}
static char *s_f(char *o, float f) // two decimals
{
    if (!finite_(f)) return s_put(o, "nan");
    long long c = (long long)(f * 100 + (f < 0 ? -0.5f : 0.5f));
    if (c < 0) { *o++ = '-'; c = -c; }
    o = s_int(o, c / 100);
    *o++ = '.'; *o++ = (char)('0' + c / 10 % 10); *o++ = (char)('0' + c % 10);
    return o;
}

// where path k leads from actor a: the address of stat 0, or 0
static u64 path_at(u64 a, int k)
{
    u64 p = a;
    for (int i = 0; i < path_len[k] - 1; i++) {
        if (!readable(p + path_off[k][i], 8)) return 0;
        p = *(u64 *)(p + path_off[k][i]);
    }
    p += path_off[k][path_len[k] - 1];
    return readable(p, 4 * (S_MAXSHIELD + 1)) ? p : 0;
}

// the stat array's shape: stat 0 (None) is 0, 0 <= HP <= MaxHP, 0 <= Shield <= MaxShield, all sane
static int shaped(const float *f)
{
    if (f[0] != 0) return 0;
    for (int i = 1; i <= S_MAXSHIELD; i++) if (!finite_(f[i])) return 0;
    return f[S_MAXHP] >= 1 && f[S_MAXHP] < 1e7f && f[S_HP] >= 0 && f[S_HP] <= f[S_MAXHP] * 1.001f &&
           f[S_SHIELD] >= 0 && f[S_MAXSHIELD] >= 0 && f[S_MAXSHIELD] < 1e6f && f[S_SHIELD] <= f[S_MAXSHIELD] * 1.001f + 0.01f;
}
static float anchor[4]; // HP, MaxHP, Shield, MaxShield her HUD shows
static int matches(const float *f)
{
    if (!shaped(f)) return 0;
    float tol = anchor[1] * 0.002f + 0.51f;
    return fabs_(f[S_HP] - anchor[0]) <= tol && fabs_(f[S_MAXHP] - anchor[1]) <= tol &&
           fabs_(f[S_SHIELD] - anchor[2]) <= 0.51f && fabs_(f[S_MAXSHIELD] - anchor[3]) <= 0.51f;
}

// the search by hits (no HUD numbers): every stats-shaped array, how it read last
#define MAX_CAND 8192
typedef struct { unsigned char n, moving; u32 off[3]; float hp0, hp, mhp, sh, msh; } cand_t; // hp0: at the note
// a quiet check drops a candidate that changed on this many checks running (a timer ticking down): fewer, and a
// combo's hits on consecutive checks lost her array (twenty-fifth playtest)
#define CAND_MOVING 6
// how far HP / MaxHP may be off her HP bar (the bar is drawn from them; a blend or rounding at most)
#define RATIO_TOL 0.015f
// HP bar readings that narrowed the candidates since the note: one reading is never enough to take one (of thousands
// of candidates, a stranger's ratio matched 0.879 within RATIO_TOL and was taken for hers, thirty-second playtest)
#define RATIO_READS 2
static cand_t cands[MAX_CAND];
static int ncand, cand_mode, ratio_reads;
static void cand_add(int n, u32 o0, u32 o1, u32 o2, const float *f)
{
    if (ncand >= MAX_CAND || f[S_HP] <= 0) return;
    cand_t *c = &cands[ncand++];
    c->n = (unsigned char)n; c->off[0] = o0; c->off[1] = o1; c->off[2] = o2;
    c->hp0 = c->hp = f[S_HP]; c->mhp = f[S_MAXHP]; c->sh = f[S_SHIELD]; c->msh = f[S_MAXSHIELD]; c->moving = 0;
}

// where candidate c leads from actor a: stat 0, or 0
static u64 cand_at(u64 a, const cand_t *c)
{
    u64 p = a;
    for (int i = 0; i < c->n - 1; i++) {
        if (!readable(p + c->off[i], 8)) return 0;
        p = *(u64 *)(p + c->off[i]);
    }
    p += c->off[c->n - 1];
    return readable(p, 4 * (S_MAXSHIELD + 1)) ? p : 0;
}

static int found_n;
static void found(int n, u32 o0, u32 o1, u32 o2)
{
    found_n++;
    if (npaths >= MAX_PATHS) return;
    u32 o[3] = { o0, o1, o2 };
    for (int k = 0; k < npaths; k++) { // the same array reached again through another pointer: one copy
        if (path_len[k] != n) continue;
        int same = 1;
        for (int i = 0; i < n; i++) same &= path_off[k][i] == o[i];
        if (same) return;
    }
    path_len[npaths] = n;
    for (int i = 0; i < n; i++) path_off[npaths][i] = o[i];
    npaths++;
}
// a boss spawned here (bosses.lua): its stats found by the MaxHP and MaxShield its row was given (any HP and shield
// under them; 1), else by their ratio within BOSS_RATIO (a difficulty scaling both; 2), and kept per actor. The
// search (boss_mode) leaves the paths and candidates glass.lua follows as they were
#define MAX_BOSS 8
#define BOSS_RATIO 0.005f
static struct { u64 a; int n; u32 off[3]; float mhp, msh; } boss[MAX_BOSS];
static int nboss, boss_mode, boss_best, boss_n;
static u32 boss_off[3];
static float boss_mhp, boss_msh;
static int boss_match(const float *f)
{
    if (!shaped(f)) return 0;
    if (fabs_(f[S_MAXHP] - boss_mhp) <= 0.51f && fabs_(f[S_MAXSHIELD] - boss_msh) <= 0.51f) return 1;
    return boss_msh > 0 && f[S_MAXSHIELD] > 0 && f[S_MAXHP] > 1 &&
           fabs_((f[S_MAXHP] / f[S_MAXSHIELD]) / (boss_mhp / boss_msh) - 1) <= BOSS_RATIO ? 2 : 0;
}
static void boss_seen(int n, u32 o0, u32 o1, u32 o2, const float *f)
{
    int m = boss_match(f);
    if (!m || (boss_best && m >= boss_best)) return;
    boss_best = m; boss_n = n; boss_off[0] = o0; boss_off[1] = o1; boss_off[2] = o2;
}
// stat arrays in [p, p + n): their offsets from p
static void scan_block(u64 p, u64 n, int depth, u32 o0, u32 o1)
{
    u64 len = readable_len(p, n);
    if (len < 4 * (S_MAXSHIELD + 1)) return;
    for (u64 o = 0; o + 4 * (S_MAXSHIELD + 1) <= len; o += 4) {
        if (boss_mode) {
            const float *x = (const float *)(p + o);
            if (depth == 0) boss_seen(1, (u32)o, 0, 0, x);
            else if (depth == 1) boss_seen(2, o0, (u32)o, 0, x);
            else boss_seen(3, o0, o1, (u32)o, x);
            continue;
        }
        if (cand_mode) {
            if (!shaped((const float *)(p + o))) continue;
            if (depth == 0) cand_add(1, (u32)o, 0, 0, (const float *)(p + o));
            else if (depth == 1) cand_add(2, o0, (u32)o, 0, (const float *)(p + o));
            else cand_add(3, o0, o1, (u32)o, (const float *)(p + o));
            continue;
        }
        if (!matches((const float *)(p + o))) continue;
        if (depth == 0) found(1, (u32)o, 0, 0);
        else if (depth == 1) found(2, o0, (u32)o, 0);
        else found(3, o0, o1, (u32)o);
    }
}
#define SCAN_ACTOR 0x4000
#define SCAN_L1 0x1000
#define SCAN_L2 0x600
static u64 seen[4096];
static int nseen;
static int seen_once(u64 p)
{
    for (int i = 0; i < nseen; i++) if (seen[i] == p) return 1;
    if (nseen < 4096) seen[nseen++] = p;
    return 0;
}
static void stats_find(u64 a)
{
    npaths = 0; found_n = 0; nseen = 0;
    scan_block(a, SCAN_ACTOR, 0, 0, 0);
    u64 alen = readable_len(a, SCAN_ACTOR);
    for (u64 q = 0; q + 8 <= alen; q += 8) {
        u64 p = *(u64 *)(a + q);
        if ((p & 7) || p == a || !readable(p, 16) || seen_once(p)) continue;
        scan_block(p, SCAN_L1, 1, (u32)q, 0);
        u64 plen = readable_len(p, SCAN_L1);
        for (u64 q2 = 0; q2 + 8 <= plen; q2 += 8) {
            u64 p2 = *(u64 *)(p + q2);
            if ((p2 & 7) || p2 == a || p2 == p || !readable(p2, 16) || seen_once(p2)) continue;
            scan_block(p2, SCAN_L2, 2, (u32)q, (u32)q2);
        }
    }
}

static char *put_paths(char *o)
{
    o = s_put(o, " paths=");
    for (int k = 0; k < npaths; k++) {
        if (k) *o++ = ';';
        for (int i = 0; i < path_len[k]; i++) { if (i) *o++ = ','; o = s_hex(o, path_off[k][i]); }
    }
    return o;
}
// the first copy that reads as stats from actor a (0 if none)
static float *stats_of(u64 a)
{
    for (int k = 0; k < npaths; k++) {
        u64 p = path_at(a, k);
        if (p && shaped((const float *)p)) return (float *)p;
    }
    return 0;
}
static void stats_set(u64 a, int idx, float v)
{
    for (int k = 0; k < npaths; k++) {
        u64 p = path_at(a, k);
        if (p && shaped((const float *)p) && readable(p + 4 * (u64)idx, 4)) ((float *)p)[idx] = v;
    }
}

typedef struct { u64 actor; int enemy; float mult; float hp, shield; int guard; } follow_t;
static follow_t fol[MAX_FOLLOW];
static int nfol;
static follow_t *follow_of(u64 a)
{
    for (int i = 0; i < nfol; i++) if (fol[i].actor == a) return &fol[i];
    if (nfol >= MAX_FOLLOW) return 0;
    fol[nfol].actor = a;
    return &fol[nfol++];
}
static void unfollow(int i) { fol[i] = fol[--nfol]; }

static void stats_tick(void)
{
    static char ev[4096];
    char *o = ev, *end = ev + sizeof ev - 160;
    for (int i = 0; i < nfol; i++) {
        follow_t *f = &fol[i];
        float *s = stats_of(f->actor);
        if (!s) { if (o < end) { o = s_put(o, "lost "); o = s_hex(o, f->actor); *o++ = '\n'; } unfollow(i--); continue; }
        float hp = s[S_HP], sh = s[S_SHIELD];
        if (!f->enemy) {
            if (hp < f->hp - 0.01f) {
                if (f->guard && f->shield > 0.01f) {
                    // her shield was up: the hit takes no HP
                    stats_set(f->actor, S_HP, f->hp);
                    if (o < end) { o = s_put(o, "guard "); o = s_f(o, f->hp - hp); o = s_put(o, " shield "); o = s_f(o, f->shield); o = s_put(o, " -> "); o = s_f(o, sh); *o++ = '\n'; }
                    hp = f->hp;
                } else if (o < end) {
                    o = s_put(o, "hit "); o = s_f(o, f->hp); o = s_put(o, " -> "); o = s_f(o, hp); o = s_put(o, " of "); o = s_f(o, s[S_MAXHP]);
                    o = s_put(o, " shield "); o = s_f(o, f->shield); o = s_put(o, " -> "); o = s_f(o, sh); *o++ = '\n';
                }
            } else if (sh < f->shield - 0.01f && o < end) {
                o = s_put(o, "shield "); o = s_f(o, f->shield); o = s_put(o, " -> "); o = s_f(o, sh); *o++ = '\n';
            }
        } else if (f->mult > 1.0f) {
            // an enemy: what it lost is multiplied; a blow that would kill leaves it at 1 HP (whether the game takes
            // a stat written to 0 as a death is unknown) and the next one does
            float nh = hp, ns = sh;
            if (hp < f->hp - 0.01f && hp > 0) {
                nh = hp - (f->hp - hp) * (f->mult - 1);
                if (nh < 1) nh = hp < 1 ? hp : 1;
                stats_set(f->actor, S_HP, nh);
            }
            if (sh < f->shield - 0.01f) {
                ns = sh - (f->shield - sh) * (f->mult - 1);
                if (ns < 0) ns = 0;
                stats_set(f->actor, S_SHIELD, ns);
            }
            if ((nh != hp || ns != sh) && o < end) {
                o = s_put(o, "enemy "); o = s_hex(o, f->actor); o = s_put(o, " hp "); o = s_f(o, f->hp); o = s_put(o, " -> "); o = s_f(o, hp);
                o = s_put(o, " -> "); o = s_f(o, nh); o = s_put(o, " shield "); o = s_f(o, f->shield); o = s_put(o, " -> "); o = s_f(o, ns); *o++ = '\n';
            }
            hp = nh; sh = ns;
        }
        f->hp = hp; f->shield = sh;
    }
    if (o != ev) { *o = 0; stats_event(ev); }
}

static u64 s_parse(const u16 *t, int len, u64 *f, int max)
{
    int k = 0; u64 v = 0;
    for (int i = 0; i < len && t[i]; i++) {
        u16 c = t[i];
        int d = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (d >= 0) { v = v << 4 | (u64)d; continue; }
        if (c == ',' && k < max) { f[k++] = v; v = 0; continue; }
        break;
    }
    if (k < max) f[k++] = v;
    return (u64)k;
}

static const float *boss_at(int i)
{
    cand_t c; c.n = (unsigned char)boss[i].n;
    for (int k = 0; k < 3; k++) c.off[k] = boss[i].off[k];
    const float *f = (const float *)cand_at(boss[i].a, &c);
    return f && shaped(f) && f[S_MAXHP] == boss[i].mhp && f[S_MAXSHIELD] == boss[i].msh ? f : 0;
}
// "vb<actor>,<maxhp>,<maxshield>": "ok [found [by ratio]] HP MaxHP Shield MaxShield", or "none"
static void boss_cmd(const u16 *txt, int len)
{
    u64 f[3] = { 0, 0, 0 };
    s_parse(txt, len, f, 3);
    char msg[160], *o = msg;
    if (f[0] < 0x10000 || !readable(f[0], 0x100) || !f[1]) { stats_result("err bad actor"); return; }
    int i = 0;
    while (i < nboss && boss[i].a != f[0]) i++;
    const float *s = i < nboss ? boss_at(i) : 0;
    if (!s) {
        if (i < nboss) boss[i] = boss[--nboss];
        boss_mhp = (float)f[1]; boss_msh = (float)f[2]; boss_best = 0;
        int keepn = npaths;
        boss_mode = 1;
        stats_find(f[0]);
        boss_mode = 0;
        npaths = keepn;
        if (!boss_best) { stats_result("none"); return; }
        if (nboss >= MAX_BOSS) nboss = MAX_BOSS - 1;
        i = nboss++;
        boss[i].a = f[0]; boss[i].n = boss_n;
        for (int j = 0; j < 3; j++) boss[i].off[j] = boss_off[j];
        boss[i].mhp = boss[i].msh = -1;
        cand_t c; c.n = (unsigned char)boss_n; for (int j = 0; j < 3; j++) c.off[j] = boss_off[j];
        s = (const float *)cand_at(f[0], &c);
        if (!s) { nboss--; stats_result("none"); return; }
        boss[i].mhp = s[S_MAXHP]; boss[i].msh = s[S_MAXSHIELD];
        o = s_put(o, boss_best == 1 ? "ok found " : "ok found by ratio ");
    } else o = s_put(o, "ok ");
    o = s_f(o, s[S_HP]); *o++ = ' '; o = s_f(o, s[S_MAXHP]); *o++ = ' ';
    o = s_f(o, s[S_SHIELD]); *o++ = ' '; o = s_f(o, s[S_MAXSHIELD]);
    *o = 0;
    stats_result(msg);
}

// a "v..." command; 1 when it was one
int stats_cmd(const u16 *txt, int len, const float *loc, const float *dir)
{
    if (len < 2 || txt[0] != 'v') return 0;
    u16 c = txt[1];
    u64 f[2] = { 0, 0 };
    if (len > 2) s_parse(txt + 2, len - 2, f, 2);
    char msg[512], *o = msg;
    if (c == 'z') { nfol = 0; stats_result("ok"); return 1; }
    if (c == 't') { stats_tick(); return 1; }
    if (c == 'b') { boss_cmd(txt + 2, len - 2); return 1; }
    if (f[0] < 0x10000 && !(c == 'y' && f[0] == 0)) { stats_result("err bad actor"); return 1; }
    if (c == 's') {
        int keepn = npaths;
        cand_mode = 1; ncand = 0; ratio_reads = 0;
        stats_find(f[0]); // (its paths stay as they were: candidates only)
        cand_mode = 0;
        npaths = keepn;
        o = s_put(o, "ok cands="); o = s_int(o, ncand);
        *o = 0;
        stats_result(msg);
        return 1;
    }
    if (c == 'd') {
        if (!ncand) { stats_result("err no candidates"); return 1; }
        // f[1]: 0 a quiet check, 1 just after a hit on her, 2 her death (her HP is 0 now: kept, what went to 0
        // from above it; when nothing did, nothing is dropped)
        int hit = f[1] == 1 || f[1] == 2, death = f[1] == 2, ratio = f[1] == 3, k = 0, dropped = 0;
        float pct = loc[0];
        if (ratio && !(pct > 0 && pct < 1)) { stats_result("err bad ratio"); return 1; }
        ratio_reads += ratio;
        if (death) {
            int any = 0;
            for (int i = 0; i < ncand && !any; i++) {
                u64 p = cand_at(f[0], &cands[i]);
                const float *s = (const float *)p;
                any = p && shaped(s) && s[S_MAXHP] == cands[i].mhp && s[S_HP] <= 0.5f && cands[i].hp0 > 0.5f;
            }
            if (!any) {
                o = s_put(o, "err none at 0, kept "); o = s_int(o, ncand); *o = 0;
                stats_result(msg);
                return 1;
            }
        }
        for (int i = 0; i < ncand; i++) {
            cand_t *cd = &cands[i];
            u64 p = cand_at(f[0], cd);
            if (!p || !shaped((const float *)p)) continue;
            const float *s = (const float *)p;
            if (s[S_MAXHP] != cd->mhp || (!ratio && s[S_HP] > cd->hp + 0.01f)) continue;
            int changed = s[S_HP] < cd->hp - 0.01f;
            dropped += changed;
            if (ratio) { if (fabs_(s[S_HP] / s[S_MAXHP] - pct) > RATIO_TOL) continue; }
            else if (death) { if (!(s[S_HP] <= 0.5f && cd->hp0 > 0.5f)) continue; cd->moving = 0; }
            else if (hit) { if (!(s[S_HP] < cd->hp0 - 0.5f && s[S_HP] > 0)) continue; cd->moving = 0; }
            else if (changed) { if (++cd->moving >= CAND_MOVING) continue; }
            else cd->moving = 0;
            cd->hp = s[S_HP]; cd->mhp = s[S_MAXHP]; cd->sh = s[S_SHIELD]; cd->msh = s[S_MAXSHIELD];
            cands[k++] = *cd;
        }
        ncand = k;
        // found: a hit left a few, all reading the same (copies of one array)
        int same = ncand > 0 && ncand <= MAX_PATHS;
        for (int i = 1; i < ncand && same; i++)
            same = cands[i].hp == cands[0].hp && cands[i].mhp == cands[0].mhp && cands[i].sh == cands[0].sh && cands[i].msh == cands[0].msh;
        if ((hit || (ratio && ratio_reads >= RATIO_READS)) && same) {
            npaths = 0;
            for (int i = 0; i < ncand; i++) {
                path_len[npaths] = cands[i].n;
                for (int j = 0; j < 3; j++) path_off[npaths][j] = cands[i].off[j];
                npaths++;
            }
            ncand = 0;
            o = s_put(o, "ok found="); o = s_int(o, npaths);
            o = put_paths(o);
            float *st = stats_of(f[0]);
            if (st) { o = s_put(o, " hp="); o = s_f(o, st[S_HP]); o = s_put(o, " maxhp="); o = s_f(o, st[S_MAXHP]); o = s_put(o, " shield="); o = s_f(o, st[S_SHIELD]); o = s_put(o, " maxshield="); o = s_f(o, st[S_MAXSHIELD]); }
        } else {
            o = s_put(o, ncand ? "more " : "err none ");
            o = s_int(o, ncand);
            o = s_put(o, " dropped="); o = s_int(o, dropped);
        }
        *o = 0;
        stats_result(msg);
        return 1;
    }
    if (c == 'f') {
        // only anchored on her HUD's numbers: by shape alone thousands of float runs match (3039 in the first
        // playtest), and the one taken read HP 0 of 700
        if (loc[1] <= 0) { stats_result("err no HUD numbers to find them by"); return 1; }
        anchor[0] = loc[0]; anchor[1] = loc[1]; anchor[2] = loc[2]; anchor[3] = dir[0];
        stats_find(f[0]);
        o = s_put(o, npaths ? "ok" : "err none");
        o = s_put(o, " found="); o = s_int(o, found_n);
        o = put_paths(o);
        float *s = stats_of(f[0]);
        if (s) { o = s_put(o, " hp="); o = s_f(o, s[S_HP]); o = s_put(o, " maxhp="); o = s_f(o, s[S_MAXHP]); o = s_put(o, " shield="); o = s_f(o, s[S_SHIELD]); o = s_put(o, " maxshield="); o = s_f(o, s[S_MAXSHIELD]); }
        *o = 0;
        stats_result(msg);
        return 1;
    }
    if (!npaths) { stats_result("err no stats found yet"); return 1; }
    if (c == 'r' || c == 'e') {
        float *s = stats_of(f[0]);
        if (!s) { stats_result("err no stats on that actor"); return 1; }
        // an enemy read through her path is only taken alive: HP 0 is no stats of its, but something shaped like them
        if (c == 'e' && s[S_HP] <= 0) { stats_result("err no live stats on that actor"); return 1; }
        if (c == 'e') {
            follow_t *fo = follow_of(f[0]);
            if (!fo) { stats_result("err following too many"); return 1; }
            fo->enemy = 1; fo->mult = (float)f[1] / 100.0f; fo->hp = s[S_HP]; fo->shield = s[S_SHIELD]; fo->guard = 0;
        }
        o = s_put(o, "ok hp="); o = s_f(o, s[S_HP]); o = s_put(o, " maxhp="); o = s_f(o, s[S_MAXHP]);
        o = s_put(o, " shield="); o = s_f(o, s[S_SHIELD]); o = s_put(o, " maxshield="); o = s_f(o, s[S_MAXSHIELD]);
        *o = 0;
        stats_result(msg);
        return 1;
    }
    if (c == 'w') {
        if (f[1] >= S_COUNT) { stats_result("err bad stat"); return 1; }
        if (!stats_of(f[0])) { stats_result("err no stats on that actor"); return 1; }
        stats_set(f[0], (int)f[1], loc[0]);
        for (int i = 0; i < nfol; i++) if (fol[i].actor == f[0]) { // not taken for a hit on the next tick
            if (f[1] == S_HP) fol[i].hp = loc[0];
            if (f[1] == S_SHIELD) fol[i].shield = loc[0];
        }
        stats_result("ok");
        return 1;
    }
    if (c == 'y') {
        for (int i = 0; i < nfol; i++) if (!fol[i].enemy) unfollow(i--);
        if (f[0] == 0) { stats_result("ok"); return 1; }
        float *s = stats_of(f[0]);
        if (!s) { stats_result("err no stats on that actor"); return 1; }
        follow_t *fo = follow_of(f[0]);
        if (!fo) { stats_result("err following too many"); return 1; }
        fo->enemy = 0; fo->mult = 1; fo->guard = (int)f[1]; fo->hp = s[S_HP]; fo->shield = s[S_SHIELD];
        stats_result("ok");
        return 1;
    }
    stats_result("err unknown v command");
    return 1;
}
