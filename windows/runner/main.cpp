#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <cwctype>
#include <iterator>
#include <string>

#include "crash_guard.h"
#include "flutter_window.h"
#include "utils.h"

// ============================================================================
// Single instance.
//
// Double-clicking the icon (or opening the app while it is open) does not open
// a second window: the new process brings the open window to the front and
// exits at once, before Flutter starts and before the database is opened.
// Two windows on one database means two sync engines, two LAN servers on the
// same port and concurrent writes - that is what this prevents.
//
// The mutex is keyed by the path of this exe: an install opens once, while a
// copy in another folder (e.g. the alnaser_pc2_sim test copy) still runs.
//
// Keep this file ASCII-only: the runner builds with /W4 /WX, and non-ASCII
// characters raise C4819 on machines with a non-UTF-8 (e.g. Arabic) code page.
// ============================================================================

static std::wstring ExePath() {
  wchar_t buf[MAX_PATH * 2] = {0};
  DWORD n = GetModuleFileNameW(nullptr, buf, static_cast<DWORD>(std::size(buf)));
  return std::wstring(buf, n);
}

static std::wstring Lower(std::wstring s) {
  for (auto& c : s) c = static_cast<wchar_t>(std::towlower(c));
  return s;
}

// Short FNV-1a hash of the exe path (mutex names cannot contain backslashes).
static std::wstring PathHash(const std::wstring& path) {
  unsigned long long h = 1469598103934665603ULL;
  for (wchar_t c : Lower(path)) {
    h ^= static_cast<unsigned long long>(c);
    h *= 1099511628211ULL;
  }
  wchar_t out[32];
  swprintf_s(out, L"%016llX", h);
  return out;
}

struct FindCtx {
  std::wstring exe;  // our exe path, lower case
  DWORD self_pid;
  HWND found;
};

// A Flutter window owned by another process of the SAME exe (not any Flutter app).
static BOOL CALLBACK FindOurWindow(HWND hwnd, LPARAM lp) {
  auto* ctx = reinterpret_cast<FindCtx*>(lp);
  wchar_t cls[128] = {0};
  GetClassNameW(hwnd, cls, 127);
  if (wcscmp(cls, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0) return TRUE;
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == 0 || pid == ctx->self_pid) return TRUE;
  HANDLE proc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!proc) return TRUE;
  wchar_t path[MAX_PATH * 2] = {0};
  DWORD len = static_cast<DWORD>(std::size(path));
  BOOL ok = QueryFullProcessImageNameW(proc, 0, path, &len);
  CloseHandle(proc);
  if (ok && Lower(std::wstring(path, len)) == ctx->exe) {
    ctx->found = hwnd;
    return FALSE;
  }
  return TRUE;
}

// Seats (multi-seat PCs such as ASTER: a second monitor + keyboard + mouse on the
// same PC works as a second cashier on the same database). The number allowed
// comes from the signed license; Dart writes it to %LOCALAPPDATA%\alnaser_logs\seats.txt.
// Each running copy holds one machine-wide mutex slot (Global\, so it also works
// when every seat is its own Windows session). Dart re-checks the limit against
// the license and the app_seats table, so editing the file gains nothing.
static int AllowedSeats() {
  wchar_t base[MAX_PATH] = {0};
  DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", base, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) return 1;
  std::wstring path = std::wstring(base) + L"\\alnaser_logs\\seats.txt";
  FILE* f = nullptr;
  if (_wfopen_s(&f, path.c_str(), L"r") != 0 || f == nullptr) return 1;
  int v = 1;
  if (fscanf_s(f, "%d", &v) != 1) v = 1;
  fclose(f);
  if (v < 1) v = 1;
  if (v > 8) v = 8;
  return v;
}

static std::wstring SlotMutexName(const std::wstring& exe, int slot) {
  std::wstring name = L"Global\\AlnaserAccounting_Single_" + PathHash(exe);
  if (slot > 1) name += L"_S" + std::to_wstring(slot);
  return name;
}

// Tries to own the mutex of [slot]. Returns the handle, or nullptr if another copy owns it.
static HANDLE TakeSlot(const std::wstring& exe, int slot) {
  HANDLE h = CreateMutexW(nullptr, FALSE, SlotMutexName(exe, slot).c_str());
  if (h == nullptr) return nullptr;
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    CloseHandle(h);
    return nullptr;
  }
  return h;
}

