// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0
//
// This owned-result shim contains no eSpeak or phonemizer source. It loads the
// exact caller-supplied eSpeak NG runtime through the public C ABI and keeps
// its process-global state behind one mutex shared by all Dart isolates.

#include "misakid_espeak_en.h"

#include <CommonCrypto/CommonDigest.h>

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <dlfcn.h>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <new>
#include <sstream>
#include <string>
#include <vector>

namespace {

constexpr uint32_t kAbiVersion = 1;
constexpr size_t kErrorStageCapacity = 48;
constexpr size_t kErrorMessageCapacity = 1024;
constexpr size_t kMaximumPathBytes = 32768;
constexpr size_t kMaximumInputBytes = 64 * 1024 * 1024;
constexpr size_t kMaximumOutputBytes = 64 * 1024 * 1024;
constexpr size_t kMaximumNativeChunks = 65536;
constexpr size_t kExpectedRuntimeLibraryBytes = 504168;
constexpr size_t kExpectedDataFiles = 364;
constexpr size_t kExpectedDataDirectories = 37;
constexpr uint64_t kExpectedDataBytes = 18373365;
constexpr char kExpectedRuntimeLibrarySha256[] =
    "bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470";
constexpr char kExpectedDataTreeSha256[] =
    "730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2";

constexpr std::array<const char *, 6> kIdentityValues = {
    "0.1.0-dev.1",
    "1.52.0",
    "bb635eee1ee9c456f4a5cf06fb6cb352ecdd4d61e1951743b423ef22bb57f470",
    "730e20a0d06976b23b8344bac21dab6e1da447d0e16906bab6a0b54db89dd6e2",
    "phonemizer-fork-3.3.2-en-preserve-stress-punctuation-tie",
    "misakid-espeak-en-owned-result-v2",
};

using InitializeFn = int (*)(int, int, const char *, int);
using InfoFn = const char *(*)(const char **);
using SetVoiceByNameFn = int (*)(const char *);
using TextToPhonemesFn = const char *(*)(const void **, int, int);
using TerminateFn = int (*)(void);

struct Runtime {
  void *handle = nullptr;
  InitializeFn initialize = nullptr;
  InfoFn info = nullptr;
  SetVoiceByNameFn set_voice_by_name = nullptr;
  TextToPhonemesFn text_to_phonemes = nullptr;
  TerminateFn terminate = nullptr;
  std::string library_path;
  std::string data_path;
  bool initialized = false;
};

std::mutex g_runtime_mutex;
Runtime g_runtime;
size_t g_live_contexts = 0;

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
          !is_continuation(bytes[index + 2]))
        return false;
      const uint8_t second = bytes[index + 1];
      if ((first == 0xE0U && second < 0xA0U) ||
          (first == 0xEDU && second >= 0xA0U))
        return false;
      index += 3;
      continue;
    }
    if (first >= 0xF0U && first <= 0xF4U) {
      if (index + 3 >= size || !is_continuation(bytes[index + 1]) ||
          !is_continuation(bytes[index + 2]) ||
          !is_continuation(bytes[index + 3]))
        return false;
      const uint8_t second = bytes[index + 1];
      if ((first == 0xF0U && second < 0x90U) ||
          (first == 0xF4U && second > 0x8FU))
        return false;
      index += 4;
      continue;
    }
    return false;
  }
  return true;
}

void update_uint64_big_endian(CC_SHA256_CTX *digest, uint64_t value) {
  std::array<uint8_t, 8> bytes{};
  for (size_t index = 0; index < bytes.size(); ++index) {
    bytes[bytes.size() - 1 - index] = static_cast<uint8_t>(value & 0xFFU);
    value >>= 8U;
  }
  CC_SHA256_Update(digest, bytes.data(), static_cast<CC_LONG>(bytes.size()));
}

std::string finish_sha256(CC_SHA256_CTX *digest) {
  std::array<uint8_t, CC_SHA256_DIGEST_LENGTH> bytes{};
  CC_SHA256_Final(bytes.data(), digest);
  std::ostringstream output;
  output << std::hex << std::setfill('0');
  for (uint8_t byte : bytes)
    output << std::setw(2) << static_cast<unsigned int>(byte);
  return output.str();
}

