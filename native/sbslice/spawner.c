// The spawner window: a small always-on-top Win32 window, its own thread, listing the enemies main.lua can spawn.
// Lua and the window talk through files next to the Lua log (paths relative to the game's Win64 dir):
//   spawner.list  Lua -> window: one enemy a line, "<alias>\t<label>" (UTF-8), read whenever the window opens
//   spawner.cmd   Lua -> window: "show" or "hide" (the hotkey), or "toast\t<text>": a note at the top of the screen
//                 that fades out by itself (click-through, never takes the focus); deleted once read
//   spawner.req   window -> Lua: "spawn\t<alias>\t<count>", "clear" or "kill", Lua deletes it once done
//   spawner.state window -> Lua: "1" while the window shows, "0" once hidden: Lua frees the game's mouse meanwhile (the
//                 game kept the cursor captured and nothing in the window could be clicked)
// Nothing here touches the game: Lua does the spawning on the game thread.
typedef unsigned long long u64;
typedef unsigned int u32;
typedef unsigned short u16;
typedef void *HANDLE;
typedef void *HWND;
typedef u64 WPARAM;
typedef long long LPARAM;
typedef long long LRESULT;
#define WINAPI __stdcall
typedef LRESULT(WINAPI *WNDPROC)(HWND, u32, WPARAM, LPARAM);
typedef struct { u32 cbSize, style; WNDPROC proc; int cls, wnd; void *inst, *icon, *cursor, *bg; const u16 *menu, *name; void *iconsm; } WNDCLASSEXW;
typedef struct { HWND hwnd; u32 message; WPARAM w; LPARAM l; u32 time; int x, y, priv; } MSG;

__declspec(dllimport) HANDLE WINAPI CreateThread(void *, u64, u32(WINAPI *)(void *), void *, u32, u32 *);
__declspec(dllimport) HANDLE WINAPI CreateFileW(const u16 *, u32, u32, void *, u32, u32, HANDLE);
__declspec(dllimport) int WINAPI ReadFile(HANDLE, void *, u32, u32 *, void *);
__declspec(dllimport) int WINAPI WriteFile(HANDLE, const void *, u32, u32 *, void *);
__declspec(dllimport) int WINAPI CloseHandle(HANDLE);
__declspec(dllimport) int WINAPI DeleteFileW(const u16 *);
__declspec(dllimport) void *WINAPI GetModuleHandleW(const u16 *);
__declspec(dllimport) int WINAPI MultiByteToWideChar(u32, u32, const char *, int, u16 *, int);
__declspec(dllimport) unsigned short WINAPI RegisterClassExW(const WNDCLASSEXW *);
__declspec(dllimport) HWND WINAPI CreateWindowExW(u32, const u16 *, const u16 *, u32, int, int, int, int, HWND, void *, void *, void *);
__declspec(dllimport) LRESULT WINAPI DefWindowProcW(HWND, u32, WPARAM, LPARAM);
__declspec(dllimport) int WINAPI GetMessageW(MSG *, HWND, u32, u32);
__declspec(dllimport) int WINAPI TranslateMessage(const MSG *);
__declspec(dllimport) LRESULT WINAPI DispatchMessageW(const MSG *);
__declspec(dllimport) LRESULT WINAPI SendMessageW(HWND, u32, WPARAM, LPARAM);
__declspec(dllimport) int WINAPI ShowWindow(HWND, int);
__declspec(dllimport) int WINAPI SetForegroundWindow(HWND);
__declspec(dllimport) void *WINAPI LoadCursorW(void *, const u16 *);
__declspec(dllimport) u64 WINAPI SetTimer(HWND, u64, u32, void *);
__declspec(dllimport) int WINAPI IsWindowVisible(HWND);
__declspec(dllimport) int WINAPI SetWindowTextW(HWND, const u16 *);
__declspec(dllimport) void *WINAPI GetStockObject(int);
__declspec(dllimport) int WINAPI GetSystemMetrics(int);
__declspec(dllimport) void *WINAPI BeginPaint(HWND, void *);
__declspec(dllimport) int WINAPI EndPaint(HWND, const void *);
__declspec(dllimport) int WINAPI FillRect(void *, const int *, void *);
__declspec(dllimport) int WINAPI DrawTextW(void *, const u16 *, int, int *, u32);
__declspec(dllimport) int WINAPI InvalidateRect(HWND, const int *, int);
__declspec(dllimport) int WINAPI SetLayeredWindowAttributes(HWND, u32, unsigned char, u32);
__declspec(dllimport) int WINAPI KillTimer(HWND, u64);
__declspec(dllimport) int WINAPI GetClientRect(HWND, int *);
__declspec(dllimport) int WINAPI SetWindowPos(HWND, HWND, int, int, int, int, u32);
__declspec(dllimport) u32 WINAPI SetTextColor(void *, u32);
__declspec(dllimport) int WINAPI SetBkMode(void *, int);
__declspec(dllimport) void *WINAPI CreateSolidBrush(u32);
__declspec(dllimport) void *WINAPI SelectObject(void *, void *);
__declspec(dllimport) void *WINAPI CreateFontW(int, int, int, int, int, u32, u32, u32, u32, u32, u32, u32, u32, const u16 *);

