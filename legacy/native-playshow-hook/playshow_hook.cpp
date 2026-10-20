#include <Windows.h>
#include <Psapi.h>

#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>

#pragma comment(lib, "Psapi.lib")

extern "C" __declspec(dllexport) int InitPlayShowHook(void*);

static std::mutex g_mu;

static std::string dll_dir()
{
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       reinterpret_cast<LPCWSTR>(&InitPlayShowHook),
                       &self);
    char path[MAX_PATH]{};
    if (!self || !GetModuleFileNameA(self, path, MAX_PATH))
    {
        return {};
    }
    std::string out = path;
    auto slash = out.find_last_of("\\/");
    if (slash != std::string::npos)
    {
        out.resize(slash);
    }
    return out;
}

static void write_text_file(const std::string& path, const char* msg)
{
    HANDLE f = CreateFileA(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE)
    {
        return;
    }
    DWORD w = 0;
    WriteFile(f, msg, static_cast<DWORD>(std::strlen(msg)), &w, nullptr);
    CloseHandle(f);
}
static char g_last[1024];
static bool g_have_new = false;
static uint8_t* g_orig = nullptr;
static uint8_t g_stolen[16]{};
static uint8_t* g_tramp = nullptr;
static bool g_installed = false;

using OrigFn = void*(__fastcall*)(void* self, void* out_fs);
static OrigFn g_orig_fn = nullptr;

static void utf16_to_utf8(const wchar_t* w, int n, char* out, int outsz)
{
    int o = 0;
    for (int i = 0; i < n && w && o + 1 < outsz; ++i)
    {
        unsigned wc = static_cast<unsigned>(w[i]);
        if (wc == 0)
        {
            break;
        }
        if (wc < 0x80)
        {
            out[o++] = static_cast<char>(wc);
        }
        else
        {
            out[o++] = '?';
        }
    }
    out[o] = 0;
}

static void* __fastcall hooked(void* self, void* out_fs);
static uint8_t* find_fn();
static bool write_abs_jmp(uint8_t* at, void* dest, size_t region);

static bool seh_read_fs(void* fs, wchar_t** data, int32_t* num)
{
    __try
    {
        *data = *reinterpret_cast<wchar_t**>(fs);
        *num = *reinterpret_cast<int32_t*>(static_cast<uint8_t*>(fs) + 8);
        return true;
    }
    __except (EXCEPTION_EXECUTE_HANDLER)
    {
        return false;
    }
}

static void record_fstring(void* fs)
{
    if (!fs)
    {
        return;
    }
    wchar_t* data = nullptr;
    int32_t num = 0;
    if (!seh_read_fs(fs, &data, &num))
    {
        return;
    }
    if (!data || num <= 1 || num > 1024)
    {
        return;
    }
    char tmp[1024];
    utf16_to_utf8(data, num, tmp, 1024);
    if (!tmp[0])
    {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(g_mu);
        std::strncpy(g_last, tmp, sizeof(g_last) - 1);
        g_last[sizeof(g_last) - 1] = 0;
        g_have_new = true;
    }
    auto dir = dll_dir();
    if (!dir.empty())
    {
        write_text_file(dir + "\\last_show.txt", tmp);
    }
}

extern "C" __declspec(dllexport) int InitPlayShowHook(void*)
{
    HMODULE self = nullptr;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_PIN,
                       reinterpret_cast<LPCWSTR>(&InitPlayShowHook),
                       &self);
    if (g_installed)
    {
        return 0;
    }
    g_orig = find_fn();
    const char* msg = "fail-find";
    if (g_orig)
    {
        std::memcpy(g_stolen, g_orig, 12);
        g_tramp = static_cast<uint8_t*>(VirtualAlloc(nullptr, 64, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE));
        if (g_tramp)
        {
            std::memcpy(g_tramp, g_stolen, 12);
            uint8_t* back = g_orig + 12;
            g_tramp[12] = 0x48;
            g_tramp[13] = 0xB8;
            std::memcpy(g_tramp + 14, &back, 8);
            g_tramp[22] = 0xFF;
            g_tramp[23] = 0xE0;
            g_orig_fn = reinterpret_cast<OrigFn>(g_tramp);
            if (write_abs_jmp(g_orig, reinterpret_cast<void*>(&hooked), 12))
            {
                g_installed = true;
                msg = "ok";
            }
            else
            {
                msg = "fail-detour";
            }
        }
        else
        {
            msg = "fail-alloc";
        }
    }
    auto dir = dll_dir();
    if (!dir.empty())
    {
        write_text_file(dir + "\\hook_status.txt", msg);
    }
    return 0;
}

