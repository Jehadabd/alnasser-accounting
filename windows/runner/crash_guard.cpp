// crash_guard.cpp
//
// Native (C++) crash log for Windows.
//
// The Firebase plugins on Windows are C++. When they throw an exception that
// nobody catches, the process dies instantly (exit code 0xE06D7363) and the
// Dart log shows nothing. That is how the Firebase setup wizard closed the
// second PC without a trace.
//
// For every C++ exception (first 40 per run) this writes: the exception type,
// its what() message, the thread, and the throw location (module + offset).
// If the process then dies, an "UNHANDLED" entry is written as well.
// It never changes behaviour: it logs and lets normal handling continue.
//
// Log files:
//   * %LOCALAPPDATA%\alnaser_logs\native_errors.log           (always; support)
//   * Desktop\alnaser_stress_reports\native_errors.log         (only when
//     Desktop\alnaser_stress_reports\sync_debug.flag exists: developer PC)
//
// Keep this file ASCII-only: the runner builds with /W4 /WX, and non-ASCII
// characters can raise C4819 on machines with a non-UTF-8 code page.

#include "crash_guard.h"

#include <windows.h>
#include <shlobj.h>

#include <cstdio>
#include <cstring>

namespace {

constexpr DWORD kCxxExceptionCode = 0xE06D7363;  // 'msc'
constexpr LONG kMaxLogged = 40;

wchar_t g_paths[2][MAX_PATH];
int g_path_count = 0;
volatile LONG g_logged = 0;
DWORD g_main_thread = 0;

void AppendText(const char* text) {
  for (int i = 0; i < g_path_count; ++i) {
    HANDLE h = ::CreateFileW(g_paths[i], FILE_APPEND_DATA,
                             FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                             OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) continue;
    DWORD written = 0;
    ::WriteFile(h, text, static_cast<DWORD>(strlen(text)), &written, nullptr);
    ::CloseHandle(h);
  }
}

// Module that contains `addr`, and the offset inside it.
void ModuleOf(const void* addr, char* out, size_t out_len,
              unsigned long long* offset) {
  HMODULE mod = nullptr;
  out[0] = 0;
  *offset = reinterpret_cast<unsigned long long>(addr);
  if (::GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCWSTR>(addr), &mod) &&
      mod != nullptr) {
    wchar_t path[MAX_PATH];
    const DWORD n = ::GetModuleFileNameW(mod, path, MAX_PATH);
    const wchar_t* base = path;
    for (DWORD i = 0; i < n; ++i) {
      if (path[i] == L'\\' || path[i] == L'/') base = path + i + 1;
    }
    ::WideCharToMultiByte(CP_UTF8, 0, base, -1, out, static_cast<int>(out_len),
                          nullptr, nullptr);
    *offset = static_cast<unsigned long long>(
        reinterpret_cast<const char*>(addr) -
        reinterpret_cast<const char*>(mod));
  } else {
    strncpy_s(out, out_len, "?", _TRUNCATE);
  }
}

// MSVC C++ exception metadata on x64 (fields are RVAs from the image base).
struct CxxThrowInfo {
  unsigned attributes;
  int pmfnUnwind;
  int pForwardCompat;
  int pCatchableTypeArray;
};
struct CxxCatchableTypeArray {
  int nCatchableTypes;
  int arrayOfCatchableTypes[1];
};
struct CxxCatchableType {
  unsigned properties;
  int pType;
  int mdisp;
  int pdisp;
  int vdisp;
  int sizeOrOffset;
  int copyFunction;
};
struct CxxTypeDescriptor {
  const void* pVFTable;
  void* spare;
  char name[1];
};

using WhatFn = const char* (*)(const void*);

