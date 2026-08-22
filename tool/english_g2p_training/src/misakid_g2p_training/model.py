"""The medium en-US CTC model architecture exported for Fonix."""

from __future__ import annotations

import torch
from torch import Tensor, nn

from .constants import (
    CLASSIFIER_CHANNELS,
    CONVOLUTION_CHANNELS,
    CONVOLUTION_DILATIONS,
    DROPOUT,
    EMBEDDING_CHANNELS,
    GRU_HIDDEN_SIZE,
    GRU_LAYERS,
    SLOT_EMBEDDING_CHANNELS,
    SLOTS_PER_GRAPHEME,
)


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

    def forward(self, values: Tensor) -> Tensor:
        residual = self.convolution(values)
        residual = residual.transpose(1, 2)
        residual = self.normalization(residual)
        residual = torch.nn.functional.gelu(residual)
        residual = self.dropout(residual)
        residual = residual.transpose(1, 2)
        return values + residual


class EnglishG2pModel(nn.Module):
    """A bounded convolutional/BiGRU encoder with per-grapheme CTC slots.

    Inputs in a batch must have the same real grapheme length. The runtime uses
    batch size one, and the training pipeline groups words by length, so the
    bidirectional encoder never observes synthetic right padding.
    """

    def __init__(
        self,
        grapheme_vocabulary_size: int,
        phoneme_vocabulary_size: int,
        *,
        embedding_channels: int = EMBEDDING_CHANNELS,
        convolution_channels: int = CONVOLUTION_CHANNELS,
        convolution_dilations: tuple[int, ...] = CONVOLUTION_DILATIONS,
        gru_hidden_size: int = GRU_HIDDEN_SIZE,
        gru_layers: int = GRU_LAYERS,
        slot_embedding_channels: int = SLOT_EMBEDDING_CHANNELS,
        classifier_channels: int = CLASSIFIER_CHANNELS,
        dropout: float = DROPOUT,
        slots_per_grapheme: int = SLOTS_PER_GRAPHEME,
    ) -> None:
        super().__init__()
        self.slots_per_grapheme = slots_per_grapheme
        self.embedding = nn.Embedding(
            grapheme_vocabulary_size,
            embedding_channels,
            padding_idx=0,
        )
        self.input_projection = nn.Linear(
            embedding_channels,
            convolution_channels,
        )
        self.blocks = nn.ModuleList(
            _ResidualBlock(convolution_channels, dilation, dropout)
            for dilation in convolution_dilations
        )
        self.encoder = nn.GRU(
            input_size=convolution_channels,
            hidden_size=gru_hidden_size,
            num_layers=gru_layers,
            batch_first=True,
            bidirectional=True,
            dropout=dropout if gru_layers > 1 else 0.0,
        )
        self.slot_embedding = nn.Embedding(
            slots_per_grapheme,
            slot_embedding_channels,
        )
        self.classifier = nn.Sequential(
            nn.Linear(
                gru_hidden_size * 2 + slot_embedding_channels,
                classifier_channels,
            ),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(classifier_channels, phoneme_vocabulary_size),
        )

    def forward(self, grapheme_ids: Tensor) -> Tensor:
        if grapheme_ids.ndim != 2:
            raise ValueError("grapheme_ids must have shape [batch, graphemes].")
        encoded = self.input_projection(self.embedding(grapheme_ids))
        encoded = encoded.transpose(1, 2)
        for block in self.blocks:
            encoded = block(encoded)
        encoded = encoded.transpose(1, 2)
        encoded, _ = self.encoder(encoded)

        batch_size, grapheme_count, encoder_channels = encoded.shape
        slot_channels = self.slot_embedding.embedding_dim
        slots = self.slot_embedding.weight.view(
            1,
            1,
            self.slots_per_grapheme,
            slot_channels,
        )
        slots = slots.expand(batch_size, grapheme_count, -1, -1)
        encoded = encoded.unsqueeze(2).expand(-1, -1, self.slots_per_grapheme, -1)
        combined = torch.cat((encoded, slots), dim=-1)
        logits = self.classifier(combined)
        return logits.reshape(
            batch_size,
            grapheme_count * self.slots_per_grapheme,
            -1,
        )
