"""Command-line entry point for the complete en-US G2P pipeline."""

from __future__ import annotations

import argparse
import json
from collections.abc import Sequence
from pathlib import Path

from .pipeline import TrainingConfiguration, run_training


def main(arguments: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Train, export, and qualify Misakid's en-US neural G2P.",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=_default_repo_root())
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--batch-size", type=int, default=512)
    parser.add_argument("--learning-rate", type=float, default=0.001)
    parser.add_argument("--weight-decay", type=float, default=0.0001)
    parser.add_argument("--maximum-examples", type=int)
    parser.add_argument("--threads", type=int, default=4)
    parser.add_argument(
        "--allow-below-threshold",
        action="store_true",
        help="publish a rejected tooling candidate for diagnostics only",
    )
    parsed = parser.parse_args(arguments)
    result = run_training(
        repo_root=parsed.repo_root,
        output=parsed.output,
        configuration=TrainingConfiguration(
            epochs=parsed.epochs,
            batch_size=parsed.batch_size,
            learning_rate=parsed.learning_rate,
            weight_decay=parsed.weight_decay,
            maximum_examples=parsed.maximum_examples,
            threads=parsed.threads,
        ),
        allow_below_threshold=parsed.allow_below_threshold,
    )
    print(
        json.dumps(
            {
                "candidateAccepted": False,
                "modelSha256": result.model_sha256,
                "modelSizeBytes": result.model_size_bytes,
                "output": str(result.output),
                "test": result.test_metrics.to_json(),
                "trainingGatesPassed": result.training_gates_passed,
                "version": result.version,
            },
            sort_keys=True,
        )
    )
    return 0


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


if __name__ == "__main__":
    raise SystemExit(main())
