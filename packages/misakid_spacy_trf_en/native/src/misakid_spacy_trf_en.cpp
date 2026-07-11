// Copyright 2026 the misakid contributors.
// SPDX-License-Identifier: Apache-2.0

#include "misakid_spacy_trf_en.h"

#include "generated_tensor_manifest.h"

#include <Accelerate/Accelerate.h>
#include <CommonCrypto/CommonDigest.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <unordered_map>
#include <utility>
#include <vector>

namespace misakid_spacy_trf_en_internal {

using misakid_spacy_trf_en_generated::kManifestSha256;
using misakid_spacy_trf_en_generated::kModelByteLength;
using misakid_spacy_trf_en_generated::kModelSha256;
using misakid_spacy_trf_en_generated::kTaggerBiasSha256;
using misakid_spacy_trf_en_generated::kTaggerWeightSha256;
using misakid_spacy_trf_en_generated::kTensorByteCount;
using misakid_spacy_trf_en_generated::kTensorRecords;

constexpr uint32_t kAbiVersion = 1;
constexpr size_t kErrorStageCapacity = 48;
constexpr size_t kErrorMessageCapacity = 256;
constexpr size_t kMaximumPathBytes = 32768;
constexpr size_t kMaximumPieceCount = 4000002;
constexpr size_t kMaximumTokenCount = 1000000;
constexpr size_t kDigestBufferBytes = 1024 * 1024;
constexpr size_t kWidth = 768;
constexpr size_t kAttentionHeads = 12;
constexpr size_t kHeadWidth = 64;
constexpr size_t kFeedForwardWidth = 3072;
constexpr size_t kTagCount = 49;
constexpr size_t kTaggerWeightCount = kTagCount * kWidth;
constexpr size_t kStride = 104;
constexpr size_t kWindow = 144;
constexpr size_t kOverlap = kWindow - kStride;
constexpr uint32_t kVocabularySize = 50265;
constexpr uint32_t kBosId = 0;
constexpr uint32_t kPaddingId = 1;
constexpr uint32_t kEosId = 2;

constexpr std::array<const char *, 6> kIdentityValues = {
    "0.1.0-dev.1",
    "3.8.0",
    kModelSha256,
    kManifestSha256,
    "roberta-base-12x768-stride104-window144-mean49",
    "misakid-spacy-trf-en-accelerate-v1",
};

class ModelWeights {
public:
  ModelWeights() = default;
  ModelWeights(const ModelWeights &) = delete;
  ModelWeights &operator=(const ModelWeights &) = delete;
  ~ModelWeights() { std::free(storage_); }

  const float *tensor(size_t index) const {
    return index < tensors_.size() ? tensors_[index] : nullptr;
  }

