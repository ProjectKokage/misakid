import numpy as np

from misakid_g2p_training.data import Example
from misakid_g2p_training.metrics import (
    edit_distance,
    greedy_decode,
    measure_quality,
)


def test_greedy_decode_applies_ctc_blank_and_repeat_rules() -> None:
    vocabulary = ("<blank>", "a", "b")
    ids = (0, 1, 1, 0, 1, 2, 2, 0)
    logits = np.full((len(ids), len(vocabulary)), -10.0, dtype=np.float32)
    for step, value in enumerate(ids):
        logits[step, value] = 10.0

    assert greedy_decode(logits, vocabulary) == "aab"


def test_quality_is_aggregate_phone_error_rate() -> None:
    examples = (
        Example(word="one", phonemes="abc"),
        Example(word="two", phonemes="de"),
    )
    metrics = measure_quality(examples, ("abc", "d"))

    assert metrics.correct_words == 1
    assert metrics.word_accuracy == 0.5
    assert metrics.phone_edits == 1
    assert metrics.reference_phones == 5
    assert metrics.phone_error_rate == 0.2
    assert edit_distance("kitten", "sitting") == 3
