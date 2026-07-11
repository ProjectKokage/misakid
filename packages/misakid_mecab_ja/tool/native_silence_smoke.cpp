// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

#include <cstddef>
#include <cstdint>
#include <dlfcn.h>
#include <string>

#include "misakid_mecab_ja.h"

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

  using Create = misakid_mecab_ja_context *(*)(const uint8_t *, size_t,
                                                size_t);
  using ContextStatus = uint32_t (*)(const misakid_mecab_ja_context *);
  using DestroyContext = void (*)(misakid_mecab_ja_context *);
  using Analyze = misakid_mecab_ja_result *(*)(misakid_mecab_ja_context *,
                                                const uint8_t *, size_t);
  using ResultStatus = uint32_t (*)(const misakid_mecab_ja_result *);
  using DestroyResult = void (*)(misakid_mecab_ja_result *);

  const auto create = load<Create>(library, "misakid_mecab_ja_context_create");
  const auto context_status =
      load<ContextStatus>(library, "misakid_mecab_ja_context_status");
  const auto destroy_context =
      load<DestroyContext>(library, "misakid_mecab_ja_context_destroy");
  const auto analyze = load<Analyze>(library, "misakid_mecab_ja_analyze");
  const auto result_status =
      load<ResultStatus>(library, "misakid_mecab_ja_result_status");
  const auto destroy_result =
      load<DestroyResult>(library, "misakid_mecab_ja_result_destroy");
  if (create == nullptr || context_status == nullptr ||
      destroy_context == nullptr || analyze == nullptr ||
      result_status == nullptr || destroy_result == nullptr) {
    dlclose(library);
    return 3;
  }

  const std::string dictionary_path(argv[2]);
  auto *context = create(
      reinterpret_cast<const uint8_t *>(dictionary_path.data()),
      dictionary_path.size(), 1024);
  if (context == nullptr || context_status(context) != MISAKID_MECAB_JA_OK) {
    if (context != nullptr) destroy_context(context);
    dlclose(library);
    return 4;
  }

  const uint8_t japanese[] = {0xE6, 0x97, 0xA5, 0xE6, 0x9C,
                              0xAC, 0xE8, 0xAA, 0x9E};
  auto *result = analyze(context, japanese, sizeof(japanese));
  if (result == nullptr || result_status(result) != MISAKID_MECAB_JA_OK) {
    if (result != nullptr) destroy_result(result);
    destroy_context(context);
    dlclose(library);
    return 5;
  }
  destroy_result(result);

  const uint8_t malformed[] = {0xC0};
  result = analyze(context, malformed, sizeof(malformed));
  if (result == nullptr ||
      result_status(result) != MISAKID_MECAB_JA_INVALID_UTF8) {
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
      context_status(context) != MISAKID_MECAB_JA_DICTIONARY_LOAD_FAILED) {
    if (context != nullptr) destroy_context(context);
    dlclose(library);
    return 7;
  }
  destroy_context(context);

  if (dlclose(library) != 0) return 8;
  return 0;
}