  void *storage_ = nullptr;
  std::array<const float *, kTensorRecords.size()> tensors_{};
};

struct LoadError {
  uint32_t status = MISAKID_SPACY_TRF_EN_INTERNAL_ERROR;
  const char *stage = "model-load";
  const char *message = "Native model initialization failed.";
};

class UniqueFd {
public:
  explicit UniqueFd(int value) : value_(value) {}
  UniqueFd(const UniqueFd &) = delete;
  UniqueFd &operator=(const UniqueFd &) = delete;
  ~UniqueFd() {
    if (value_ >= 0)
      ::close(value_);
  }
  int get() const { return value_; }

private:
  int value_;
};

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

std::string finish_sha256(CC_SHA256_CTX *context) {
  std::array<uint8_t, CC_SHA256_DIGEST_LENGTH> digest{};
  CC_SHA256_Final(digest.data(), context);
  constexpr char kHex[] = "0123456789abcdef";
  std::string output(digest.size() * 2, '0');
  for (size_t index = 0; index < digest.size(); ++index) {
    output[index * 2] = kHex[digest[index] >> 4U];
    output[index * 2 + 1] = kHex[digest[index] & 0x0FU];
  }
  return output;
}

std::string sha256_bytes(const void *data, size_t size) {
  CC_SHA256_CTX context{};
  CC_SHA256_Init(&context);
  const auto *bytes = static_cast<const uint8_t *>(data);
  size_t offset = 0;
  while (offset < size) {
    const size_t chunk =
        std::min(size - offset,
                 static_cast<size_t>(std::numeric_limits<CC_LONG>::max()));
    CC_SHA256_Update(&context, bytes + offset, static_cast<CC_LONG>(chunk));
    offset += chunk;
  }
  return finish_sha256(&context);
}

bool pread_all(int descriptor, void *destination, size_t size,
               uint64_t offset) {
  auto *bytes = static_cast<uint8_t *>(destination);
  size_t copied = 0;
  while (copied < size) {
    const ssize_t count = ::pread(descriptor, bytes + copied, size - copied,
                                  static_cast<off_t>(offset + copied));
    if (count <= 0)
      return false;
    copied += static_cast<size_t>(count);
  }
  return true;
}

bool sha256_file(int descriptor, uint64_t size, std::string *output) {
  std::array<uint8_t, kDigestBufferBytes> buffer{};
  CC_SHA256_CTX context{};
  CC_SHA256_Init(&context);
  uint64_t offset = 0;
  while (offset < size) {
    const size_t chunk = static_cast<size_t>(
        std::min<uint64_t>(buffer.size(), size - offset));
    if (!pread_all(descriptor, buffer.data(), chunk, offset))
      return false;
    CC_SHA256_Update(&context, buffer.data(), static_cast<CC_LONG>(chunk));
    offset += chunk;
  }
  *output = finish_sha256(&context);
  return true;
}

bool same_file_snapshot(const struct stat &left, const struct stat &right) {
  return left.st_dev == right.st_dev && left.st_ino == right.st_ino &&
         left.st_mode == right.st_mode && left.st_size == right.st_size &&
         left.st_mtimespec.tv_sec == right.st_mtimespec.tv_sec &&
         left.st_mtimespec.tv_nsec == right.st_mtimespec.tv_nsec &&
         left.st_ctimespec.tv_sec == right.st_ctimespec.tv_sec &&
         left.st_ctimespec.tv_nsec == right.st_ctimespec.tv_nsec;
}

std::string canonical_regular_file(const std::string &path, LoadError *error) {
  struct stat link_status {};
  if (::lstat(path.c_str(), &link_status) != 0 ||
      !S_ISREG(link_status.st_mode) || S_ISLNK(link_status.st_mode)) {
    error->status = MISAKID_SPACY_TRF_EN_RESOURCE_UNAVAILABLE;
    error->stage = "model-open";
    error->message = "The transformer model must be a real regular file.";
    return {};
  }
  char *resolved_raw = ::realpath(path.c_str(), nullptr);
  if (resolved_raw == nullptr) {
    error->status = MISAKID_SPACY_TRF_EN_RESOURCE_UNAVAILABLE;
    error->stage = "model-open";
    error->message = "The transformer model path could not be resolved.";
    return {};
  }
  std::unique_ptr<char, decltype(&std::free)> resolved(resolved_raw,
                                                       &std::free);
  const std::string canonical(resolved.get());
  if (canonical != path) {
    error->status = MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT;
    error->stage = "model-open";
    error->message = "The transformer model path must be canonical.";
    return {};
  }
  return canonical;
}

std::shared_ptr<ModelWeights> load_model(const std::string &path,
                                         LoadError *error) {
  const int raw_descriptor =
      ::open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
  if (raw_descriptor < 0) {
    error->status = MISAKID_SPACY_TRF_EN_RESOURCE_UNAVAILABLE;
    error->stage = "model-open";
    error->message = "The transformer model could not be opened.";
    return nullptr;
  }
  UniqueFd descriptor(raw_descriptor);
  struct stat before {};
  if (::fstat(descriptor.get(), &before) != 0 || !S_ISREG(before.st_mode)) {
    error->status = MISAKID_SPACY_TRF_EN_RESOURCE_UNAVAILABLE;
    error->stage = "model-open";
    error->message = "The transformer model file could not be inspected.";
    return nullptr;
  }
  if (static_cast<uint64_t>(before.st_size) != kModelByteLength) {
    error->status = MISAKID_SPACY_TRF_EN_RESOURCE_IDENTITY_MISMATCH;
    error->stage = "model-identity";
    error->message = "The transformer model byte length is incompatible.";
    return nullptr;
  }
  std::string model_digest;
  if (!sha256_file(descriptor.get(), kModelByteLength, &model_digest)) {
    error->status = MISAKID_SPACY_TRF_EN_RESOURCE_UNAVAILABLE;
    error->stage = "model-read";
    error->message = "The transformer model could not be read completely.";
    return nullptr;
  }
  if (model_digest != kModelSha256) {
    error->status = MISAKID_SPACY_TRF_EN_RESOURCE_IDENTITY_MISMATCH;
    error->stage = "model-identity";
    error->message = "The transformer model SHA-256 is incompatible.";
    return nullptr;
  }

  auto model = std::make_shared<ModelWeights>();
  if (::posix_memalign(&model->storage_, 64,
                       static_cast<size_t>(kTensorByteCount)) != 0) {
    error->status = MISAKID_SPACY_TRF_EN_OUT_OF_MEMORY;
    error->stage = "model-allocation";
    error->message = "The aligned transformer weight allocation failed.";
    return nullptr;
  }
  auto *storage = static_cast<uint8_t *>(model->storage_);
  size_t cursor = 0;
  for (size_t index = 0; index < kTensorRecords.size(); ++index) {
    const auto &record = kTensorRecords[index];
    cursor = (cursor + 63U) & ~size_t{63U};
    const size_t byte_length = static_cast<size_t>(record.byte_length);
    if (cursor > kTensorByteCount - byte_length ||
        !pread_all(descriptor.get(), storage + cursor, byte_length,
                   record.byte_offset)) {
      error->status = MISAKID_SPACY_TRF_EN_RESOURCE_UNAVAILABLE;
      error->stage = "tensor-read";
      error->message = "A transformer tensor could not be read completely.";
      return nullptr;
    }
    if (sha256_bytes(storage + cursor, byte_length) != record.sha256) {
      error->status = MISAKID_SPACY_TRF_EN_TENSOR_IDENTITY_MISMATCH;
      error->stage = "tensor-identity";
      error->message = "A transformer tensor SHA-256 is incompatible.";
      return nullptr;
    }
    model->tensors_[index] =
        reinterpret_cast<const float *>(storage + cursor);
    cursor += byte_length;
  }
  if (cursor != kTensorByteCount) {
    error->status = MISAKID_SPACY_TRF_EN_INTERNAL_ERROR;
    error->stage = "tensor-layout";
    error->message = "The compiled transformer tensor layout is invalid.";
    return nullptr;
  }
  struct stat after {};
  if (::fstat(descriptor.get(), &after) != 0 ||
      !same_file_snapshot(before, after)) {
    error->status = MISAKID_SPACY_TRF_EN_RESOURCE_IDENTITY_MISMATCH;
    error->stage = "model-snapshot";
    error->message = "The transformer model changed during initialization.";
    return nullptr;
  }
  return model;
}

std::mutex g_model_cache_mutex;
std::unordered_map<std::string, std::weak_ptr<ModelWeights>> g_model_cache;

std::shared_ptr<ModelWeights> acquire_model(const std::string &path,
                                            LoadError *error) {
  std::lock_guard<std::mutex> lock(g_model_cache_mutex);
  const auto found = g_model_cache.find(path);
  if (found != g_model_cache.end()) {
    if (auto shared = found->second.lock())
      return shared;
    g_model_cache.erase(found);
  }
  auto loaded = load_model(path, error);
  if (loaded)
    g_model_cache[path] = loaded;
  return loaded;
}

void linear(const float *input, size_t rows, size_t input_width,
            const float *weights, size_t output_width, const float *biases,
            std::vector<float> *output) {
  output->resize(rows * output_width);
  cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans,
              static_cast<int>(rows),
              static_cast<int>(output_width),
              static_cast<int>(input_width), 1.0F, input,
              static_cast<int>(input_width), weights,
              static_cast<int>(input_width), 0.0F, output->data(),
              static_cast<int>(output_width));
  for (size_t row = 0; row < rows; ++row) {
    float *target = output->data() + row * output_width;
    for (size_t column = 0; column < output_width; ++column)
      target[column] += biases[column];
  }
}

