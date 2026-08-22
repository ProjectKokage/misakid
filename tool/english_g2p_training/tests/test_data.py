from pathlib import Path

from misakid_g2p_training.constants import UPSTREAM_COMMIT
from misakid_g2p_training.data import prepare_data


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def test_pinned_data_preparation_is_deterministic_and_case_grouped() -> None:
    first = prepare_data(_repo_root(), maximum_examples=4096)
    second = prepare_data(_repo_root(), maximum_examples=4096)

    assert first == second
    assert first.selected_entries == 4096
    assert first.eligible_entries > first.selected_entries
    assert len(first.train) + len(first.development) + len(first.test) == 4096
    assert first.graphemes[:2] == ("<pad>", "<unk>")
    assert first.phonemes[0] == "<blank>"
    assert len(first.sources) == 2
    assert all(len(source.sha256) == 64 for source in first.sources)
    assert all(0 < len(example.word) <= 64 for example in first.train)

    memberships: dict[str, set[str]] = {}
    for split_name, examples in (
        ("train", first.train),
        ("development", first.development),
        ("test", first.test),
    ):
        for example in examples:
            memberships.setdefault(example.word.casefold(), set()).add(split_name)
    assert all(len(values) == 1 for values in memberships.values())


def test_source_commit_is_frozen() -> None:
    assert UPSTREAM_COMMIT == "fba1236595f2d2bf21d414ba6e57d25256afada3"
