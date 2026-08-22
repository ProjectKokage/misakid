"""The fixed en-US CTC model architecture exported for Fonix."""

from __future__ import annotations

import torch
from torch import Tensor, nn

from .constants import CHANNELS, DILATIONS, DROPOUT, SLOTS_PER_GRAPHEME


class _ResidualBlock(nn.Module):
    def __init__(self, channels: int, dilation: int, dropout: float) -> None:
        super().__init__()
        self.convolution = nn.Conv1d(
            channels,
            channels,
            kernel_size=3,
            dilation=dilation,
            padding=dilation,
        )
        self.normalization = nn.LayerNorm(channels)
        self.dropout = nn.Dropout(dropout)

    def forward(self, values: Tensor, mask: Tensor) -> Tensor:
        residual = self.convolution(values)
        residual = residual.transpose(1, 2)
        residual = self.normalization(residual)
        residual = torch.nn.functional.gelu(residual)
        residual = self.dropout(residual)
        residual = residual.transpose(1, 2)
        return (values + residual) * mask


class EnglishG2pModel(nn.Module):
    """A bounded convolutional encoder with learned per-grapheme CTC slots."""

    def __init__(
        self,
        grapheme_vocabulary_size: int,
        phoneme_vocabulary_size: int,
        *,
        channels: int = CHANNELS,
        dilations: tuple[int, ...] = DILATIONS,
        dropout: float = DROPOUT,
        slots_per_grapheme: int = SLOTS_PER_GRAPHEME,
    ) -> None:
        super().__init__()
        self.slots_per_grapheme = slots_per_grapheme
        self.embedding = nn.Embedding(
            grapheme_vocabulary_size,
            channels,
            padding_idx=0,
        )
        self.blocks = nn.ModuleList(
            _ResidualBlock(channels, dilation, dropout) for dilation in dilations
        )
        self.slot_embedding = nn.Embedding(slots_per_grapheme, channels)
        self.classifier = nn.Sequential(
            nn.Linear(channels * 2, channels),
            nn.GELU(),
            nn.Linear(channels, phoneme_vocabulary_size),
        )

    def forward(self, grapheme_ids: Tensor) -> Tensor:
        if grapheme_ids.ndim != 2:
            raise ValueError("grapheme_ids must have shape [batch, graphemes].")
        mask = grapheme_ids.ne(0).unsqueeze(1).to(dtype=torch.float32)
        encoded = self.embedding(grapheme_ids).transpose(1, 2)
        encoded = encoded * mask
        for block in self.blocks:
            encoded = block(encoded, mask)
        encoded = encoded.transpose(1, 2)

        batch_size, grapheme_count, channels = encoded.shape
        slots = self.slot_embedding.weight.view(1, 1, self.slots_per_grapheme, channels)
        slots = slots.expand(batch_size, grapheme_count, -1, -1)
        encoded = encoded.unsqueeze(2).expand(-1, -1, self.slots_per_grapheme, -1)
        combined = torch.cat((encoded, slots), dim=-1)
        logits = self.classifier(combined)
        return logits.reshape(batch_size, grapheme_count * self.slots_per_grapheme, -1)
