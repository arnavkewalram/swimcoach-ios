"""
Model-timebase windowing — torch-free so tests and CI can exercise it
without heavy dependencies.

The model consumes 90-frame windows at 30 fps (3 s). Clips are resampled to
that timebase and windowed with 50% overlap; squeezing a whole clip into one
window would time-compress it and distort frequency-sensitive labels.
"""

import numpy as np

MODEL_FPS = 30.0
WINDOW_LEN = 90
WINDOW_STRIDE = 45

# Below this many model-timebase frames (~1/3 s of real footage) a clip has
# no usable temporal signal — resampling it up to 90 frames would fabricate
# a frozen "motion" pattern for the kick-rate labels.
MIN_TIMEBASE_FRAMES = 10


def resample_frames(keypoints: np.ndarray, target_len: int) -> np.ndarray:
    """Linear-resample (T, 13, 3) along time to (target_len, 13, 3)."""
    T = keypoints.shape[0]
    if T == target_len:
        return keypoints.copy()
    src_idx = np.linspace(0, T - 1, target_len)
    idx_lo = np.floor(src_idx).astype(int)
    idx_hi = np.minimum(idx_lo + 1, T - 1)
    frac = (src_idx - idx_lo)[:, None, None]
    return keypoints[idx_lo] * (1 - frac) + keypoints[idx_hi] * frac


def prediction_windows(keypoints: np.ndarray, fps: float) -> list[np.ndarray]:
    """
    Split a clip into model-timebase windows.

    Returns [] when the clip carries too little real time to analyze
    (fewer than MIN_TIMEBASE_FRAMES after conversion to the model fps) —
    callers treat that exactly like the too-short-clip case.

    fps <= 0 (some containers report no frame rate) is assumed to be
    MODEL_FPS: analysis proceeds, but frequency-sensitive labels may be
    skewed if the true rate differs. Callers should surface fps in output
    so the assumption is visible.
    """
    if fps > 0 and abs(fps - MODEL_FPS) > 1e-6:
        t30 = max(1, int(round(len(keypoints) * MODEL_FPS / fps)))
        kp = resample_frames(keypoints, t30)
    else:
        kp = keypoints

    if len(kp) < MIN_TIMEBASE_FRAMES:
        return []

    if len(kp) <= WINDOW_LEN:
        return [kp]
    starts = list(range(0, len(kp) - WINDOW_LEN + 1, WINDOW_STRIDE))
    if starts[-1] != len(kp) - WINDOW_LEN:
        starts.append(len(kp) - WINDOW_LEN)
    return [kp[s:s + WINDOW_LEN] for s in starts]
