"""
Synthetic training data generator for SwimTCN.

Generates labelled keypoint sequences programmatically by simulating
good and bad swimming technique with known biomechanical properties.

All joint positions follow the MediaPipe 33-landmark scheme, subsampled
to the 13 joints used by pose/extractor.py:
  0=nose, 1=left_shoulder, 2=right_shoulder, 3=left_elbow,
  4=right_elbow, 5=left_wrist, 6=right_wrist, 7=left_hip,
  8=right_hip, 9=left_knee, 10=right_knee, 11=left_ankle, 12=right_ankle

Coordinates are normalised [0,1] as in the real extractor.
"""

import numpy as np
from typing import Optional


# ---- Joint indices (match pose/extractor.py KEYPOINT_INDICES) ----
NOSE        = 0
L_SHOULDER  = 1; R_SHOULDER = 2
L_ELBOW     = 3; R_ELBOW    = 4
L_WRIST     = 5; R_WRIST    = 6
L_HIP       = 7; R_HIP      = 8
L_KNEE      = 9; R_KNEE     = 10
L_ANKLE     = 11; R_ANKLE   = 12
N_JOINTS    = 13


def _make_swimmer_base(
    t: np.ndarray,
    noise: float = 0.005,
    rng: Optional[np.random.Generator] = None,
) -> np.ndarray:
    """
    Build a (T, 13, 3) baseline swimming pose sequence.
    Swimmer faces left, horizontal (lying on side in pool).
    All coords normalised [0,1].
    """
    if rng is None:
        rng = np.random.default_rng()
    T = len(t)
    kp = np.zeros((T, N_JOINTS, 3), dtype=np.float32)

    # Stroke cycle ~ 1.5 Hz (90 strokes/min), kick ~ 2.2 Hz (~130/min) —
    # mid-range so the excessive-kick injection (5 Hz) is clearly distinct.
    stroke_freq = 1.5
    kick_freq   = 2.2

    # Base body horizontal positions (x = progress along pool, y = depth)
    body_x = 0.5 + 0.05 * np.sin(2 * np.pi * stroke_freq * t)  # slight forward motion
    body_y = 0.5  # mid-frame vertically

    # Body roll: shoulder rolls with each stroke
    roll = 0.05 * np.sin(2 * np.pi * stroke_freq * t)

    # --- Torso ---
    kp[:, NOSE,       0] = body_x + 0.18
    kp[:, NOSE,       1] = body_y - 0.04
    kp[:, L_SHOULDER, 0] = body_x + 0.10
    kp[:, L_SHOULDER, 1] = body_y - 0.04 + roll
    kp[:, R_SHOULDER, 0] = body_x + 0.10
    kp[:, R_SHOULDER, 1] = body_y + 0.04 - roll
    kp[:, L_HIP,      0] = body_x - 0.06
    kp[:, L_HIP,      1] = body_y - 0.03
    kp[:, R_HIP,      0] = body_x - 0.06
    kp[:, R_HIP,      1] = body_y + 0.03

    # --- Arms (freestyle alternating catch/pull) ---
    # Left arm: enters water, extends, pulls back
    l_phase = 2 * np.pi * stroke_freq * t
    r_phase = l_phase + np.pi  # opposite phase

    # Left elbow — good technique: genuinely bent catch (~110-130°).
    # The wrist drops well below the elbow line so that the overextension
    # injection (collinear, ~178°) is geometrically distinct from "good".
    kp[:, L_ELBOW, 0] = kp[:, L_SHOULDER, 0] + 0.07 + 0.02 * np.cos(l_phase)
    kp[:, L_ELBOW, 1] = kp[:, L_SHOULDER, 1] + 0.02 * np.sin(l_phase)
    kp[:, L_WRIST, 0] = kp[:, L_ELBOW, 0] + 0.04 + 0.02 * np.cos(l_phase)
    kp[:, L_WRIST, 1] = kp[:, L_ELBOW, 1] + 0.06 + 0.02 * np.sin(l_phase)

    # Right elbow
    kp[:, R_ELBOW, 0] = kp[:, R_SHOULDER, 0] + 0.07 + 0.02 * np.cos(r_phase)
    kp[:, R_ELBOW, 1] = kp[:, R_SHOULDER, 1] + 0.02 * np.sin(r_phase)
    kp[:, R_WRIST, 0] = kp[:, R_ELBOW, 0] + 0.04 + 0.02 * np.cos(r_phase)
    kp[:, R_WRIST, 1] = kp[:, R_ELBOW, 1] + 0.06 + 0.02 * np.sin(r_phase)

    # --- Legs (flutter kick) ---
    kick_phase = 2 * np.pi * kick_freq * t
    kp[:, L_KNEE,   0] = kp[:, L_HIP, 0] - 0.08
    kp[:, L_KNEE,   1] = kp[:, L_HIP, 1] + 0.01 * np.sin(kick_phase)
    kp[:, R_KNEE,   0] = kp[:, R_HIP, 0] - 0.08
    kp[:, R_KNEE,   1] = kp[:, R_HIP, 1] - 0.01 * np.sin(kick_phase)
    kp[:, L_ANKLE,  0] = kp[:, L_KNEE, 0] - 0.08
    kp[:, L_ANKLE,  1] = kp[:, L_KNEE, 1] + 0.02 * np.sin(kick_phase + 0.3)
    kp[:, R_ANKLE,  0] = kp[:, R_KNEE, 0] - 0.08
    kp[:, R_ANKLE,  1] = kp[:, R_KNEE, 1] - 0.02 * np.sin(kick_phase + 0.3)

    # Confidence starts at 1; realistic per-joint confidence is applied later
    # by _apply_confidence_model (after issue injection).
    kp[:, :, 2] = 1.0

    # Add positional noise
    kp[:, :, :2] += rng.standard_normal((T, N_JOINTS, 2)).astype(np.float32) * noise

    return kp


