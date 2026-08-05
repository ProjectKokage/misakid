// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// Frontend sequence adapted for compatibility with pyopenjtalk 0.4.1 and
// hexgrad/misaki 0.9.4. Open JTalk and its embedded MeCab retain their
// original notices; see THIRD_PARTY_NOTICES.md. This file deliberately copies
// every returned field into an adapter-owned snapshot before releasing the
// process-global frontend lock.

#include "misakid_openjtalk.h"

#include <array>
#include <climits>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <utility>
#include <vector>

#include "mecab.h"
#include "njd.h"
#include "mecab2njd.h"
#include "njd_set_accent_phrase.h"
#include "njd_set_accent_type.h"
#include "njd_set_digit.h"
#include "njd_set_long_vowel.h"
#include "njd_set_pronunciation.h"
#include "njd_set_unvoiced_vowel.h"
#include "text2mecab.h"

namespace {

constexpr uint32_t kAbiVersion = 1;
constexpr size_t kErrorStageCapacity = 48;
constexpr size_t kErrorMessageCapacity = 1024;
constexpr size_t kMaximumDictionaryPathBytes = 32768;
constexpr size_t kMaximumWords = 65536;
constexpr size_t kMaximumFieldBytes = 1024 * 1024;
constexpr size_t kMaximumResultBytes = 64 * 1024 * 1024;

constexpr std::array<const char *, 7> kIdentityValues = {
    "0.1.0-dev.2",
    "0.4.1",
    "1.11",
    "dea0f240fad8dc8b9ea1984920a4d64a48227a40c2924a3c545eaeca50357857",
    "d5ada46f7fc2b52c1c79c273eb9668ff6ad7ab276a8db9d8be119ef93440f0dc",
    "misakid-openjtalk-safety-v1",
    "8b26c37228c9e9b92333e612e1144c958f2788d219e46c8652f698a089be1ccc",
};

std::mutex g_frontend_mutex;

struct NativeDiagnostic {
  bool raised = false;
  char stage[kErrorStageCapacity] = {};
  char message[kErrorMessageCapacity] = {};
};

thread_local NativeDiagnostic *g_current_diagnostic = nullptr;

size_t bounded_string_length(const char *value, size_t maximum) {
  size_t length = 0;
  while (length < maximum && value[length] != '\0') {
    ++length;
  }
  return length;
}

void copy_bounded(char *destination, size_t capacity, const char *source) {
  if (destination == nullptr || capacity == 0) return;
  destination[0] = '\0';
  if (source == nullptr) return;
  const size_t length = bounded_string_length(source, capacity - 1);
  std::memcpy(destination, source, length);
  destination[length] = '\0';
}

struct DiagnosticScope {
  explicit DiagnosticScope(NativeDiagnostic *diagnostic)
      : previous(g_current_diagnostic) {
    g_current_diagnostic = diagnostic;
  }

  ~DiagnosticScope() { g_current_diagnostic = previous; }

  NativeDiagnostic *previous;
};

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
      if (index + 1 >= size || !is_continuation(bytes[index + 1])) return false;
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

struct WordSnapshot {
  std::array<std::string, 11> strings;
  std::array<int32_t, 3> integers = {};
};

}  // namespace

struct misakid_openjtalk_context {
  Mecab mecab = {};
  NJD njd = {};
  size_t max_input_bytes = 0;
  uint32_t status = MISAKID_OPENJTALK_INTERNAL_ERROR;
  char error_stage[kErrorStageCapacity] = {};
  char error_message[kErrorMessageCapacity] = {};
  bool initialized = false;
};

struct misakid_openjtalk_result {
  uint32_t status = MISAKID_OPENJTALK_INTERNAL_ERROR;
  char error_stage[kErrorStageCapacity] = {};
  char error_message[kErrorMessageCapacity] = {};
  std::vector<WordSnapshot> words;
};

