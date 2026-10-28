// Linux harness for the objects watched as they are made ("O", new_watch in sbslice.c) on a made-up GUObjectArray
// and engine listener list. Checks: the listener goes into the list (in place, and onto a bigger copy when full);
// the SuperStruct offset is found from a child/parent pair; an object of a watched class or a subclass is queued, a
// default object or an unwatched class isn't; "O" hands them out in order into the field, skipping one freed since,
// then null; a full queue drops and counts; the engine's shutdown call takes ours out of its list. Run:
// ./test/run.sh newobj
#include "host.h"
int mem_readable(u64 p, u64 n) { (void)n; return p >= 0x10000; }
static unsigned char cls[5][0x80], objs[6][0x40];
static u64 field;
typedef void (*made_fn)(void *, u64, int);
typedef void (*shut_fn)(void *);
static u64 gm_vt[8], gm_obj[1];
static void *gm_malloc(u64 self, u64 n, u32 align) { (void)self; (void)align; return calloc(1, n); }
static void gm_free(u64 self, void *p) { (void)self; free(p); }
int main(void)
{
    void *m = mmap(0, 0x7100000, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    if (m == MAP_FAILED) { perror("mmap"); return 1; }
    exe = (u64)m;
    int fails = 0;
    gm_vt[2] = (u64)gm_malloc; gm_vt[6] = (u64)gm_free; gm_obj[0] = (u64)gm_vt; *(u64 *)(exe + RVA_GMALLOC) = (u64)gm_obj;
    static unsigned char chunk0[GUO_CHUNK * GUO_ITEM];
    static u64 chunks[1];
    chunks[0] = (u64)chunk0;
    u64 arr = exe + RVA_GUOBJECTARRAY + GUO_OBJOBJECTS;
    *(u64 *)arr = (u64)chunks; *(int *)(arr + 0x14) = GUO_CHUNK;
    // the engine's list: two listeners (the engine's, its vtable in the exe; UE4SS's, its vtable in its own dll:
    // refused when held to the exe, playtest on 3.1.0-6), room for three
    static u64 eng[2][1], lst[3], ue4ss_vt[3];
    eng[0][0] = exe + 0x1000; eng[1][0] = (u64)ue4ss_vt;
    lst[0] = (u64)eng[0]; lst[1] = (u64)eng[1];
    u64 la = exe + RVA_GUOBJECTARRAY + GUO_CREATE_LISTENERS;
    *(u64 *)la = (u64)lst; *(int *)(la + 8) = 2; *(int *)(la + 12) = 3;
    // classes: 0 UObject <- 1 UserWidget <- 2 a widget Blueprint; 3 SBCharacter (unwatched parent chain: 0); 4 other
    *(u64 *)(cls[1] + 0x40) = (u64)cls[0];
    *(u64 *)(cls[2] + 0x40) = (u64)cls[1];
    *(u64 *)(cls[3] + 0x40) = (u64)cls[0];
    *(u64 *)(cls[4] + 0x40) = (u64)cls[0];
    u64 f[] = { (u64)&field, (u64)cls[2], (u64)cls[1], (u64)cls[1], (u64)cls[3] };
    field = 0x1234;
    new_watch(f, 5);
    if (strcmp(lastres, "ok watching 2, super +64") || field) { printf("FAIL watch: \"%s\", field %llx\n", lastres, field); fails++; }
    if (*(int *)(la + 8) != 3 || lst[2] != (u64)&new_listener) { printf("FAIL listener not added in place\n"); fails++; }
    new_watch(f, 5); // (again: not added twice)
    if (*(int *)(la + 8) != 3) { printf("FAIL listener added twice\n"); fails++; }
    // made: a Blueprint widget, a UserWidget's default object, a character, another class, a character freed before
    // its turn, and the last widget
    u64 ocls[6] = { (u64)cls[2], (u64)cls[1], (u64)cls[3], (u64)cls[4], (u64)cls[3], (u64)cls[1] };
    for (int i = 0; i < 6; i++) {
        *(u64 *)(objs[i] + 0x10) = ocls[i];
        *(int *)(objs[i] + UOBJ_INTERNAL_INDEX) = 10 + i;
        *(u64 *)(chunk0 + (u64)(10 + i) * GUO_ITEM) = (u64)objs[i];
    }
    *(u32 *)(objs[1] + 8) = 0x10; // RF_ClassDefaultObject
    u64 *L = *(u64 **)la;
    for (int i = 0; i < 6; i++) ((made_fn)(*(void ***)L[2])[1])((void *)L[2], (u64)objs[i], 10 + i);
    *(u64 *)(chunk0 + 14 * GUO_ITEM) = 0; // objs[4] freed
    new_status();
    if (strcmp(lastres, "ok 4 queued, 0 dropped, 0 taken")) { printf("FAIL status \"%s\"\n", lastres); fails++; }
    u64 want[4] = { (u64)objs[0], (u64)objs[2], (u64)objs[5], 0 };
    for (int i = 0; i < 4; i++) {
        new_next();
        if (field != want[i]) { printf("FAIL next %d: %llx, want %llx\n", i, field, want[i]); fails++; }
    }
    // a full queue: the rest dropped and counted
    for (int i = 0; i < NEW_MAX + 5; i++) new_listener_made(0, (u64)objs[0], 10);
    new_status();
    if (strcmp(lastres, "ok 8192 queued, 5 dropped, 3 taken")) { printf("FAIL full \"%s\"\n", lastres); fails++; }
    // shutdown: out of the engine's list
    ((shut_fn)(*(void ***)L[2])[2])((void *)L[2]);
    if (*(int *)(la + 8) != 2 || new_on) { printf("FAIL shutdown: %d listeners\n", *(int *)(la + 8)); fails++; }
    // a full list: ours onto a bigger copy, the engine's kept (GMalloc: a made-up one over calloc)
    static u64 lst2[2];
    lst2[0] = (u64)eng[0]; lst2[1] = (u64)eng[1];
    *(u64 *)la = (u64)lst2; *(int *)(la + 8) = 2; *(int *)(la + 12) = 2;
    new_watch(f, 5);
    u64 *nd = *(u64 **)la;
    if (strncmp(lastres, "ok", 2) || nd == lst2 || *(int *)(la + 8) != 3 || *(int *)(la + 12) < 3 || nd[0] != (u64)eng[0]
        || nd[2] != (u64)&new_listener) { printf("FAIL grown list: \"%s\"\n", lastres); fails++; }
    // a pair with no SuperStruct link between them
    u64 g[] = { (u64)&field, (u64)cls[3], (u64)cls[1], (u64)cls[1] };
    new_watch(g, 4);
    if (strncmp(lastres, "err", 3)) { printf("FAIL unlinked pair: \"%s\"\n", lastres); fails++; }
    printf("%s\n", fails ? "FAIL" : "PASS");
    return fails;
}