def _apply_view_jitter(kp: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """
    Randomise camera viewpoint: swim direction (p=0.5 horizontal mirror),
    global scale, and frame position. Real footage varies in all three;
    the base sequence is always a left-facing swimmer centred at (0.5, 0.5).

    Mirroring flips only the x coordinate — joint identities (the swimmer's
    own left/right) are unchanged, so labels stay valid.
    """
    kp = kp.copy()
    if rng.random() < 0.5:
        kp[:, :, 0] = 1.0 - kp[:, :, 0]
    scale = rng.uniform(0.8, 1.2)
    shift = rng.uniform(-0.08, 0.08, size=2).astype(np.float32)
    kp[:, :, :2] = np.clip((kp[:, :, :2] - 0.5) * scale + 0.5 + shift, 0.0, 1.0)
    return kp


def _apply_confidence_model(kp: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """
    Replace the constant confidence channel with realistic values.

    - Per-joint, per-frame confidence varies (~0.7–1.0).
    - Distal joints (wrists/ankles) get occlusion episodes — they submerge
      during the stroke/kick cycle and detectors lose them.
    - Coordinate noise grows as confidence drops (uncertain detections jitter).
    - Joints with confidence <= 0.1 are zeroed exactly as the iOS
      FeatureExtractor does, so that input pattern exists in training.
    """
    kp = kp.copy()
    T = kp.shape[0]
    conf = np.clip(
        0.88 + 0.08 * rng.standard_normal((T, N_JOINTS)), 0.3, 1.0
    ).astype(np.float32)

    # Occlusion episodes on distal joints (cap total ~20% of frames per joint
    # so the label-carrying signal survives)
    max_occluded = T // 5
    for j in (L_WRIST, R_WRIST, L_ANKLE, R_ANKLE):
        if rng.random() < 0.4:
            occluded = 0
            for _ in range(rng.integers(1, 4)):
                start = int(rng.integers(0, T))
                length = int(rng.integers(3, 10))
                length = min(length, max_occluded - occluded)
                if length <= 0:
                    break
                conf[start:start + length, j] = rng.uniform(0.0, 0.25)
                occluded += length

    kp[:, :, :2] += (
        rng.standard_normal((T, N_JOINTS, 2)).astype(np.float32)
        * (0.015 * (1.0 - conf))[..., None]
    )
    kp[:, :, 2] = conf

    # Zero-mask low-confidence joints (mirrors FeatureExtractor.swift)
    kp[conf <= 0.1] = 0.0
    return kp


_LEFT_JOINTS  = (L_SHOULDER, L_ELBOW, L_WRIST, L_HIP, L_KNEE, L_ANKLE)
_RIGHT_JOINTS = (R_SHOULDER, R_ELBOW, R_WRIST, R_HIP, R_KNEE, R_ANKLE)


def _apply_side_occlusion(kp: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """
    Side-consistent far-side degradation. In real side-on footage one side of
    the body faces away from the camera; pose detectors report those joints
    with lower confidence, extra noise, and sometimes fabricated positions
    near the visible side's joints. Synthetic data without this teaches the
    model spurious left/right asymmetries that fire on every real clip.

    Must run AFTER _apply_confidence_model (it scales the realistic
    confidence channel rather than the placeholder 1.0s).
    """
    kp = kp.copy()
    T = kp.shape[0]
    left_far = rng.random() < 0.5
    far  = _LEFT_JOINTS if left_far else _RIGHT_JOINTS
    near = _RIGHT_JOINTS if left_far else _LEFT_JOINTS

    far_idx = list(far)
    kp[:, far_idx, 2] *= rng.uniform(0.55, 0.85)
    kp[:, far_idx, :2] += rng.standard_normal((T, len(far_idx), 2)).astype(np.float32) * 0.008

    # Fabricated-position episodes: the far joint's estimate collapses toward
    # its visible counterpart for a stretch of frames.
    for fj, nj in zip(far, near):
        if rng.random() < 0.35:
            start = int(rng.integers(0, T))
            end = min(T, start + int(rng.integers(5, max(6, T // 4))))
            alpha = rng.uniform(0.5, 0.9)
            live = kp[start:end, fj, 2] > 0  # leave zero-masked frames zeroed
            kp[start:end, fj, :2][live] = (
                alpha * kp[start:end, nj, :2][live]
                + (1 - alpha) * kp[start:end, fj, :2][live]
            )
    return kp


def _apply_frame_dropout(kp: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """
    Zero out short bursts of whole frames, as the real extractor produces
    when pose detection fails entirely (splashes, turns, submersion).
    """
    kp = kp.copy()
    if rng.random() < 0.35:
        T = kp.shape[0]
        for _ in range(rng.integers(1, 3)):
            start = int(rng.integers(0, T))
            length = int(rng.integers(2, 9))
            kp[start:start + length] = 0.0
    return kp


def _inject_elbow_overextension(kp: np.ndarray, side: str) -> np.ndarray:
    """Push wrist away from shoulder to straighten elbow angle."""
    kp = kp.copy()
    e_idx = L_ELBOW if side == "left" else R_ELBOW
    w_idx = L_WRIST if side == "left" else R_WRIST
    s_idx = L_SHOULDER if side == "left" else R_SHOULDER
    # Push wrist further out — collinear with shoulder-elbow → ~175°
    direction = kp[:, e_idx, :2] - kp[:, s_idx, :2]
    kp[:, w_idx, :2] = kp[:, e_idx, :2] + direction * 1.2
    return kp


def _inject_elbow_collapse(
    kp: np.ndarray, side: str, rng: Optional[np.random.Generator] = None
) -> np.ndarray:
    """Bend elbow sharply so angle < 70°."""
    if rng is None:
        rng = np.random.default_rng()
    kp = kp.copy()
    e_idx = L_ELBOW if side == "left" else R_ELBOW
    w_idx = L_WRIST if side == "left" else R_WRIST
    s_idx = L_SHOULDER if side == "left" else R_SHOULDER
    # Pull wrist back toward shoulder
    midpoint = (kp[:, s_idx, :2] + kp[:, e_idx, :2]) / 2
    kp[:, w_idx, :2] = midpoint + rng.standard_normal(midpoint.shape).astype(np.float32) * 0.005
    return kp


def _inject_knee_overbend(kp: np.ndarray, side: str) -> np.ndarray:
    """Exaggerate knee bend to < 120° (shin folded back toward the hip)."""
    kp = kp.copy()
    k_idx = L_KNEE if side == "left" else R_KNEE
    a_idx = L_ANKLE if side == "left" else R_ANKLE
    h_idx = L_HIP if side == "left" else R_HIP
    # Fold the shin: ankle x moves back toward the hip, ankle drops below the
    # knee, and the knee itself drops slightly (thigh angle changes when the
    # shin folds). The knee component is essential — knees are never
    # occlusion-masked and kick injections preserve their mean, so the
    # overbend signal survives occlusion and co-occurring kick labels.
    kp[:, a_idx, 0] = (kp[:, k_idx, 0] + kp[:, h_idx, 0]) / 2
    kp[:, a_idx, 1] = kp[:, k_idx, 1] + 0.06
    kp[:, k_idx, 0] += 0.02
    kp[:, k_idx, 1] += 0.035
    return kp


def _inject_body_sag(kp: np.ndarray) -> np.ndarray:
    """Drop hips and legs so body_alignment angle < 145°."""
    kp = kp.copy()
    # Drop hips, knees, ankles downward
    for idx in [L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE]:
        kp[:, idx, 1] += 0.08
    return kp


def _inject_stroke_asymmetry(kp: np.ndarray) -> np.ndarray:
    """Make left and right arm motions significantly different."""
    kp = kp.copy()
    T = kp.shape[0]
    # Make right wrist stay high, left arm normal → elbow angles diverge
    kp[:, R_WRIST, 1] -= 0.06
    kp[:, R_ELBOW, 1] -= 0.03
    return kp


def _inject_low_kick_rate(kp: np.ndarray) -> np.ndarray:
    """Still legs: freeze knees AND ankles at their temporal mean positions.

    Freezing the knees matters — they are never occlusion-masked, so they
    carry the kick-rate signal even when the ankles are underwater.  Uses
    each joint's own mean so prior injections (knee overbend, body sag)
    are preserved rather than overwritten.
    """
    kp = kp.copy()
    for idx in (L_KNEE, R_KNEE, L_ANKLE, R_ANKLE):
        kp[:, idx, :2] = kp[:, idx, :2].mean(axis=0, keepdims=True)
    return kp


def _inject_excessive_kick_rate(kp: np.ndarray, fps: float) -> np.ndarray:
    """Very fast kick (300 kicks/min = 5 Hz) driving the whole leg.

    Knees oscillate along with ankles — redundant signal on joints that
    never get occlusion-masked.  Oscillates around each joint's own
    temporal mean so prior injections are preserved.
    """
    kp = kp.copy()
    T = kp.shape[0]
    t = np.arange(T) / fps
    kick_phase = 2 * np.pi * 5.0 * t
    osc = np.sin(kick_phase).astype(np.float32)
    kp[:, L_KNEE,  1] = kp[:, L_KNEE,  1].mean() + 0.025 * osc
    kp[:, R_KNEE,  1] = kp[:, R_KNEE,  1].mean() - 0.025 * osc
    kp[:, L_ANKLE, 1] = kp[:, L_ANKLE, 1].mean() + 0.05 * np.sin(kick_phase + 0.3).astype(np.float32)
    kp[:, R_ANKLE, 1] = kp[:, R_ANKLE, 1].mean() - 0.05 * np.sin(kick_phase + 0.3).astype(np.float32)
    return kp


# Label indices
LABEL_IDX = {name: i for i, name in enumerate([
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
])}
N_LABELS = len(LABEL_IDX)


def generate_sample(
    seq_len: int = 90,
    fps: float = 30.0,
    noise: float = 0.005,
    rng: Optional[np.random.Generator] = None,
) -> tuple[np.ndarray, np.ndarray]:
    """
    Generate one (keypoints, label) training sample.

    Label sampling respects physical exclusivity:
      - per arm: one of good (p=0.4) / overextension (p=0.3) / collapse (p=0.3)
      - knee overbend, body_sag, stroke_asymmetry: independent, p=0.5 each
      - kick rate: one of neither (p=0.5) / low (p=0.25) / excessive (p=0.25)
    Train-time pos_weight compensates for labels with sub-50% positive rates.

    After issue injection the sample is passed through realism augmentations
    matching what the real extractors produce: viewpoint jitter (mirror /
    scale / shift), a varying confidence channel with occlusion episodes and
    low-confidence zero-masking, and whole-frame detection dropout.

    Returns:
        kp:    (N_JOINTS, 3, seq_len) float32 — ready for TCN input
        label: (N_LABELS,) float32 binary vector
    """
    if rng is None:
        rng = np.random.default_rng()

    t = np.arange(seq_len) / fps
    kp = _make_swimmer_base(t, noise=noise, rng=rng)
    label = np.zeros(N_LABELS, dtype=np.float32)

    chosen = []

    # Per-arm elbow state — overextension and collapse are contradictory on
    # the same arm (a static injection can't show both), so draw one of
    # {good, overextension, collapse} per side.  Independent draws would
    # contaminate ~25% of overextension positives with collapse geometry.
    for side in ("left", "right"):
        r = rng.random()
        if r < 0.3:
            chosen.append(f"{side}_elbow_overextension")
        elif r < 0.6:
            chosen.append(f"{side}_elbow_collapse")

    # Independent issues — each fires with p=0.5
    for issue in (
        "left_knee_overbend",
        "right_knee_overbend",
        "body_sag",
        "stroke_asymmetry",
    ):
        if rng.random() < 0.5:
            chosen.append(issue)

    # Mutually exclusive kick-rate pair — one three-way draw:
    # neither (p=0.5), low (p=0.25), excessive (p=0.25).
    r = rng.random()
    if r < 0.25:
        chosen.append("low_kick_rate")
    elif r < 0.5:
        chosen.append("excessive_kick_rate")

    for issue in chosen:
        label[LABEL_IDX[issue]] = 1.0
        if issue == "left_elbow_overextension":
            kp = _inject_elbow_overextension(kp, "left")
        elif issue == "right_elbow_overextension":
            kp = _inject_elbow_overextension(kp, "right")
        elif issue == "left_elbow_collapse":
            kp = _inject_elbow_collapse(kp, "left", rng=rng)
        elif issue == "right_elbow_collapse":
            kp = _inject_elbow_collapse(kp, "right", rng=rng)
        elif issue == "left_knee_overbend":
            kp = _inject_knee_overbend(kp, "left")
        elif issue == "right_knee_overbend":
            kp = _inject_knee_overbend(kp, "right")
        elif issue == "body_sag":
            kp = _inject_body_sag(kp)
        elif issue == "stroke_asymmetry":
            kp = _inject_stroke_asymmetry(kp)
        elif issue == "low_kick_rate":
            kp = _inject_low_kick_rate(kp)
        elif issue == "excessive_kick_rate":
            kp = _inject_excessive_kick_rate(kp, fps)

    # Realism augmentations — order matters: viewpoint first (mirroring a
    # zeroed joint would move it to x=1), then confidence, then side
    # occlusion (scales the realistic conf channel), then dropout.
    kp = _apply_view_jitter(kp, rng)
    kp = _apply_confidence_model(kp, rng)
    kp = _apply_side_occlusion(kp, rng)
    kp = _apply_frame_dropout(kp, rng)

    # Reshape to (39, seq_len) for TCN
    kp_tcn = kp.transpose(1, 2, 0).reshape(N_JOINTS * 3, seq_len)  # (39, T)
    return kp_tcn.astype(np.float32), label


def generate_dataset(
    n_samples: int = 8000,
    seq_len: int = 90,
    fps: float = 30.0,
    seed: int = 42,
) -> tuple[np.ndarray, np.ndarray]:
    """
    Generate a full training/validation dataset.

    Returns:
        X: (N, 39, seq_len)
        y: (N, N_LABELS)
    """
    rng = np.random.default_rng(seed)
    X = np.zeros((n_samples, 39, seq_len), dtype=np.float32)
    y = np.zeros((n_samples, N_LABELS), dtype=np.float32)
    for i in range(n_samples):
        x_i, y_i = generate_sample(seq_len=seq_len, fps=fps, rng=rng)
        X[i] = x_i
        y[i] = y_i
    return X, y
