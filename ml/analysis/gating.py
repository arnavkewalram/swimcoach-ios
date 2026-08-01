"""
Input-quality gating — port of the iOS PoseAnalyzer acceptance filters.

The CLI previously analyzed anything MediaPipe emitted, producing confident
coaching reports for archival race footage, marching soldiers, and even an
ffmpeg color-bar test pattern (scored 100/100). The iOS app rejects such
input via per-frame shoulder-confidence and horizontal-body checks; this
module applies the same rules so both platforms agree on what is analyzable.
"""

import numpy as np

# Joint indices (match pose/extractor.py KEYPOINT_INDICES order)
L_SHOULDER, R_SHOULDER = 1, 2
L_HIP, R_HIP = 7, 8

# Acceptance thresholds — keep in sync with iOS/SwimCoach/Core/PoseAnalyzer.swift
MIN_SWIMMER_FRAMES = 10      # AnalyzingView guard
SHOULDER_MIN_VIS = 0.3       # shoulder confidence filter
TORSO_MIN_VIS = 0.2          # shoulder vis needed for the torso-angle check
HIP_MIN_VIS = 0.15           # hip vis needed for the torso-angle check
HORIZONTAL_MAX_DEG = 55.0    # accepted: angle < 55 or > 125 (either direction)
LOW_DETECTION_RATE = 0.20    # below this, results carry a quality warning

# CLI-only additions. The iOS app gets a distance gate for free — Vision
# simply fails on small/far people — but MediaPipe happily estimates tiny
# distant swimmers (1900s archival race footage measured 0.084) and
# hallucinates impossible geometry on crowd shots (median torso 1.06 on
# far-field race video). Calibrated against the validation clip set:
# legitimate 3–6 m footage measures 0.095–0.19.
MIN_MEDIAN_TORSO = 0.09      # normalized shoulder→hip distance
MAX_MEDIAN_TORSO = 0.60      # larger is geometrically implausible


def _torso_angle_deg(frame: np.ndarray) -> float | None:
    """Torso angle from horizontal (0 = flat swimmer, 90 = standing person).

    Returns None when shoulder/hip landmarks are below the confidence
    thresholds — the caller treats that as "orientation unknown", which is
    accepted (practice footage where hips sit below the waterline).
    """
    ls, rs, lh, rh = frame[L_SHOULDER], frame[R_SHOULDER], frame[L_HIP], frame[R_HIP]
    if ls[2] < TORSO_MIN_VIS or rs[2] < TORSO_MIN_VIS:
        return None
    if lh[2] < HIP_MIN_VIS or rh[2] < HIP_MIN_VIS:
        return None
    mid_s = (ls[:2] + rs[:2]) / 2.0
    mid_h = (lh[:2] + rh[:2]) / 2.0
    d = mid_h - mid_s
    return float(abs(np.degrees(np.arctan2(d[1], d[0]))))


def validate_footage(keypoints: np.ndarray) -> tuple[bool, str, dict]:
    """
    Decide whether extracted keypoints look like an analyzable swimmer.

    Args:
        keypoints: (T, 13, 3) from pose.extractor — zero rows mean no pose.

    Returns:
        (ok, reason, stats). `reason` is empty when ok; `stats` always has
        total_frames / detected_frames / swimmer_frames / detection_rate.
    """
    total = len(keypoints)
    detected = ~(keypoints == 0).all(axis=(1, 2))
    n_detected = int(detected.sum())

    swimmer_frames = 0
    torso_lengths = []
    for frame in keypoints[detected]:
        # Shoulder filter — shoulders are reliably detected even for
        # horizontal swimmers where hips fall below the waterline.
        if max(frame[L_SHOULDER, 2], frame[R_SHOULDER, 2]) <= SHOULDER_MIN_VIS:
            continue
        # Horizontal-or-unknown body orientation. Rejects upright people
        # (spectators, marching soldiers); accepts unknown orientation.
        angle = _torso_angle_deg(frame)
        if angle is None or angle < HORIZONTAL_MAX_DEG or angle > 180 - HORIZONTAL_MAX_DEG:
            swimmer_frames += 1
            mid_s = (frame[L_SHOULDER, :2] + frame[R_SHOULDER, :2]) / 2.0
            mid_h = (frame[L_HIP, :2] + frame[R_HIP, :2]) / 2.0
            torso_lengths.append(float(np.linalg.norm(mid_s - mid_h)))

    median_torso = float(np.median(torso_lengths)) if torso_lengths else 0.0
    stats = {
        "total_frames": total,
        "detected_frames": n_detected,
        "swimmer_frames": swimmer_frames,
        "detection_rate": swimmer_frames / total if total else 0.0,
        "median_torso": median_torso,
    }

    if swimmer_frames == 0:
        return False, (
            "No horizontal swimmer detected. Film from the pool deck at water "
            "level with the swimmer's full body in frame. The swimmer must be "
            "actively stroking above the water line — avoid underwater angles."
        ), stats
    if swimmer_frames < MIN_SWIMMER_FRAMES:
        return False, (
            f"Too few swimmer frames detected ({swimmer_frames}). Film side-on "
            "from pool deck height, full body visible, within 3–6 m of the swimmer."
        ), stats
    if median_torso < MIN_MEDIAN_TORSO:
        return False, (
            f"Swimmer too small in frame (torso {median_torso:.2f} of frame; "
            f"need ≥ {MIN_MEDIAN_TORSO}). Film within 3–6 m so the full body "
            "fills a good part of the frame."
        ), stats
    if median_torso > MAX_MEDIAN_TORSO:
        return False, (
            "Pose geometry is implausible — the detector is likely tracking "
            "the wrong subject (crowd, spectators). Film a single swimmer "
            "side-on from the pool deck."
        ), stats
    return True, "", stats