void layer_norm(const float *input, size_t rows, const float *gain,
                const float *bias, std::vector<float> *output) {
  output->resize(rows * kWidth);
  for (size_t row = 0; row < rows; ++row) {
    const float *source = input + row * kWidth;
    float *target = output->data() + row * kWidth;
    float mean = 0.0F;
    for (size_t column = 0; column < kWidth; ++column)
      mean += source[column];
    mean /= static_cast<float>(kWidth);
    float variance = 0.0F;
    for (size_t column = 0; column < kWidth; ++column) {
      const float delta = source[column] - mean;
      variance += delta * delta;
    }
    variance /= static_cast<float>(kWidth);
    const float inverse = 1.0F / std::sqrt(variance + 1.0e-5F);
    for (size_t column = 0; column < kWidth; ++column) {
      target[column] =
          (source[column] - mean) * inverse * gain[column] + bias[column];
    }
  }
}

void add_and_norm(const std::vector<float> &residual,
                  const std::vector<float> &update, size_t rows,
                  const float *gain, const float *bias,
                  std::vector<float> *output) {
  std::vector<float> sum(residual.size());
  for (size_t index = 0; index < sum.size(); ++index)
    sum[index] = residual[index] + update[index];
  layer_norm(sum.data(), rows, gain, bias, output);
}