bool update_file_digest(const std::filesystem::path &path,
                        CC_SHA256_CTX *digest, uint64_t expected_size) {
  std::ifstream input(path, std::ios::binary);
  if (!input)
    return false;
  std::array<char, 1024 * 1024> buffer{};
  uint64_t total = 0;
  while (input) {
    input.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
    const std::streamsize count = input.gcount();
    if (count > 0) {
      total += static_cast<uint64_t>(count);
      CC_SHA256_Update(digest, buffer.data(), static_cast<CC_LONG>(count));
    }
  }
  return input.eof() && !input.bad() && total == expected_size;
}

bool has_exact_library_identity(const std::string &path_value) {
  const std::filesystem::path path(path_value);
  std::error_code error;
  const auto status = std::filesystem::symlink_status(path, error);
  if (error || !std::filesystem::is_regular_file(status) ||
      std::filesystem::is_symlink(status))
    return false;
  const uint64_t size = std::filesystem::file_size(path, error);
  if (error || size != kExpectedRuntimeLibraryBytes)
    return false;
  CC_SHA256_CTX digest{};
  CC_SHA256_Init(&digest);
  if (!update_file_digest(path, &digest, size))
    return false;
  return finish_sha256(&digest) == kExpectedRuntimeLibrarySha256;
}

struct DataFile {
  std::filesystem::path absolute;
  std::string relative;
  uint64_t size = 0;
};

bool has_exact_data_identity(const std::string &root_value) {
  const std::filesystem::path root(root_value);
  std::error_code error;
  const auto root_status = std::filesystem::symlink_status(root, error);
  if (error || !std::filesystem::is_directory(root_status) ||
      std::filesystem::is_symlink(root_status))
    return false;

  std::vector<DataFile> files;
  size_t directories = 1; // Include the configured root.
  uint64_t total_bytes = 0;
  std::filesystem::recursive_directory_iterator iterator(root, error);
  const std::filesystem::recursive_directory_iterator end;
  while (!error && iterator != end) {
    const auto status = iterator->symlink_status(error);
    if (error || std::filesystem::is_symlink(status))
      return false;
    if (std::filesystem::is_regular_file(status)) {
      if (files.size() >= kExpectedDataFiles)
        return false;
      const uint64_t size = iterator->file_size(error);
      if (error || size > kExpectedDataBytes - total_bytes)
        return false;
      const auto relative_path = std::filesystem::relative(iterator->path(),
                                                            root, error);
      if (error)
        return false;
      const std::string relative = relative_path.generic_string();
      if (relative.empty() || relative.find('\0') != std::string::npos)
        return false;
      files.push_back(DataFile{iterator->path(), relative, size});
      total_bytes += size;
    } else if (std::filesystem::is_directory(status)) {
      if (++directories > kExpectedDataDirectories)
        return false;
    } else {
      return false;
    }
    iterator.increment(error);
  }
  if (error || files.size() != kExpectedDataFiles ||
      directories != kExpectedDataDirectories ||
      total_bytes != kExpectedDataBytes)
    return false;
  std::sort(files.begin(), files.end(),
            [](const DataFile &left, const DataFile &right) {
              return left.relative < right.relative;
            });

  CC_SHA256_CTX digest{};
  CC_SHA256_Init(&digest);
  for (const DataFile &file : files) {
    update_uint64_big_endian(&digest, file.relative.size());
    CC_SHA256_Update(&digest, file.relative.data(),
                     static_cast<CC_LONG>(file.relative.size()));
    update_uint64_big_endian(&digest, file.size);
    if (!update_file_digest(file.absolute, &digest, file.size))
      return false;
  }
  return finish_sha256(&digest) == kExpectedDataTreeSha256;
}

bool has_exact_external_resources(const std::string &library_path,
                                  const std::string &data_path) {
  return has_exact_library_identity(library_path) &&
         has_exact_data_identity(data_path);
}

