/* Actual guard source, with every invoked Win32 operation replaced below.
 * Never installs a hook, posts a real message, or reads/writes audio settings.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

typedef struct {
    BOOL window_exists, class_matches, title_matches, post_ok, hook_ok, unhook_ok;
    DWORD actual_pid, owner_pid, current_pid, now, deadline, last_error;
    unsigned int post_calls, next_calls, hook_calls, unhook_calls, remove_calls;
} MockState;

static MockState mock;
#define TEST_BRIDGE ((HWND)(ULONG_PTR)0x1234)
#define TEST_HOOK ((HHOOK)(ULONG_PTR)0x5678)
#define NEXT_RESULT ((LRESULT)77)

static void check(int condition, const char *message)
{
    if (!condition) {
        printf("FAIL: %s\n", message);
        exit(1);
    }
}

static BOOL WINAPI test_IsWindow(HWND window)
{ return mock.window_exists && window == TEST_BRIDGE; }

static int WINAPI test_GetClassNameW(HWND window, LPWSTR value, int size)
{
    const WCHAR *text = mock.class_matches ? L"AutoHotkeyGUI" : L"WrongClass";
    check(window == TEST_BRIDGE && size > (int)wcslen(text), "Class query arguments");
    wcscpy(value, text);
    return (int)wcslen(text);
}

static int WINAPI test_GetWindowTextW(HWND window, LPWSTR value, int size)
{
    const WCHAR *text = mock.title_matches ? L"AirKey.VolumeGuard.Probe.v1" : L"WrongTitle";
    check(window == TEST_BRIDGE && size > (int)wcslen(text), "Title query arguments");
    wcscpy(value, text);
    return (int)wcslen(text);
}

static DWORD WINAPI test_GetWindowThreadProcessId(HWND window, LPDWORD process)
{
    check(window == TEST_BRIDGE, "Process query target");
    *process = mock.actual_pid;
    return 1;
}

static HANDLE WINAPI test_GetPropW(HWND window, LPCWSTR name)
{
    check(window == TEST_BRIDGE, "Property query target");
    if (wcscmp(name, L"AirKey.VolumeGuard.OwnerPID") == 0)
        return (HANDLE)(ULONG_PTR)mock.owner_pid;
    if (wcscmp(name, L"AirKey.VolumeGuard.Deadline") == 0)
        return (HANDLE)(ULONG_PTR)mock.deadline;
    check(0, "Only contract properties may be queried");
    return NULL;
}

static DWORD WINAPI test_GetCurrentProcessId(void) { return mock.current_pid; }
static DWORD WINAPI test_GetTickCount(void) { return mock.now; }
static int WINAPI test_lstrcmpW(LPCWSTR a, LPCWSTR b) { return wcscmp(a, b); }

static HWND WINAPI test_FindWindowW(LPCWSTR cls, LPCWSTR title)
{
    check(wcscmp(cls, L"AutoHotkeyGUI") == 0 &&
          wcscmp(title, L"AirKey.VolumeGuard.Probe.v1") == 0, "Exact bridge lookup");
    return mock.window_exists ? TEST_BRIDGE : NULL;
}

static BOOL WINAPI test_PostMessageW(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    check(window == TEST_BRIDGE && message == WM_APP + 0x47 && wparam == 10 && lparam == 0,
          "Only fixed counter notification may be posted");
    mock.post_calls++;
    return mock.post_ok;
}

static LRESULT WINAPI test_CallNextHookEx(HHOOK hook, int code, WPARAM wparam, LPARAM lparam)
{
    (void)code; (void)wparam; (void)lparam;
    check(hook == NULL, "CallNext uses ignored NULL handle");
    mock.next_calls++;
    return NEXT_RESULT;
}

static void WINAPI test_SetLastError(DWORD error) { mock.last_error = error; }

static HHOOK WINAPI test_SetWindowsHookExW(int type, HOOKPROC callback, HINSTANCE module, DWORD thread)
{
    check(type == WH_SHELL && callback != NULL && module != NULL && thread == 0,
          "Requested hook is global WH_SHELL");
    mock.hook_calls++;
    return mock.hook_ok ? TEST_HOOK : NULL;
}

static HANDLE WINAPI test_RemovePropW(HWND window, LPCWSTR name)
{
    DWORD old = mock.deadline;
    check(window == TEST_BRIDGE && wcscmp(name, L"AirKey.VolumeGuard.Deadline") == 0,
          "Stop removes only its deadline property");
    mock.remove_calls++;
    mock.deadline = 0;
    return (HANDLE)(ULONG_PTR)old;
}

static BOOL WINAPI test_UnhookWindowsHookEx(HHOOK hook)
{
    check(hook == TEST_HOOK, "Unhook uses the original handle");
    check(mock.deadline == 0, "Disarm precedes unhook");
    mock.unhook_calls++;
    return mock.unhook_ok;
}

static BOOL WINAPI test_DisableThreadLibraryCalls(HMODULE module)
{ (void)module; return TRUE; }

/* Define seams only after the Windows declarations. The production include's
 * windows.h is protected by its include guard, so declarations are not rewritten.
 */
