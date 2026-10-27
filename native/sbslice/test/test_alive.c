// Linux harness for the liveness check ("G", alive_cmd in sbslice.c) on a made-up GUObjectArray: two chunks of items,
// objects in both. Checks: an object whose item points at it is alive, by its index or read off it (ffffffff, with
// the index in the answer); one whose item was cleared (freed) or points elsewhere (its slot reused), or flagged
// Unreachable or PendingKill, is not; an index past the array is not. And the mesh assets' records (assets_prune): a
// sink on an asset that lives is written back on "r"; one on an asset that went (its item cleared, a level reload) is
// dropped with nothing written, and a later asset at the same address with another index isn't taken for it. Run:
// ./test/run.sh alive
#include "host.h"
int mem_readable(u64 p, u64 n) { (void)n; return p >= 0x10000; }
static unsigned char objs[4][0x40];
int main(void)
{
    void *m = mmap(0, 0x7100000, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) { perror("mmap"); return 1; }
    exe = (u64)m;
    static unsigned char chunk0[GUO_CHUNK * GUO_ITEM], chunk1[16 * GUO_ITEM];
    static u64 chunks[2];
    chunks[0] = (u64)chunk0; chunks[1] = (u64)chunk1;
    u64 arr = exe + RVA_GUOBJECTARRAY + GUO_OBJOBJECTS;
    *(u64 *)arr = (u64)chunks; *(int *)(arr + 0x14) = GUO_CHUNK + 16;
    int idx[4] = { 5, 70, GUO_CHUNK + 3, GUO_CHUNK + 9 };
    for (int i = 0; i < 4; i++) {
        *(int *)(objs[i] + UOBJ_INTERNAL_INDEX) = idx[i];
        unsigned char *it = (idx[i] < GUO_CHUNK ? chunk0 + (u64)idx[i] * GUO_ITEM : chunk1 + (u64)(idx[i] - GUO_CHUNK) * GUO_ITEM);
        *(u64 *)it = (u64)objs[i];
    }
    // objs[1] freed, objs[3] PendingKill; objs[0] asked at objs[2]'s slot (its index reused) and past the array
    *(u64 *)(chunk0 + 70 * GUO_ITEM) = 0;
    *(u32 *)(chunk1 + 9 * GUO_ITEM + 8) = EIF_PENDINGKILL;
    int fails = 0;
    u64 f[] = { (u64)objs[0], 5, (u64)objs[1], 70, (u64)objs[2], 0xffffffff, (u64)objs[3], GUO_CHUNK + 9,
                (u64)objs[0], GUO_CHUNK + 3, (u64)objs[0], GUO_CHUNK + 400 };
    alive_cmd(f, 12);
    const char *want = "ok 101:65539 000";
    if (strcmp(lastres, want)) { printf("FAIL got \"%s\", want \"%s\"\n", lastres, want); fails++; }
    *(u32 *)(chunk0 + 5 * GUO_ITEM + 8) = EIF_UNREACHABLE;
    u64 g[] = { (u64)objs[0], 5 };
    alive_cmd(g, 2);
    if (strcmp(lastres, "ok 0")) { printf("FAIL unreachable: \"%s\"\n", lastres); fails++; }
    *(u32 *)(chunk0 + 5 * GUO_ITEM + 8) = 0;

    // two mesh assets (objects 0 and 2), a collapsed sink on each
    static float ri0[4 * 16], ri2[4 * 16];
    static unsigned char a0[0x400], a2[0x400];
    u64 as[2] = { (u64)a0, (u64)a2 };
    float *ris[2] = { ri0, ri2 };
    int aidx[2] = { 11, GUO_CHUNK + 5 };
    for (int i = 0; i < 2; i++) {
        *(int *)(as[i] + UOBJ_INTERNAL_INDEX) = aidx[i];
        unsigned char *it = aidx[i] < GUO_CHUNK ? chunk0 + (u64)aidx[i] * GUO_ITEM : chunk1 + (u64)(aidx[i] - GUO_CHUNK) * GUO_ITEM;
        *(u64 *)it = as[i];
        *(float **)(as[i] + SM_REF_BASES_INV) = ris[i];
        *(int *)(as[i] + SM_REF_BASES_INV + 8) = 4;
        sinks[nsinks].mesh = as[i]; sinks[nsinks].bone = 2; sinks[nsinks].down = 1;
        for (int j = 0; j < 16; j++) sinks[nsinks].m[j] = 7;
        nsinks++;
    }
    regrown[nregrown].mesh = as[1]; regrown[nregrown].bone = 3; nregrown++;
    // the grip's eased bones on each ("F": the crash in 0.4.6, relax_restore writing into a freed outfit's asset)
    for (int i = 0; i < 2; i++) {
        relaxed[nrelaxed].mesh = as[i]; relaxed[nrelaxed].bone = 1;
        for (int j = 0; j < 16; j++) relaxed[nrelaxed].m[j] = 5;
        nrelaxed++;
    }
    // a BoneMap entry borrowed on each (in place: no array of ours)
    static unsigned short bm0[16], bm2[16];
    static unsigned char sec0[0x40], sec2[0x40];
    *(unsigned short **)sec0 = bm0; *(unsigned short **)sec2 = bm2;
    bm_owner = as[0]; tarray_push16((u64)sec0, 9, 255);
    bm_owner = as[1]; tarray_push16((u64)sec2, 9, 255);
    assets_prune(); // (noted: both alive)
    if (nsinks != 2 || nassets != 2) { printf("FAIL prune of live assets: %d sinks, %d noted\n", nsinks, nassets); fails++; }
    // asset 2 goes with the level: its item cleared, then its memory taken by another asset at another index
    *(u64 *)(chunk1 + 5 * GUO_ITEM) = 0;
    *(int *)(as[1] + UOBJ_INTERNAL_INDEX) = 40;
    *(u64 *)(chunk0 + 40 * GUO_ITEM) = as[1];
    assets_prune();
    if (nsinks != 1 || sinks[0].mesh != as[0] || nregrown != 0 || nassets != 1 || nbmfix != 1 || bmfix[0].sm != as[0]
        || nrelaxed != 1 || relaxed[0].mesh != as[0]) {
        printf("FAIL prune of a gone asset: %d sinks, %d regrown, %d BoneMap entries, %d eased, %d noted\n", nsinks, nregrown, nbmfix,
            nrelaxed, nassets); fails++;
    }
    int eased = relax_restore();
    if (eased != 1 || ri0[16] != 5 || ri2[16] != 0) {
        printf("FAIL grip put back after the prune: %d put back, live %.0f, gone %.0f\n", eased, ri0[16], ri2[16]); fails++;
    }
    int put = skin_restore(0);
    if (put != 1 || ri0[2 * 16] != 7 || ri2[2 * 16] != 0 || ri0[3 * 16] != 0 || ri2[3 * 16] != 0) {
        printf("FAIL restore after the prune: %d put back, live %.0f, gone %.0f\n", put, ri0[2 * 16], ri2[2 * 16]); fails++;
    }
    // (the gone asset's array left as it was: count 1, nothing written back into it)
    if (*(int *)(sec0 + 8) != 0 || *(int *)(sec2 + 8) != 1) { printf("FAIL BoneMap counts %d, %d\n", *(int *)(sec0 + 8), *(int *)(sec2 + 8)); fails++; }
    if (assets_gone != 4) { printf("FAIL %d records counted gone, want 4\n", assets_gone); fails++; }
    printf("%s\n", fails ? "FAIL" : "PASS");
    return fails;
}