template <typename Function>
bool load_symbol(void *handle, const char *name, Function *destination) {
  ::dlerror();
  void *symbol = ::dlsym(handle, name);
  if (symbol == nullptr || ::dlerror() != nullptr)
    return false;
  *destination = reinterpret_cast<Function>(symbol);
  return true;
}

void close_runtime_locked() {
  if (g_runtime.initialized && g_runtime.terminate != nullptr)
    g_runtime.terminate();
  g_runtime.initialized = false;
  if (g_runtime.handle != nullptr)
    ::dlclose(g_runtime.handle);
  g_runtime = Runtime{};
}

bool version_is_exact(const char *version) {
  if (version == nullptr)
    return false;
  constexpr char kVersion[] = "1.52.0";
  const size_t length = ::strnlen(version, 64);
  return length < 64 && length >= sizeof(kVersion) - 1 &&
         std::memcmp(version, kVersion, sizeof(kVersion) - 1) == 0 &&
         (length == sizeof(kVersion) - 1 || version[sizeof(kVersion) - 1] == ' ');
}

bool ensure_runtime_locked(const std::string &library_path,
                           const std::string &data_path, uint32_t *status,
                           char *stage, char *message) {
  if (g_runtime.initialized && g_runtime.library_path == library_path &&
      g_runtime.data_path == data_path)
    return true;

  close_runtime_locked();
  g_runtime.handle = ::dlopen(library_path.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (g_runtime.handle == nullptr) {
    set_error(status, stage, message, MISAKID_ESPEAK_EN_RUNTIME_LOAD_FAILED,
              "runtime-load", "The eSpeak NG runtime could not be loaded.");
    return false;
  }
  if (!load_symbol(g_runtime.handle, "espeak_Initialize",
                   &g_runtime.initialize) ||
      !load_symbol(g_runtime.handle, "espeak_Info", &g_runtime.info) ||
      !load_symbol(g_runtime.handle, "espeak_SetVoiceByName",
                   &g_runtime.set_voice_by_name) ||
      !load_symbol(g_runtime.handle, "espeak_TextToPhonemes",
                   &g_runtime.text_to_phonemes) ||
      !load_symbol(g_runtime.handle, "espeak_Terminate",
                   &g_runtime.terminate)) {
    set_error(status, stage, message,
              MISAKID_ESPEAK_EN_RUNTIME_SYMBOL_MISSING, "runtime-bind",
              "The eSpeak NG runtime has an incompatible C ABI.");
    close_runtime_locked();
    return false;
  }

  // AUDIO_OUTPUT_SYNCHRONOUS == 2, matching phonemizer-fork 3.3.2.
  if (g_runtime.initialize(2, 0, data_path.c_str(), 0) <= 0) {
    set_error(status, stage, message,
              MISAKID_ESPEAK_EN_RUNTIME_INITIALIZE_FAILED, "runtime-init",
              "The eSpeak NG runtime could not initialize its data.");
    close_runtime_locked();
    return false;
  }
  g_runtime.initialized = true;
  g_runtime.library_path = library_path;
  g_runtime.data_path = data_path;

  const char *reported_data_path = nullptr;
  const char *version = g_runtime.info(&reported_data_path);
  if (!version_is_exact(version) || reported_data_path == nullptr ||
      data_path != reported_data_path) {
    set_error(status, stage, message,
              MISAKID_ESPEAK_EN_RUNTIME_IDENTITY_MISMATCH,
              "runtime-identity",
              "The loaded eSpeak NG version or data path is incompatible.");
    close_runtime_locked();
    return false;
  }
  if (g_runtime.set_voice_by_name("gmw/en-US") != 0 ||
      g_runtime.set_voice_by_name("gmw/en") != 0) {
    set_error(status, stage, message, MISAKID_ESPEAK_EN_VOICE_FAILED,
              "voice-select", "The required English voices are unavailable.");
    close_runtime_locked();
    return false;
  }
  return true;
}

} // namespace

struct misakid_espeak_en_context {
  std::string runtime_library_path;
  std::string data_path;
  size_t max_input_bytes = 0;
  size_t max_output_bytes = 0;
  bool counted = false;
  uint32_t status = MISAKID_ESPEAK_EN_INTERNAL_ERROR;
  char error_stage[kErrorStageCapacity] = {};
  char error_message[kErrorMessageCapacity] = {};
};

