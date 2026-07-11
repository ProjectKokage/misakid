// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// Native compatibility boundary for the pinned mecab-ko 0.996/ko-0.9.2
// runtime and dictionary. MeCab and mecab-ko retain their original notices;
// see the package's THIRD_PARTY_NOTICES.md. All token data is copied into an
// adapter-owned snapshot while the process-global MeCab lock is held.

#include "misakid_mecab_ko.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <new>
#include <string>
#include <utility>
#include <vector>

#include "mecab.h"

namespace {

constexpr uint32_t kAbiVersion = 1;
constexpr size_t kErrorStageCapacity = 48;
constexpr size_t kErrorMessageCapacity = 1024;
constexpr size_t kMaximumDictionaryPathBytes = 32768;
constexpr size_t kMaximumInputBytes = 64 * 1024 * 1024;
constexpr size_t kMaximumTokens = 65536;
constexpr size_t kMaximumTraversedNodes = kMaximumTokens + 16;
constexpr size_t kMaximumFieldBytes = 1024 * 1024;
constexpr size_t kMaximumResultBytes = 64 * 1024 * 1024;

constexpr unsigned int kExpectedDictionarySize = 816283;
constexpr unsigned int kExpectedDictionaryLeftSize = 3822;
constexpr unsigned int kExpectedDictionaryRightSize = 2693;
constexpr unsigned short kExpectedDictionaryVersion = 102;

constexpr std::array<const char *, 6> kIdentityValues = {
    "0.1.0-dev.1",
    "0.996/ko-0.9.2",
    "9b870a921e8d80fa11eec1066d21c0960916fa617e77a8c83758223dfe28827f",
    "d0e0f696fc33c2183307d4eb87ec3b17845f90b81bf843bd0981e574ee3c38cb",
    "misakid-mecab-ko-safety-v1",
    "d851fab8708745442ac3a2d970851dbd0ef598e786a363f406847461d77a6f51",
};

std::mutex g_mecab_mutex;

void copy_bounded(char *destination, size_t capacity, const char *source) {
  if (destination == nullptr || capacity == 0)
    return;
  destination[0] = '\0';
  if (source == nullptr)
    return;
  const size_t length = ::strnlen(source, capacity - 1);
  std::memcpy(destination, source, length);
  destination[length] = '\0';
}

void set_error(uint32_t *status, char *stage, char *message, uint32_t code,
               const char *stage_value, const char *message_value) {
  *status = code;
  copy_bounded(stage, kErrorStageCapacity, stage_value);
  copy_bounded(message, kErrorMessageCapacity, message_value);
}

bool has_embedded_nul(const uint8_t *bytes, size_t size) {
  return size != 0 && std::memchr(bytes, 0, size) != nullptr;
}

bool is_continuation(uint8_t value) { return (value & 0xC0U) == 0x80U; }

bool is_valid_utf8(const uint8_t *bytes, size_t size) {
  size_t index = 0;
  while (index < size) {
    const uint8_t first = bytes[index];
    if (first <= 0x7FU) {
      ++index;
      continue;
    }
    if (first >= 0xC2U && first <= 0xDFU) {
      if (index + 1 >= size || !is_continuation(bytes[index + 1]))
        return false;
      index += 2;
      continue;
    }
    if (first >= 0xE0U && first <= 0xEFU) {
      if (index + 2 >= size || !is_continuation(bytes[index + 1]) ||
          !is_continuation(bytes[index + 2])) {
        return false;
      }
      const uint8_t second = bytes[index + 1];
      if ((first == 0xE0U && second < 0xA0U) ||
          (first == 0xEDU && second >= 0xA0U)) {
        return false;
      }
      index += 3;
      continue;
    }
    if (first >= 0xF0U && first <= 0xF4U) {
      if (index + 3 >= size || !is_continuation(bytes[index + 1]) ||
          !is_continuation(bytes[index + 2]) ||
          !is_continuation(bytes[index + 3])) {
        return false;
      }
      const uint8_t second = bytes[index + 1];
      if ((first == 0xF0U && second < 0x90U) ||
          (first == 0xF4U && second > 0x8FU)) {
        return false;
      }
      index += 4;
      continue;
    }
    return false;
  }
  return true;
}

struct TokenSnapshot {
  std::array<std::string, 2> strings;
};

} // namespace