#define INVALID ((HANDLE)(long long)-1)
#define WM_CLOSE 0x10
#define WM_SETFONT 0x30
#define WM_COMMAND 0x111
#define WM_TIMER 0x113
#define LB_ADDSTRING 0x180
#define LB_RESETCONTENT 0x184
#define LB_GETCURSEL 0x188
#define LB_SETCURSEL 0x186
#define LBN_DBLCLK 2
#define WS_CHILD 0x40000000
#define WS_VISIBLE 0x10000000
#define WS_BORDER 0x800000
#define WS_VSCROLL 0x200000
#define WS_TABSTOP 0x10000
#define WS_CAPTION 0xC00000
#define WS_SYSMENU 0x80000
#define WS_MINIMIZEBOX 0x20000
#define WS_EX_TOPMOST 0x8
#define WS_EX_TOOLWINDOW 0x80
#define LBS_NOTIFY 0x1
#define BS_PUSHBUTTON 0
#define ID_LIST 100
#define ID_SPAWN 101
#define ID_SPAWN3 102
#define ID_CLEAR 103
#define ID_KILL 104
#define MAX_ENEMIES 64

static const u16 LIST[] = u"ue4ss\\Mods\\StellarBladeGore\\spawner.list";
static const u16 CMD[] = u"ue4ss\\Mods\\StellarBladeGore\\spawner.cmd";
static const u16 REQ[] = u"ue4ss\\Mods\\StellarBladeGore\\spawner.req";
static const u16 STATE[] = u"ue4ss\\Mods\\StellarBladeGore\\spawner.state";

static HWND win, list, status, toast;
static u16 toast_text[128];
static int toast_alpha, toast_hold;
static void *toast_font, *toast_bg;
#define WM_PAINT 0x0f
#define TOAST_W 420
#define TOAST_H 54
#define TOAST_HOLD 30   // ticks of 50 ms at full strength (1.5 s), then
#define TOAST_FADE 12   // alpha steps down per tick (about 1 s to nothing)
static char aliases[MAX_ENEMIES][64];
static int naliases;

static int read_all(const u16 *path, char *buf, int max)
{
    HANDLE h = CreateFileW(path, 0x80000000 /*GENERIC_READ*/, 7, 0, 3 /*OPEN_EXISTING*/, 0x80, 0);
    if (h == INVALID) return -1;
    u32 got = 0;
    ReadFile(h, buf, (u32)max - 1, &got, 0);
    CloseHandle(h);
    buf[got] = 0;
    return (int)got;
}

static void write_to(const u16 *path, const char *s)
{
    HANDLE h = CreateFileW(path, 0x40000000 /*GENERIC_WRITE*/, 1, 0, 2 /*CREATE_ALWAYS*/, 0x80, 0);
    if (h == INVALID) return;
    u32 n = 0, w;
    while (s[n]) n++;
    WriteFile(h, s, n, &w, 0);
    CloseHandle(h);
}
static void write_req(const char *s) { write_to(REQ, s); }

static void say(const char *s)
{
    u16 w[128];
    int n = MultiByteToWideChar(65001, 0, s, -1, w, 127);
    w[n > 0 ? n : 0] = 0;
    SetWindowTextW(status, w);
}