struct misakid_espeak_en_result {
  uint32_t status = MISAKID_ESPEAK_EN_INTERNAL_ERROR;
  char error_stage[kErrorStageCapacity] = {};
  char error_message[kErrorMessageCapacity] = {};
  std::string output;
};

namespace {

void set_context_error(misakid_espeak_en_context *context, uint32_t code,
                       const char *stage, const char *message) {
  set_error(&context->status, context->error_stage, context->error_message,
            code, stage, message);
}

void set_result_error(misakid_espeak_en_result *result, uint32_t code,
                      const char *stage, const char *message) {
  set_error(&result->status, result->error_stage, result->error_message, code,
            stage, message);
}

bool convert_locked(misakid_espeak_en_context *context, const uint8_t *utf8,
                    size_t utf8_size, uint32_t dialect,
                    misakid_espeak_en_result *result) {
  if (!ensure_runtime_locked(context->runtime_library_path, context->data_path,
                             &result->status, result->error_stage,
                             result->error_message))
    return false;

  const char *voice = dialect == MISAKID_ESPEAK_EN_AMERICAN ? "gmw/en-US"
                                                            : "gmw/en";
  if (g_runtime.set_voice_by_name(voice) != 0) {
    set_result_error(result, MISAKID_ESPEAK_EN_VOICE_FAILED, "voice-select",
                     "The requested English voice could not be selected.");
    return false;
  }

  std::string input(reinterpret_cast<const char *>(utf8), utf8_size);
  const void *cursor = input.c_str();
  size_t chunks = 0;
  while (cursor != nullptr) {
    if (++chunks > kMaximumNativeChunks) {
      set_result_error(result, MISAKID_ESPEAK_EN_CONVERSION_FAILED,
                       "text-to-phonemes",
                       "The eSpeak NG chunk limit was exceeded.");
      return false;
    }
    const void *before = cursor;
    // UTF-8 input (1); IPA output (2), tie mode (bit 7), U+0361 tie scalar.
    constexpr int kPhonemeMode = 0x02 | (0x01 << 7) | (0x0361 << 8);
    const char *chunk =
        g_runtime.text_to_phonemes(&cursor, 1, kPhonemeMode);
    if (chunk != nullptr) {
      const size_t remaining = context->max_output_bytes - result->output.size();
      const size_t chunk_size = ::strnlen(chunk, remaining + 1);
      if (chunk_size > remaining) {
        set_result_error(result, MISAKID_ESPEAK_EN_RESULT_LIMIT_EXCEEDED,
                         "result-copy",
                         "The eSpeak NG output exceeded the configured limit.");
        return false;
      }
      if (!is_valid_utf8(reinterpret_cast<const uint8_t *>(chunk), chunk_size)) {
        set_result_error(result, MISAKID_ESPEAK_EN_CONVERSION_FAILED,
                         "result-copy", "eSpeak NG returned invalid UTF-8.");
        return false;
      }
      // phonemizer only retains truthy eSpeak chunks. In particular, an empty
      // chunk must not add a separator or fail merely because an earlier
      // chunk exactly filled the configured result capacity.
      if (chunk_size != 0) {
        if (!result->output.empty()) {
          if (result->output.size() == context->max_output_bytes) {
            set_result_error(result, MISAKID_ESPEAK_EN_RESULT_LIMIT_EXCEEDED,
                             "result-copy",
                             "The eSpeak NG output exceeded the configured limit.");
            return false;
          }
          result->output.push_back(' ');
        }
        if (chunk_size > context->max_output_bytes - result->output.size()) {
          set_result_error(result, MISAKID_ESPEAK_EN_RESULT_LIMIT_EXCEEDED,
                           "result-copy",
                           "The eSpeak NG output exceeded the configured limit.");
          return false;
        }
        result->output.append(chunk, chunk_size);
      }
    }
    if (cursor == before) {
      set_result_error(result, MISAKID_ESPEAK_EN_CONVERSION_FAILED,
                       "text-to-phonemes",
                       "eSpeak NG did not consume the input.");
      return false;
    }
  }
  result->status = MISAKID_ESPEAK_EN_OK;
  return true;
}

} // namespace

