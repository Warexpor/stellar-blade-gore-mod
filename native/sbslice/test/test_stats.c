// stats.c natively: a made-up actor whose stat array hangs two pointers down (as an ASBCharacter's might), a decoy
// array with the same shape but other numbers, and an enemy built the same way. Checks the find (anchored only, never
// by shape), the reads and writes through the path, the shield guard, the enemy multiplier and losing an actor.
#define STATS_TEST
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../stats.c"

static char res[4096], evt[4096];
void stats_result(const char *s) { snprintf(res, sizeof res, "%s", s); }
void stats_event(const char *s) { snprintf(evt, sizeof evt, "%s", s); }

// every block handed out here is readable; anything else isn't
#define NB 64
static unsigned char *blk[NB];
static u64 blen[NB];
static int nblk;
static unsigned char *mk(u64 n)
{
    unsigned char *p = aligned_alloc(16, (n + 15) & ~15ull);
    memset(p, 0, n);
    blk[nblk] = p; blen[nblk++] = n;
    return p;
}
static int blk_of(u64 p)
{
    for (int i = 0; i < nblk; i++) if (p >= (u64)blk[i] && p < (u64)blk[i] + blen[i]) return i;
    return -1;
}
int readable(u64 p, u64 n)
{
    int i = blk_of(p);
    return i >= 0 && (p & 3) == 0 && p + n <= (u64)blk[i] + blen[i];
}
u64 readable_len(u64 p, u64 max)
{
    int i = blk_of(p);
    if (i < 0) return 0;
    u64 left = (u64)blk[i] + blen[i] - p;
    return left < max ? left : max;
}

static int fails;
static void check(int ok, const char *what) { printf("%s: %s\n", ok ? "ok" : "FAIL", what); if (!ok) fails++; }

static u16 cmdbuf[64];
static int cmd(const char *s, float a, float b, float c, float d)
{
    int n = 0;
    while (s[n]) { cmdbuf[n] = (u16)s[n]; n++; }
    cmdbuf[n] = 0;
    float loc[3] = { a, b, c }, dir[3] = { d, 0, 0 };
    res[0] = 0;
    return stats_cmd(cmdbuf, n, loc, dir);
}

// an actor: 0x900 bytes, +0x6a8 -> a component (0x400), +0x158 -> a block whose +0x30 is stat 0
static float *actor(unsigned char **out, float hp, float maxhp, float sh, float maxsh)
{
    unsigned char *a = mk(0x900), *comp = mk(0x400), *arr = mk(4 * S_COUNT + 0x30);
    *(u64 *)(a + 0x6a8) = (u64)comp;
    *(u64 *)(comp + 0x158) = (u64)arr;
    *(u64 *)(a + 0x10) = (u64)a; // a pointer back to itself, as UObjects have (Outer, etc.)
    float *f = (float *)(arr + 0x30);
    f[S_HP] = hp; f[S_MAXHP] = maxhp; f[S_SHIELD] = sh; f[S_MAXSHIELD] = maxsh; f[6] = 1;
    *out = a;
    return f;
}