// the enemies Lua offers, into the list box (the alias is what a request names)
static void load_list(void)
{
    static char buf[16384];
    SendMessageW(list, LB_RESETCONTENT, 0, 0);
    naliases = 0;
    if (read_all(LIST, buf, sizeof buf) < 0) { say("no spawner.list yet (press the hotkey in game)"); return; }
    char *p = buf;
    while (*p && naliases < MAX_ENEMIES) {
        char *line = p;
        while (*p && *p != '\n') p++;
        if (*p) *p++ = 0;
        char *tab = line;
        while (*tab && *tab != '\t') tab++;
        if (!*tab) continue;
        *tab = 0;
        char *label = tab + 1;
        int k = 0;
        for (; line[k] && k < 63; k++) aliases[naliases][k] = line[k];
        aliases[naliases][k] = 0;
        int ln = 0;
        while (label[ln] && label[ln] != '\r') ln++;
        label[ln] = 0;
        u16 w[160];
        int n = MultiByteToWideChar(65001, 0, label, -1, w, 159);
        w[n > 0 ? n : 0] = 0;
        SendMessageW(list, LB_ADDSTRING, 0, (LPARAM)w);
        naliases++;
    }
    SendMessageW(list, LB_SETCURSEL, 0, 0);
    say(naliases ? "pick one, Spawn (or double-click)" : "the list is empty");
}

static void spawn(int count)
{
    int i = (int)SendMessageW(list, LB_GETCURSEL, 0, 0);
    if (i < 0 || i >= naliases) { say("pick an enemy first"); return; }
    char req[96] = "spawn\t";
    int o = 6;
    for (int k = 0; aliases[i][k] && o < 90; k++) req[o++] = aliases[i][k];
    req[o++] = '\t';
    req[o++] = (char)('0' + count);
    req[o] = 0;
    write_req(req);
    char msg[96] = "asked for ";
    int m = 10;
    for (int k = 0; aliases[i][k] && m < 90; k++) msg[m++] = aliases[i][k];
    msg[m] = 0;
    say(msg);
}

// the toast: a click-through layered popup at the top centre of the screen, shown at full strength for a moment,
// then faded out on its own timer
static void toast_show(const char *utf8)
{
    if (!toast) return;
    int n = MultiByteToWideChar(65001, 0, utf8, -1, toast_text, 127);
    toast_text[n > 0 ? n : 0] = 0;
    int sw = GetSystemMetrics(0 /*SM_CXSCREEN*/);
    SetWindowPos(toast, (HWND)(long long)-1 /*HWND_TOPMOST*/, (sw - TOAST_W) / 2, 80, TOAST_W, TOAST_H, 0x10 /*NOACTIVATE*/);
    toast_alpha = 235; toast_hold = TOAST_HOLD;
    SetLayeredWindowAttributes(toast, 0, (unsigned char)toast_alpha, 2 /*LWA_ALPHA*/);
    InvalidateRect(toast, 0, 1);
    ShowWindow(toast, 4 /*SW_SHOWNOACTIVATE*/);
    SetTimer(toast, 2, 50, 0);
}
static LRESULT WINAPI toast_proc(HWND h, u32 msg, WPARAM w, LPARAM l)
{
    if (msg == WM_PAINT) {
        unsigned char ps[72];
        void *dc = BeginPaint(h, ps);
        int r[4];
        GetClientRect(h, r);
        FillRect(dc, r, toast_bg);
        SetBkMode(dc, 1 /*TRANSPARENT*/);
        SetTextColor(dc, 0x00f0f0f0);
        if (toast_font) SelectObject(dc, toast_font);
        DrawTextW(dc, toast_text, -1, r, 0x1 | 0x4 | 0x20 /*CENTER | VCENTER | SINGLELINE*/);
        EndPaint(h, ps);
        return 0;
    }
    if (msg == WM_TIMER) {
        if (toast_hold > 0) { toast_hold--; return 0; }
        toast_alpha -= TOAST_FADE;
        if (toast_alpha <= 0) { KillTimer(h, 2); ShowWindow(h, 0); return 0; }
        SetLayeredWindowAttributes(h, 0, (unsigned char)toast_alpha, 2);
        return 0;
    }
    return DefWindowProcW(h, msg, w, l);
}

