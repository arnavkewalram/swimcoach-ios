"""
ML-based technique issue detector — the pipeline's only detection path.

Uses a trained SwimTCN model to detect technique issues from raw keypoint sequences.

Usage:
    from ml.detector_ml import detect_issues_ml
    issues = detect_issues_ml(keypoints, motion)
"""

import os
import numpy as np
import torch
from pathlib import Path

from .model import SwimTCN, ISSUE_LABELS, IN_CHANNELS
from analysis.issues import TechniqueIssue

# Default confidence threshold for flagging an issue
DEFAULT_THRESHOLD = 0.45

# Windowing lives in ml/windowing.py (torch-free, CI-testable).
from .windowing import (  # noqa: E402  (re-exported for compatibility)
    MODEL_FPS, WINDOW_LEN, WINDOW_STRIDE,
    prediction_windows as _prediction_windows,
    resample_frames as _resample_frames,
)

# Weights path. Missing weights raise by default; auto-training is opt-in
# via SWIM_TCN_AUTOTRAIN=1 (a server must never train inside a request).
_WEIGHTS_PATH = Path(__file__).parent / "swim_tcn.pt"

# Severity mapping by label.
# MUST match `catalog` in iOS/SwimCoach/Core/FeedbackEngine.swift — both feed
# the same score formula (minor 5 / moderate 15 / major 25), so any drift makes
# the CLI and the app grade the same clip differently.
# Guarded by tests/test_severity_parity.py.
_SEVERITY = {
    "left_elbow_overextension":  "moderate",
    "right_elbow_overextension": "moderate",
    "left_elbow_collapse":       "moderate",
    "right_elbow_collapse":      "moderate",
    "left_knee_overbend":        "minor",
    "right_knee_overbend":       "minor",
    "body_sag":                  "major",
    "stroke_asymmetry":          "moderate",
    "low_kick_rate":             "minor",
    "excessive_kick_rate":       "minor",
}

_DESCRIPTIONS = {
    "left_elbow_overextension":  "Left arm entering water with too straight an elbow. Enter with a slight bend to protect the shoulder and improve catch efficiency.",
    "right_elbow_overextension": "Right arm entering water with too straight an elbow. Enter with a slight bend to protect the shoulder and improve catch efficiency.",
    "left_elbow_collapse":       "Left elbow collapsing excessively during the pull phase. Maintain a high elbow position through the catch.",
    "right_elbow_collapse":      "Right elbow collapsing excessively during the pull phase. Maintain a high elbow position through the catch.",
    "left_knee_overbend":        "Left knee bending too much during flutter kick. Effective kick uses mostly hip rotation with minimal knee bend.",
    "right_knee_overbend":       "Right knee bending too much during flutter kick. Effective kick uses mostly hip rotation with minimal knee bend.",
    "body_sag":                  "Hips and legs dropping, creating drag. Engage core, press chest slightly down, and kick from the hips to stay horizontal.",
    "stroke_asymmetry":          "Significant left-right stroke imbalance detected. Uneven strokes reduce efficiency and cause lateral drift.",
    "low_kick_rate":             "Kick rate very low. Even a minimal 2-beat kick helps with balance and body rotation timing.",
    "excessive_kick_rate":       "Kick rate very high. Excessive kicking wastes energy — aim for a 2-beat or 6-beat pattern unless sprinting.",
}


_model_cache: dict[str, SwimTCN] = {}


def _get_model(weights_path: str = None, device: str = "cpu") -> SwimTCN:
    """Load and cache model, auto-training if weights don't exist."""
    path = weights_path or str(_WEIGHTS_PATH)
    if path not in _model_cache:
        if not os.path.exists(path):
            if os.environ.get("SWIM_TCN_AUTOTRAIN") == "1":
                print(f"[SwimTCN] No weights at {path} — training now...")
                from .train import train
                train(weights_path=path)
            else:
                raise FileNotFoundError(
                    f"SwimTCN weights not found at {path}. Train with "
                    "'python -m ml.train' or set SWIM_TCN_AUTOTRAIN=1."
                )
        model = SwimTCN()
        model.load_state_dict(torch.load(path, map_location=device))
        model.eval()
        _model_cache[path] = model
    return _model_cache[path]