namespace {

void set_context_error(misakid_openjtalk_context *context, uint32_t code,
                       const char *stage, const char *message) {
  set_error(&context->status, context->error_stage, context->error_message,
            code, stage, message);
}

void set_result_error(misakid_openjtalk_result *result, uint32_t code,
                      const char *stage, const char *message) {
  set_error(&result->status, result->error_stage, result->error_message, code,
            stage, message);
}

const char *node_string(NJDNode *node, uint32_t field) {
  switch (field) {
    case MISAKID_OPENJTALK_STRING:
      return NJDNode_get_string(node);
    case MISAKID_OPENJTALK_POS:
      return NJDNode_get_pos(node);
    case MISAKID_OPENJTALK_POS_GROUP1:
      return NJDNode_get_pos_group1(node);
    case MISAKID_OPENJTALK_POS_GROUP2:
      return NJDNode_get_pos_group2(node);
    case MISAKID_OPENJTALK_POS_GROUP3:
      return NJDNode_get_pos_group3(node);
    case MISAKID_OPENJTALK_CTYPE:
      return NJDNode_get_ctype(node);
    case MISAKID_OPENJTALK_CFORM:
      return NJDNode_get_cform(node);
    case MISAKID_OPENJTALK_ORIG:
      return NJDNode_get_orig(node);
    case MISAKID_OPENJTALK_READ:
      return NJDNode_get_read(node);
    case MISAKID_OPENJTALK_PRON:
      return NJDNode_get_pron(node);
    case MISAKID_OPENJTALK_CHAIN_RULE:
      return NJDNode_get_chain_rule(node);
    default:
      return nullptr;
  }
}

bool copy_words(NJD *njd, misakid_openjtalk_result *result) {
  size_t count = 0;
  for (NJDNode *node = njd->head; node != nullptr; node = node->next) {
    if (++count > kMaximumWords) {
      set_result_error(result, MISAKID_OPENJTALK_RESULT_LIMIT_EXCEEDED,
                       "result-copy", "Frontend word limit exceeded.");
      return false;
    }
  }

  result->words.reserve(count);
  size_t total_bytes = 0;
  for (NJDNode *node = njd->head; node != nullptr; node = node->next) {
    WordSnapshot word;
    for (uint32_t field = MISAKID_OPENJTALK_STRING;
         field <= MISAKID_OPENJTALK_CHAIN_RULE; ++field) {
      const char *value = node_string(node, field);
      if (value == nullptr) value = "";
      const size_t length =
          bounded_string_length(value, kMaximumFieldBytes + 1);
      if (length > kMaximumFieldBytes ||
          total_bytes > kMaximumResultBytes - length) {
        set_result_error(result, MISAKID_OPENJTALK_RESULT_LIMIT_EXCEEDED,
                         "result-copy", "Frontend string limit exceeded.");
        return false;
      }
      total_bytes += length;
      word.strings[field].assign(value, length);
    }
    word.integers[MISAKID_OPENJTALK_ACC] = NJDNode_get_acc(node);
    word.integers[MISAKID_OPENJTALK_MORA_SIZE] =
        NJDNode_get_mora_size(node);
    word.integers[MISAKID_OPENJTALK_CHAIN_FLAG] =
        NJDNode_get_chain_flag(node);
    result->words.push_back(std::move(word));
  }
  return true;
}

const std::string *result_string(const misakid_openjtalk_result *result,
                                 size_t word_index, uint32_t field) {
  if (result == nullptr || result->status != MISAKID_OPENJTALK_OK ||
      word_index >= result->words.size() ||
      field > MISAKID_OPENJTALK_CHAIN_RULE) {
    return nullptr;
  }
  return &result->words[word_index].strings[field];
}

void refresh_frontend(misakid_openjtalk_context *context) {
  NJD_refresh(&context->njd);
  Mecab_refresh(&context->mecab);
}

struct FrontendRefreshScope {
  explicit FrontendRefreshScope(misakid_openjtalk_context *context_value)
      : context(context_value) {
    refresh_frontend(context);
  }

  FrontendRefreshScope(const FrontendRefreshScope &) = delete;
  FrontendRefreshScope &operator=(const FrontendRefreshScope &) = delete;

  ~FrontendRefreshScope() noexcept { refresh_frontend(context); }

  misakid_openjtalk_context *context;
};

}  // namespace

extern "C" void misakid_openjtalk_report_native_error(const char *stage,
                                                       const char *message) {
  if (g_current_diagnostic == nullptr || g_current_diagnostic->raised) return;
  g_current_diagnostic->raised = true;
  copy_bounded(g_current_diagnostic->stage, kErrorStageCapacity, stage);
  copy_bounded(g_current_diagnostic->message, kErrorMessageCapacity, message);
}