void attention(const std::vector<float> &input, size_t sequence_length,
               const float *input_weights, const float *input_biases,
               const float *output_weights, const float *output_biases,
               std::vector<float> *output) {
  std::vector<float> projected;
  linear(input.data(), sequence_length, kWidth, input_weights, 3 * kWidth,
         input_biases, &projected);
  std::vector<float> combined(sequence_length * kWidth);
  std::vector<float> query(sequence_length * kHeadWidth);
  std::vector<float> key(sequence_length * kHeadWidth);
  std::vector<float> value(sequence_length * kHeadWidth);
  std::vector<float> scores(sequence_length * sequence_length);
  std::vector<float> attended(sequence_length * kHeadWidth);

  for (size_t head = 0; head < kAttentionHeads; ++head) {
    for (size_t token = 0; token < sequence_length; ++token) {
      const float *row = projected.data() + token * 3 * kWidth;
      std::memcpy(query.data() + token * kHeadWidth,
                  row + head * kHeadWidth, kHeadWidth * sizeof(float));
      std::memcpy(key.data() + token * kHeadWidth,
                  row + kWidth + head * kHeadWidth,
                  kHeadWidth * sizeof(float));
      std::memcpy(value.data() + token * kHeadWidth,
                  row + 2 * kWidth + head * kHeadWidth,
                  kHeadWidth * sizeof(float));
    }
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasTrans,
                static_cast<int>(sequence_length),
                static_cast<int>(sequence_length),
                static_cast<int>(kHeadWidth), 0.125F, query.data(),
                static_cast<int>(kHeadWidth), key.data(),
                static_cast<int>(kHeadWidth), 0.0F, scores.data(),
                static_cast<int>(sequence_length));
    for (size_t row = 0; row < sequence_length; ++row) {
      float *row_scores = scores.data() + row * sequence_length;
      float maximum = row_scores[0];
      for (size_t column = 1; column < sequence_length; ++column)
        maximum = std::max(maximum, row_scores[column]);
      float total = 0.0F;
      for (size_t column = 0; column < sequence_length; ++column) {
        row_scores[column] = std::exp(row_scores[column] - maximum);
        total += row_scores[column];
      }
      for (size_t column = 0; column < sequence_length; ++column)
        row_scores[column] /= total;
    }
    cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
                static_cast<int>(sequence_length),
                static_cast<int>(kHeadWidth),
                static_cast<int>(sequence_length), 1.0F, scores.data(),
                static_cast<int>(sequence_length), value.data(),
                static_cast<int>(kHeadWidth), 0.0F, attended.data(),
                static_cast<int>(kHeadWidth));
    for (size_t token = 0; token < sequence_length; ++token) {
      std::memcpy(combined.data() + token * kWidth + head * kHeadWidth,
                  attended.data() + token * kHeadWidth,
                  kHeadWidth * sizeof(float));
    }
  }
  linear(combined.data(), sequence_length, kWidth, output_weights, kWidth,
         output_biases, output);
}

std::vector<float> infer_span(const ModelWeights &model,
                              const uint32_t *piece_ids,
                              size_t sequence_length) {
  std::vector<float> embeddings(sequence_length * kWidth);
  const float *word = model.tensor(0);
  const float *type = model.tensor(1);
  const float *position = model.tensor(2);
  for (size_t token = 0; token < sequence_length; ++token) {
    for (size_t column = 0; column < kWidth; ++column) {
      embeddings[token * kWidth + column] =
          word[static_cast<size_t>(piece_ids[token]) * kWidth + column] +
          type[column] + position[(token + 2) * kWidth + column];
    }
  }
  std::vector<float> hidden;
  layer_norm(embeddings.data(), sequence_length, model.tensor(3),
             model.tensor(4), &hidden);
  for (size_t layer = 0; layer < 12; ++layer) {
    const size_t base = 5 + layer * 12;
    std::vector<float> attended;
    attention(hidden, sequence_length, model.tensor(base),
              model.tensor(base + 1), model.tensor(base + 2),
              model.tensor(base + 3), &attended);
    std::vector<float> attended_normalized;
    add_and_norm(hidden, attended, sequence_length, model.tensor(base + 4),
                 model.tensor(base + 5), &attended_normalized);
    std::vector<float> intermediate;
    linear(attended_normalized.data(), sequence_length, kWidth,
           model.tensor(base + 6), kFeedForwardWidth, model.tensor(base + 7),
           &intermediate);
    for (float &entry : intermediate) {
      entry = 0.5F * entry *
              (1.0F + std::erf(entry * 0.7071067811865475244F));
    }
    std::vector<float> feed_forward;
    linear(intermediate.data(), sequence_length, kFeedForwardWidth,
           model.tensor(base + 8), kWidth, model.tensor(base + 9),
           &feed_forward);
    std::vector<float> next;
    add_and_norm(attended_normalized, feed_forward, sequence_length,
                 model.tensor(base + 10), model.tensor(base + 11), &next);
    hidden.swap(next);
  }
  return hidden;
}