int main(void)
{
    unsigned char *eve, *foe;
    float *es = actor(&eve, 830, 1000, 3, 5);
    // a decoy: the same shape, other numbers (her base stats, say), right in the actor
    float *dec = (float *)(eve + 0x200);
    dec[S_HP] = 500; dec[S_MAXHP] = 500; dec[S_SHIELD] = 1; dec[S_MAXSHIELD] = 1;
    float *fs = actor(&foe, 2000, 2000, 0, 0);
    char a[32], b[32], c[64];
    snprintf(a, sizeof a, "vf%llx", (unsigned long long)eve);

    cmd(a, 830, 1000, 3, 5);
    printf("find: %s\n", res);
    check(!strncmp(res, "ok found=1 paths=6a8,158,30 hp=830.00 ", 38), "anchored find takes her array, not the decoy");

    cmd(a, 831.4f, 1000.2f, 3, 5);
    check(!strncmp(res, "ok found=1", 10), "HUD numbers rounded off by under half a point still match");

    cmd(a, 0, 0, 0, 0);
    check(!strncmp(res, "err", 3) && npaths == 1, "no HUD numbers: refused, the path found stays");
    cmd(a, 600, 900, 3, 5);
    check(!strncmp(res, "err none", 8), "numbers matching nothing: none, never a guess by shape");
    cmd(a, 830, 1000, 3, 5);

    snprintf(b, sizeof b, "vr%llx", (unsigned long long)foe);
    cmd(b, 0, 0, 0, 0);
    check(!strcmp(res, "ok hp=2000.00 maxhp=2000.00 shield=0.00 maxshield=0.00"), "an enemy's stats through her path");

    snprintf(c, sizeof c, "vw%llx,1", (unsigned long long)eve);
    cmd(c, 700, 0, 0, 0);
    check(es[S_HP] == 700, "write HP");

    // her guard: a hit while the shield is up takes no HP
    snprintf(c, sizeof c, "vy%llx,1", (unsigned long long)eve);
    cmd(c, 0, 0, 0, 0);
    check(!strcmp(res, "ok"), "follow her");
    es[S_HP] = 640; es[S_SHIELD] = 2;
    evt[0] = 0; cmd("vt", 0, 0, 0, 0);
    printf("tick: %s", evt);
    check(es[S_HP] == 700 && !strncmp(evt, "guard 60.00 shield 3.00 -> 2.00", 31), "a hit with the shield up is given back");
    es[S_SHIELD] = 0;
    evt[0] = 0; cmd("vt", 0, 0, 0, 0);
    check(!strncmp(evt, "shield 2.00 -> 0.00", 19), "the shield breaking is told");
    es[S_HP] = 620;
    evt[0] = 0; cmd("vt", 0, 0, 0, 0);
    printf("tick: %s", evt);
    check(es[S_HP] == 620 && !strncmp(evt, "hit 700.00 -> 620.00 of 1000.00 shield 0.00 -> 0.00", 51), "a hit with the shield down lands and is told");
    evt[0] = 0; cmd("vt", 0, 0, 0, 0);
    check(evt[0] == 0, "a quiet tick says nothing");

    // an enemy: 1.9 times what it loses (0xbe = 190), never under 1 HP from the multiplying
    snprintf(c, sizeof c, "ve%llx,be", (unsigned long long)foe);
    cmd(c, 0, 0, 0, 0);
    printf("follow enemy: %s\n", res);
    fs[S_HP] = 1900;
    evt[0] = 0; cmd("vt", 0, 0, 0, 0);
    printf("tick: %s", evt);
    check(fs[S_HP] > 1809.9f && fs[S_HP] < 1810.1f, "enemy damage multiplied (100 lost, 90 more)");
    fs[S_HP] = 1500;
    cmd("vt", 0, 0, 0, 0);
    check(fs[S_HP] > 1220.9f && fs[S_HP] < 1221.1f, "and again from the multiplied HP (310 lost, 279 more)");
    fs[S_HP] = 10;
    cmd("vt", 0, 0, 0, 0);
    check(fs[S_HP] == 1, "a multiplied blow that would kill leaves 1 HP");
    fs[S_HP] = 0;
    cmd("vt", 0, 0, 0, 0);
    check(fs[S_HP] == 0, "the next blow's 0 stays");
    snprintf(b, sizeof b, "ve%llx,be", (unsigned long long)foe);
    cmd(b, 0, 0, 0, 0);
    check(!strncmp(res, "err", 3), "a dead (HP 0) actor isn't followed");

    // the enemy's array goes (freed, pooled): it is dropped and told
    *(u64 *)(*(u64 *)(foe + 0x6a8) + 0x158) = 0;
    evt[0] = 0; cmd("vt", 0, 0, 0, 0);
    check(strstr(evt, "lost ") != 0 && nfol == 1, "an actor whose stats are gone is dropped");

    cmd("vy0", 0, 0, 0, 0);
    check(nfol == 0, "stop following her");
    snprintf(c, sizeof c, "vr%llx", (unsigned long long)0x1234);
    cmd(c, 0, 0, 0, 0);
    check(!strncmp(res, "err", 3), "a bad actor is refused");
    check(cmd("x1", 0, 0, 0, 0) == 0, "other commands are left alone");

    // the search by hits, with no HUD numbers: her array, the decoy and a stats-shaped run that keeps dropping by
    // itself (a timer, say); a quiet check drops the timer, her hit leaves her array alone
    {
        unsigned char *eve2;
        float *e2 = actor(&eve2, 830, 1000, 3, 5);
        float *d2 = (float *)(eve2 + 0x200);
        d2[S_HP] = 500; d2[S_MAXHP] = 500; d2[S_SHIELD] = 1; d2[S_MAXSHIELD] = 1;
        float *tm = (float *)(eve2 + 0x300);
        tm[S_HP] = 40; tm[S_MAXHP] = 60;
        npaths = 0;
        char s1[32], s2[40], s3[40];
        snprintf(s1, sizeof s1, "vs%llx", (unsigned long long)eve2);
        snprintf(s2, sizeof s2, "vd%llx,0", (unsigned long long)eve2);
        snprintf(s3, sizeof s3, "vd%llx,1", (unsigned long long)eve2);
        cmd(s1, 0, 0, 0, 0);
        printf("search: %s\n", res);
        int nc = 0; sscanf(res, "ok cands=%d", &nc);
        check(nc >= 3 && npaths == 0, "every stats-shaped array is a candidate, nothing found yet");
        cmd(s2, 0, 0, 0, 0);
        check(!strncmp(res, "more ", 5), "a quiet check keeps the unchanged ones");
        int left = 0;
        for (int k = 1; k <= CAND_MOVING; k++) {
            tm[S_HP] = 40 - 5 * k;
            cmd(s2, 0, 0, 0, 0);
        }
        sscanf(res, "more %d", &left);
        check(left == nc - 1, "what keeps changing with no hit is dropped");
        // hits the script missed (her HP drops on quiet checks, a combo on two running) keep her array; the next hit
        // it sees finds it
        e2[S_HP] = 790;
        cmd(s2, 0, 0, 0, 0);
        e2[S_HP] = 760;
        cmd(s2, 0, 0, 0, 0);
        sscanf(res, "more %d", &left);
        check(left == nc - 1, "missed hits, two checks running, don't lose her array");
        e2[S_HP] = 700;
        cmd(s3, 0, 0, 0, 0);
        printf("search hit: %s\n", res);
        check(!strncmp(res, "ok found=1 paths=6a8,158,30 hp=700.00", 37), "her hit finds her array");
        cmd(s1, 0, 0, 0, 0);
        cmd(s3, 0, 0, 0, 0);
        check(!strncmp(res, "err none", 8) && npaths == 1, "a hit that dropped nothing: none, the path found stays");

        // her death finds her stats with no hit ever seen: noted, a few missed hits, then HP 0
        npaths = 0;
        e2[S_HP] = 830;
        char s4[40];
        snprintf(s4, sizeof s4, "vd%llx,2", (unsigned long long)eve2);
        cmd(s1, 0, 0, 0, 0);
        cmd(s4, 0, 0, 0, 0);
        check(!strncmp(res, "err none at 0, kept ", 20) && npaths == 0, "a death check with nothing at 0 keeps every candidate");
        e2[S_HP] = 500; cmd(s2, 0, 0, 0, 0);
        e2[S_HP] = 0;
        cmd(s4, 0, 0, 0, 0);
        printf("search death: %s\n", res);
        check(!strncmp(res, "ok found=1 paths=6a8,158,30 hp=0.00", 35), "her death finds her array");

        // her HUD's HP bar (live while the HUD's numbers stay 0): HP / MaxHP at the bar's reading stays. The decoy
        // reads 1.0, a run at the same HP but another MaxHP doesn't match; a heal between the checks loses nothing
        npaths = 0;
        e2[S_HP] = 830;
        cmd(s1, 0, 0, 0, 0);
        char s5[40];
        snprintf(s5, sizeof s5, "vd%llx,3", (unsigned long long)eve2);
        cmd(s5, 1.0f, 0, 0, 0);
        check(!strncmp(res, "err bad ratio", 13), "a full bar (everything at full matches it) is refused");
        e2[S_HP] = 410.5f;
        cmd(s5, 0.41049999f, 0, 0, 0);
        check(!strncmp(res, "more 1", 6) && npaths == 0, "one bar reading never takes an array, however few are left");
        e2[S_HP] = 300;
        cmd(s5, 0.3f, 0, 0, 0);
        printf("search bar: %s\n", res);
        check(!strncmp(res, "ok found=1 paths=6a8,158,30 hp=300.00", 37), "her HP bar's second reading finds her array");
        npaths = 0;
        e2[S_HP] = 300;
        cmd(s1, 0, 0, 0, 0);
        e2[S_HP] = 600; tm[S_HP] = 36; tm[S_MAXHP] = 60;
        cmd(s5, 0.6f, 0, 0, 0);
        check(!strncmp(res, "more 2", 6), "a heal before the bar's check keeps her array (and what reads the same ratio)");
        e2[S_HP] = 500;
        cmd(s5, 0.5f, 0, 0, 0);
        check(!strncmp(res, "ok found=1 paths=6a8,158,30 hp=500.00", 37), "a second reading tells them apart");
    }

    // a boss spawned here (bosses.lua, vb): found by the MaxHP and MaxShield its row was given, whatever its HP; a
    // decoy of another maximum never; then read through the kept path; by their ratio when a difficulty scaled both;
    // her paths and candidates (glass.lua's) left as they were
    {
        int keepn = npaths, keepc = ncand;
        unsigned char *bo;
        float *bs = actor(&bo, 3100, 5456, 0, 166);
        float *bd = (float *)(bo + 0x300);
        bd[S_HP] = 400; bd[S_MAXHP] = 400; bd[S_SHIELD] = 0; bd[S_MAXSHIELD] = 10;
        char s6[64];
        snprintf(s6, sizeof s6, "vb%llx,%x,%x", (unsigned long long)bo, 5456, 166);
        cmd(s6, 0, 0, 0, 0);
        check(!strcmp(res, "ok found 3100.00 5456.00 0.00 166.00"), "boss: found by its row's maximum");
        check(npaths == keepn && ncand == keepc, "boss: her paths and candidates left as they were");
        bs[S_HP] = 2900;
        cmd(s6, 0, 0, 0, 0);
        check(!strcmp(res, "ok 2900.00 5456.00 0.00 166.00"), "boss: read again through its path");
        unsigned char *bo2;
        actor(&bo2, 8000, 8184, 249, 249);
        snprintf(s6, sizeof s6, "vb%llx,%x,%x", (unsigned long long)bo2, 5456, 166);
        cmd(s6, 0, 0, 0, 0);
        check(!strcmp(res, "ok found by ratio 8000.00 8184.00 249.00 249.00"), "boss: both scaled by 1.5: found by their ratio");
        snprintf(s6, sizeof s6, "vb%llx,%x,%x", (unsigned long long)bo2, 7000, 166);
        nboss = 0;
        cmd(s6, 0, 0, 0, 0);
        check(!strcmp(res, "none"), "boss: no maximum or ratio of its: none");
    }

    printf("%s\n", fails ? "FAIL" : "PASS");
    return fails != 0;
}
