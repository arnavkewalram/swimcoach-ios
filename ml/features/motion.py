"""
Compute motion features: stroke cycles, wrist velocity, kick frequency.
"""

import numpy as np
from scipy.signal import find_peaks
from pose.keypoints import KEYPOINT_NAMES


def _kp_idx(name: str) -> int:
    return KEYPOINT_NAMES.index(name)


def compute_wrist_velocity(keypoints: np.ndarray, fps: float) -> dict[str, np.ndarray]:
    """
    Compute per-frame wrist speed (pixels/second, normalized coords).

    Args:
        keypoints: (n_frames, N_KEYPOINTS, 3)
        fps: video frames per second

    Returns:
        dict with 'left_wrist_speed' and 'right_wrist_speed', shape (n_frames,).
        Frame 0 velocity is set to 0.
    """
    lw = _kp_idx("left_wrist")
    rw = _kp_idx("right_wrist")

    lw_pos = keypoints[:, lw, :2]   # (n_frames, 2)
    rw_pos = keypoints[:, rw, :2]

    # Finite difference: speed = ||delta_pos|| * fps
    lw_speed = np.zeros(len(keypoints))
    rw_speed = np.zeros(len(keypoints))

    if len(keypoints) > 1:
        lw_speed[1:] = np.linalg.norm(np.diff(lw_pos, axis=0), axis=1) * fps
        rw_speed[1:] = np.linalg.norm(np.diff(rw_pos, axis=0), axis=1) * fps

    return {
        "left_wrist_speed": lw_speed,
        "right_wrist_speed": rw_speed,
    }


def compute_ankle_velocity(keypoints: np.ndarray, fps: float) -> dict[str, np.ndarray]:
    """
    Compute per-frame ankle speed (used for kick detection).
    """
    la = _kp_idx("left_ankle")
    ra = _kp_idx("right_ankle")

    la_pos = keypoints[:, la, :2]
    ra_pos = keypoints[:, ra, :2]

    la_speed = np.zeros(len(keypoints))
    ra_speed = np.zeros(len(keypoints))

    if len(keypoints) > 1:
        la_speed[1:] = np.linalg.norm(np.diff(la_pos, axis=0), axis=1) * fps
        ra_speed[1:] = np.linalg.norm(np.diff(ra_pos, axis=0), axis=1) * fps

    return {
        "left_ankle_speed": la_speed,
        "right_ankle_speed": ra_speed,
    }


def detect_stroke_cycles(
    keypoints: np.ndarray,
    fps: float,
    min_peak_distance_s: float = 0.4,
) -> dict[str, object]:
    """
    Detect stroke cycles from wrist vertical position oscillation.

    Uses the y-coordinate of each wrist: peaks in the y-signal correspond to
    the catch/pull phase transitions.

    Args:
        keypoints: (n_frames, N_KEYPOINTS, 3)
        fps: frames per second
        min_peak_distance_s: minimum seconds between stroke peaks

    Returns:
        dict with:
          - 'left_stroke_frames': list of frame indices (peaks)
          - 'right_stroke_frames': list of frame indices
          - 'left_stroke_rate_spm': strokes per minute (float)
          - 'right_stroke_rate_spm': strokes per minute (float)
          - 'stroke_count': total strokes (mean of left + right)
    """
    lw = _kp_idx("left_wrist")
    rw = _kp_idx("right_wrist")

    lw_y = keypoints[:, lw, 1]
    rw_y = keypoints[:, rw, 1]

    min_dist_frames = max(1, int(min_peak_distance_s * fps))

    left_peaks, _ = find_peaks(lw_y, distance=min_dist_frames)
    right_peaks, _ = find_peaks(rw_y, distance=min_dist_frames)

    duration_s = len(keypoints) / fps if fps > 0 else 1.0

    left_spm = (len(left_peaks) / duration_s) * 60.0 if duration_s > 0 else 0.0
    right_spm = (len(right_peaks) / duration_s) * 60.0 if duration_s > 0 else 0.0

    avg_count = (len(left_peaks) + len(right_peaks)) / 2.0

    return {
        "left_stroke_frames": left_peaks.tolist(),
        "right_stroke_frames": right_peaks.tolist(),
        "left_stroke_rate_spm": round(left_spm, 1),
        "right_stroke_rate_spm": round(right_spm, 1),
        "stroke_count": round(avg_count, 1),
    }


def detect_kick_frequency(
    keypoints: np.ndarray,
    fps: float,
    min_peak_distance_s: float = 0.2,
) -> dict[str, object]:
    """
    Detect kick frequency from ankle vertical oscillation.

    Returns:
        dict with:
          - 'kick_frames': list of frame indices where kicks occur
          - 'kick_rate_per_min': kicks per minute (float)
    """
    la = _kp_idx("left_ankle")
    ra = _kp_idx("right_ankle")

    la_y = keypoints[:, la, 1]
    ra_y = keypoints[:, ra, 1]

    min_dist_frames = max(1, int(min_peak_distance_s * fps))

    la_peaks, _ = find_peaks(la_y, distance=min_dist_frames)
    ra_peaks, _ = find_peaks(ra_y, distance=min_dist_frames)

    all_kicks = sorted(set(la_peaks.tolist() + ra_peaks.tolist()))
    duration_s = len(keypoints) / fps if fps > 0 else 1.0
    kick_rate = (len(all_kicks) / duration_s) * 60.0 if duration_s > 0 else 0.0

    return {
        "kick_frames": all_kicks,
        "kick_rate_per_min": round(kick_rate, 1),
    }


def compute_motion_features(
    keypoints: np.ndarray, fps: float
) -> dict[str, object]:
    """
    Compute all motion features and return as a single dict.
    """
    result = {}
    result.update(compute_wrist_velocity(keypoints, fps))
    result.update(compute_ankle_velocity(keypoints, fps))
    result.update(detect_stroke_cycles(keypoints, fps))
    result.update(detect_kick_frequency(keypoints, fps))
    return result
