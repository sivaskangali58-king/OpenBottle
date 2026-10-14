/*
 * OpenBottle Steam CEF compatibility shim, MIT License.
 * Inspired by notpop/steam-on-m1-wine (MIT), see THIRD_PARTY_NOTICES.md.
 * This is not distributed as a binary. Compile locally using mingw-w64.
 */
#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>
#include <stdlib.h>
#include <wchar.h>

static const wchar_t *skip_executable(const wchar_t *p) {
    int quoted = 0;
    while (*p) {
        if (*p == L'"') quoted = !quoted;
        else if ((*p == L' ' || *p == L'\t') && !quoted) break;
        ++p;
    }
    while (*p == L' ' || *p == L'\t') ++p;
    return p;
}

int wmain(void) {
    wchar_t exe[MAX_PATH];
    DWORD count = GetModuleFileNameW(NULL, exe, MAX_PATH);
    if (count == 0 || count >= MAX_PATH) return 10;
    wchar_t *slash = wcsrchr(exe, L'\\');
    if (!slash) return 11;
    *(slash + 1) = L'\0';
    const wchar_t *name = L"steamwebhelper_real.exe";
    size_t realSize = wcslen(exe) + wcslen(name) + 1;
    wchar_t *real = (wchar_t *)calloc(realSize, sizeof(wchar_t));
    if (!real) return 12;
    wcscpy(real, exe);
    wcscat(real, name);
    const wchar_t *tail = skip_executable(GetCommandLineW());
    const wchar_t *flags = L" --disable-gpu --single-process ";
    size_t cmdSize = wcslen(real) + wcslen(flags) + wcslen(tail) + 4;
    wchar_t *cmd = (wchar_t *)calloc(cmdSize, sizeof(wchar_t));
    if (!cmd) { free(real); return 13; }
    swprintf(cmd, cmdSize, L"\"%ls\"%ls%ls", real, flags, tail);
    STARTUPINFOW si = {0};
    PROCESS_INFORMATION pi = {0};
    si.cb = sizeof(si);
    BOOL launched = CreateProcessW(real, cmd, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi);
    free(cmd); free(real);
    if (!launched) return 14;
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD status = 0;
    GetExitCodeProcess(pi.hProcess, &status);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return (int)status;
}
