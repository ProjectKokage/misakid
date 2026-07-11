// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

#include <stdarg.h>
#include <stdio.h>

int misakid_openjtalk_silent_fprintf(FILE *stream, const char *format, ...) {
  (void)stream;
  (void)format;
  return 0;
}

int misakid_openjtalk_silent_printf(const char *format, ...) {
  (void)format;
  return 0;
}
