// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// This frontend-only ABI calls the Open JTalk pipeline distributed in the
// pyopenjtalk 0.4.1 source archive. It is a new compatibility boundary, not
// part of upstream Open JTalk or pyopenjtalk. See THIRD_PARTY_NOTICES.md.

#ifndef MISAKID_OPENJTALK_H_
#define MISAKID_OPENJTALK_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(MISAKID_OPENJTALK_BUILD)
#define MISAKID_OPENJTALK_EXPORT __declspec(dllexport)
#else
#define MISAKID_OPENJTALK_EXPORT __declspec(dllimport)
#endif
#else
#define MISAKID_OPENJTALK_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct misakid_openjtalk_context misakid_openjtalk_context;
typedef struct misakid_openjtalk_result misakid_openjtalk_result;

enum misakid_openjtalk_status {
  MISAKID_OPENJTALK_OK = 0,
  MISAKID_OPENJTALK_INVALID_ARGUMENT = 1,
  MISAKID_OPENJTALK_INPUT_TOO_LARGE = 2,
  MISAKID_OPENJTALK_INVALID_UTF8 = 3,
  MISAKID_OPENJTALK_DICTIONARY_LOAD_FAILED = 4,
  MISAKID_OPENJTALK_ANALYSIS_FAILED = 5,
  MISAKID_OPENJTALK_RESULT_LIMIT_EXCEEDED = 6,
  MISAKID_OPENJTALK_NATIVE_DIAGNOSTIC = 7,
  MISAKID_OPENJTALK_OUT_OF_MEMORY = 8,
  MISAKID_OPENJTALK_INTERNAL_ERROR = 9,
};

enum misakid_openjtalk_identity_field {
  MISAKID_OPENJTALK_ID_ADAPTER_VERSION = 0,
  MISAKID_OPENJTALK_ID_PYOPENJTALK_VERSION = 1,
  MISAKID_OPENJTALK_ID_OPENJTALK_VERSION = 2,
  MISAKID_OPENJTALK_ID_SOURCE_TREE_SHA256 = 3,
  MISAKID_OPENJTALK_ID_SOURCE_SDIST_SHA256 = 4,
  MISAKID_OPENJTALK_ID_PATCH_SET = 5,
  MISAKID_OPENJTALK_ID_DICTIONARY_TREE_SHA256 = 6,
};

enum misakid_openjtalk_string_field {
  MISAKID_OPENJTALK_STRING = 0,
  MISAKID_OPENJTALK_POS = 1,
  MISAKID_OPENJTALK_POS_GROUP1 = 2,
  MISAKID_OPENJTALK_POS_GROUP2 = 3,
  MISAKID_OPENJTALK_POS_GROUP3 = 4,
  MISAKID_OPENJTALK_CTYPE = 5,
  MISAKID_OPENJTALK_CFORM = 6,
  MISAKID_OPENJTALK_ORIG = 7,
  MISAKID_OPENJTALK_READ = 8,
  MISAKID_OPENJTALK_PRON = 9,
  MISAKID_OPENJTALK_CHAIN_RULE = 10,
};

enum misakid_openjtalk_integer_field {
  MISAKID_OPENJTALK_ACC = 0,
  MISAKID_OPENJTALK_MORA_SIZE = 1,
  MISAKID_OPENJTALK_CHAIN_FLAG = 2,
};

MISAKID_OPENJTALK_EXPORT uint32_t misakid_openjtalk_abi_version(void);

MISAKID_OPENJTALK_EXPORT const uint8_t *misakid_openjtalk_identity_data(
    uint32_t field);

MISAKID_OPENJTALK_EXPORT size_t misakid_openjtalk_identity_size(
    uint32_t field);

// Allocates memory owned by this library so Dart does not need a platform
// allocator dependency. A zero-byte request still returns writable storage.
MISAKID_OPENJTALK_EXPORT uint8_t *misakid_openjtalk_buffer_alloc(size_t size);

MISAKID_OPENJTALK_EXPORT void misakid_openjtalk_buffer_free(void *buffer);

MISAKID_OPENJTALK_EXPORT misakid_openjtalk_context *
misakid_openjtalk_context_create(const uint8_t *dictionary_path,
                                 size_t dictionary_path_size,
                                 size_t max_input_bytes);

MISAKID_OPENJTALK_EXPORT uint32_t misakid_openjtalk_context_status(
    const misakid_openjtalk_context *context);

MISAKID_OPENJTALK_EXPORT const uint8_t *
misakid_openjtalk_context_error_stage_data(
    const misakid_openjtalk_context *context);

MISAKID_OPENJTALK_EXPORT size_t misakid_openjtalk_context_error_stage_size(
    const misakid_openjtalk_context *context);

MISAKID_OPENJTALK_EXPORT const uint8_t *
misakid_openjtalk_context_error_message_data(
    const misakid_openjtalk_context *context);

MISAKID_OPENJTALK_EXPORT size_t misakid_openjtalk_context_error_message_size(
    const misakid_openjtalk_context *context);

MISAKID_OPENJTALK_EXPORT void misakid_openjtalk_context_destroy(
    misakid_openjtalk_context *context);

MISAKID_OPENJTALK_EXPORT misakid_openjtalk_result *
misakid_openjtalk_analyze(misakid_openjtalk_context *context,
                          const uint8_t *utf8, size_t utf8_size);

MISAKID_OPENJTALK_EXPORT uint32_t misakid_openjtalk_result_status(
    const misakid_openjtalk_result *result);

MISAKID_OPENJTALK_EXPORT const uint8_t *
misakid_openjtalk_result_error_stage_data(
    const misakid_openjtalk_result *result);

MISAKID_OPENJTALK_EXPORT size_t misakid_openjtalk_result_error_stage_size(
    const misakid_openjtalk_result *result);

MISAKID_OPENJTALK_EXPORT const uint8_t *
misakid_openjtalk_result_error_message_data(
    const misakid_openjtalk_result *result);

MISAKID_OPENJTALK_EXPORT size_t misakid_openjtalk_result_error_message_size(
    const misakid_openjtalk_result *result);

MISAKID_OPENJTALK_EXPORT size_t misakid_openjtalk_result_word_count(
    const misakid_openjtalk_result *result);

MISAKID_OPENJTALK_EXPORT const uint8_t *
misakid_openjtalk_result_word_string_data(
    const misakid_openjtalk_result *result, size_t word_index,
    uint32_t field);

MISAKID_OPENJTALK_EXPORT size_t misakid_openjtalk_result_word_string_size(
    const misakid_openjtalk_result *result, size_t word_index,
    uint32_t field);

MISAKID_OPENJTALK_EXPORT int32_t misakid_openjtalk_result_word_integer(
    const misakid_openjtalk_result *result, size_t word_index,
    uint32_t field);

MISAKID_OPENJTALK_EXPORT void misakid_openjtalk_result_destroy(
    misakid_openjtalk_result *result);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // MISAKID_OPENJTALK_H_