extern "C" {

uint32_t misakid_espeak_en_abi_version(void) { return kAbiVersion; }

const uint8_t *misakid_espeak_en_identity_data(uint32_t field) {
  if (field >= kIdentityValues.size())
    return nullptr;
  return reinterpret_cast<const uint8_t *>(kIdentityValues[field]);
}

size_t misakid_espeak_en_identity_size(uint32_t field) {
  if (field >= kIdentityValues.size())
    return 0;
  return std::strlen(kIdentityValues[field]);
}

uint8_t *misakid_espeak_en_buffer_alloc(size_t size) {
  return static_cast<uint8_t *>(std::malloc(size == 0 ? 1 : size));
}

void misakid_espeak_en_buffer_free(void *buffer) { std::free(buffer); }

misakid_espeak_en_context *misakid_espeak_en_context_create(
    const uint8_t *runtime_library_path, size_t runtime_library_path_size,
    const uint8_t *data_path, size_t data_path_size, size_t max_input_bytes,
    size_t max_output_bytes) {
  auto *context = new (std::nothrow) misakid_espeak_en_context;
  if (context == nullptr)
    return nullptr;
  try {
    if (runtime_library_path == nullptr || data_path == nullptr ||
        runtime_library_path_size == 0 || data_path_size == 0 ||
        runtime_library_path_size > kMaximumPathBytes ||
        data_path_size > kMaximumPathBytes || max_input_bytes == 0 ||
        max_input_bytes > kMaximumInputBytes || max_output_bytes == 0 ||
        max_output_bytes > kMaximumOutputBytes ||
        has_embedded_nul(runtime_library_path, runtime_library_path_size) ||
        has_embedded_nul(data_path, data_path_size) ||
        !is_valid_utf8(runtime_library_path, runtime_library_path_size) ||
        !is_valid_utf8(data_path, data_path_size)) {
      set_context_error(context, MISAKID_ESPEAK_EN_INVALID_ARGUMENT,
                        "configuration", "Native configuration is invalid.");
      return context;
    }
    context->runtime_library_path.assign(
        reinterpret_cast<const char *>(runtime_library_path),
        runtime_library_path_size);
    context->data_path.assign(reinterpret_cast<const char *>(data_path),
                              data_path_size);
    context->max_input_bytes = max_input_bytes;
    context->max_output_bytes = max_output_bytes;

    if (!has_exact_external_resources(context->runtime_library_path,
                                      context->data_path)) {
      set_context_error(
          context, MISAKID_ESPEAK_EN_RUNTIME_IDENTITY_MISMATCH,
          "resource-identity",
          "The eSpeak NG library or data tree is incompatible.");
      return context;
    }

    std::lock_guard<std::mutex> lock(g_runtime_mutex);
    if (!ensure_runtime_locked(context->runtime_library_path,
                               context->data_path, &context->status,
                               context->error_stage,
                               context->error_message))
      return context;
    ++g_live_contexts;
    context->counted = true;
    context->status = MISAKID_ESPEAK_EN_OK;
    return context;
  } catch (const std::bad_alloc &) {
    set_context_error(context, MISAKID_ESPEAK_EN_OUT_OF_MEMORY,
                      "configuration", "Native allocation failed.");
    return context;
  } catch (...) {
    set_context_error(context, MISAKID_ESPEAK_EN_INTERNAL_ERROR,
                      "configuration", "Unexpected native failure.");
    return context;
  }
}

uint32_t misakid_espeak_en_context_status(
    const misakid_espeak_en_context *context) {
  return context == nullptr ? MISAKID_ESPEAK_EN_INVALID_ARGUMENT
                            : context->status;
}

const uint8_t *misakid_espeak_en_context_error_stage_data(
    const misakid_espeak_en_context *context) {
  return context == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(context->error_stage);
}

size_t misakid_espeak_en_context_error_stage_size(
    const misakid_espeak_en_context *context) {
  return context == nullptr ? 0 : ::strnlen(context->error_stage,
                                            kErrorStageCapacity);
}

const uint8_t *misakid_espeak_en_context_error_message_data(
    const misakid_espeak_en_context *context) {
  return context == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(context->error_message);
}

size_t misakid_espeak_en_context_error_message_size(
    const misakid_espeak_en_context *context) {
  return context == nullptr ? 0 : ::strnlen(context->error_message,
                                            kErrorMessageCapacity);
}

void misakid_espeak_en_context_destroy(misakid_espeak_en_context *context) {
  if (context == nullptr)
    return;
  if (context->counted) {
    std::lock_guard<std::mutex> lock(g_runtime_mutex);
    if (g_live_contexts != 0)
      --g_live_contexts;
    if (g_live_contexts == 0)
      close_runtime_locked();
    context->counted = false;
  }
  delete context;
}

misakid_espeak_en_result *misakid_espeak_en_phonemize(
    misakid_espeak_en_context *context, const uint8_t *utf8, size_t utf8_size,
    uint32_t dialect) {
  auto *result = new (std::nothrow) misakid_espeak_en_result;
  if (result == nullptr)
    return nullptr;
  try {
    if (context == nullptr || context->status != MISAKID_ESPEAK_EN_OK ||
        utf8 == nullptr || dialect > MISAKID_ESPEAK_EN_BRITISH) {
      set_result_error(result, MISAKID_ESPEAK_EN_INVALID_ARGUMENT,
                       "configuration", "Native call arguments are invalid.");
      return result;
    }
    if (utf8_size > context->max_input_bytes) {
      set_result_error(result, MISAKID_ESPEAK_EN_INPUT_TOO_LARGE, "input",
                       "Input exceeds the configured byte limit.");
      return result;
    }
    if (has_embedded_nul(utf8, utf8_size) || !is_valid_utf8(utf8, utf8_size)) {
      set_result_error(result, MISAKID_ESPEAK_EN_INVALID_UTF8, "input",
                       "Input is not valid NUL-free UTF-8.");
      return result;
    }
    std::lock_guard<std::mutex> lock(g_runtime_mutex);
    convert_locked(context, utf8, utf8_size, dialect, result);
    return result;
  } catch (const std::bad_alloc &) {
    set_result_error(result, MISAKID_ESPEAK_EN_OUT_OF_MEMORY, "conversion",
                     "Native allocation failed.");
    return result;
  } catch (...) {
    set_result_error(result, MISAKID_ESPEAK_EN_INTERNAL_ERROR, "conversion",
                     "Unexpected native failure.");
    return result;
  }
}

uint32_t
misakid_espeak_en_result_status(const misakid_espeak_en_result *result) {
  return result == nullptr ? MISAKID_ESPEAK_EN_INVALID_ARGUMENT
                           : result->status;
}

const uint8_t *misakid_espeak_en_result_error_stage_data(
    const misakid_espeak_en_result *result) {
  return result == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(result->error_stage);
}

size_t misakid_espeak_en_result_error_stage_size(
    const misakid_espeak_en_result *result) {
  return result == nullptr
             ? 0
             : ::strnlen(result->error_stage, kErrorStageCapacity);
}

const uint8_t *misakid_espeak_en_result_error_message_data(
    const misakid_espeak_en_result *result) {
  return result == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(result->error_message);
}

size_t misakid_espeak_en_result_error_message_size(
    const misakid_espeak_en_result *result) {
  return result == nullptr
             ? 0
             : ::strnlen(result->error_message, kErrorMessageCapacity);
}

const uint8_t *misakid_espeak_en_result_output_data(
    const misakid_espeak_en_result *result) {
  if (result == nullptr || result->status != MISAKID_ESPEAK_EN_OK)
    return nullptr;
  return reinterpret_cast<const uint8_t *>(result->output.data());
}

size_t misakid_espeak_en_result_output_size(
    const misakid_espeak_en_result *result) {
  return result == nullptr || result->status != MISAKID_ESPEAK_EN_OK
             ? 0
             : result->output.size();
}

void misakid_espeak_en_result_destroy(misakid_espeak_en_result *result) {
  delete result;
}

} // extern "C"
