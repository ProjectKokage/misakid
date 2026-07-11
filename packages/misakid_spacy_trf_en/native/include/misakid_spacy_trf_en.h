/* Copyright 2026 the misakid contributors.
 * SPDX-License-Identifier: Apache-2.0 */

#ifndef MISAKID_SPACY_TRF_EN_H_
#define MISAKID_SPACY_TRF_EN_H_

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32)
#if defined(MISAKID_SPACY_TRF_EN_BUILD)
#define MISAKID_SPACY_TRF_EN_API __declspec(dllexport)
#else
#define MISAKID_SPACY_TRF_EN_API __declspec(dllimport)
#endif
#else
#define MISAKID_SPACY_TRF_EN_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct misakid_spacy_trf_en_context misakid_spacy_trf_en_context;
typedef struct misakid_spacy_trf_en_result misakid_spacy_trf_en_result;

enum misakid_spacy_trf_en_status {
  MISAKID_SPACY_TRF_EN_OK = 0,
  MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT = 1,
  MISAKID_SPACY_TRF_EN_INPUT_LIMIT_EXCEEDED = 2,
  MISAKID_SPACY_TRF_EN_INVALID_UTF8 = 3,
  MISAKID_SPACY_TRF_EN_RESOURCE_UNAVAILABLE = 4,
  MISAKID_SPACY_TRF_EN_RESOURCE_IDENTITY_MISMATCH = 5,
  MISAKID_SPACY_TRF_EN_TENSOR_IDENTITY_MISMATCH = 6,
  MISAKID_SPACY_TRF_EN_OUT_OF_MEMORY = 7,
  MISAKID_SPACY_TRF_EN_INFERENCE_FAILED = 8,
  MISAKID_SPACY_TRF_EN_INTERNAL_ERROR = 9
};

MISAKID_SPACY_TRF_EN_API uint32_t misakid_spacy_trf_en_abi_version(void);
MISAKID_SPACY_TRF_EN_API const uint8_t *
misakid_spacy_trf_en_identity_data(uint32_t field);
MISAKID_SPACY_TRF_EN_API size_t
misakid_spacy_trf_en_identity_size(uint32_t field);

MISAKID_SPACY_TRF_EN_API uint8_t *
misakid_spacy_trf_en_buffer_alloc(size_t size);
MISAKID_SPACY_TRF_EN_API void
misakid_spacy_trf_en_buffer_free(void *buffer);

/* Creates a context from one exact caller-provided transformer/model file.
 * The context copies both tagger arrays before returning. */
MISAKID_SPACY_TRF_EN_API misakid_spacy_trf_en_context *
misakid_spacy_trf_en_context_create(
    const uint8_t *model_path, size_t model_path_size,
    const float *tagger_weights, size_t tagger_weight_count,
    const float *tagger_biases, size_t tagger_bias_count);
MISAKID_SPACY_TRF_EN_API uint32_t misakid_spacy_trf_en_context_status(
    const misakid_spacy_trf_en_context *context);
MISAKID_SPACY_TRF_EN_API const uint8_t *
misakid_spacy_trf_en_context_error_stage_data(
    const misakid_spacy_trf_en_context *context);
MISAKID_SPACY_TRF_EN_API size_t
misakid_spacy_trf_en_context_error_stage_size(
    const misakid_spacy_trf_en_context *context);
MISAKID_SPACY_TRF_EN_API const uint8_t *
misakid_spacy_trf_en_context_error_message_data(
    const misakid_spacy_trf_en_context *context);
MISAKID_SPACY_TRF_EN_API size_t
misakid_spacy_trf_en_context_error_message_size(
    const misakid_spacy_trf_en_context *context);
MISAKID_SPACY_TRF_EN_API void misakid_spacy_trf_en_context_destroy(
    misakid_spacy_trf_en_context *context);

/* piece_ids contains exactly one BOS and EOS. token_piece_lengths contains
 * non-whitespace tokens only, and its sum must equal piece_count - 2. */
MISAKID_SPACY_TRF_EN_API misakid_spacy_trf_en_result *
misakid_spacy_trf_en_infer(
    const misakid_spacy_trf_en_context *context,
    const uint32_t *piece_ids, size_t piece_count,
    const uint32_t *token_piece_lengths, size_t token_count);
MISAKID_SPACY_TRF_EN_API uint32_t misakid_spacy_trf_en_result_status(
    const misakid_spacy_trf_en_result *result);
MISAKID_SPACY_TRF_EN_API const uint8_t *
misakid_spacy_trf_en_result_error_stage_data(
    const misakid_spacy_trf_en_result *result);
MISAKID_SPACY_TRF_EN_API size_t
misakid_spacy_trf_en_result_error_stage_size(
    const misakid_spacy_trf_en_result *result);
MISAKID_SPACY_TRF_EN_API const uint8_t *
misakid_spacy_trf_en_result_error_message_data(
    const misakid_spacy_trf_en_result *result);
MISAKID_SPACY_TRF_EN_API size_t
misakid_spacy_trf_en_result_error_message_size(
    const misakid_spacy_trf_en_result *result);
MISAKID_SPACY_TRF_EN_API const uint16_t *
misakid_spacy_trf_en_result_tags_data(
    const misakid_spacy_trf_en_result *result);
MISAKID_SPACY_TRF_EN_API size_t misakid_spacy_trf_en_result_tags_size(
    const misakid_spacy_trf_en_result *result);
MISAKID_SPACY_TRF_EN_API void misakid_spacy_trf_en_result_destroy(
    misakid_spacy_trf_en_result *result);

#ifdef __cplusplus
}
#endif

#endif /* MISAKID_SPACY_TRF_EN_H_ */
