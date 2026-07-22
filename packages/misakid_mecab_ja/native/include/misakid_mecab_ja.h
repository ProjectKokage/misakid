/* Copyright 2026 the misakid contributors.
 * SPDX-License-Identifier: Apache-2.0 */

#ifndef MISAKID_MECAB_JA_H_
#define MISAKID_MECAB_JA_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(MISAKID_MECAB_JA_BUILD)
#define MISAKID_MECAB_JA_API __declspec(dllexport)
#else
#define MISAKID_MECAB_JA_API __declspec(dllimport)
#endif
#else
#define MISAKID_MECAB_JA_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct misakid_mecab_ja_context misakid_mecab_ja_context;
typedef struct misakid_mecab_ja_result misakid_mecab_ja_result;

enum misakid_mecab_ja_status {
  MISAKID_MECAB_JA_OK = 0,
  MISAKID_MECAB_JA_INVALID_ARGUMENT = 1,
  MISAKID_MECAB_JA_INPUT_TOO_LARGE = 2,
  MISAKID_MECAB_JA_INVALID_UTF8 = 3,
  MISAKID_MECAB_JA_DICTIONARY_LOAD_FAILED = 4,
  MISAKID_MECAB_JA_ANALYSIS_FAILED = 5,
  MISAKID_MECAB_JA_RESULT_LIMIT_EXCEEDED = 6,
  MISAKID_MECAB_JA_NATIVE_DIAGNOSTIC = 7,
  MISAKID_MECAB_JA_OUT_OF_MEMORY = 8,
  MISAKID_MECAB_JA_INTERNAL_ERROR = 9
};

enum misakid_mecab_ja_word_string_field {
  MISAKID_MECAB_JA_SURFACE = 0,
  MISAKID_MECAB_JA_PRONUNCIATION = 1,
  MISAKID_MECAB_JA_KANA = 2
};

enum misakid_mecab_ja_word_integer_field {
  MISAKID_MECAB_JA_CHAR_TYPE = 0,
  MISAKID_MECAB_JA_IS_UNKNOWN = 1,
  MISAKID_MECAB_JA_HAS_PRONUNCIATION = 2,
  MISAKID_MECAB_JA_HAS_KANA = 3
};

MISAKID_MECAB_JA_API uint32_t misakid_mecab_ja_abi_version(void);
MISAKID_MECAB_JA_API const uint8_t *
misakid_mecab_ja_identity_data(uint32_t field);
MISAKID_MECAB_JA_API size_t misakid_mecab_ja_identity_size(uint32_t field);

MISAKID_MECAB_JA_API uint8_t *misakid_mecab_ja_buffer_alloc(size_t size);
MISAKID_MECAB_JA_API void misakid_mecab_ja_buffer_free(void *buffer);

MISAKID_MECAB_JA_API misakid_mecab_ja_context *
misakid_mecab_ja_context_create(const uint8_t *dictionary_path,
                                size_t dictionary_path_size,
                                size_t max_input_bytes);
MISAKID_MECAB_JA_API uint32_t misakid_mecab_ja_context_status(
    const misakid_mecab_ja_context *context);
MISAKID_MECAB_JA_API uint32_t misakid_mecab_ja_context_feature_field_count(
    const misakid_mecab_ja_context *context);
MISAKID_MECAB_JA_API const uint8_t *
misakid_mecab_ja_context_error_stage_data(
    const misakid_mecab_ja_context *context);
MISAKID_MECAB_JA_API size_t misakid_mecab_ja_context_error_stage_size(
    const misakid_mecab_ja_context *context);
MISAKID_MECAB_JA_API const uint8_t *
misakid_mecab_ja_context_error_message_data(
    const misakid_mecab_ja_context *context);
MISAKID_MECAB_JA_API size_t misakid_mecab_ja_context_error_message_size(
    const misakid_mecab_ja_context *context);
MISAKID_MECAB_JA_API void
misakid_mecab_ja_context_destroy(misakid_mecab_ja_context *context);

MISAKID_MECAB_JA_API misakid_mecab_ja_result *misakid_mecab_ja_analyze(
    misakid_mecab_ja_context *context, const uint8_t *utf8, size_t utf8_size);
MISAKID_MECAB_JA_API uint32_t
misakid_mecab_ja_result_status(const misakid_mecab_ja_result *result);
MISAKID_MECAB_JA_API const uint8_t *
misakid_mecab_ja_result_error_stage_data(
    const misakid_mecab_ja_result *result);
MISAKID_MECAB_JA_API size_t misakid_mecab_ja_result_error_stage_size(
    const misakid_mecab_ja_result *result);
MISAKID_MECAB_JA_API const uint8_t *
misakid_mecab_ja_result_error_message_data(
    const misakid_mecab_ja_result *result);
MISAKID_MECAB_JA_API size_t misakid_mecab_ja_result_error_message_size(
    const misakid_mecab_ja_result *result);
MISAKID_MECAB_JA_API size_t misakid_mecab_ja_result_word_count(
    const misakid_mecab_ja_result *result);
MISAKID_MECAB_JA_API const uint8_t *
misakid_mecab_ja_result_word_string_data(
    const misakid_mecab_ja_result *result, size_t word_index, uint32_t field);
MISAKID_MECAB_JA_API size_t misakid_mecab_ja_result_word_string_size(
    const misakid_mecab_ja_result *result, size_t word_index, uint32_t field);
MISAKID_MECAB_JA_API int32_t misakid_mecab_ja_result_word_integer(
    const misakid_mecab_ja_result *result, size_t word_index, uint32_t field);
MISAKID_MECAB_JA_API void
misakid_mecab_ja_result_destroy(misakid_mecab_ja_result *result);

#ifdef __cplusplus
}
#endif

#endif /* MISAKID_MECAB_JA_H_ */
