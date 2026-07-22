// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// Native compatibility boundary for the MeCab 0.996 runtime embedded in
// pyopenjtalk 0.4.1 and compatible UTF-8 UniDic resources. MeCab and UniDic
// keep their original notices; see the package's THIRD_PARTY_NOTICES.md.

#include "misakid_mecab_ja.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <limits>
#include <mutex>
#include <new>
#include <string>
#include <utility>
#include <vector>

#include "mecab.h"

namespace {

constexpr uint32_t kAbiVersion = 3;
constexpr size_t kErrorStageCapacity = 48;
constexpr size_t kErrorMessageCapacity = 1024;
constexpr size_t kMaximumDictionaryPathBytes = 32768;
constexpr size_t kMaximumInputBytes = 64 * 1024 * 1024;
constexpr size_t kMaximumWords = 65536;
constexpr size_t kMaximumTraversedNodes = kMaximumWords + 16;
constexpr size_t kMaximumFieldBytes = 1024 * 1024;
constexpr size_t kMaximumResultBytes = 64 * 1024 * 1024;

constexpr unsigned short kExpectedMecabDictionaryFormatVersion = 102;

constexpr std::array<const char *, 6> kIdentityValues = {
    "0.1.0",
    "0.996",
    "dea0f240fad8dc8b9ea1984920a4d64a48227a40c2924a3c545eaeca50357857",
    "d5ada46f7fc2b52c1c79c273eb9668ff6ad7ab276a8db9d8be119ef93440f0dc",
    "misakid-mecab-ja-build-v4-portable",
    "unidic-features-26-29-v1",
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

// UniDic feature records are RFC-4180-like CSV. Only doubled quotes are
// accepted inside quoted values; quotes elsewhere make the record malformed.
bool parse_csv_fields(const char *data, size_t size,
                      std::vector<std::string> *fields) {
  fields->clear();
  size_t index = 0;
  while (true) {
    std::string field;
    bool quoted = index < size && data[index] == '"';
    if (quoted)
      ++index;
    bool closed_quote = !quoted;
    while (index < size) {
      const char value = data[index];
      if (quoted) {
        if (value != '"') {
          field.push_back(value);
          ++index;
          continue;
        }
        if (index + 1 < size && data[index + 1] == '"') {
          field.push_back('"');
          index += 2;
          continue;
        }
        quoted = false;
        closed_quote = true;
        ++index;
        if (index < size && data[index] != ',')
          return false;
        continue;
      }
      if (value == ',')
        break;
      if (value == '"')
        return false;
      field.push_back(value);
      ++index;
    }
    if (quoted || !closed_quote)
      return false;
    fields->push_back(std::move(field));
    if (index == size)
      return true;
    ++index; // comma
    if (index == size) {
      fields->emplace_back();
      return true;
    }
  }
}

bool ascii_equal_ignore_case(char actual, char expected) {
  if (actual >= 'A' && actual <= 'Z')
    actual = static_cast<char>(actual - 'A' + 'a');
  return actual == expected;
}

bool is_utf8_charset(const char *charset) {
  if (charset == nullptr)
    return false;
  const size_t size = ::strnlen(charset, 6);
  if (size != 4 && size != 5)
    return false;
  if (!ascii_equal_ignore_case(charset[0], 'u') ||
      !ascii_equal_ignore_case(charset[1], 't') ||
      !ascii_equal_ignore_case(charset[2], 'f')) {
    return false;
  }
  if (size == 4)
    return charset[3] == '8';
  return (charset[3] == '-' || charset[3] == '_') && charset[4] == '8';
}

bool is_supported_feature_schema(size_t field_count) {
  return field_count == 26 || field_count == 29;
}

struct WordSnapshot {
  std::array<std::string, 3> strings;
  std::array<int32_t, 4> integers = {};
};

} // namespace

struct misakid_mecab_ja_context {
  mecab_t *tagger = nullptr;
  size_t max_input_bytes = 0;
  size_t feature_schema = 0;
  uint32_t status = MISAKID_MECAB_JA_INTERNAL_ERROR;
  char error_stage[kErrorStageCapacity] = {};
  char error_message[kErrorMessageCapacity] = {};
};

struct misakid_mecab_ja_result {
  uint32_t status = MISAKID_MECAB_JA_INTERNAL_ERROR;
  char error_stage[kErrorStageCapacity] = {};
  char error_message[kErrorMessageCapacity] = {};
  std::vector<WordSnapshot> words;
};

namespace {

void set_context_error(misakid_mecab_ja_context *context, uint32_t code,
                       const char *stage, const char *message) {
  set_error(&context->status, context->error_stage, context->error_message,
            code, stage, message);
}

void set_result_error(misakid_mecab_ja_result *result, uint32_t code,
                      const char *stage, const char *message) {
  set_error(&result->status, result->error_stage, result->error_message, code,
            stage, message);
}

bool has_compatible_dictionary_format(const mecab_dictionary_info_t *info) {
  if (info == nullptr || info->next != nullptr || info->charset == nullptr ||
      info->type != MECAB_SYS_DIC || info->size == 0) {
    return false;
  }
  return is_utf8_charset(info->charset) &&
         info->version == kExpectedMecabDictionaryFormatVersion;
}

bool copy_words(const mecab_node_t *first, size_t feature_schema,
                misakid_mecab_ja_result *result) {
  size_t traversed_nodes = 0;
  size_t total_bytes = 0;
  std::vector<std::string> features;
  features.reserve(29);

  for (const mecab_node_t *node = first; node != nullptr; node = node->next) {
    if (++traversed_nodes > kMaximumTraversedNodes) {
      set_result_error(result, MISAKID_MECAB_JA_RESULT_LIMIT_EXCEEDED,
                       "result-copy", "MeCab node limit exceeded.");
      return false;
    }
    if (node->stat != MECAB_NOR_NODE && node->stat != MECAB_UNK_NODE)
      continue;
    if (result->words.size() >= kMaximumWords) {
      set_result_error(result, MISAKID_MECAB_JA_RESULT_LIMIT_EXCEEDED,
                       "result-copy", "MeCab word limit exceeded.");
      return false;
    }
    if (node->surface == nullptr || node->feature == nullptr) {
      set_result_error(result, MISAKID_MECAB_JA_ANALYSIS_FAILED,
                       "result-copy", "MeCab returned malformed word data.");
      return false;
    }

    const size_t surface_size = node->length;
    if (surface_size == 0 || surface_size > kMaximumFieldBytes ||
        has_embedded_nul(reinterpret_cast<const uint8_t *>(node->surface),
                         surface_size) ||
        !is_valid_utf8(reinterpret_cast<const uint8_t *>(node->surface),
                       surface_size)) {
      set_result_error(result, MISAKID_MECAB_JA_ANALYSIS_FAILED,
                       "result-copy", "MeCab returned malformed surface data.");
      return false;
    }
    const size_t feature_size =
        ::strnlen(node->feature, kMaximumFieldBytes + 1);
    if (feature_size > kMaximumFieldBytes) {
      set_result_error(result, MISAKID_MECAB_JA_RESULT_LIMIT_EXCEEDED,
                       "result-copy", "MeCab feature limit exceeded.");
      return false;
    }
    if (!is_valid_utf8(reinterpret_cast<const uint8_t *>(node->feature),
                       feature_size) ||
        !parse_csv_fields(node->feature, feature_size, &features)) {
      set_result_error(result, MISAKID_MECAB_JA_ANALYSIS_FAILED,
                       "feature-parse", "UniDic returned malformed features.");
      return false;
    }

    const bool is_unknown = node->stat == MECAB_UNK_NODE;
    if ((!is_unknown && features.size() != feature_schema) ||
        (is_unknown && features.size() != 6)) {
      set_result_error(result, MISAKID_MECAB_JA_ANALYSIS_FAILED,
                       "feature-parse",
                       "UniDic returned an incompatible feature schema.");
      return false;
    }

    const std::string *pronunciation = is_unknown ? nullptr : &features[9];
    const std::string *kana = nullptr;
    if (!is_unknown && feature_schema == 26)
      kana = &features[17];
    else if (!is_unknown && feature_schema == 29)
      kana = &features[20];
    size_t copied_bytes = surface_size;
    if (pronunciation != nullptr)
      copied_bytes += pronunciation->size();
    if (kana != nullptr)
      copied_bytes += kana->size();
    if (copied_bytes > kMaximumResultBytes - total_bytes) {
      set_result_error(result, MISAKID_MECAB_JA_RESULT_LIMIT_EXCEEDED,
                       "result-copy", "MeCab aggregate result limit exceeded.");
      return false;
    }
    total_bytes += copied_bytes;

    WordSnapshot word;
    word.strings[MISAKID_MECAB_JA_SURFACE].assign(node->surface, surface_size);
    if (pronunciation != nullptr)
      word.strings[MISAKID_MECAB_JA_PRONUNCIATION] = *pronunciation;
    if (kana != nullptr)
      word.strings[MISAKID_MECAB_JA_KANA] = *kana;
    word.integers[MISAKID_MECAB_JA_CHAR_TYPE] = node->char_type;
    word.integers[MISAKID_MECAB_JA_IS_UNKNOWN] = is_unknown ? 1 : 0;
    word.integers[MISAKID_MECAB_JA_HAS_PRONUNCIATION] =
        pronunciation == nullptr ? 0 : 1;
    word.integers[MISAKID_MECAB_JA_HAS_KANA] = kana == nullptr ? 0 : 1;
    result->words.push_back(std::move(word));
  }
  return true;
}

const std::string *result_string(const misakid_mecab_ja_result *result,
                                 size_t word_index, uint32_t field) {
  if (result == nullptr || result->status != MISAKID_MECAB_JA_OK ||
      word_index >= result->words.size() || field > MISAKID_MECAB_JA_KANA) {
    return nullptr;
  }
  return &result->words[word_index].strings[field];
}

} // namespace

extern "C" {

uint32_t misakid_mecab_ja_abi_version(void) { return kAbiVersion; }

const uint8_t *misakid_mecab_ja_identity_data(uint32_t field) {
  if (field >= kIdentityValues.size())
    return nullptr;
  return reinterpret_cast<const uint8_t *>(kIdentityValues[field]);
}

size_t misakid_mecab_ja_identity_size(uint32_t field) {
  if (field >= kIdentityValues.size())
    return 0;
  return std::strlen(kIdentityValues[field]);
}

uint8_t *misakid_mecab_ja_buffer_alloc(size_t size) {
  return static_cast<uint8_t *>(std::malloc(size == 0 ? 1 : size));
}

void misakid_mecab_ja_buffer_free(void *buffer) { std::free(buffer); }

misakid_mecab_ja_context *
misakid_mecab_ja_context_create(const uint8_t *dictionary_path,
                                size_t dictionary_path_size,
                                size_t max_input_bytes) {
  auto *context = new (std::nothrow) misakid_mecab_ja_context;
  if (context == nullptr)
    return nullptr;
  try {
    if (dictionary_path == nullptr || dictionary_path_size == 0 ||
        dictionary_path_size > kMaximumDictionaryPathBytes ||
        max_input_bytes == 0 || max_input_bytes > kMaximumInputBytes ||
        has_embedded_nul(dictionary_path, dictionary_path_size)) {
      set_context_error(context, MISAKID_MECAB_JA_INVALID_ARGUMENT,
                        "configuration", "Native configuration is invalid.");
      return context;
    }
    if (!is_valid_utf8(dictionary_path, dictionary_path_size)) {
      set_context_error(context, MISAKID_MECAB_JA_INVALID_UTF8,
                        "configuration",
                        "Dictionary path is not valid UTF-8.");
      return context;
    }

    const std::string dictionary(
        reinterpret_cast<const char *>(dictionary_path), dictionary_path_size);
    std::array<std::string, 5> arguments = {"misakid", "--rcfile", "/dev/null",
                                            "--dicdir", dictionary};
    std::array<char *, 5> argv = {};
    for (size_t index = 0; index < arguments.size(); ++index)
      argv[index] = const_cast<char *>(arguments[index].c_str());

    std::lock_guard<std::mutex> lock(g_mecab_mutex);
    context->tagger = mecab_new(static_cast<int>(argv.size()), argv.data());
    if (context->tagger == nullptr) {
      set_context_error(context, MISAKID_MECAB_JA_DICTIONARY_LOAD_FAILED,
                        "dictionary-load",
                        "MeCab could not load the validated dictionary.");
      return context;
    }
    if (!has_compatible_dictionary_format(
            mecab_dictionary_info(context->tagger))) {
      set_context_error(context, MISAKID_MECAB_JA_DICTIONARY_LOAD_FAILED,
                        "dictionary-format",
                        "The live MeCab dictionary format is not supported.");
      return context;
    }

    // Fugashi's UniDic Tagger selects its named feature tuple from the first
    // token produced for this same probe. Keep that behavior at initialization
    // so an incompatible dictionary cannot fail halfway through user input.
    constexpr char kFeatureSchemaProbe[] = "\xE6\x97\xA5\xE6\x9C\xAC";
    const mecab_node_t *probe_nodes = mecab_sparse_tonode2(
        context->tagger, kFeatureSchemaProbe, sizeof(kFeatureSchemaProbe) - 1);
    if (probe_nodes == nullptr) {
      set_context_error(context, MISAKID_MECAB_JA_DICTIONARY_LOAD_FAILED,
                        "dictionary-schema",
                        "MeCab could not probe the UniDic feature schema.");
      return context;
    }
    const mecab_node_t *probe_word = probe_nodes;
    while (probe_word != nullptr && probe_word->stat != MECAB_NOR_NODE &&
           probe_word->stat != MECAB_UNK_NODE) {
      probe_word = probe_word->next;
    }
    if (probe_word == nullptr || probe_word->stat != MECAB_NOR_NODE ||
        probe_word->feature == nullptr) {
      set_context_error(context, MISAKID_MECAB_JA_DICTIONARY_LOAD_FAILED,
                        "dictionary-schema",
                        "UniDic did not recognize the feature schema probe.");
      return context;
    }
    const size_t probe_feature_size =
        ::strnlen(probe_word->feature, kMaximumFieldBytes + 1);
    std::vector<std::string> probe_features;
    probe_features.reserve(29);
    if (probe_feature_size > kMaximumFieldBytes ||
        !is_valid_utf8(
            reinterpret_cast<const uint8_t *>(probe_word->feature),
            probe_feature_size) ||
        !parse_csv_fields(probe_word->feature, probe_feature_size,
                          &probe_features) ||
        !is_supported_feature_schema(probe_features.size())) {
      set_context_error(context, MISAKID_MECAB_JA_DICTIONARY_LOAD_FAILED,
                        "dictionary-schema",
                        "UniDic has an incompatible feature schema.");
      return context;
    }
    context->feature_schema = probe_features.size();
    context->max_input_bytes = max_input_bytes;
    context->status = MISAKID_MECAB_JA_OK;
    return context;
  } catch (const std::bad_alloc &) {
    set_context_error(context, MISAKID_MECAB_JA_OUT_OF_MEMORY, "initialize",
                      "Native allocation failed during initialization.");
    return context;
  } catch (const std::exception &) {
    set_context_error(context, MISAKID_MECAB_JA_NATIVE_DIAGNOSTIC,
                      "initialize",
                      "Native initialization reported a diagnostic.");
    return context;
  } catch (...) {
    set_context_error(context, MISAKID_MECAB_JA_INTERNAL_ERROR, "initialize",
                      "Unexpected native initialization failure.");
    return context;
  }
}

uint32_t
misakid_mecab_ja_context_status(const misakid_mecab_ja_context *context) {
  return context == nullptr ? MISAKID_MECAB_JA_OUT_OF_MEMORY : context->status;
}

uint32_t misakid_mecab_ja_context_feature_field_count(
    const misakid_mecab_ja_context *context) {
  if (context == nullptr || context->status != MISAKID_MECAB_JA_OK ||
      !is_supported_feature_schema(context->feature_schema)) {
    return 0;
  }
  return static_cast<uint32_t>(context->feature_schema);
}

const uint8_t *misakid_mecab_ja_context_error_stage_data(
    const misakid_mecab_ja_context *context) {
  return context == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(context->error_stage);
}

size_t misakid_mecab_ja_context_error_stage_size(
    const misakid_mecab_ja_context *context) {
  return context == nullptr ? 0 : std::strlen(context->error_stage);
}

const uint8_t *misakid_mecab_ja_context_error_message_data(
    const misakid_mecab_ja_context *context) {
  return context == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(context->error_message);
}

size_t misakid_mecab_ja_context_error_message_size(
    const misakid_mecab_ja_context *context) {
  return context == nullptr ? 0 : std::strlen(context->error_message);
}

void misakid_mecab_ja_context_destroy(misakid_mecab_ja_context *context) {
  if (context == nullptr)
    return;
  try {
    std::lock_guard<std::mutex> lock(g_mecab_mutex);
    if (context->tagger != nullptr) {
      mecab_destroy(context->tagger);
      context->tagger = nullptr;
    }
  } catch (...) {
    // Best-effort destruction must never throw through the C ABI.
  }
  delete context;
}

misakid_mecab_ja_result *misakid_mecab_ja_analyze(
    misakid_mecab_ja_context *context, const uint8_t *utf8, size_t utf8_size) {
  auto *result = new (std::nothrow) misakid_mecab_ja_result;
  if (result == nullptr)
    return nullptr;
  try {
    if (context == nullptr || utf8 == nullptr) {
      set_result_error(result, MISAKID_MECAB_JA_INVALID_ARGUMENT, "input",
                       "Native analysis arguments are invalid.");
      return result;
    }
    if (utf8_size > kMaximumInputBytes) {
      set_result_error(result, MISAKID_MECAB_JA_INPUT_TOO_LARGE, "input",
                       "Input exceeds the native byte limit.");
      return result;
    }

    std::lock_guard<std::mutex> lock(g_mecab_mutex);
    if (context->status != MISAKID_MECAB_JA_OK || context->tagger == nullptr) {
      set_result_error(result, MISAKID_MECAB_JA_INVALID_ARGUMENT, "input",
                       "Native analysis context is unavailable.");
      return result;
    }
    if (utf8_size > context->max_input_bytes) {
      set_result_error(result, MISAKID_MECAB_JA_INPUT_TOO_LARGE, "input",
                       "Input exceeds the configured native byte limit.");
      return result;
    }
    if (has_embedded_nul(utf8, utf8_size)) {
      set_result_error(result, MISAKID_MECAB_JA_INVALID_ARGUMENT, "input",
                       "Input contains an unsupported NUL scalar.");
      return result;
    }
    if (!is_valid_utf8(utf8, utf8_size)) {
      set_result_error(result, MISAKID_MECAB_JA_INVALID_UTF8, "input",
                       "Input is not valid UTF-8.");
      return result;
    }

    const mecab_node_t *nodes = mecab_sparse_tonode2(
        context->tagger, reinterpret_cast<const char *>(utf8), utf8_size);
    if (nodes == nullptr) {
      set_result_error(result, MISAKID_MECAB_JA_ANALYSIS_FAILED,
                       "mecab-analysis", "MeCab analysis failed.");
      return result;
    }
    if (!copy_words(nodes, context->feature_schema, result))
      return result;
    result->status = MISAKID_MECAB_JA_OK;
    return result;
  } catch (const std::bad_alloc &) {
    set_result_error(result, MISAKID_MECAB_JA_OUT_OF_MEMORY, "analysis",
                     "Native allocation failed during analysis.");
    return result;
  } catch (const std::exception &) {
    set_result_error(result, MISAKID_MECAB_JA_NATIVE_DIAGNOSTIC, "analysis",
                     "Native analysis reported a diagnostic.");
    return result;
  } catch (...) {
    set_result_error(result, MISAKID_MECAB_JA_INTERNAL_ERROR, "analysis",
                     "Unexpected native analysis failure.");
    return result;
  }
}

uint32_t
misakid_mecab_ja_result_status(const misakid_mecab_ja_result *result) {
  return result == nullptr ? MISAKID_MECAB_JA_OUT_OF_MEMORY : result->status;
}

const uint8_t *misakid_mecab_ja_result_error_stage_data(
    const misakid_mecab_ja_result *result) {
  return result == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(result->error_stage);
}

size_t misakid_mecab_ja_result_error_stage_size(
    const misakid_mecab_ja_result *result) {
  return result == nullptr ? 0 : std::strlen(result->error_stage);
}

const uint8_t *misakid_mecab_ja_result_error_message_data(
    const misakid_mecab_ja_result *result) {
  return result == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(result->error_message);
}

size_t misakid_mecab_ja_result_error_message_size(
    const misakid_mecab_ja_result *result) {
  return result == nullptr ? 0 : std::strlen(result->error_message);
}

size_t
misakid_mecab_ja_result_word_count(const misakid_mecab_ja_result *result) {
  return result == nullptr || result->status != MISAKID_MECAB_JA_OK
             ? 0
             : result->words.size();
}

const uint8_t *misakid_mecab_ja_result_word_string_data(
    const misakid_mecab_ja_result *result, size_t word_index, uint32_t field) {
  const std::string *value = result_string(result, word_index, field);
  return value == nullptr ? nullptr
                          : reinterpret_cast<const uint8_t *>(value->data());
}

size_t misakid_mecab_ja_result_word_string_size(
    const misakid_mecab_ja_result *result, size_t word_index, uint32_t field) {
  const std::string *value = result_string(result, word_index, field);
  return value == nullptr ? 0 : value->size();
}

int32_t misakid_mecab_ja_result_word_integer(
    const misakid_mecab_ja_result *result, size_t word_index, uint32_t field) {
  if (result == nullptr || result->status != MISAKID_MECAB_JA_OK ||
      word_index >= result->words.size() ||
      field > MISAKID_MECAB_JA_HAS_KANA) {
    return std::numeric_limits<int32_t>::min();
  }
  return result->words[word_index].integers[field];
}

void misakid_mecab_ja_result_destroy(misakid_mecab_ja_result *result) {
  delete result;
}

} // extern "C"
