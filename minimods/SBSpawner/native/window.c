// SBSpawner's window DLL (ue4ss/Mods/SBSpawnerWindow/dlls/main.dll): the gore mod's spawner window alone
// (native/sbslice/spawner.c), its files in the SBSpawner Lua mod's folder. UE4SS loads it as a C++ mod; it exports no
// start_mod: UE4SS logs it as not installable and unloads it, so DllMain pins it in memory first (the window's thread
// ran on in unmapped code: a crash at launch), then starts that thread. Nothing here touches the game
#define SPAWNER_DIR u"ue4ss\\Mods\\SBSpawner\\"
#define SPAWNER_CLASS u"SBSpawnerWindow"
#define SPAWNER_TOAST u"SBSpawnerToast"
#define SPAWNER_TITLE u"Enemy spawner"
#include "../../../native/sbslice/spawner.c"

__declspec(dllimport) int WINAPI DisableThreadLibraryCalls(void *);
__declspec(dllimport) int WINAPI GetModuleHandleExW(u32, const void *, void **);
int WINAPI DllMain(void *inst, u32 reason, void *reserved)
{
    (void)reserved;
    if (reason == 1 /*DLL_PROCESS_ATTACH*/) {
        DisableThreadLibraryCalls(inst);
        void *self = 0;
        if (!GetModuleHandleExW(0x4 /*FROM_ADDRESS*/ | 0x1 /*PIN*/, (const void *)DllMain, &self)) return 1;
        spawner_start();
    }
    return 1;
}
