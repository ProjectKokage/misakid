// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

#include <cstddef>
#include <cstdint>
#include <dlfcn.h>
#include <string>

#include "misakid_openjtalk.h"

namespace {

template <typename Function>
Function load(void *library, const char *symbol) {
  return reinterpret_cast<Function>(dlsym(library, symbol));
}

}  // namespace

int main(int argc, char **argv) {
  if (argc != 3) return 1;

  void *library = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (library == nullptr) return 2;

  using Create = misakid_openjtalk_context *(*)(const uint8_t *, size_t,
                                                 size_t);
  using ContextStatus = uint32_t (*)(const misakid_openjtalk_context *);
  using DestroyContext = void (*)(misakid_openjtalk_context *);
  using Analyze = misakid_openjtalk_result *(*)(misakid_openjtalk_context *,
                                                 const uint8_t *, size_t);
  using ResultStatus = uint32_t (*)(const misakid_openjtalk_result *);
  using WordCount = size_t (*)(const misakid_openjtalk_result *);
  using DestroyResult = void (*)(misakid_openjtalk_result *);

  const auto create =
      load<Create>(library, "misakid_openjtalk_context_create");
  const auto context_status =
      load<ContextStatus>(library, "misakid_openjtalk_context_status");
  const auto destroy_context =
      load<DestroyContext>(library, "misakid_openjtalk_context_destroy");
  const auto analyze = load<Analyze>(library, "misakid_openjtalk_analyze");
  const auto result_status =
      load<ResultStatus>(library, "misakid_openjtalk_result_status");
  const auto word_count =
      load<WordCount>(library, "misakid_openjtalk_result_word_count");
  const auto destroy_result =
      load<DestroyResult>(library, "misakid_openjtalk_result_destroy");
  if (create == nullptr || context_status == nullptr ||
      destroy_context == nullptr || analyze == nullptr ||
      result_status == nullptr || word_count == nullptr ||
      destroy_result == nullptr) {
    dlclose(library);
    return 3;
  }

  const std::string dictionary_path(argv[2]);
  auto *context = create(
      reinterpret_cast<const uint8_t *>(dictionary_path.data()),
      dictionary_path.size(), 1024);
  if (context == nullptr ||
      context_status(context) != MISAKID_OPENJTALK_OK) {
    if (context != nullptr) destroy_context(context);
    dlclose(library);
    return 4;
  }

  const uint8_t japanese[] = {
      0xE7, 0x8C, 0xAB, 0xF0, 0x9F, 0x98, 0x80,
      0xE7, 0x8A, 0xAC, 0xE3, 0x80, 0x82,
  };
  auto *result = analyze(context, japanese, sizeof(japanese));
  if (result == nullptr || result_status(result) != MISAKID_OPENJTALK_OK ||
      word_count(result) != 4) {
    if (result != nullptr) destroy_result(result);
    destroy_context(context);
    dlclose(library);
    return 5;
  }
  destroy_result(result);

  const uint8_t embedded_nul[] = {0};
  result = analyze(context, embedded_nul, sizeof(embedded_nul));
  if (result == nullptr ||
      result_status(result) != MISAKID_OPENJTALK_INVALID_ARGUMENT) {
    if (result != nullptr) destroy_result(result);
    destroy_context(context);
    dlclose(library);
    return 6;
  }
  destroy_result(result);
  destroy_context(context);

  const std::string missing_dictionary = dictionary_path + "/does-not-exist";
  context = create(
      reinterpret_cast<const uint8_t *>(missing_dictionary.data()),
      missing_dictionary.size(), 1024);
  if (context == nullptr ||
      context_status(context) != MISAKID_OPENJTALK_DICTIONARY_LOAD_FAILED) {
    if (context != nullptr) destroy_context(context);
    dlclose(library);
    return 7;
  }
  destroy_context(context);

  if (dlclose(library) != 0) return 8;
  return 0;
}