struct misakid_mecab_ko_context {
  mecab_t *tagger = nullptr;
  size_t max_input_bytes = 0;
  uint32_t status = MISAKID_MECAB_KO_INTERNAL_ERROR;
  char error_stage[kErrorStageCapacity] = {};
  char error_message[kErrorMessageCapacity] = {};
};

struct misakid_mecab_ko_result {
  uint32_t status = MISAKID_MECAB_KO_INTERNAL_ERROR;
  char error_stage[kErrorStageCapacity] = {};
  char error_message[kErrorMessageCapacity] = {};
  std::vector<TokenSnapshot> tokens;
};

namespace {

void set_context_error(misakid_mecab_ko_context *context, uint32_t code,
                       const char *stage, const char *message) {
  set_error(&context->status, context->error_stage, context->error_message,
            code, stage, message);
}

void set_result_error(misakid_mecab_ko_result *result, uint32_t code,
                      const char *stage, const char *message) {
  set_error(&result->status, result->error_stage, result->error_message, code,
            stage, message);
}

bool has_expected_dictionary_identity(const mecab_dictionary_info_t *info) {
  if (info == nullptr || info->next != nullptr || info->charset == nullptr) {
    return false;
  }

  constexpr char kExpectedCharset[] = "UTF-8";
  const size_t charset_length =
      ::strnlen(info->charset, sizeof(kExpectedCharset));
  if (charset_length != sizeof(kExpectedCharset) - 1 ||
      std::memcmp(info->charset, kExpectedCharset,
                  sizeof(kExpectedCharset) - 1) != 0) {
    return false;
  }

  return info->version == kExpectedDictionaryVersion &&
         info->size == kExpectedDictionarySize &&
         info->lsize == kExpectedDictionaryLeftSize &&
         info->rsize == kExpectedDictionaryRightSize;
}

bool copy_tokens(const mecab_node_t *first, misakid_mecab_ko_result *result) {
  size_t traversed_nodes = 0;
  size_t total_bytes = 0;

  for (const mecab_node_t *node = first; node != nullptr; node = node->next) {
    if (++traversed_nodes > kMaximumTraversedNodes) {
      set_result_error(result, MISAKID_MECAB_KO_RESULT_LIMIT_EXCEEDED,
                       "result-copy", "MeCab node limit exceeded.");
      return false;
    }
    if (node->stat != MECAB_NOR_NODE && node->stat != MECAB_UNK_NODE) {
      continue;
    }
    if (result->tokens.size() >= kMaximumTokens) {
      set_result_error(result, MISAKID_MECAB_KO_RESULT_LIMIT_EXCEEDED,
                       "result-copy", "MeCab token limit exceeded.");
      return false;
    }
    if (node->surface == nullptr || node->feature == nullptr) {
      set_result_error(result, MISAKID_MECAB_KO_ANALYSIS_FAILED, "result-copy",
                       "MeCab returned malformed token data.");
      return false;
    }

    const size_t surface_size = node->length;
    if (surface_size > kMaximumFieldBytes ||
        has_embedded_nul(reinterpret_cast<const uint8_t *>(node->surface),
                         surface_size) ||
        !is_valid_utf8(reinterpret_cast<const uint8_t *>(node->surface),
                       surface_size)) {
      set_result_error(result, MISAKID_MECAB_KO_ANALYSIS_FAILED, "result-copy",
                       "MeCab returned malformed surface data.");
      return false;
    }

    const size_t feature_size =
        ::strnlen(node->feature, kMaximumFieldBytes + 1);
    if (feature_size > kMaximumFieldBytes) {
      set_result_error(result, MISAKID_MECAB_KO_RESULT_LIMIT_EXCEEDED,
                       "result-copy", "MeCab feature limit exceeded.");
      return false;
    }
    if (!is_valid_utf8(reinterpret_cast<const uint8_t *>(node->feature),
                       feature_size)) {
      set_result_error(result, MISAKID_MECAB_KO_ANALYSIS_FAILED, "result-copy",
                       "MeCab returned malformed feature data.");
      return false;
    }

    size_t comma_count = 0;
    size_t tag_size = feature_size;
    for (size_t index = 0; index < feature_size; ++index) {
      if (node->feature[index] != ',')
        continue;
      if (comma_count == 0)
        tag_size = index;
      ++comma_count;
    }
    // python-mecab-ko's Feature._from_feature performs split(',') and requires
    // exactly eight values. Seven commas is the byte-equivalent condition.
    if (comma_count != 7) {
      set_result_error(result, MISAKID_MECAB_KO_ANALYSIS_FAILED, "result-copy",
                       "MeCab returned malformed feature data.");
      return false;
    }

    if (surface_size > kMaximumResultBytes - total_bytes) {
      set_result_error(result, MISAKID_MECAB_KO_RESULT_LIMIT_EXCEEDED,
                       "result-copy", "MeCab aggregate result limit exceeded.");
      return false;
    }
    total_bytes += surface_size;
    if (tag_size > kMaximumResultBytes - total_bytes) {
      set_result_error(result, MISAKID_MECAB_KO_RESULT_LIMIT_EXCEEDED,
                       "result-copy", "MeCab aggregate result limit exceeded.");
      return false;
    }
    total_bytes += tag_size;

    TokenSnapshot token;
    token.strings[MISAKID_MECAB_KO_SURFACE].assign(node->surface, surface_size);
    token.strings[MISAKID_MECAB_KO_TAG].assign(node->feature, tag_size);
    result->tokens.push_back(std::move(token));
  }

  return true;
}

const std::string *result_string(const misakid_mecab_ko_result *result,
                                 size_t token_index, uint32_t field) {
  if (result == nullptr || result->status != MISAKID_MECAB_KO_OK ||
      token_index >= result->tokens.size() || field > MISAKID_MECAB_KO_TAG) {
    return nullptr;
  }
  return &result->tokens[token_index].strings[field];
}

} // namespace

