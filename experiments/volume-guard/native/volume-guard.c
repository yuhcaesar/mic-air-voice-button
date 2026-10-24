/*
 * Temporary x64, user-mode WH_SHELL probe. No input injection or audio writes.
 *
 * Exports (BOOL return, GetLastError on failure):
 *   AirKeyGuardStart(HWND bridge) -- install one global shell hook.
 *   AirKeyGuardStop(void)         -- disarm first, then unhook; retry on FALSE.
 *
 * Host bridge contract:
 *   class: AutoHotkeyGUI; title: AirKey.VolumeGuard.Probe.v1
 *   property AirKey.VolumeGuard.OwnerPID: actual bridge process ID.
 *   property AirKey.VolumeGuard.Deadline: DWORD GetTickCount() + 1500,
 *       refreshed every 250 ms only while the user enabled this probe.
 *       Missing/zero/expired deadline means disabled. Host must stop its
 *       heartbeat before Stop(), and remove both properties before destroying.
 *   message 0x8047: wParam=10, lParam=0. Count received messages in the host.
 *
 * Keep the host DLL loaded until process exit, including after successful Stop.
 * UnhookWindowsHookEx may return while another callback is still executing.
 * Never force-unload the DLL in another process; Windows owns injected copies.
 * Calls to Start/Stop are serialized by the host GUI thread.
 *
 * Deliberate probe limitation: shell events contain no physical device ID.
 * While enabled, this intercepts every volume-up shell command that reaches
 * this hook, not only Mic Air. Commands already handled by the foreground app,
 * other desktops, and security/architecture boundaries may bypass this hook.
 */

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#define GUARD_MESSAGE (WM_APP + 0x47)
#define GUARD_VOLUME_UP 10

static const WCHAR bridge_class[] = L"AutoHotkeyGUI";
static const WCHAR bridge_title[] = L"AirKey.VolumeGuard.Probe.v1";
static const WCHAR owner_property[] = L"AirKey.VolumeGuard.OwnerPID";
static const WCHAR deadline_property[] = L"AirKey.VolumeGuard.Deadline";

/* Each injected process has its own copy; only the installing host uses these. */
static HINSTANCE module_instance = NULL;
static HHOOK installed_hook = NULL;
static HWND host_bridge = NULL;

static BOOL bridge_matches(HWND window, BOOL require_current_process)
{
    WCHAR class_name[64];
    WCHAR title[128];
    DWORD actual_pid = 0;
    ULONG_PTR marked_pid;

    if (!IsWindow(window))
        return FALSE;
    if (!GetClassNameW(window, class_name, 64) ||
        lstrcmpW(class_name, bridge_class) != 0)
        return FALSE;
    if (!GetWindowTextW(window, title, 128) ||
        lstrcmpW(title, bridge_title) != 0)
        return FALSE;
    if (!GetWindowThreadProcessId(window, &actual_pid) || !actual_pid)
        return FALSE;
    marked_pid = (ULONG_PTR)GetPropW(window, owner_property);
    if (marked_pid != (ULONG_PTR)actual_pid)
        return FALSE;
    return !require_current_process || actual_pid == GetCurrentProcessId();
}

static BOOL bridge_is_armed(HWND window)
{
    DWORD deadline;

    if (!bridge_matches(window, FALSE))
        return FALSE;
    deadline = (DWORD)(ULONG_PTR)GetPropW(window, deadline_property);
    /* DWORD subtraction plus signed comparison tolerates GetTickCount wrap. */
    return deadline != 0 && (LONG)(deadline - GetTickCount()) > 0;
}

static LRESULT CALLBACK volume_shell_proc(int code, WPARAM wparam, LPARAM lparam)
{
    HWND bridge;
    UINT command;

    if (code == HSHELL_APPCOMMAND) {
        /* GET_APPCOMMAND_LPARAM: high word, without FAPPCOMMAND source bits. */
        command = HIWORD((DWORD_PTR)lparam) & 0x0fff;
        if (command == GUARD_VOLUME_UP) {
            bridge = FindWindowW(bridge_class, bridge_title);
            if (bridge_is_armed(bridge) &&
                PostMessageW(bridge, GUARD_MESSAGE, GUARD_VOLUME_UP, 0)) {
                /* Actual ShellProc consumption, not a shell-window notice. */
                return 1;
            }
        }
    }
    /* Includes code < 0 and a dead/disabled/expired/unreachable bridge. */
    return CallNextHookEx(NULL, code, wparam, lparam);
}

__declspec(dllexport) BOOL WINAPI AirKeyGuardStart(HWND bridge)
{
    HHOOK hook;

    if (!module_instance || !bridge_matches(bridge, TRUE)) {
        SetLastError(ERROR_INVALID_PARAMETER);
        return FALSE;
    }
    if (installed_hook) {
        if (host_bridge == bridge)
            return TRUE;
        SetLastError(ERROR_BUSY);
        return FALSE;
    }
    hook = SetWindowsHookExW(WH_SHELL, volume_shell_proc, module_instance, 0);
    if (!hook)
        return FALSE;
    host_bridge = bridge;
    installed_hook = hook;
    return TRUE;
}

__declspec(dllexport) BOOL WINAPI AirKeyGuardStop(void)
{
    /* Do not clear properties on a recycled or foreign window handle. */
    if (host_bridge && bridge_matches(host_bridge, TRUE))
        RemovePropW(host_bridge, deadline_property);

    if (installed_hook && !UnhookWindowsHookEx(installed_hook))
        return FALSE; /* Preserve handle and bridge so the host can retry. */

    installed_hook = NULL;
    host_bridge = NULL;
    return TRUE;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    if (reason == DLL_PROCESS_ATTACH) {
        module_instance = instance;
        DisableThreadLibraryCalls(instance);
    }
    /* No hook operations under the loader lock; host explicitly calls Stop. */
    (void)reserved;
    return TRUE;
}

#ifdef AIRKEY_NOCRT
/* TinyCC's PE linker expects _dllstart. This Windows-only DLL needs no CRT. */
BOOL WINAPI _dllstart(HINSTANCE instance, DWORD reason, LPVOID reserved)
{
    return DllMain(instance, reason, reserved);
}
#endif
