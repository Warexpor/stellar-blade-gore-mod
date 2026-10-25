// Linux harness for the liveness check ("G", alive_cmd in sbslice.c) on a made-up GUObjectArray: two chunks of items,
// objects in both. Checks: an object whose item points at it is alive, by its index or read off it (ffffffff, with
// the index in the answer); one whose item was cleared (freed) or points elsewhere (its slot reused), or flagged
// Unreachable or PendingKill, is not; an index past the array is not. Run: ./test/run.sh alive
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
    printf("%s\n", fails ? "FAIL" : "PASS");
    return fails;
}