// Exception type chain and, for std::exception, its message. Every memory
// read is inside __try: the crash logger must never be a crash itself.
void DescribeCxx(const EXCEPTION_RECORD* rec, char* out, size_t n) {
  out[0] = 0;
  __try {
    if (rec->NumberParameters < 3) return;
    const ULONG_PTR magic = rec->ExceptionInformation[0];
    if (magic != 0x19930520 && magic != 0x19930521 && magic != 0x19930522) {
      return;
    }
    const char* obj =
        reinterpret_cast<const char*>(rec->ExceptionInformation[1]);
    const CxxThrowInfo* ti =
        reinterpret_cast<const CxxThrowInfo*>(rec->ExceptionInformation[2]);
    const ULONG_PTR base =
        rec->NumberParameters >= 4 ? rec->ExceptionInformation[3] : 0;
    if (ti == nullptr) return;
    const CxxCatchableTypeArray* cta =
        reinterpret_cast<const CxxCatchableTypeArray*>(
            base + ti->pCatchableTypeArray);
    size_t used = 0;
    const char* std_ex = nullptr;
    for (int i = 0; i < cta->nCatchableTypes && i < 8; ++i) {
      const CxxCatchableType* ct = reinterpret_cast<const CxxCatchableType*>(
          base + cta->arrayOfCatchableTypes[i]);
      const CxxTypeDescriptor* td =
          reinterpret_cast<const CxxTypeDescriptor*>(base + ct->pType);
      const int k = _snprintf_s(out + used, n - used, _TRUNCATE, "%s%s",
                                i == 0 ? "type=" : " < ", td->name);
      if (k > 0) used += static_cast<size_t>(k);
      if (obj != nullptr && strcmp(td->name, ".?AVexception@std@@") == 0) {
        std_ex = obj + ct->mdisp;
      }
    }
    if (std_ex != nullptr) {
      // std::exception vtable: [0] deleting destructor, [1] what().
      const void* const* vtbl = *reinterpret_cast<const void* const* const*>(std_ex);
      const WhatFn what_fn =
          reinterpret_cast<WhatFn>(const_cast<void*>(vtbl[1]));
      const char* what = what_fn(std_ex);
      if (what != nullptr) {
        _snprintf_s(out + used, n - used, _TRUNCATE, "\n  what=%s", what);
      }
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    strncat_s(out, n, " (describe failed)", _TRUNCATE);
  }
}

void AppendStack(char* buf, size_t n) {
  void* frames[40];
  const USHORT count = ::RtlCaptureStackBackTrace(1, 40, frames, nullptr);
  size_t used = strlen(buf);
  for (USHORT i = 0; i < count && used + 1 < n; ++i) {
    char mod[160];
    unsigned long long off = 0;
    ModuleOf(frames[i], mod, sizeof(mod), &off);
    const int k = _snprintf_s(buf + used, n - used, _TRUNCATE,
                              "    #%02u %s+0x%llx\n",
                              static_cast<unsigned>(i), mod, off);
    if (k <= 0) break;
    used += static_cast<size_t>(k);
  }
}

void WriteReport(PEXCEPTION_POINTERS info, const char* kind) {
  static char buf[16384];  // static: keep the faulting thread's stack small
  SYSTEMTIME st;
  ::GetLocalTime(&st);
  const DWORD code = info->ExceptionRecord->ExceptionCode;
  char where[160];
  unsigned long long where_off = 0;
  ModuleOf(info->ExceptionRecord->ExceptionAddress, where, sizeof(where),
           &where_off);
  const DWORD tid = ::GetCurrentThreadId();
  _snprintf_s(buf, sizeof(buf), _TRUNCATE,
              "\n[%04u-%02u-%02u %02u:%02u:%02u.%03u] %s code=0x%08lX at "
              "%s+0x%llx thread=%lu%s\n  ",
              st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
              st.wMilliseconds, kind, code, where, where_off, tid,
              tid == g_main_thread ? " (main/platform thread)" : "");
  if (code == kCxxExceptionCode) {
    char desc[2048];
    DescribeCxx(info->ExceptionRecord, desc, sizeof(desc));
    strncat_s(buf, sizeof(buf), desc, _TRUNCATE);
  }
  strncat_s(buf, sizeof(buf), "\n  stack:\n", _TRUNCATE);
  AppendStack(buf, sizeof(buf));
  AppendText(buf);
}

LONG CALLBACK OnFirstChance(PEXCEPTION_POINTERS info) {
  if (info->ExceptionRecord->ExceptionCode != kCxxExceptionCode) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  if (::InterlockedIncrement(&g_logged) > kMaxLogged) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  WriteReport(info, "C++ exception (first chance)");
  return EXCEPTION_CONTINUE_SEARCH;
}

LONG WINAPI OnUnhandled(PEXCEPTION_POINTERS info) {
  WriteReport(info, "UNHANDLED - the app is closing");
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void InstallCrashGuard() {
  g_main_thread = ::GetCurrentThreadId();

  PWSTR known = nullptr;
  if (SUCCEEDED(::SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr,
                                       &known))) {
    wchar_t dir[MAX_PATH];
    swprintf_s(dir, L"%s\\alnaser_logs", known);
    ::CreateDirectoryW(dir, nullptr);
    swprintf_s(g_paths[g_path_count++], MAX_PATH, L"%s\\native_errors.log",
               dir);
    ::CoTaskMemFree(known);
  }
  known = nullptr;
  if (SUCCEEDED(
          ::SHGetKnownFolderPath(FOLDERID_Desktop, 0, nullptr, &known))) {
    wchar_t flag[MAX_PATH];
    swprintf_s(flag, L"%s\\alnaser_stress_reports\\sync_debug.flag", known);
    if (::GetFileAttributesW(flag) != INVALID_FILE_ATTRIBUTES) {
      swprintf_s(g_paths[g_path_count++], MAX_PATH,
                 L"%s\\alnaser_stress_reports\\native_errors.log", known);
    }
    ::CoTaskMemFree(known);
  }

  ::AddVectoredExceptionHandler(1, OnFirstChance);
  ::SetUnhandledExceptionFilter(OnUnhandled);

  SYSTEMTIME st;
  ::GetLocalTime(&st);
  char line[160];
  _snprintf_s(line, sizeof(line), _TRUNCATE,
              "\n===== %04u-%02u-%02u %02u:%02u:%02u start (pid %lu) =====\n",
              st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
              ::GetCurrentProcessId());
  AppendText(line);
}
