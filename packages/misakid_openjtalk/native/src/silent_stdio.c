// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

#include <stdarg.h>
#include <stdio.h>
#include <limits.h>
#include <stdlib.h>

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

#if defined(_WIN32) && !defined(__CYGWIN__)

#define MISAKID_OPENJTALK_MAXIMUM_PATH_UTF8_BYTES 32768
#define MISAKID_OPENJTALK_MAXIMUM_PATH_WIDE_CHARACTERS 32767

static size_t misakid_openjtalk_bounded_string_length(const char *value,
                                                       size_t maximum) {
  size_t length = 0;
  while (length < maximum && value[length] != '\0') {
    ++length;
  }
  return length;
}

static int misakid_openjtalk_is_ascii_letter(wchar_t value) {
  return (value >= L'A' && value <= L'Z') ||
         (value >= L'a' && value <= L'z');
}

/*
 * Dart passes a canonical absolute path after resolveSymbolicLinks(). Prefix
 * drive and UNC paths explicitly so CreateFileW does not depend on the
 * application's longPathAware manifest. The MeCab sources may append a file
 * name with '/', which the extended namespace does not normalize for us.
 */
static wchar_t *misakid_openjtalk_extended_path(wchar_t *path,
                                                size_t path_characters) {
  static const wchar_t drive_prefix[] = L"\\\\?\\";
  static const wchar_t unc_prefix[] = L"\\\\?\\UNC\\";
  size_t prefix_characters = 0;
  size_t skipped_characters = 0;

  for (size_t index = 0; index < path_characters; ++index) {
    if (path[index] == L'/') {
      path[index] = L'\\';
    }
  }

  if (path_characters >= 4 && path[0] == L'\\' && path[1] == L'\\' &&
      path[2] == L'?' && path[3] == L'\\') {
    /* Preserve an already extended path. */
  } else if (path_characters >= 3 &&
             misakid_openjtalk_is_ascii_letter(path[0]) &&
             path[1] == L':' && path[2] == L'\\') {
    prefix_characters = 4;
  } else if (path_characters >= 3 && path[0] == L'\\' &&
             path[1] == L'\\') {
    prefix_characters = 8;
    skipped_characters = 2;
  } else {
    SetLastError(ERROR_BAD_PATHNAME);
    return NULL;
  }

  const size_t normalized_characters =
      prefix_characters + path_characters - skipped_characters;
  if (normalized_characters >
      MISAKID_OPENJTALK_MAXIMUM_PATH_WIDE_CHARACTERS) {
    SetLastError(ERROR_FILENAME_EXCED_RANGE);
    return NULL;
  }

  wchar_t *normalized =
      (wchar_t *)calloc(normalized_characters + 1, sizeof(wchar_t));
  if (normalized == NULL) {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return NULL;
  }
  if (prefix_characters != 0) {
    const wchar_t *prefix =
        skipped_characters == 0 ? drive_prefix : unc_prefix;
    memcpy(normalized, prefix, prefix_characters * sizeof(wchar_t));
  }
  memcpy(normalized + prefix_characters, path + skipped_characters,
         (path_characters - skipped_characters) * sizeof(wchar_t));
  return normalized;
}

HANDLE WINAPI misakid_openjtalk_create_file_utf8(
    LPCSTR filename, DWORD desired_access, DWORD share_mode,
    LPSECURITY_ATTRIBUTES security_attributes, DWORD creation_disposition,
    DWORD flags_and_attributes, HANDLE template_file) {
  if (filename == NULL) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return INVALID_HANDLE_VALUE;
  }

  const size_t utf8_size = misakid_openjtalk_bounded_string_length(
      filename, MISAKID_OPENJTALK_MAXIMUM_PATH_UTF8_BYTES + 1);
  if (utf8_size > MISAKID_OPENJTALK_MAXIMUM_PATH_UTF8_BYTES) {
    SetLastError(ERROR_FILENAME_EXCED_RANGE);
    return INVALID_HANDLE_VALUE;
  }

  const int wide_size = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, filename, -1, NULL, 0);
  if (wide_size <= 0 ||
      wide_size > MISAKID_OPENJTALK_MAXIMUM_PATH_UTF8_BYTES + 1) {
    if (wide_size > MISAKID_OPENJTALK_MAXIMUM_PATH_UTF8_BYTES + 1) {
      SetLastError(ERROR_FILENAME_EXCED_RANGE);
    }
    return INVALID_HANDLE_VALUE;
  }

  wchar_t *wide_filename =
      (wchar_t *)calloc((size_t)wide_size, sizeof(wchar_t));
  if (wide_filename == NULL) {
    SetLastError(ERROR_NOT_ENOUGH_MEMORY);
    return INVALID_HANDLE_VALUE;
  }
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, filename, -1,
                          wide_filename, wide_size) != wide_size) {
    const DWORD error = GetLastError();
    free(wide_filename);
    SetLastError(error);
    return INVALID_HANDLE_VALUE;
  }

  wchar_t *extended_filename = misakid_openjtalk_extended_path(
      wide_filename, (size_t)wide_size - 1);
  const DWORD path_error = GetLastError();
  free(wide_filename);
  if (extended_filename == NULL) {
    SetLastError(path_error);
    return INVALID_HANDLE_VALUE;
  }

  const HANDLE result =
      CreateFileW(extended_filename, desired_access, share_mode,
                  security_attributes, creation_disposition,
                  flags_and_attributes, template_file);
  const DWORD error = GetLastError();
  free(extended_filename);
  SetLastError(error);
  return result;
}

#endif