class TokenPooler {
public:
  TokenPooler(const std::array<float, kTaggerWeightCount> &weights,
              const std::array<float, kTagCount> &biases,
              const uint32_t *lengths, size_t token_count,
              size_t total_piece_count, std::vector<uint16_t> *tags)
      : weights_(weights), biases_(biases), lengths_(lengths),
        token_count_(token_count), total_piece_count_(total_piece_count),
        tags_(tags) {
    if (token_count_ != 0)
      remaining_ = lengths_[0];
  }

  bool consume(size_t global_piece_index, const float *row) {
    if (global_piece_index == 0 ||
        global_piece_index + 1 == total_piece_count_)
      return true;
    if (token_index_ >= token_count_ || remaining_ == 0)
      return false;
    for (size_t column = 0; column < kWidth; ++column)
      sum_[column] += row[column];
    --remaining_;
    if (remaining_ != 0)
      return true;

    const float divisor = static_cast<float>(lengths_[token_index_]);
    for (size_t column = 0; column < kWidth; ++column)
      pooled_[column] = sum_[column] / divisor;
    std::array<float, kTagCount> scores{};
    cblas_sgemv(CblasRowMajor, CblasNoTrans,
                static_cast<int>(kTagCount),
                static_cast<int>(kWidth), 1.0F, weights_.data(),
                static_cast<int>(kWidth), pooled_.data(), 1, 0.0F,
                scores.data(), 1);
    size_t best = 0;
    scores[0] += biases_[0];
    if (!std::isfinite(scores[0]))
      return false;
    for (size_t tag = 1; tag < kTagCount; ++tag) {
      scores[tag] += biases_[tag];
      if (!std::isfinite(scores[tag]))
        return false;
      if (scores[tag] > scores[best])
        best = tag;
    }
    tags_->push_back(static_cast<uint16_t>(best));
    ++token_index_;
    sum_.fill(0.0F);
    if (token_index_ < token_count_)
      remaining_ = lengths_[token_index_];
    return true;
  }

  bool complete() const {
    return token_index_ == token_count_ && remaining_ == 0 &&
           tags_->size() == token_count_;
  }

private:
  const std::array<float, kTaggerWeightCount> &weights_;
  const std::array<float, kTagCount> &biases_;
  const uint32_t *lengths_;
  size_t token_count_;
  size_t total_piece_count_;
  std::vector<uint16_t> *tags_;
  size_t token_index_ = 0;
  uint32_t remaining_ = 0;
  std::array<float, kWidth> sum_{};
  std::array<float, kWidth> pooled_{};
};

bool infer_document(const ModelWeights &model,
                    const std::array<float, kTaggerWeightCount> &weights,
                    const std::array<float, kTagCount> &biases,
                    const uint32_t *piece_ids, size_t piece_count,
                    const uint32_t *token_lengths, size_t token_count,
                    std::vector<uint16_t> *tags) {
  tags->clear();
  tags->reserve(token_count);
  if (token_count == 0)
    return true;
  TokenPooler pooler(weights, biases, token_lengths, token_count, piece_count,
                     tags);

  size_t span_start = 0;
  size_t previous_length = std::min(kWindow, piece_count);
  std::vector<float> previous =
      infer_span(model, piece_ids, previous_length);
  const size_t first_rows = std::min(kStride, piece_count);
  for (size_t row = 0; row < first_rows; ++row) {
    if (!pooler.consume(row, previous.data() + row * kWidth))
      return false;
  }

  for (span_start = kStride; span_start < piece_count;
       span_start += kStride) {
    const size_t current_length =
        std::min(kWindow, piece_count - span_start);
    std::vector<float> current =
        infer_span(model, piece_ids + span_start, current_length);
    const size_t overlap = std::min(kOverlap, current_length);
    const size_t previous_overlap_start = previous_length - overlap;
    for (size_t row = 0; row < overlap; ++row) {
      for (size_t column = 0; column < kWidth; ++column) {
        const size_t current_index = row * kWidth + column;
        current[current_index] =
            (previous[(previous_overlap_start + row) * kWidth + column] +
             current[current_index]) /
            2.0F;
      }
    }
    const size_t rows = std::min(kStride, piece_count - span_start);
    for (size_t row = 0; row < rows; ++row) {
      if (!pooler.consume(span_start + row,
                          current.data() + row * kWidth))
        return false;
    }
    previous.swap(current);
    previous_length = current_length;
  }
  return pooler.complete();
}

} // namespace misakid_spacy_trf_en_internal

