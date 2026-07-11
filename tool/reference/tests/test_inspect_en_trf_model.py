from __future__ import annotations

import hashlib
import io
from pathlib import Path
import tempfile
import unittest
import zipfile

from tool.reference import inspect_en_trf_model as inspection


class TransformerModelInspectionTests(unittest.TestCase):
    def test_static_tensor_contract_is_complete_and_exact(self):
        tensors = inspection.expected_transformer_tensors()
        self.assertEqual(len(tensors), 149)
        self.assertEqual(len({name for name, _ in tensors}), 149)
        self.assertEqual(
            tensors[0],
            (
                "curated_encoder.embeddings.inner.word_embeddings.weight",
                (50265, 768),
            ),
        )
        self.assertEqual(
            tensors[-1],
            ("curated_encoder.layers.11.ffn_output_layernorm.bias", (768,)),
        )
        element_count = sum(_product(shape) for _, shape in tensors)
        self.assertEqual(element_count, 124_055_040)
        self.assertEqual(element_count * 4, 496_220_160)
        self.assertEqual(len(inspection.TAGGER_LABELS), 49)
        self.assertNotIn("_SP", inspection.TAGGER_LABELS)
        self.assertEqual(
            inspection.EXPECTED_VERSIONS["regex"], "2024.11.6"
        )
        self.assertEqual(
            inspection.EXPECTED_REGEX_PROPERTY_COUNTS,
            {
                "letter": (677, 141_028),
                "number": (144, 1_911),
                "whiteSpace": (10, 25),
            },
        )

    def test_ranges_are_contiguous_and_within_the_pinned_model(self):
        model_size = inspection.EXPECTED_RESOURCES["transformer/model"][0]
        bpe_offset, bpe_length, _ = inspection.BYTE_BPE_RANGE
        shim_offset, shim_length, _ = inspection.PYTORCH_SHIM_RANGE
        state_offset, state_length, _ = inspection.TORCH_STATE_RANGE
        self.assertEqual(shim_offset + shim_length, model_size)
        self.assertEqual(state_offset + state_length, model_size)
        self.assertEqual(state_offset, shim_offset + 20)
        self.assertLess(bpe_offset + bpe_length, shim_offset)

    def test_prefixed_stored_zip_offsets_point_at_member_data(self):
        buffer = io.BytesIO()
        buffer.write(b"pinned-prefix")
        with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.writestr("archive/data/0", b"tensor-bytes")

        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model"
            path.write_bytes(buffer.getvalue())
            with path.open("rb") as stream, zipfile.ZipFile(path) as archive:
                info = archive.getinfo("archive/data/0")
                offset = inspection._zip_data_offset(stream, info)
            self.assertEqual(
                inspection._sha256_range(path, offset, len(b"tensor-bytes")),
                hashlib.sha256(b"tensor-bytes").hexdigest(),
            )


def _product(shape: tuple[int, ...]) -> int:
    value = 1
    for dimension in shape:
        value *= dimension
    return value


if __name__ == "__main__":
    unittest.main()
