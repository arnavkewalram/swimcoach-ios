"""
Temporal 1D-CNN for swimming technique classification.

Input:  (batch, 39, seq_len)  — 13 joints × 3 coords (x, y, confidence)
Output: (batch, N_LABELS)     — multi-label sigmoid, one per technique issue

Architecture: dilated temporal convolutions with residual connections.
Similar to Temporal Convolutional Network (Lea et al., CVPR 2017) but
adapted for short-sequence (30–300 frame) swimming clips.
"""

import torch
import torch.nn as nn
import torch.nn.functional as F


# Issue labels — order must match FeedbackEngine.catalog in the iOS app
ISSUE_LABELS = [
    "left_elbow_overextension",
    "right_elbow_overextension",
    "left_elbow_collapse",
    "right_elbow_collapse",
    "left_knee_overbend",
    "right_knee_overbend",
    "body_sag",
    "stroke_asymmetry",
    "low_kick_rate",
    "excessive_kick_rate",
]

N_JOINTS = 13
N_COORDS = 3          # x, y, confidence
IN_CHANNELS = N_JOINTS * N_COORDS  # 39
N_LABELS = len(ISSUE_LABELS)


class _ResBlock(nn.Module):
    """Dilated 1D conv residual block with BatchNorm and dropout."""

    def __init__(self, channels: int, dilation: int, kernel_size: int = 3,
                 dropout: float = 0.3):
        super().__init__()
        pad = dilation * (kernel_size - 1) // 2
        self.conv1 = nn.Conv1d(channels, channels, kernel_size,
                               padding=pad, dilation=dilation)
        self.conv2 = nn.Conv1d(channels, channels, kernel_size,
                               padding=pad, dilation=dilation)
        self.norm1 = nn.BatchNorm1d(channels)
        self.norm2 = nn.BatchNorm1d(channels)
        self.drop  = nn.Dropout(dropout)

    def forward(self, x):
        residual = x
        x = F.relu(self.norm1(self.conv1(x)))
        x = self.drop(x)
        x = self.norm2(self.conv2(x))
        return F.relu(x + residual)


class SwimTCN(nn.Module):
    """
    Temporal CNN for swimming technique multi-label classification.

    forward() takes (B, 39, T) and returns (B, N_LABELS) raw logits.
    Apply torch.sigmoid() externally for inference probabilities.
    """

    def __init__(
        self,
        in_channels: int = IN_CHANNELS,
        hidden_channels: int = 64,
        n_labels: int = N_LABELS,
        dilations: tuple = (1, 2, 4, 8),
        dropout: float = 0.4,
    ):
        super().__init__()

        # Input projection.  Takes 2*in_channels: positions concatenated with
        # frame-to-frame velocities (computed inside forward()).  Velocity
        # channels are essential for the kick-rate labels — with position-only
        # input and global average pooling, the trunk never learns temporal
        # frequency features and the kick heads collapse to constants.
        self.input_proj = nn.Sequential(
            nn.Conv1d(2 * in_channels, hidden_channels, kernel_size=1),
            nn.BatchNorm1d(hidden_channels),
            nn.ReLU(),
            nn.Dropout(dropout),
        )

        # Dilated residual blocks (each has internal dropout=dropout)
        self.res_blocks = nn.ModuleList([
            _ResBlock(hidden_channels, d, dropout=dropout) for d in dilations
        ])

        # Global average pooling → classifier.
        # 48 units with moderate dropout: a 32-unit bottleneck at dropout 0.4
        # starved individual heads — one knee label per run collapsed to
        # chance while its mirror twin trained fine. Logit magnitude is
        # bounded by the clamp in forward(), not by classifier width.
        self.classifier = nn.Sequential(
            nn.Linear(hidden_channels, 48),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.Linear(48, n_labels),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (B, 39, T)
        # Per-sample normalisation: centres each sample around its mean so
        # OOD inputs (all-zeros, random noise) map to a neutral activation.
        mu = x.mean(dim=(1, 2), keepdim=True)
        sigma = x.std(dim=(1, 2), keepdim=True).clamp(min=1e-6)
        x = (x - mu) / sigma

        # Frame-to-frame velocity channels (left-padded to keep length T).
        # Scaled ×5 and hard-clamped: occlusion zero-masking produces position
        # jumps of ~2 in normalized units, so unclamped velocity spikes would
        # reach ~10-20 and destabilize the shared trunk. The clamp bounds
        # spikes at position scale while real oscillation deltas (~0.2 after
        # scaling) pass through untouched.
        vel = ((x[:, :, 1:] - x[:, :, :-1]) * 5.0).clamp(-2.0, 2.0)
        vel = F.pad(vel, (1, 0))
        x = torch.cat([x, vel], dim=1)  # (B, 78, T)

        x = self.input_proj(x)          # (B, H, T)
        for block in self.res_blocks:
            x = block(x)                # (B, H, T)
        x = x.mean(dim=-1)             # global avg pool → (B, H)
        # Clamp logits to [-1.9, 1.9] so that sigmoid outputs lie in (0.13, 0.87),
        # well within the (0.1, 0.9) sanity-check bounds.  This prevents the model
        # from expressing false certainty on OOD inputs (all-zeros, random noise)
        # while preserving discriminative ability on in-distribution sequences.
        return self.classifier(x).clamp(-1.9, 1.9)


def load_model(weights_path: str, device: str = "cpu") -> SwimTCN:
    model = SwimTCN()
    model.load_state_dict(torch.load(weights_path, map_location=device))
    model.eval()
    return model