struct misakid_spacy_trf_en_context {
  uint32_t status = MISAKID_SPACY_TRF_EN_OK;
  std::array<char,
             misakid_spacy_trf_en_internal::kErrorStageCapacity>
      error_stage{};
  std::array<char,
             misakid_spacy_trf_en_internal::kErrorMessageCapacity>
      error_message{};
  std::shared_ptr<misakid_spacy_trf_en_internal::ModelWeights> model;
  std::array<float,
             misakid_spacy_trf_en_internal::kTaggerWeightCount>
      tagger_weights{};
  std::array<float, misakid_spacy_trf_en_internal::kTagCount> tagger_biases{};
};

struct misakid_spacy_trf_en_result {
  uint32_t status = MISAKID_SPACY_TRF_EN_OK;
  std::array<char,
             misakid_spacy_trf_en_internal::kErrorStageCapacity>
      error_stage{};
  std::array<char,
             misakid_spacy_trf_en_internal::kErrorMessageCapacity>
      error_message{};
  std::vector<uint16_t> tags;
};

namespace misakid_spacy_trf_en_internal {

template <typename Owner>
void set_error(Owner *owner, uint32_t status, const char *stage,
               const char *message) {
  owner->status = status;
  copy_bounded(owner->error_stage.data(), owner->error_stage.size(), stage);
  copy_bounded(owner->error_message.data(), owner->error_message.size(),
               message);
}

template <typename Owner>
const uint8_t *stage_data(const Owner *owner) {
  return owner == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(owner->error_stage.data());
}

template <typename Owner> size_t stage_size(const Owner *owner) {
  return owner == nullptr
             ? 0
             : ::strnlen(owner->error_stage.data(), owner->error_stage.size());
}

template <typename Owner>
const uint8_t *message_data(const Owner *owner) {
  return owner == nullptr
             ? nullptr
             : reinterpret_cast<const uint8_t *>(owner->error_message.data());
}

template <typename Owner> size_t message_size(const Owner *owner) {
  return owner == nullptr
             ? 0
             : ::strnlen(owner->error_message.data(),
                         owner->error_message.size());
}

} // namespace misakid_spacy_trf_en_internal