extern "C" {

uint32_t misakid_mecab_ko_abi_version(void) { return kAbiVersion; }

const uint8_t *misakid_mecab_ko_identity_data(uint32_t field) {
  if (field >= kIdentityValues.size())
    return nullptr;
  return reinterpret_cast<const uint8_t *>(kIdentityValues[field]);
}

size_t misakid_mecab_ko_identity_size(uint32_t field) {
  if (field >= kIdentityValues.size())
    return 0;
  return std::strlen(kIdentityValues[field]);
}

uint8_t *misakid_mecab_ko_buffer_alloc(size_t size) {
  const size_t allocation_size = size == 0 ? 1 : size;
  return static_cast<uint8_t *>(std::malloc(allocation_size));
}

void misakid_mecab_ko_buffer_free(void *buffer) { std::free(buffer); }

misakid_mecab_ko_context *
misakid_mecab_ko_context_create(const uint8_t *dictionary_path,
                                size_t dictionary_path_size,
                                size_t max_input_bytes) {
  auto *context = new (std::nothrow) misakid_mecab_ko_context;
  if (context == nullptr)
    return nullptr;

  try {
    if (dictionary_path == nullptr || dictionary_path_size == 0 ||
        dictionary_path_size > kMaximumDictionaryPathBytes ||
        max_input_bytes == 0 || max_input_bytes > kMaximumInputBytes ||
        has_embedded_nul(dictionary_path, dictionary_path_size)) {
      set_context_error(context, MISAKID_MECAB_KO_INVALID_ARGUMENT,
                        "configuration", "Native configuration is invalid.");
      return context;
    }
    if (!is_valid_utf8(dictionary_path, dictionary_path_size)) {
      set_context_error(context, MISAKID_MECAB_KO_INVALID_UTF8, "configuration",
                        "Dictionary path is not valid UTF-8.");
      return context;
    }

    const std::string dictionary(
        reinterpret_cast<const char *>(dictionary_path), dictionary_path_size);
    std::array<std::string, 5> arguments = {"misakid", "--rcfile", "/dev/null",
                                            "--dicdir", dictionary};
    std::array<char *, 5> argv = {};
    for (size_t index = 0; index < arguments.size(); ++index) {
      argv[index] = const_cast<char *>(arguments[index].c_str());
    }

    std::lock_guard<std::mutex> lock(g_mecab_mutex);
    context->tagger = mecab_new(static_cast<int>(argv.size()), argv.data());
    if (context->tagger == nullptr) {
      set_context_error(context, MISAKID_MECAB_KO_DICTIONARY_LOAD_FAILED,
                        "dictionary-load",
                        "MeCab could not load the validated dictionary.");
      return context;
    }
    if (!has_expected_dictionary_identity(
            mecab_dictionary_info(context->tagger))) {
      set_context_error(context, MISAKID_MECAB_KO_DICTIONARY_LOAD_FAILED,
                        "dictionary-identity",
                        "MeCab dictionary identity does not match.");
      return context;
    }

    context->max_input_bytes = max_input_bytes;
    context->status = MISAKID_MECAB_KO_OK;
    return context;
  } catch (const std::bad_alloc &) {
    set_context_error(context, MISAKID_MECAB_KO_OUT_OF_MEMORY, "initialize",
                      "Native allocation failed during initialization.");
    return context;
  } catch (const std::exception &) {
    set_context_error(context, MISAKID_MECAB_KO_NATIVE_DIAGNOSTIC, "initialize",
                      "Native initialization reported a diagnostic.");
    return context;
  } catch (...) {
    set_context_error(context, MISAKID_MECAB_KO_INTERNAL_ERROR, "initialize",
                      "Unexpected native initialization failure.");
    return context;
  }
}

uint32_t
misakid_mecab_ko_context_status(const misakid_mecab_ko_context *context) {
  return context == nullptr ? MISAKID_MECAB_KO_OUT_OF_MEMORY : context->status;
}

const uint8_t *misakid_mecab_ko_context_error_stage_data(
    const misakid_mecab_ko_context *context) {
  return context == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(context->error_stage);
}

size_t misakid_mecab_ko_context_error_stage_size(
    const misakid_mecab_ko_context *context) {
  return context == nullptr ? 0 : std::strlen(context->error_stage);
}

const uint8_t *misakid_mecab_ko_context_error_message_data(
    const misakid_mecab_ko_context *context) {
  return context == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(context->error_message);
}

size_t misakid_mecab_ko_context_error_message_size(
    const misakid_mecab_ko_context *context) {
  return context == nullptr ? 0 : std::strlen(context->error_message);
}

void misakid_mecab_ko_context_destroy(misakid_mecab_ko_context *context) {
  if (context == nullptr)
    return;
  try {
    std::lock_guard<std::mutex> lock(g_mecab_mutex);
    if (context->tagger != nullptr) {
      mecab_destroy(context->tagger);
      context->tagger = nullptr;
    }
  } catch (...) {
    // Destruction is best-effort and must never throw through the C ABI.
  }
  delete context;
}

misakid_mecab_ko_result *
misakid_mecab_ko_analyze(misakid_mecab_ko_context *context, const uint8_t *utf8,
                         size_t utf8_size) {
  auto *result = new (std::nothrow) misakid_mecab_ko_result;
  if (result == nullptr)
    return nullptr;

  try {
    if (context == nullptr || utf8 == nullptr) {
      set_result_error(result, MISAKID_MECAB_KO_INVALID_ARGUMENT, "input",
                       "Native analysis arguments are invalid.");
      return result;
    }
    if (utf8_size > kMaximumInputBytes) {
      set_result_error(result, MISAKID_MECAB_KO_INPUT_TOO_LARGE, "input",
                       "Input exceeds the native byte limit.");
      return result;
    }

    std::lock_guard<std::mutex> lock(g_mecab_mutex);
    if (context->status != MISAKID_MECAB_KO_OK || context->tagger == nullptr) {
      set_result_error(result, MISAKID_MECAB_KO_INVALID_ARGUMENT, "input",
                       "Native analysis context is unavailable.");
      return result;
    }
    if (utf8_size > context->max_input_bytes) {
      set_result_error(result, MISAKID_MECAB_KO_INPUT_TOO_LARGE, "input",
                       "Input exceeds the configured native byte limit.");
      return result;
    }
    if (has_embedded_nul(utf8, utf8_size)) {
      set_result_error(result, MISAKID_MECAB_KO_INVALID_ARGUMENT, "input",
                       "Input contains an unsupported NUL scalar.");
      return result;
    }
    if (!is_valid_utf8(utf8, utf8_size)) {
      set_result_error(result, MISAKID_MECAB_KO_INVALID_UTF8, "input",
                       "Input is not valid UTF-8.");
      return result;
    }

    const mecab_node_t *nodes = mecab_sparse_tonode2(
        context->tagger, reinterpret_cast<const char *>(utf8), utf8_size);
    if (nodes == nullptr) {
      set_result_error(result, MISAKID_MECAB_KO_ANALYSIS_FAILED,
                       "mecab-analysis", "MeCab analysis failed.");
      return result;
    }
    if (!copy_tokens(nodes, result))
      return result;

    result->status = MISAKID_MECAB_KO_OK;
    return result;
  } catch (const std::bad_alloc &) {
    set_result_error(result, MISAKID_MECAB_KO_OUT_OF_MEMORY, "analysis",
                     "Native allocation failed during analysis.");
    return result;
  } catch (const std::exception &) {
    set_result_error(result, MISAKID_MECAB_KO_NATIVE_DIAGNOSTIC, "analysis",
                     "Native analysis reported a diagnostic.");
    return result;
  } catch (...) {
    set_result_error(result, MISAKID_MECAB_KO_INTERNAL_ERROR, "analysis",
                     "Unexpected native analysis failure.");
    return result;
  }
}

uint32_t misakid_mecab_ko_result_status(const misakid_mecab_ko_result *result) {
  return result == nullptr ? MISAKID_MECAB_KO_OUT_OF_MEMORY : result->status;
}

const uint8_t *misakid_mecab_ko_result_error_stage_data(
    const misakid_mecab_ko_result *result) {
  return result == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(result->error_stage);
}

size_t misakid_mecab_ko_result_error_stage_size(
    const misakid_mecab_ko_result *result) {
  return result == nullptr ? 0 : std::strlen(result->error_stage);
}

const uint8_t *misakid_mecab_ko_result_error_message_data(
    const misakid_mecab_ko_result *result) {
  return result == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(result->error_message);
}

size_t misakid_mecab_ko_result_error_message_size(
    const misakid_mecab_ko_result *result) {
  return result == nullptr ? 0 : std::strlen(result->error_message);
}

size_t
misakid_mecab_ko_result_token_count(const misakid_mecab_ko_result *result) {
  return result == nullptr || result->status != MISAKID_MECAB_KO_OK
             ? 0
             : result->tokens.size();
}

const uint8_t *
misakid_mecab_ko_result_token_string_data(const misakid_mecab_ko_result *result,
                                          size_t token_index, uint32_t field) {
  const std::string *value = result_string(result, token_index, field);
  return value == nullptr ? nullptr
                          : reinterpret_cast<const uint8_t *>(value->data());
}

size_t
misakid_mecab_ko_result_token_string_size(const misakid_mecab_ko_result *result,
                                          size_t token_index, uint32_t field) {
  const std::string *value = result_string(result, token_index, field);
  return value == nullptr ? 0 : value->size();
}

void misakid_mecab_ko_result_destroy(misakid_mecab_ko_result *result) {
  delete result;
}

} // extern "C"
