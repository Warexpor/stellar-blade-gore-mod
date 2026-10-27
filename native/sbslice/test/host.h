// The DLL's code built for Linux: Win32 calls go to stubs (the answer file's last text lands in lastres), engine
// calls to trampolines at exe + RVA. Each harness defines mem_readable for the memory it made up.
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#define __declspec(x)
#define __stdcall
#define u64 U64_
#define u32 U32_
#define u16 U16_
typedef unsigned long long U64_; typedef unsigned int U32_; typedef unsigned short U16_;
#undef u64
#undef u32
#undef u16
#define CreateThread CreateThread_
#define Sleep Sleep_
#define GetAsyncKeyState GetAsyncKeyState_
#define CreateFileW CreateFileW_
#define ReadFile ReadFile_
#define WriteFile WriteFile_
#define CloseHandle CloseHandle_
#define DeleteFileW DeleteFileW_
#define GetModuleHandleW GetModuleHandleW_
#define GetModuleHandleExW GetModuleHandleExW_
#define GetModuleFileNameW GetModuleFileNameW_
#define DisableThreadLibraryCalls DisableThreadLibraryCalls_
#define GetProcessHeap GetProcessHeap_
#define HeapAlloc HeapAlloc_
#define HeapFree HeapFree_
#define VirtualAlloc VirtualAlloc_
#define VirtualFree VirtualFree_
#define VirtualProtect VirtualProtect_
#define FlushInstructionCache FlushInstructionCache_
#define GetCurrentProcess GetCurrentProcess_
#define GetTickCount64 GetTickCount64_
#define GetCurrentThreadId GetCurrentThreadId_
#define AddVectoredExceptionHandler AddVectoredExceptionHandler_
#define DllMain DllMain_
#define SBSLICE_HOSTED
#include "../sbslice.c"
void spawner_start(void) {} // the window is Win32 only
int stats_cmd(const u16 *t, int l, const float *a, const float *b) { (void)t; (void)l; (void)a; (void)b; return 0; } // stats.c: test_stats.c
#undef CreateThread
#undef Sleep
#undef GetAsyncKeyState
#undef CreateFileW
#undef ReadFile
#undef WriteFile
#undef CloseHandle
#undef DeleteFileW
#undef GetModuleHandleW
#undef GetModuleHandleExW
#undef GetModuleFileNameW
#undef DisableThreadLibraryCalls
#undef GetProcessHeap
#undef HeapAlloc
#undef HeapFree
#undef VirtualAlloc
#undef VirtualFree
#undef VirtualProtect
#undef FlushInstructionCache
#undef GetCurrentProcess
#undef GetTickCount64
#undef GetCurrentThreadId
#undef AddVectoredExceptionHandler
static char lastres[65536];
HANDLE CreateThread_(void *a, u64 b, u32(WINAPI *c)(void *), void *d, u32 e, u32 *f) { (void)a;(void)b;(void)c;(void)d;(void)e;(void)f; return 0; }
void Sleep_(u32 x) { (void)x; }
short GetAsyncKeyState_(int k) { (void)k; return 0; }
u64 GetTickCount64_(void) { return 0; }
u32 GetCurrentThreadId_(void) { return 1; }
void *AddVectoredExceptionHandler_(u32 f, long(WINAPI *h)(void *)) { (void)f; (void)h; return 0; }
HANDLE CreateFileW_(const u16 *p, u32 a, u32 b, void *c, u32 d, u32 e, HANDLE f) { (void)p;(void)a;(void)b;(void)c;(void)d;(void)e;(void)f; return (HANDLE)1; }
int ReadFile_(HANDLE h, void *b, u32 n, u32 *g, void *o) { (void)h;(void)b;(void)n;(void)o; *g = 0; return 1; }
int WriteFile_(HANDLE h, const void *b, u32 n, u32 *w, void *o) { (void)h;(void)o; memcpy(lastres, b, n); lastres[n] = 0; *w = n; return 1; }
int CloseHandle_(HANDLE h) { (void)h; return 1; }
int DeleteFileW_(const u16 *p) { (void)p; return 1; }
void *GetModuleHandleW_(const u16 *p) { (void)p; return 0; }
int GetModuleHandleExW_(u32 a, const void *b, void **c) { (void)a;(void)b;(void)c; return 1; }
u32 GetModuleFileNameW_(void *a, u16 *b, u32 c) { (void)a; (void)c; if (b) b[0] = 0; return 0; }
int DisableThreadLibraryCalls_(void *a) { (void)a; return 1; }
HANDLE GetProcessHeap_(void) { return 0; }
void *HeapAlloc_(HANDLE h, u32 f, u64 n) { (void)h; (void)f; return calloc(1, n); }
int HeapFree_(HANDLE h, u32 f, void *p) { (void)h; (void)f; free(p); return 1; }
void *VirtualAlloc_(void *a, u64 n, u32 t, u32 p) { (void)a;(void)t;(void)p; void *m = mmap(0, n, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0); return m == MAP_FAILED ? 0 : m; }
int VirtualFree_(void *a, u64 n, u32 t) { (void)a;(void)n;(void)t; return 1; } // leak, fine
int VirtualProtect_(void *a, u64 n, u32 p, u32 *o) { (void)a;(void)n;(void)p;(void)o; return 0; } // the NeedCPUData patch: never in the harness
int FlushInstructionCache_(HANDLE h, const void *a, u64 n) { (void)h;(void)a;(void)n; return 1; }
HANDLE GetCurrentProcess_(void) { return 0; }
