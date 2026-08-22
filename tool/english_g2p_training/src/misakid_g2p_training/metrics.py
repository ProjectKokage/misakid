"""Encoding, greedy CTC decoding, and held-out quality metrics."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from numpy.typing import NDArray

from .data import Example


@dataclass(frozen=True)
class QualityMetrics:
    """Exact-word accuracy and aggregate Unicode-scalar phone error rate."""

    examples: int
    correct_words: int
    word_accuracy: float
    phone_edits: int
    reference_phones: int
    phone_error_rate: float

    def to_json(self) -> dict[str, int | float]:
        return {
            "examples": self.examples,
            "correctWords": self.correct_words,
            "wordAccuracy": self.word_accuracy,
            "phoneEdits": self.phone_edits,
            "referencePhones": self.reference_phones,
            "phoneErrorRate": self.phone_error_rate,
        }


def encode_word(word: str, grapheme_ids: dict[str, int]) -> list[int]:
    """Encode exact Unicode scalars; training data must never use unknown IDs."""

    try:
        return [grapheme_ids[symbol] for symbol in word]
    except KeyError as error:
        raise ValueError(
            f"Missing training grapheme U+{ord(error.args[0]):04X}."
        ) from error


def encode_phonemes(phonemes: str, phoneme_ids: dict[str, int]) -> list[int]:
    """Encode a non-empty target without the reserved CTC blank."""

    if not phonemes:
        raise ValueError("A training pronunciation cannot be empty.")
    try:
        encoded = [phoneme_ids[symbol] for symbol in phonemes]
    except KeyError as error:
        raise ValueError(
            f"Missing training phoneme U+{ord(error.args[0]):04X}."
        ) from error
    if any(value == 0 for value in encoded):
        raise ValueError("A training pronunciation cannot contain CTC blank.")
    return encoded


def greedy_decode(logits: NDArray[np.floating], phonemes: tuple[str, ...]) -> str:
    """Decode one [time, vocabulary] logit matrix with standard CTC collapse."""

    if logits.ndim != 2 or logits.shape[0] < 1 or logits.shape[1] != len(phonemes):
        raise ValueError("The logits shape is incompatible with the vocabulary.")
    if not np.isfinite(logits).all():
        raise ValueError("The logits contain non-finite values.")
    best = np.argmax(logits, axis=1)
    output: list[str] = []
    previous = -1
    for raw_id in best:
        phoneme_id = int(raw_id)
        if phoneme_id != 0 and phoneme_id != previous:
            output.append(phonemes[phoneme_id])
        previous = phoneme_id
    return "".join(output)


def measure_quality(
    examples: tuple[Example, ...], predictions: tuple[str, ...]
) -> QualityMetrics:
    """Measure predictions against a frozen ordered example tuple."""

    if not examples or len(examples) != len(predictions):
        raise ValueError("Quality metrics require one prediction per example.")
    correct = 0
    edits = 0
    reference_phones = 0
    for example, prediction in zip(examples, predictions, strict=True):
        correct += prediction == example.phonemes
        edits += edit_distance(example.phonemes, prediction)
        reference_phones += len(example.phonemes)
    return QualityMetrics(
        examples=len(examples),
        correct_words=correct,
        word_accuracy=correct / len(examples),
        phone_edits=edits,
        reference_phones=reference_phones,
        phone_error_rate=edits / reference_phones,
    )


def edit_distance(reference: str, prediction: str) -> int:
    """Return Levenshtein distance over Unicode scalar values."""

    previous = list(range(len(prediction) + 1))
    for reference_index, reference_symbol in enumerate(reference, start=1):
        current = [reference_index]
        for prediction_index, prediction_symbol in enumerate(prediction, start=1):
            current.append(
                min(
                    current[-1] + 1,
                    previous[prediction_index] + 1,
                    previous[prediction_index - 1]
                    + (reference_symbol != prediction_symbol),
                )
            )
        previous = current
    return previous[-1]