extern "C" {

uint32_t misakid_spacy_trf_en_abi_version(void) {
  return misakid_spacy_trf_en_internal::kAbiVersion;
}

const uint8_t *misakid_spacy_trf_en_identity_data(uint32_t field) {
  using namespace misakid_spacy_trf_en_internal;
  if (field >= kIdentityValues.size())
    return nullptr;
  return reinterpret_cast<const uint8_t *>(kIdentityValues[field]);
}

size_t misakid_spacy_trf_en_identity_size(uint32_t field) {
  using namespace misakid_spacy_trf_en_internal;
  return field < kIdentityValues.size() ? std::strlen(kIdentityValues[field])
                                        : 0;
}

uint8_t *misakid_spacy_trf_en_buffer_alloc(size_t size) {
  return static_cast<uint8_t *>(std::malloc(size == 0 ? 1 : size));
}

void misakid_spacy_trf_en_buffer_free(void *buffer) { std::free(buffer); }

misakid_spacy_trf_en_context *misakid_spacy_trf_en_context_create(
    const uint8_t *model_path, size_t model_path_size,
    const float *tagger_weights, size_t tagger_weight_count,
    const float *tagger_biases, size_t tagger_bias_count) {
  using namespace misakid_spacy_trf_en_internal;
  auto *context = new (std::nothrow) misakid_spacy_trf_en_context();
  if (context == nullptr)
    return nullptr;
  try {
    if (model_path == nullptr || model_path_size == 0 ||
        model_path_size > kMaximumPathBytes ||
        has_embedded_nul(model_path, model_path_size) ||
        tagger_weights == nullptr || tagger_biases == nullptr ||
        tagger_weight_count != kTaggerWeightCount ||
        tagger_bias_count != kTagCount ||
        reinterpret_cast<uintptr_t>(tagger_weights) % alignof(float) != 0 ||
        reinterpret_cast<uintptr_t>(tagger_biases) % alignof(float) != 0) {
      set_error(context, MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT, "initialize",
                "Native context arguments are invalid.");
      return context;
    }
    if (!is_valid_utf8(model_path, model_path_size)) {
      set_error(context, MISAKID_SPACY_TRF_EN_INVALID_UTF8, "model-path",
                "The transformer model path is not valid UTF-8.");
      return context;
    }
    if (sha256_bytes(tagger_weights,
                     kTaggerWeightCount * sizeof(float)) !=
            kTaggerWeightSha256 ||
        sha256_bytes(tagger_biases, kTagCount * sizeof(float)) !=
            kTaggerBiasSha256) {
      set_error(context, MISAKID_SPACY_TRF_EN_RESOURCE_IDENTITY_MISMATCH,
                "tagger-identity",
                "The transformer tagger arrays are incompatible.");
      return context;
    }
    std::copy(tagger_weights, tagger_weights + kTaggerWeightCount,
              context->tagger_weights.begin());
    std::copy(tagger_biases, tagger_biases + kTagCount,
              context->tagger_biases.begin());
    if (std::any_of(context->tagger_weights.begin(),
                    context->tagger_weights.end(),
                    [](float value) { return !std::isfinite(value); }) ||
        std::any_of(context->tagger_biases.begin(),
                    context->tagger_biases.end(),
                    [](float value) { return !std::isfinite(value); })) {
      set_error(context, MISAKID_SPACY_TRF_EN_RESOURCE_IDENTITY_MISMATCH,
                "tagger-identity",
                "The transformer tagger arrays contain non-finite values.");
      return context;
    }
    const std::string supplied_path(
        reinterpret_cast<const char *>(model_path), model_path_size);
    LoadError error;
    const std::string canonical = canonical_regular_file(supplied_path, &error);
    if (canonical.empty()) {
      set_error(context, error.status, error.stage, error.message);
      return context;
    }
    context->model = acquire_model(canonical, &error);
    if (!context->model) {
      set_error(context, error.status, error.stage, error.message);
      return context;
    }
    return context;
  } catch (const std::bad_alloc &) {
    set_error(context, MISAKID_SPACY_TRF_EN_OUT_OF_MEMORY, "initialize",
              "Native context initialization ran out of memory.");
    return context;
  } catch (...) {
    set_error(context, MISAKID_SPACY_TRF_EN_INTERNAL_ERROR, "initialize",
              "Native context initialization failed.");
    return context;
  }
}

uint32_t misakid_spacy_trf_en_context_status(
    const misakid_spacy_trf_en_context *context) {
  return context == nullptr ? MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT
                            : context->status;
}

const uint8_t *misakid_spacy_trf_en_context_error_stage_data(
    const misakid_spacy_trf_en_context *context) {
  return misakid_spacy_trf_en_internal::stage_data(context);
}

size_t misakid_spacy_trf_en_context_error_stage_size(
    const misakid_spacy_trf_en_context *context) {
  return misakid_spacy_trf_en_internal::stage_size(context);
}

const uint8_t *misakid_spacy_trf_en_context_error_message_data(
    const misakid_spacy_trf_en_context *context) {
  return misakid_spacy_trf_en_internal::message_data(context);
}

size_t misakid_spacy_trf_en_context_error_message_size(
    const misakid_spacy_trf_en_context *context) {
  return misakid_spacy_trf_en_internal::message_size(context);
}

void misakid_spacy_trf_en_context_destroy(
    misakid_spacy_trf_en_context *context) {
  delete context;
}

misakid_spacy_trf_en_result *misakid_spacy_trf_en_infer(
    const misakid_spacy_trf_en_context *context,
    const uint32_t *piece_ids, size_t piece_count,
    const uint32_t *token_piece_lengths, size_t token_count) {
  using namespace misakid_spacy_trf_en_internal;
  auto *result = new (std::nothrow) misakid_spacy_trf_en_result();
  if (result == nullptr)
    return nullptr;
  try {
    if (context == nullptr || context->status != MISAKID_SPACY_TRF_EN_OK ||
        !context->model) {
      set_error(result, MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT, "context",
                "The native transformer context is unavailable.");
      return result;
    }
    if (piece_ids == nullptr || piece_count < 2 ||
        (token_count != 0 && token_piece_lengths == nullptr) ||
        reinterpret_cast<uintptr_t>(piece_ids) % alignof(uint32_t) != 0 ||
        (token_piece_lengths != nullptr &&
         reinterpret_cast<uintptr_t>(token_piece_lengths) %
                 alignof(uint32_t) !=
             0)) {
      set_error(result, MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT, "input",
                "Native transformer input buffers are invalid.");
      return result;
    }
    if (piece_count > kMaximumPieceCount || token_count > kMaximumTokenCount) {
      set_error(result, MISAKID_SPACY_TRF_EN_INPUT_LIMIT_EXCEEDED, "input",
                "Native transformer input exceeds its fixed limits.");
      return result;
    }
    if (piece_ids[0] != kBosId || piece_ids[piece_count - 1] != kEosId) {
      set_error(result, MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT, "input",
                "Native transformer input markers are invalid.");
      return result;
    }
    for (size_t index = 0; index < piece_count; ++index) {
      if (piece_ids[index] >= kVocabularySize ||
          (index != 0 && index + 1 != piece_count &&
           piece_ids[index] == kPaddingId)) {
        set_error(result, MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT, "input",
                  "Native transformer piece identifiers are invalid.");
        return result;
      }
    }
    uint64_t length_sum = 0;
    for (size_t index = 0; index < token_count; ++index) {
      const uint32_t length = token_piece_lengths[index];
      if (length == 0 || length > piece_count - 2 ||
          length_sum > piece_count - 2 - length) {
        set_error(result, MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT, "input",
                  "Native transformer token piece lengths are invalid.");
        return result;
      }
      length_sum += length;
    }
    if (length_sum != piece_count - 2) {
      set_error(result, MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT, "input",
                "Native transformer token lengths do not cover all pieces.");
      return result;
    }
    if (!infer_document(*context->model, context->tagger_weights,
                        context->tagger_biases, piece_ids, piece_count,
                        token_piece_lengths, token_count, &result->tags)) {
      set_error(result, MISAKID_SPACY_TRF_EN_INFERENCE_FAILED, "inference",
                "Native transformer inference produced an invalid result.");
      result->tags.clear();
    }
    return result;
  } catch (const std::bad_alloc &) {
    set_error(result, MISAKID_SPACY_TRF_EN_OUT_OF_MEMORY, "inference",
              "Native transformer inference ran out of memory.");
    result->tags.clear();
    return result;
  } catch (...) {
    set_error(result, MISAKID_SPACY_TRF_EN_INTERNAL_ERROR, "inference",
              "Native transformer inference failed.");
    result->tags.clear();
    return result;
  }
}

uint32_t misakid_spacy_trf_en_result_status(
    const misakid_spacy_trf_en_result *result) {
  return result == nullptr ? MISAKID_SPACY_TRF_EN_INVALID_ARGUMENT
                           : result->status;
}

const uint8_t *misakid_spacy_trf_en_result_error_stage_data(
    const misakid_spacy_trf_en_result *result) {
  return misakid_spacy_trf_en_internal::stage_data(result);
}

size_t misakid_spacy_trf_en_result_error_stage_size(
    const misakid_spacy_trf_en_result *result) {
  return misakid_spacy_trf_en_internal::stage_size(result);
}

const uint8_t *misakid_spacy_trf_en_result_error_message_data(
    const misakid_spacy_trf_en_result *result) {
  return misakid_spacy_trf_en_internal::message_data(result);
}

size_t misakid_spacy_trf_en_result_error_message_size(
    const misakid_spacy_trf_en_result *result) {
  return misakid_spacy_trf_en_internal::message_size(result);
}

const uint16_t *misakid_spacy_trf_en_result_tags_data(
    const misakid_spacy_trf_en_result *result) {
  return result == nullptr || result->tags.empty() ? nullptr
                                                   : result->tags.data();
}

size_t misakid_spacy_trf_en_result_tags_size(
    const misakid_spacy_trf_en_result *result) {
  return result == nullptr ? 0 : result->tags.size();
}

void misakid_spacy_trf_en_result_destroy(
    misakid_spacy_trf_en_result *result) {
  delete result;
}

} // extern "C"
