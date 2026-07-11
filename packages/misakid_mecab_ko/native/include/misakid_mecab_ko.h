// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// This ABI wraps the pinned mecab-ko runtime and dictionary used by the
// misakid Korean adapter. It is a new compatibility boundary and is not part
// of upstream MeCab, mecab-ko, or python-mecab-ko.

#ifndef MISAKID_MECAB_KO_H_
#define MISAKID_MECAB_KO_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(MISAKID_MECAB_KO_BUILD)
#define MISAKID_MECAB_KO_EXPORT __declspec(dllexport)
#else
#define MISAKID_MECAB_KO_EXPORT __declspec(dllimport)
#endif
#else
#define MISAKID_MECAB_KO_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct misakid_mecab_ko_context misakid_mecab_ko_context;
typedef struct misakid_mecab_ko_result misakid_mecab_ko_result;

enum misakid_mecab_ko_status {
  MISAKID_MECAB_KO_OK = 0,
  MISAKID_MECAB_KO_INVALID_ARGUMENT = 1,
  MISAKID_MECAB_KO_INPUT_TOO_LARGE = 2,
  MISAKID_MECAB_KO_INVALID_UTF8 = 3,
  MISAKID_MECAB_KO_DICTIONARY_LOAD_FAILED = 4,
  MISAKID_MECAB_KO_ANALYSIS_FAILED = 5,
  MISAKID_MECAB_KO_RESULT_LIMIT_EXCEEDED = 6,
  MISAKID_MECAB_KO_NATIVE_DIAGNOSTIC = 7,
  MISAKID_MECAB_KO_OUT_OF_MEMORY = 8,
  MISAKID_MECAB_KO_INTERNAL_ERROR = 9,
};

enum misakid_mecab_ko_identity_field {
  MISAKID_MECAB_KO_ID_ADAPTER_VERSION = 0,
  MISAKID_MECAB_KO_ID_MECAB_KO_VERSION = 1,
  MISAKID_MECAB_KO_ID_SOURCE_TREE_SHA256 = 2,
  MISAKID_MECAB_KO_ID_SOURCE_ARCHIVE_SHA256 = 3,
  MISAKID_MECAB_KO_ID_PATCH_SET = 4,
  MISAKID_MECAB_KO_ID_DICTIONARY_TREE_SHA256 = 5,
};

enum misakid_mecab_ko_string_field {
  MISAKID_MECAB_KO_SURFACE = 0,
  MISAKID_MECAB_KO_TAG = 1,
};

MISAKID_MECAB_KO_EXPORT uint32_t misakid_mecab_ko_abi_version(void);

MISAKID_MECAB_KO_EXPORT const uint8_t *
misakid_mecab_ko_identity_data(uint32_t field);

MISAKID_MECAB_KO_EXPORT size_t misakid_mecab_ko_identity_size(uint32_t field);

// Allocates memory owned by this library so Dart does not need a platform
// allocator dependency. A zero-byte request still returns writable storage.
MISAKID_MECAB_KO_EXPORT uint8_t *misakid_mecab_ko_buffer_alloc(size_t size);

MISAKID_MECAB_KO_EXPORT void misakid_mecab_ko_buffer_free(void *buffer);

// The dictionary path must identify a caller-validated copy of the pinned
// dictionary. This function additionally verifies the identity fields exposed
// by mecab_dictionary_info(). max_input_bytes must be in the range 1..64 MiB.
MISAKID_MECAB_KO_EXPORT misakid_mecab_ko_context *
misakid_mecab_ko_context_create(const uint8_t *dictionary_path,
                                size_t dictionary_path_size,
                                size_t max_input_bytes);

MISAKID_MECAB_KO_EXPORT uint32_t
misakid_mecab_ko_context_status(const misakid_mecab_ko_context *context);

MISAKID_MECAB_KO_EXPORT const uint8_t *
misakid_mecab_ko_context_error_stage_data(
    const misakid_mecab_ko_context *context);

MISAKID_MECAB_KO_EXPORT size_t misakid_mecab_ko_context_error_stage_size(
    const misakid_mecab_ko_context *context);

MISAKID_MECAB_KO_EXPORT const uint8_t *
misakid_mecab_ko_context_error_message_data(
    const misakid_mecab_ko_context *context);

MISAKID_MECAB_KO_EXPORT size_t misakid_mecab_ko_context_error_message_size(
    const misakid_mecab_ko_context *context);

// Safe to use as a Dart NativeFinalizer callback.
MISAKID_MECAB_KO_EXPORT void
misakid_mecab_ko_context_destroy(misakid_mecab_ko_context *context);

MISAKID_MECAB_KO_EXPORT misakid_mecab_ko_result *
misakid_mecab_ko_analyze(misakid_mecab_ko_context *context, const uint8_t *utf8,
                         size_t utf8_size);

MISAKID_MECAB_KO_EXPORT uint32_t
misakid_mecab_ko_result_status(const misakid_mecab_ko_result *result);

MISAKID_MECAB_KO_EXPORT const uint8_t *
misakid_mecab_ko_result_error_stage_data(const misakid_mecab_ko_result *result);

MISAKID_MECAB_KO_EXPORT size_t
misakid_mecab_ko_result_error_stage_size(const misakid_mecab_ko_result *result);

MISAKID_MECAB_KO_EXPORT const uint8_t *
misakid_mecab_ko_result_error_message_data(
    const misakid_mecab_ko_result *result);

MISAKID_MECAB_KO_EXPORT size_t misakid_mecab_ko_result_error_message_size(
    const misakid_mecab_ko_result *result);

MISAKID_MECAB_KO_EXPORT size_t
misakid_mecab_ko_result_token_count(const misakid_mecab_ko_result *result);

MISAKID_MECAB_KO_EXPORT const uint8_t *
misakid_mecab_ko_result_token_string_data(const misakid_mecab_ko_result *result,
                                          size_t token_index, uint32_t field);

MISAKID_MECAB_KO_EXPORT size_t misakid_mecab_ko_result_token_string_size(
    const misakid_mecab_ko_result *result, size_t token_index, uint32_t field);

// Safe to use as a Dart NativeFinalizer callback.
MISAKID_MECAB_KO_EXPORT void
misakid_mecab_ko_result_destroy(misakid_mecab_ko_result *result);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // MISAKID_MECAB_KO_H_
