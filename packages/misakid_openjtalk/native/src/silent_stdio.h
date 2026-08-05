// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// Force-included only while compiling the pinned Open JTalk frontend sources.
// The original runtime writes diagnostics directly to process stdio. The Dart
// adapter reports bounded structured errors instead, so those writes are
// replaced with inert functions. The shim still checks every status-bearing
// stage and records its own diagnostic.

#ifndef MISAKID_OPENJTALK_SILENT_STDIO_H_
#define MISAKID_OPENJTALK_SILENT_STDIO_H_

#if defined(_WIN32) && !defined(__CYGWIN__)
#ifndef _CRT_DECLARE_NONSTDC_NAMES
#define _CRT_DECLARE_NONSTDC_NAMES 1
#endif
#ifndef _CRT_NONSTDC_NO_DEPRECATE
#define _CRT_NONSTDC_NO_DEPRECATE 1
#endif
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS 1
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN 1
#endif
#ifndef NOMINMAX
#define NOMINMAX 1
#endif
#include <windows.h>
/* MeCab's option parser owns a label named ERROR. */
#ifdef ERROR
#undef ERROR
#endif
#endif

#include <stdio.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

int misakid_openjtalk_silent_fprintf(FILE *stream, const char *format, ...);
int misakid_openjtalk_silent_printf(const char *format, ...);
void misakid_openjtalk_report_native_error(const char *stage,
                                           const char *message);

#if defined(_WIN32) && !defined(__CYGWIN__)
/*
 * The pinned MeCab mmap implementation uses CreateFileA even though this ABI
 * accepts a UTF-8 dictionary path. Force its call through a bounded, strict
 * UTF-8-to-UTF-16 adapter without modifying the identity-pinned vendor tree.
 */
HANDLE WINAPI misakid_openjtalk_create_file_utf8(
    LPCSTR filename, DWORD desired_access, DWORD share_mode,
    LPSECURITY_ATTRIBUTES security_attributes, DWORD creation_disposition,
    DWORD flags_and_attributes, HANDLE template_file);
#endif

#ifdef __cplusplus
}
#endif

#if defined(_WIN32) && !defined(__CYGWIN__)
#define CreateFileA misakid_openjtalk_create_file_utf8
/*
 * Open JTalk's C frontend uses the POSIX spelling while the Windows CRT
 * guarantees the underscored entry point. The force-include makes the mapping
 * explicit; MeCab methods named `strdup` are renamed consistently within this
 * private translation-unit set and do not cross the adapter ABI.
 */
#define strdup _strdup
#endif

#define fprintf misakid_openjtalk_silent_fprintf
#define printf misakid_openjtalk_silent_printf

#endif  // MISAKID_OPENJTALK_SILENT_STDIO_H_
