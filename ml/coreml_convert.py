"""Convert trained SwimTCN PyTorch model to CoreML .mlpackage for iOS."""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

import torch
import torch.nn as nn
import coremltools as ct
from ml.model import SwimTCN

# Paths are relative to this script so the repo can live anywhere.
_HERE = os.path.dirname(os.path.abspath(__file__))
WEIGHTS = os.path.join(_HERE, "ml", "swim_tcn.pt")
OUT = os.path.normpath(os.path.join(
    _HERE, "..", "iOS", "SwimCoach", "Resources", "swim_tcn.mlpackage"
))


class SwimTCNWithSigmoid(nn.Module):
    """Wraps SwimTCN to apply sigmoid on the raw logits for CoreML export.

    The base model returns raw logits (for BCEWithLogitsLoss during training).
    CoreML consumers expect probabilities in [0, 1], so we apply sigmoid here.
    """

    def __init__(self, base: SwimTCN):
        super().__init__()
        self.base = base

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return torch.sigmoid(self.base(x))


model = SwimTCN()
model.load_state_dict(torch.load(WEIGHTS, map_location="cpu", weights_only=True))
model.eval()

export_model = SwimTCNWithSigmoid(model)
export_model.eval()

# Trace with fixed (1, 39, 90) input — 13 joints × 3 coords, 90 resampled frames
# Use randn (not zeros) so BatchNorm running stats are exercised meaningfully.
example_input = torch.randn(1, 39, 90)
traced = torch.jit.trace(export_model, example_input)

# Delete old mlpackage if it exists
import shutil
if os.path.exists(OUT):
    shutil.rmtree(OUT)
    print(f"Deleted old: {OUT}")

mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="pose_sequence", shape=(1, 39, 90))],
    outputs=[ct.TensorType(name="issue_probabilities")],
    minimum_deployment_target=ct.target.iOS17,
    convert_to="mlprogram",
    # FP32 keeps CoreML output bit-comparable to the PyTorch reference;
    # the model is tiny, so FP16 savings are irrelevant.
    compute_precision=ct.precision.FLOAT32,
)
mlmodel.save(OUT)
print(f"Saved: {OUT}")
