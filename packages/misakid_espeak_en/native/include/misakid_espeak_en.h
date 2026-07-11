/* Copyright 2026 the misakid contributors.
 * SPDX-License-Identifier: Apache-2.0 */

#ifndef MISAKID_ESPEAK_EN_H_
#define MISAKID_ESPEAK_EN_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(MISAKID_ESPEAK_EN_BUILD)
#define MISAKID_ESPEAK_EN_API __declspec(dllexport)
#else
#define MISAKID_ESPEAK_EN_API __declspec(dllimport)
#endif
#else
#define MISAKID_ESPEAK_EN_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct misakid_espeak_en_context misakid_espeak_en_context;
typedef struct misakid_espeak_en_result misakid_espeak_en_result;

enum misakid_espeak_en_status {
  MISAKID_ESPEAK_EN_OK = 0,
  MISAKID_ESPEAK_EN_INVALID_ARGUMENT = 1,
  MISAKID_ESPEAK_EN_INPUT_TOO_LARGE = 2,
  MISAKID_ESPEAK_EN_INVALID_UTF8 = 3,
  MISAKID_ESPEAK_EN_RUNTIME_LOAD_FAILED = 4,
  MISAKID_ESPEAK_EN_RUNTIME_SYMBOL_MISSING = 5,
  MISAKID_ESPEAK_EN_RUNTIME_INITIALIZE_FAILED = 6,
  MISAKID_ESPEAK_EN_RUNTIME_IDENTITY_MISMATCH = 7,
  MISAKID_ESPEAK_EN_VOICE_FAILED = 8,
  MISAKID_ESPEAK_EN_CONVERSION_FAILED = 9,
  MISAKID_ESPEAK_EN_RESULT_LIMIT_EXCEEDED = 10,
  MISAKID_ESPEAK_EN_OUT_OF_MEMORY = 11,
  MISAKID_ESPEAK_EN_INTERNAL_ERROR = 12
};

enum misakid_espeak_en_dialect {
  MISAKID_ESPEAK_EN_AMERICAN = 0,
  MISAKID_ESPEAK_EN_BRITISH = 1
};

MISAKID_ESPEAK_EN_API uint32_t misakid_espeak_en_abi_version(void);
MISAKID_ESPEAK_EN_API const uint8_t *
misakid_espeak_en_identity_data(uint32_t field);
MISAKID_ESPEAK_EN_API size_t misakid_espeak_en_identity_size(uint32_t field);

MISAKID_ESPEAK_EN_API uint8_t *misakid_espeak_en_buffer_alloc(size_t size);
MISAKID_ESPEAK_EN_API void misakid_espeak_en_buffer_free(void *buffer);

MISAKID_ESPEAK_EN_API misakid_espeak_en_context *
misakid_espeak_en_context_create(const uint8_t *runtime_library_path,
                                 size_t runtime_library_path_size,
                                 const uint8_t *data_path,
                                 size_t data_path_size,
                                 size_t max_input_bytes,
                                 size_t max_output_bytes);
MISAKID_ESPEAK_EN_API uint32_t misakid_espeak_en_context_status(
    const misakid_espeak_en_context *context);
MISAKID_ESPEAK_EN_API const uint8_t *
misakid_espeak_en_context_error_stage_data(
    const misakid_espeak_en_context *context);
MISAKID_ESPEAK_EN_API size_t misakid_espeak_en_context_error_stage_size(
    const misakid_espeak_en_context *context);
MISAKID_ESPEAK_EN_API const uint8_t *
misakid_espeak_en_context_error_message_data(
    const misakid_espeak_en_context *context);
MISAKID_ESPEAK_EN_API size_t misakid_espeak_en_context_error_message_size(
    const misakid_espeak_en_context *context);
MISAKID_ESPEAK_EN_API void
misakid_espeak_en_context_destroy(misakid_espeak_en_context *context);

MISAKID_ESPEAK_EN_API misakid_espeak_en_result *misakid_espeak_en_phonemize(
    misakid_espeak_en_context *context, const uint8_t *utf8, size_t utf8_size,
    uint32_t dialect);
MISAKID_ESPEAK_EN_API uint32_t
misakid_espeak_en_result_status(const misakid_espeak_en_result *result);
MISAKID_ESPEAK_EN_API const uint8_t *
misakid_espeak_en_result_error_stage_data(
    const misakid_espeak_en_result *result);
MISAKID_ESPEAK_EN_API size_t misakid_espeak_en_result_error_stage_size(
    const misakid_espeak_en_result *result);
MISAKID_ESPEAK_EN_API const uint8_t *
misakid_espeak_en_result_error_message_data(
    const misakid_espeak_en_result *result);
MISAKID_ESPEAK_EN_API size_t misakid_espeak_en_result_error_message_size(
    const misakid_espeak_en_result *result);
MISAKID_ESPEAK_EN_API const uint8_t *misakid_espeak_en_result_output_data(
    const misakid_espeak_en_result *result);
MISAKID_ESPEAK_EN_API size_t misakid_espeak_en_result_output_size(
    const misakid_espeak_en_result *result);
MISAKID_ESPEAK_EN_API void
misakid_espeak_en_result_destroy(misakid_espeak_en_result *result);

#ifdef __cplusplus
}
#endif

#endif /* MISAKID_ESPEAK_EN_H_ */
