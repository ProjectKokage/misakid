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

#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

int misakid_openjtalk_silent_fprintf(FILE *stream, const char *format, ...);
int misakid_openjtalk_silent_printf(const char *format, ...);
void misakid_openjtalk_report_native_error(const char *stage,
                                           const char *message);

#ifdef __cplusplus
}
#endif

#define fprintf misakid_openjtalk_silent_fprintf
#define printf misakid_openjtalk_silent_printf

#endif  // MISAKID_OPENJTALK_SILENT_STDIO_H_