static bool module_span(uint8_t*& base, size_t& size)
{
    MODULEINFO info{};
    HMODULE m = GetModuleHandleW(nullptr);
    if (!GetModuleInformation(GetCurrentProcess(), m, &info, sizeof(info)))
    {
        return false;
    }
    base = static_cast<uint8_t*>(info.lpBaseOfDll);
    size = static_cast<size_t>(info.SizeOfImage);
    return true;
}

static uint8_t* find_fn()
{
    uint8_t* base = nullptr;
    size_t size = 0;
    if (!module_span(base, size))
    {
        return nullptr;
    }
    const wchar_t needle[] = L" PlayShow : %s";
    uint8_t* str = nullptr;
    const size_t nlen = sizeof(needle);
    for (size_t i = 0; i + nlen < size; ++i)
    {
        if (std::memcmp(base + i, needle, nlen) == 0)
        {
            str = base + i;
            break;
        }
    }
    if (!str)
    {
        return nullptr;
    }

    MEMORY_BASIC_INFORMATION mbi{};
    uint8_t* lea = nullptr;
    for (uint8_t* p = base; p < base + size; p += mbi.RegionSize ? mbi.RegionSize : 0x1000)
    {
        if (!VirtualQuery(p, &mbi, sizeof(mbi)))
        {
            break;
        }
        if (!(mbi.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)))
        {
            continue;
        }
        auto* start = static_cast<uint8_t*>(mbi.BaseAddress);
        auto* end = start + mbi.RegionSize;
        if (end > base + size)
        {
            end = base + size;
        }
        for (uint8_t* i = start; i + 7 < end; ++i)
        {
            if (i[0] != 0x48 || i[1] != 0x8D || (i[2] & 0xC7) != 0x05)
            {
                continue;
            }
            int32_t disp = 0;
            std::memcpy(&disp, i + 3, 4);
            if (i + 7 + disp == str)
            {
                lea = i;
                break;
            }
        }
        if (lea)
        {
            break;
        }
    }
    if (!lea)
    {
        return nullptr;
    }
    static const uint8_t pro[] = {0x48, 0x89, 0x74, 0x24, 0x18, 0x57, 0x48, 0x83, 0xEC, 0x50, 0x33, 0xF6};
    for (uint8_t* i = lea; i > lea - 0x400; --i)
    {
        if (std::memcmp(i, pro, sizeof(pro)) == 0)
        {
            return i;
        }
    }
    return nullptr;
}

static bool write_abs_jmp(uint8_t* at, void* dest, size_t region)
{
    DWORD old = 0;
    if (!VirtualProtect(at, region, PAGE_EXECUTE_READWRITE, &old))
    {
        return false;
    }
    at[0] = 0x48;
    at[1] = 0xB8;
    std::memcpy(at + 2, &dest, 8);
    at[10] = 0xFF;
    at[11] = 0xE0;
    VirtualProtect(at, region, old, &old);
    FlushInstructionCache(GetCurrentProcess(), at, region);
    return true;
}

static void* __fastcall hooked(void* self, void* out_fs)
{
    void* ret = g_orig_fn(self, out_fs);
    record_fstring(out_fs);
    return ret;
}

BOOL APIENTRY DllMain(HMODULE, DWORD, LPVOID)
{
    return TRUE;
}
