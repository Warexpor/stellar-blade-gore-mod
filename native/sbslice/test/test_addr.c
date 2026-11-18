// Verify the address resolver against known Steam executables mapped at their section RVAs.
// Both the normal startup path and a forced search must match the executable's reference offsets.
// Skipped without the exe (SB_EXE, default the Steam install). Run: ./test/run.sh addr
#include "host.h"
int mem_readable(u64 p, u64 n) { (void)n; return p >= 0x10000; }
int main(void)
{
    const char *path = getenv("SB_EXE");
    char def[512];
    if (!path || !*path) { snprintf(def, sizeof def, "%s/.local/share/Steam/steamapps/common/StellarBlade/SB/Binaries/Win64/SB-Win64-Shipping.exe", getenv("HOME")); path = def; }
    FILE *f = fopen(path, "rb");
    if (!f) { printf("SKIP no exe\nPASS\n"); return 0; }
    unsigned char hdr[0x1000];
    if (fread(hdr, 1, sizeof hdr, f) != sizeof hdr) return 1;
    u32 nt = *(u32 *)(hdr + 0x3c);
    u32 stamp = *(u32 *)(hdr + nt + 8);
    u32 size = *(u32 *)(hdr + nt + 0x18 + 56); // SizeOfImage
    unsigned char *img = mmap(0, size, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
    memcpy(img, hdr, sizeof hdr);
    int nsec = *(unsigned short *)(hdr + nt + 6), opt = *(unsigned short *)(hdr + nt + 0x14);
    for (int i = 0; i < nsec; i++) {
        unsigned char *s = hdr + nt + 0x18 + opt + i * 40;
        u32 va = *(u32 *)(s + 12), raw = *(u32 *)(s + 16), rp = *(u32 *)(s + 20);
        fseek(f, rp, SEEK_SET);
        if (raw && fread(img + va, 1, raw, f) != raw) { printf("FAIL read section\n"); return 1; }
    }
    fclose(f);
    exe = (u64)img;
    u64 *all[] = { &RVA_EXEC_REWARD_DROP_FORMATION_PATH_LOCATION, &RVA_SET_SKIN_WEIGHT_OVERRIDE, &RVA_GET_SKIN_WEIGHT_BUFFER,
        &RVA_RELEASE_OVERRIDE_SKIN_WEIGHTS, &RVA_MARK_RENDER_STATE_DIRTY, &RVA_WEAK_PTR_GET, &RVA_GUOBJECTARRAY, &RVA_GMALLOC,
        &RVA_NEED_CPU_DATA, &RVA_SB_CONFIG, &RVA_STRIHASH, &RVA_PHOTO_MGR, &RVA_PHOTO_ENTER, &RVA_PHOTO_GATE, &RVA_UI_STACK,
        &RVA_ACTORS_GETTER, &RVA_OBJECTS_GETTER, &RVA_OBJECT_BY_GUID, &RVA_APPLY_STATE,
        &RVA_TEXT_FROM_TABLE, &RVA_UI_LOGICS };
    enum { N = sizeof all / sizeof all[0] };
    u64 want[N];
    for (int i = 0; i < N; i++) want[i] = *all[i];
    if (stamp == 0x6ad8eff1 && size == 0x15fa3000) {
        static const u64 steam_current[] = {
            0x26a81a0, 0x412eb50, 0x412cc00, 0x412e470, 0x408e490, 0x2ba9510, 0x6ddd240, 0x70703c0,
            0x452f530, 0x7037400, 0x117c4f0, 0x7037440, 0x22af080, 0x2321bd0, 0x2134420,
            0x1a98b50, 0x1a98bc0, 0x201d4e0, 0x1a63ac0, 0x2632e30, 0x1a987d0
        };
        _Static_assert(sizeof steam_current == sizeof want, "Steam reference address count");
        memcpy(want, steam_current, sizeof want);
    }
    int fails = 0;
    resolve_addresses();
    printf("Steam executable timestamp %08x, image size %08x: %s\n", stamp, size, addr_state);
    if (addr_missing_core) { printf("FAIL startup: core missing (%s)\n", addr_state); fails++; }
    for (int i = 0; i < N; i++) if (*all[i] != want[i]) { printf("FAIL in place: address %d %llx, want %llx\n", i, *all[i], want[i]); fails++; }
    // every guess off: found by the search
    for (int i = 0; i < N; i++) *all[i] = want[i] + 0x40;
    addr_missing_core = 0;
    resolve_addresses();
    for (int i = 0; i < N; i++) if (*all[i] != want[i]) { printf("FAIL searched: address %d %llx, want %llx\n", i, *all[i], want[i]); fails++; }
    if (addr_missing_core) { printf("FAIL searched: core missing (%s)\n", addr_state); fails++; }
    printf("%s\n", addr_state);
    printf(fails ? "FAIL\n" : "PASS\n");
    return fails != 0;
}