def _keypoints_to_tcn_input(
    keypoints: np.ndarray,
    target_len: int = WINDOW_LEN,
) -> torch.Tensor:
    """
    Convert a keypoints window to a TCN input tensor.

    Args:
        keypoints: (T, 13, 3) — raw extractor output
        target_len: sequence length expected by model

    Returns:
        (1, 39, target_len) tensor
    """
    kp = _resample_frames(keypoints, target_len)
    # Reshape (target_len, 13, 3) → (39, target_len) for TCN
    x = kp.transpose(1, 2, 0).reshape(IN_CHANNELS, target_len)
    return torch.tensor(x[None], dtype=torch.float32)  # (1, 39, T)


def detect_issues_ml(
    keypoints: np.ndarray,
    motion: dict,
    angles: dict = None,
    threshold: float = DEFAULT_THRESHOLD,
    weights_path: str = None,
    fps: float = MODEL_FPS,
) -> list[TechniqueIssue]:
    """
    ML-based technique issue detection.

    Args:
        keypoints: (T, 13, 3) array from pose.extractor
        motion:    dict from features.motion (used for kick rate context)
        angles:    dict from features.angles (optional, used for observed values)
        threshold: confidence threshold for flagging (0–1)
        weights_path: path to model weights (auto-trains if missing)
        fps:       source frame rate of `keypoints` — needed to window the
                   clip in the model's 30 fps / 3 s timebase

    Returns:
        List of TechniqueIssue objects
    """
    if len(keypoints) < 10:
        return []

    model = _get_model(weights_path)

    # Predict per 3-second window and average — frequency-sensitive labels
    # are meaningless if the whole clip is squeezed into one window.
    window_probs = []
    with torch.no_grad():
        for w in _prediction_windows(keypoints, fps):
            x = _keypoints_to_tcn_input(w)
            # forward() returns raw logits (see SwimTCN docstring) — sigmoid
            # matches the CoreML export (SwimTCNWithSigmoid) used on iOS.
            window_probs.append(torch.sigmoid(model(x))[0].numpy())
    if not window_probs:
        # Clip carries too little real time in the model timebase (e.g. a
        # dozen frames tagged 240fps) — nothing analyzable.
        return []
    probs = np.mean(window_probs, axis=0)  # (N_LABELS,)

    issues = []
    for i, label in enumerate(ISSUE_LABELS):
        confidence = float(probs[i])
        if confidence < threshold:
            continue

        # Compute observed value from angles if available
        observed_value = round(confidence * 100, 1)  # confidence as "score"
        if angles is not None:
            if "elbow" in label:
                side = "left" if label.startswith("left") else "right"
                arr = angles.get(f"{side}_elbow", np.array([]))
                if len(arr) > 0:
                    observed_value = round(float(np.mean(arr)), 1)
            elif "knee" in label:
                side = "left" if label.startswith("left") else "right"
                arr = angles.get(f"{side}_knee", np.array([]))
                if len(arr) > 0:
                    observed_value = round(float(np.mean(arr)), 1)
            elif label == "body_sag":
                arr = angles.get("body_alignment", np.array([]))
                if len(arr) > 0:
                    observed_value = round(float(np.mean(arr)), 1)
            elif label == "stroke_asymmetry":
                le = angles.get("left_elbow", np.array([]))
                re = angles.get("right_elbow", np.array([]))
                if len(le) > 0 and len(re) > 0:
                    observed_value = round(float(np.mean(np.abs(le - re))), 1)
        if "kick_rate" in label:
            observed_value = round(float(motion.get("kick_rate_per_min", 0)), 1)

        # Severity: scale by confidence
        base_sev = _SEVERITY[label]
        if confidence > 0.8:
            severity = "major" if base_sev in ("moderate", "major") else "moderate"
        else:
            severity = base_sev

        issues.append(TechniqueIssue(
            name=label,
            severity=severity,
            affected_frames=list(range(len(keypoints))),
            metric_name=label,
            observed_value=observed_value,
            threshold=threshold,
            description=_DESCRIPTIONS[label],
        ))

    return issues