static LRESULT WINAPI proc(HWND h, u32 msg, WPARAM w, LPARAM l)
{
    if (msg == WM_COMMAND) {
        int id = (int)(w & 0xffff), code = (int)(w >> 16 & 0xffff);
        if (id == ID_SPAWN) spawn(1);
        else if (id == ID_SPAWN3) spawn(3);
        else if (id == ID_CLEAR) { write_req("clear"); say("asked to remove every spawned enemy"); }
        else if (id == ID_KILL) { write_req("kill"); say("asked to kill the one nearest her"); }
        else if (id == ID_LIST && code == LBN_DBLCLK) spawn(1);
        return 0;
    }
    if (msg == WM_TIMER) {
        char buf[256];
        if (read_all(CMD, buf, sizeof buf) >= 0) {
            DeleteFileW(CMD);
            if (buf[0] == 't' && buf[1] == 'o' && buf[2] == 'a' && buf[3] == 's' && buf[4] == 't') {
                int k = 5;
                while (buf[k] == '\t' || buf[k] == ' ') k++;
                toast_show(buf + k);
            } else if (buf[0] == 's') { load_list(); ShowWindow(h, 5 /*SW_SHOW*/); SetForegroundWindow(h); }
            else if (buf[0] == 'h') ShowWindow(h, 0 /*SW_HIDE*/);
            else if (buf[0] == 't') {
                if (IsWindowVisible(h)) ShowWindow(h, 0);
                else { load_list(); ShowWindow(h, 5); SetForegroundWindow(h); }
            }
        }
        static int was = -1;
        int v = IsWindowVisible(h) != 0;
        if (v != was) { was = v; write_to(STATE, v ? "1" : "0"); }
        return 0;
    }
    if (msg == WM_CLOSE) { ShowWindow(h, 0); return 0; } // hidden, not destroyed: the hotkey brings it back
    return DefWindowProcW(h, msg, w, l);
}

static HWND child(const u16 *cls, const u16 *text, u32 style, int x, int y, int w, int h, int id, void *inst, void *font)
{
    HWND c = CreateWindowExW(0, cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h, win, (void *)(u64)id, inst, 0);
    if (c && font) SendMessageW(c, WM_SETFONT, (WPARAM)font, 1);
    return c;
}

static u32 WINAPI spawner_thread(void *arg)
{
    (void)arg;
    void *inst = GetModuleHandleW(0);
    WNDCLASSEXW wc = { 0 };
    wc.cbSize = sizeof wc;
    wc.proc = proc;
    wc.inst = inst;
    wc.cursor = LoadCursorW(0, (const u16 *)(u64)32512 /*IDC_ARROW*/);
    wc.bg = (void *)(u64)(15 + 1); // COLOR_BTNFACE + 1
    wc.name = u"SBGoreSpawner";
    if (!RegisterClassExW(&wc)) return 0;
    win = CreateWindowExW(WS_EX_TOPMOST | WS_EX_TOOLWINDOW, u"SBGoreSpawner", u"Stellar Blade Gore: spawner",
                          WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, 60, 60, 320, 464, 0, 0, inst, 0);
    if (!win) return 0;
    void *font = GetStockObject(17 /*DEFAULT_GUI_FONT*/);
    list = child(u"LISTBOX", u"", WS_BORDER | WS_VSCROLL | WS_TABSTOP | LBS_NOTIFY, 8, 8, 288, 300, ID_LIST, inst, font);
    child(u"BUTTON", u"Spawn", WS_TABSTOP | BS_PUSHBUTTON, 8, 312, 90, 28, ID_SPAWN, inst, font);
    child(u"BUTTON", u"Spawn 3", WS_TABSTOP | BS_PUSHBUTTON, 104, 312, 90, 28, ID_SPAWN3, inst, font);
    child(u"BUTTON", u"Remove all", WS_TABSTOP | BS_PUSHBUTTON, 200, 312, 96, 28, ID_CLEAR, inst, font);
    child(u"BUTTON", u"Kill nearest", WS_TABSTOP | BS_PUSHBUTTON, 8, 346, 288, 28, ID_KILL, inst, font);
    status = child(u"STATIC", u"", 0, 8, 382, 288, 40, 0, inst, font);
    WNDCLASSEXW tc = { 0 };
    tc.cbSize = sizeof tc;
    tc.proc = toast_proc;
    tc.inst = inst;
    tc.name = u"SBGoreToast";
    toast_bg = CreateSolidBrush(0x00201818);
    toast_font = CreateFontW(-24, 0, 0, 0, 600 /*SEMIBOLD*/, 0, 0, 0, 1 /*DEFAULT_CHARSET*/, 0, 0, 5 /*CLEARTYPE*/, 0, u"Segoe UI");
    if (RegisterClassExW(&tc))
        toast = CreateWindowExW(0x8 | 0x80 | 0x20 | 0x80000 | 0x08000000 /*TOPMOST TOOLWINDOW TRANSPARENT LAYERED NOACTIVATE*/,
                                u"SBGoreToast", u"", 0x80000000 /*WS_POPUP*/, 0, 0, TOAST_W, TOAST_H, 0, 0, inst, 0);
    SetTimer(win, 1, 200, 0);
    MSG m;
    while (GetMessageW(&m, 0, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageW(&m); }
    return 0;
}

void spawner_start(void)
{
    DeleteFileW(CMD);
    DeleteFileW(STATE);
    CreateThread(0, 0, spawner_thread, 0, 0, 0);
}