static int SeatFromCommandLine(const wchar_t* cl) {
  if (cl == nullptr) return 0;
  const wchar_t* p = wcsstr(cl, L"--seat=");
  if (p == nullptr) return 0;
  int v = _wtoi(p + 7);
  return (v >= 1 && v <= 8) ? v : 0;
}

static void BringExistingToFront(const std::wstring& exe) {
  FindCtx ctx{Lower(exe), GetCurrentProcessId(), nullptr};
  // The first instance may still be creating its window (fast double click): wait up to 5 s.
  for (int i = 0; i < 50 && ctx.found == nullptr; i++) {
    EnumWindows(FindOurWindow, reinterpret_cast<LPARAM>(&ctx));
    if (ctx.found == nullptr) Sleep(100);
  }
  HWND h = ctx.found;
  if (h == nullptr) return;
  if (IsIconic(h)) {
    ShowWindow(h, SW_RESTORE);
  } else if (!IsWindowVisible(h)) {
    ShowWindow(h, SW_SHOW);
  }
  // This process was just started by the user, so it may set the foreground window.
  SetForegroundWindow(h);
  BringWindowToTop(h);
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single instance per seat: checked first, before any initialization.
  const std::wstring exe = ExePath();
  const bool relaunch = command_line != nullptr && wcsstr(command_line, L"--relaunch") != nullptr;
  HANDLE single_mutex = nullptr;
  int slot = 0;
  if (relaunch) {
    // In-app restart: the old process (same seat) is exiting now. Wait for its
    // slot (up to 15 s) instead of focusing it and exiting, which would close the app.
    const int want = SeatFromCommandLine(command_line) > 0 ? SeatFromCommandLine(command_line) : 1;
    for (int i = 0; i < 75 && single_mutex == nullptr; i++) {
      single_mutex = TakeSlot(exe, want);
      if (single_mutex == nullptr) Sleep(200);
    }
    if (single_mutex != nullptr) slot = want;
  } else {
    const int seats = AllowedSeats();
    for (int k = 1; k <= seats && single_mutex == nullptr; k++) {
      single_mutex = TakeSlot(exe, k);
      if (single_mutex != nullptr) slot = k;
    }
  }
  if (single_mutex == nullptr) {
    // Every allowed seat is taken: bring this desktop's window to the front, or
    // explain (the open copy may be on another seat's screen).
    FindCtx probe{Lower(exe), GetCurrentProcessId(), nullptr};
    EnumWindows(FindOurWindow, reinterpret_cast<LPARAM>(&probe));
    if (probe.found != nullptr) {
      BringExistingToFront(exe);
    } else {
      MessageBoxW(nullptr,
                  L"\x0627\x0644\x0628\x0631\x0646\x0627\x0645\x062C \x0645\x0641\x062A\x0648\x062D \x0627\x0644\x0622\x0646 \x0639\x0644\x0649 \x0634\x0627\x0634\x0629 \x0623\x062E\x0631\x0649 \x0645\x0646 \x0647\x0630\x0647 \x0627\x0644\x062D\x0627\x0633\x0628\x0629\x060C \x0648\x0643\x0644 \x0627\x0644\x0634\x0627\x0634\x0627\x062A \x0627\x0644\x0645\x0633\x0645\x0648\x062D\x0629 \x0641\x064A \x0627\x0644\x062A\x0631\x062E\x064A\x0635 \x0645\x0633\x062A\x0639\x0645\x0644\x0629.",
                  L"\x0627\x0644\x0646\x0627\x0635\x0631 \x0644\x0644\x062D\x0633\x0627\x0628\x0627\x062A",
                  MB_OK | MB_ICONINFORMATION | MB_RTLREADING | MB_RIGHT);
    }
    return EXIT_SUCCESS;
  }

  // Native crash log (C++ exceptions from plugins): see crash_guard.cpp.
  InstallCrashGuard();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  // Tell Dart which seat this copy holds (relaunch keeps the same seat).
  if (SeatFromCommandLine(command_line) == 0) {
    command_line_arguments.push_back("--seat=" + std::to_string(slot));
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"\x0627\x0644\x0646\x0627\x0635\x0631 \x0644\x0644\x062D\x0633\x0627\x0628\x0627\x062A", origin, size)) {
    if (single_mutex) CloseHandle(single_mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  // The mutex is also released automatically if the process is killed.
  if (single_mutex) CloseHandle(single_mutex);
  return EXIT_SUCCESS;
}
