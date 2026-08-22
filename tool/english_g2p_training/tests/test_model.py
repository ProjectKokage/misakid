from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import torch

from misakid_g2p_training.constants import INPUT_NAME, OUTPUT_NAME
from misakid_g2p_training.model import EnglishG2pModel
from misakid_g2p_training.pipeline import _export_onnx


def _small_model() -> EnglishG2pModel:
    torch.manual_seed(7)
    model = EnglishG2pModel(
        12,
        7,
        channels=8,
        dilations=(1, 2),
        dropout=0.0,
    )
    model.eval()
    return model


def test_model_shape_and_padding_do_not_change_the_prefix() -> None:
    model = _small_model()
    padded = torch.tensor([[2, 3, 0, 0], [2, 3, 4, 5]], dtype=torch.int64)
    short = torch.tensor([[2, 3]], dtype=torch.int64)

    with torch.inference_mode():
        padded_logits = model(padded)
        short_logits = model(short)

    assert padded_logits.shape == (2, 32, 7)
    assert short_logits.shape == (1, 16, 7)
    torch.testing.assert_close(padded_logits[0, :16], short_logits[0])


def test_export_has_dynamic_contract_and_matches_torch(tmp_path: Path) -> None:
    model = _small_model()
    path = tmp_path / "model.onnx"
    _export_onnx(model, path)
    onnx.checker.check_model(onnx.load(path))
    session = ort.InferenceSession(path, providers=["CPUExecutionProvider"])
    assert session.get_inputs()[0].name == INPUT_NAME
    assert session.get_outputs()[0].name == OUTPUT_NAME

    inputs = np.asarray([[2, 3, 4]], dtype=np.int64)
    with torch.inference_mode():
        expected = model(torch.from_numpy(inputs)).numpy()
    actual = session.run([OUTPUT_NAME], {INPUT_NAME: inputs})[0]
    assert isinstance(actual, np.ndarray)
    np.testing.assert_allclose(actual, expected, rtol=1.0e-5, atol=2.0e-5)