extern "C" {

uint32_t misakid_openjtalk_abi_version(void) { return kAbiVersion; }

const uint8_t *misakid_openjtalk_identity_data(uint32_t field) {
  if (field >= kIdentityValues.size()) return nullptr;
  return reinterpret_cast<const uint8_t *>(kIdentityValues[field]);
}

size_t misakid_openjtalk_identity_size(uint32_t field) {
  if (field >= kIdentityValues.size()) return 0;
  return std::strlen(kIdentityValues[field]);
}

uint8_t *misakid_openjtalk_buffer_alloc(size_t size) {
  const size_t allocation_size = size == 0 ? 1 : size;
  return static_cast<uint8_t *>(std::malloc(allocation_size));
}

void misakid_openjtalk_buffer_free(void *buffer) { std::free(buffer); }

misakid_openjtalk_context *misakid_openjtalk_context_create(
    const uint8_t *dictionary_path, size_t dictionary_path_size,
    size_t max_input_bytes) {
  auto *context = new (std::nothrow) misakid_openjtalk_context;
  if (context == nullptr) return nullptr;
  try {
    if (dictionary_path == nullptr || dictionary_path_size == 0 ||
        dictionary_path_size > kMaximumDictionaryPathBytes ||
        max_input_bytes == 0 || max_input_bytes > INT_MAX ||
        max_input_bytes > (std::numeric_limits<size_t>::max() - 1) / 3 ||
        has_embedded_nul(dictionary_path, dictionary_path_size) ||
        !is_valid_utf8(dictionary_path, dictionary_path_size)) {
      set_context_error(context, MISAKID_OPENJTALK_INVALID_ARGUMENT,
                        "configuration", "Native configuration is invalid.");
      return context;
    }

    const std::string path(
        reinterpret_cast<const char *>(dictionary_path), dictionary_path_size);
    std::lock_guard<std::mutex> lock(g_frontend_mutex);
    Mecab_initialize(&context->mecab);
    NJD_initialize(&context->njd);
    context->initialized = true;
    if (Mecab_load(&context->mecab, path.c_str()) != 1) {
      set_context_error(
          context, MISAKID_OPENJTALK_DICTIONARY_LOAD_FAILED, "dictionary-load",
          "Open JTalk could not load the validated dictionary.");
      return context;
    }
    context->max_input_bytes = max_input_bytes;
    context->status = MISAKID_OPENJTALK_OK;
    return context;
  } catch (const std::bad_alloc &) {
    set_context_error(context, MISAKID_OPENJTALK_OUT_OF_MEMORY, "initialize",
                      "Native allocation failed during initialization.");
    return context;
  } catch (...) {
    set_context_error(context, MISAKID_OPENJTALK_INTERNAL_ERROR, "initialize",
                      "Unexpected native initialization failure.");
    return context;
  }
}

uint32_t misakid_openjtalk_context_status(
    const misakid_openjtalk_context *context) {
  return context == nullptr ? MISAKID_OPENJTALK_OUT_OF_MEMORY : context->status;
}

const uint8_t *misakid_openjtalk_context_error_stage_data(
    const misakid_openjtalk_context *context) {
  return context == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(context->error_stage);
}

size_t misakid_openjtalk_context_error_stage_size(
    const misakid_openjtalk_context *context) {
  return context == nullptr ? 0 : std::strlen(context->error_stage);
}

const uint8_t *misakid_openjtalk_context_error_message_data(
    const misakid_openjtalk_context *context) {
  return context == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(context->error_message);
}

size_t misakid_openjtalk_context_error_message_size(
    const misakid_openjtalk_context *context) {
  return context == nullptr ? 0 : std::strlen(context->error_message);
}

void misakid_openjtalk_context_destroy(misakid_openjtalk_context *context) {
  if (context == nullptr) return;
  try {
    std::lock_guard<std::mutex> lock(g_frontend_mutex);
    if (context->initialized) {
      Mecab_clear(&context->mecab);
      NJD_clear(&context->njd);
      context->initialized = false;
    }
  } catch (...) {
    // Destruction is best-effort and must never throw through the C ABI.
  }
  delete context;
}

misakid_openjtalk_result *misakid_openjtalk_analyze(
    misakid_openjtalk_context *context, const uint8_t *utf8,
    size_t utf8_size) {
  auto *result = new (std::nothrow) misakid_openjtalk_result;
  if (result == nullptr) return nullptr;
  try {
    if (context == nullptr || context->status != MISAKID_OPENJTALK_OK ||
        utf8 == nullptr) {
      set_result_error(result, MISAKID_OPENJTALK_INVALID_ARGUMENT, "input",
                       "Native analysis arguments are invalid.");
      return result;
    }
    if (utf8_size > context->max_input_bytes) {
      set_result_error(result, MISAKID_OPENJTALK_INPUT_TOO_LARGE, "input",
                       "Input exceeds the configured native byte limit.");
      return result;
    }
    if (has_embedded_nul(utf8, utf8_size)) {
      set_result_error(result, MISAKID_OPENJTALK_INVALID_ARGUMENT, "input",
                       "Input contains an unsupported NUL scalar.");
      return result;
    }
    if (!is_valid_utf8(utf8, utf8_size)) {
      set_result_error(result, MISAKID_OPENJTALK_INVALID_UTF8, "input",
                       "Input is not valid UTF-8.");
      return result;
    }

    const size_t normalized_size = utf8_size * 3 + 1;
    using MallocBuffer = std::unique_ptr<char, decltype(&std::free)>;
    MallocBuffer input(static_cast<char *>(std::malloc(utf8_size + 1)),
                       &std::free);
    MallocBuffer normalized(static_cast<char *>(std::malloc(normalized_size)),
                            &std::free);
    if (input == nullptr || normalized == nullptr) {
      set_result_error(result, MISAKID_OPENJTALK_OUT_OF_MEMORY, "input",
                       "Native input allocation failed.");
      return result;
    }
    if (utf8_size != 0) std::memcpy(input.get(), utf8, utf8_size);
    input.get()[utf8_size] = '\0';

    std::lock_guard<std::mutex> lock(g_frontend_mutex);
    FrontendRefreshScope refresh_scope(context);
    NativeDiagnostic diagnostic;
    DiagnosticScope diagnostic_scope(&diagnostic);
    text2mecab(normalized.get(), input.get());
    input.reset();
    if (diagnostic.raised) {
      set_result_error(result, MISAKID_OPENJTALK_NATIVE_DIAGNOSTIC,
                       diagnostic.stage, diagnostic.message);
      return result;
    }
    if (Mecab_analysis(&context->mecab, normalized.get()) != 1) {
      set_result_error(result, MISAKID_OPENJTALK_ANALYSIS_FAILED,
                       "mecab-analysis", "MeCab analysis failed.");
      return result;
    }
    normalized.reset();

    const int mecab_word_count = Mecab_get_size(&context->mecab);
    if (mecab_word_count < 0) {
      set_result_error(result, MISAKID_OPENJTALK_ANALYSIS_FAILED,
                       "mecab-analysis", "MeCab returned an invalid word count.");
      return result;
    }
    if (static_cast<size_t>(mecab_word_count) > kMaximumWords) {
      set_result_error(result, MISAKID_OPENJTALK_RESULT_LIMIT_EXCEEDED,
                       "mecab-word-limit", "Frontend word limit exceeded.");
      return result;
    }

    mecab2njd(&context->njd, Mecab_get_feature(&context->mecab),
              mecab_word_count);
    njd_set_pronunciation(&context->njd);
    njd_set_digit(&context->njd);
    njd_set_accent_phrase(&context->njd);
    njd_set_accent_type(&context->njd);
    njd_set_unvoiced_vowel(&context->njd);
    njd_set_long_vowel(&context->njd);
    if (diagnostic.raised) {
      set_result_error(result, MISAKID_OPENJTALK_NATIVE_DIAGNOSTIC,
                       diagnostic.stage, diagnostic.message);
      return result;
    }
    if (!copy_words(&context->njd, result)) {
      return result;
    }
    result->status = MISAKID_OPENJTALK_OK;
    return result;
  } catch (const std::bad_alloc &) {
    set_result_error(result, MISAKID_OPENJTALK_OUT_OF_MEMORY, "analysis",
                     "Native allocation failed during analysis.");
    return result;
  } catch (...) {
    set_result_error(result, MISAKID_OPENJTALK_INTERNAL_ERROR, "analysis",
                     "Unexpected native analysis failure.");
    return result;
  }
}

uint32_t misakid_openjtalk_result_status(
    const misakid_openjtalk_result *result) {
  return result == nullptr ? MISAKID_OPENJTALK_OUT_OF_MEMORY : result->status;
}

const uint8_t *misakid_openjtalk_result_error_stage_data(
    const misakid_openjtalk_result *result) {
  return result == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(result->error_stage);
}

size_t misakid_openjtalk_result_error_stage_size(
    const misakid_openjtalk_result *result) {
  return result == nullptr ? 0 : std::strlen(result->error_stage);
}

const uint8_t *misakid_openjtalk_result_error_message_data(
    const misakid_openjtalk_result *result) {
  return result == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(result->error_message);
}

size_t misakid_openjtalk_result_error_message_size(
    const misakid_openjtalk_result *result) {
  return result == nullptr ? 0 : std::strlen(result->error_message);
}

size_t misakid_openjtalk_result_word_count(
    const misakid_openjtalk_result *result) {
  return result == nullptr || result->status != MISAKID_OPENJTALK_OK
             ? 0
             : result->words.size();
}

const uint8_t *misakid_openjtalk_result_word_string_data(
    const misakid_openjtalk_result *result, size_t word_index,
    uint32_t field) {
  const std::string *value = result_string(result, word_index, field);
  return value == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(value->data());
}

size_t misakid_openjtalk_result_word_string_size(
    const misakid_openjtalk_result *result, size_t word_index,
    uint32_t field) {
  const std::string *value = result_string(result, word_index, field);
  return value == nullptr ? 0 : value->size();
}

int32_t misakid_openjtalk_result_word_integer(
    const misakid_openjtalk_result *result, size_t word_index,
    uint32_t field) {
  if (result == nullptr || result->status != MISAKID_OPENJTALK_OK ||
      word_index >= result->words.size() ||
      field > MISAKID_OPENJTALK_CHAIN_FLAG) {
    return 0;
  }
  return result->words[word_index].integers[field];
}

void misakid_openjtalk_result_destroy(misakid_openjtalk_result *result) {
  delete result;
}

}  // extern "C"