#define IsWindow test_IsWindow
#define GetClassNameW test_GetClassNameW
#define GetWindowTextW test_GetWindowTextW
#define GetWindowThreadProcessId test_GetWindowThreadProcessId
#define GetPropW test_GetPropW
#define GetCurrentProcessId test_GetCurrentProcessId
#define GetTickCount test_GetTickCount
#define lstrcmpW test_lstrcmpW
#define FindWindowW test_FindWindowW
#define PostMessageW test_PostMessageW
#define CallNextHookEx test_CallNextHookEx
#define SetLastError test_SetLastError
#define SetWindowsHookExW test_SetWindowsHookExW
#define RemovePropW test_RemovePropW
#define UnhookWindowsHookEx test_UnhookWindowsHookEx
#define DisableThreadLibraryCalls test_DisableThreadLibraryCalls
#include "../native/volume-guard.c"

static void reset(void)
{
    memset(&mock, 0, sizeof mock);
    mock.window_exists = mock.class_matches = mock.title_matches = TRUE;
    mock.post_ok = mock.hook_ok = mock.unhook_ok = TRUE;
    mock.actual_pid = mock.owner_pid = mock.current_pid = 100;
    mock.now = 10000;
    mock.deadline = 11500;
    module_instance = (HINSTANCE)(ULONG_PTR)1;
    installed_hook = NULL;
    host_bridge = NULL;
}

static LPARAM command_param(UINT command, UINT source)
{ return (LPARAM)(((DWORD)command | source) << 16); }

static void expect_pass_through(const char *reason)
{
    check(volume_shell_proc(HSHELL_APPCOMMAND, 0, command_param(10, 0)) == NEXT_RESULT, reason);
    check(mock.next_calls == 1, "Pass-through chains once");
}

int main(void)
{
    reset();
    check(volume_shell_proc(-1, 0, command_param(10, 0)) == NEXT_RESULT
          && mock.next_calls == 1 && mock.post_calls == 0, "Negative hook code always chains");
    reset();
    check(volume_shell_proc(HSHELL_WINDOWCREATED, 0, command_param(10, 0)) == NEXT_RESULT
          && mock.next_calls == 1 && mock.post_calls == 0, "Other hook events always chain");
    reset();
    check(volume_shell_proc(HSHELL_APPCOMMAND, 0, command_param(9, 0)) == NEXT_RESULT
          && mock.next_calls == 1 && mock.post_calls == 0, "Volume down is not swallowed");
    puts("PASS negative/non-command/non-volume-up events chain without posting.");

    reset(); mock.deadline = 0; expect_pass_through("Missing deadline fails open");
    reset(); mock.deadline = mock.now; expect_pass_through("Deadline equal to now is expired");
    reset(); mock.deadline = mock.now - 1; expect_pass_through("Expired heartbeat fails open");
    reset(); mock.owner_pid = 0; expect_pass_through("Missing owner fails open");
    reset(); mock.owner_pid++; expect_pass_through("Mismatched owner PID fails open");
    reset(); mock.window_exists = FALSE; expect_pass_through("Missing bridge fails open");
    reset(); mock.class_matches = FALSE; expect_pass_through("Wrong class fails open");
    reset(); mock.title_matches = FALSE; expect_pass_through("Wrong title fails open");
    reset(); mock.post_ok = FALSE; expect_pass_through("Failed counter notification fails open");
    check(mock.post_calls == 1, "Post failure attempted once");
    puts("PASS missing/expired heartbeat, invalid identity and PostMessage failure all fail open.");

    reset();
    check(volume_shell_proc(HSHELL_APPCOMMAND, 0, command_param(10, 0x1000)) == 1
          && mock.next_calls == 0 && mock.post_calls == 1, "Valid OEM volume-up consumes once");
    reset(); mock.now = 0xffffff00UL; mock.deadline = 500;
    check(volume_shell_proc(HSHELL_APPCOMMAND, 0, command_param(10, 0)) == 1
          && mock.next_calls == 0, "Fresh heartbeat survives DWORD tick wrap");
    puts("PASS valid volume-up consumes only after posting; tick wrap remains correct.");

    reset();
    check(AirKeyGuardStart(TEST_BRIDGE) && installed_hook == TEST_HOOK
          && host_bridge == TEST_BRIDGE && mock.hook_calls == 1, "Mock start stores handle");
    check(AirKeyGuardStart(TEST_BRIDGE) && mock.hook_calls == 1, "Repeated start is idempotent");
    mock.unhook_ok = FALSE;
    check(!AirKeyGuardStop() && installed_hook == TEST_HOOK && host_bridge == TEST_BRIDGE,
          "Failed stop preserves handle/bridge for retry");
    check(mock.deadline == 0 && mock.unhook_calls == 1, "Failed stop remains disarmed");
    expect_pass_through("Failed unhook leaves callbacks harmless");
    mock.unhook_ok = TRUE;
    check(AirKeyGuardStop() && installed_hook == NULL && host_bridge == NULL
          && mock.unhook_calls == 2, "Stop retries retained handle and clears state");
    check(AirKeyGuardStop() && mock.unhook_calls == 2, "Repeated stopped state is harmless");
    puts("PASS Stop disarms first, preserves failed-unhook state, retries and is idempotent.");

    reset(); mock.current_pid++;
    check(!AirKeyGuardStart(TEST_BRIDGE) && mock.last_error == ERROR_INVALID_PARAMETER
          && mock.hook_calls == 0, "Foreign host cannot install hook");
    reset(); mock.hook_ok = FALSE;
    check(!AirKeyGuardStart(TEST_BRIDGE) && installed_hook == NULL && host_bridge == NULL,
          "Failed installation retains no hook state");
    puts("PASS invalid host and installation failure leave no installed state.");
    puts("All checks used mocks. No real hook, messages, key input or audio access.");
    return 0;
}
