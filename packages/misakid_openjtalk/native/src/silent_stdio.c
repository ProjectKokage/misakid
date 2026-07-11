// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

#include <stdarg.h>
#include <stdio.h>
#include <limits.h>

#if CHAR_MIN != -128 || CHAR_MAX != 127
#error "Open JTalk UTF-8 rule tables require signed 8-bit char semantics."
#endif

int misakid_openjtalk_silent_fprintf(FILE *stream, const char *format, ...) {
  (void)stream;
  (void)format;
  return 0;
}

int misakid_openjtalk_silent_printf(const char *format, ...) {
  (void)format;
  return 0;
}
