"""
Build a weakly-supervised training dataset from real freestyle swimming videos.

Pipeline:
  1. For each .mp4 in /tmp/swim_raw/, extract pose sequences at ~10fps
  2. Filter low-visibility frames and short sequences
  3. Filter to side-on camera angle only (shoulder x-separation > 0.15)
  4. Slide a 90-frame window (stride 45) over each sequence
  5. Auto-label each window with geometric rules matching datagen.py
     (body_sag is always forced to 0 for real sequences — only synthetic
      data contributes body_sag labels, where coordinates are controlled)
  6. Combine with synthetic data (5000 samples) from datagen.py
  7. Save to /tmp/swim_dataset_v2.npz

Usage (from swim-analyzer-src/):
    python -m ml.build_real_dataset
"""

import os
import sys
import time
import glob
import traceback
from typing import Optional

import cv2
import numpy as np
from scipy.signal import find_peaks


# ── MediaPipe Tasks API (not the deprecated solutions.pose) ──────────────────
import mediapipe as mp
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision as mp_vision
from mediapipe.tasks.python.vision import PoseLandmarker, PoseLandmarkerOptions
from mediapipe.tasks.python.vision.core.vision_task_running_mode import VisionTaskRunningMode

MODEL_PATH = "/tmp/pose_landmarker_lite.task"

# ── Joint order (must match datagen.py / model.py) ──────────────────────────
NOSE        = 0
L_SHOULDER  = 1;  R_SHOULDER = 2
L_ELBOW     = 3;  R_ELBOW    = 4
L_WRIST     = 5;  R_WRIST    = 6
L_HIP       = 7;  R_HIP      = 8
L_KNEE      = 9;  R_KNEE     = 10
L_ANKLE     = 11; R_ANKLE    = 12
N_JOINTS    = 13

# MediaPipe landmark index for each joint (in the same order)
MP_INDICES = [0, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28]

# ── Label order (must match datagen.py LABEL_IDX) ───────────────────────────
LABEL_NAMES = [
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
N_LABELS = len(LABEL_NAMES)

# ── Configuration ────────────────────────────────────────────────────────────
SAMPLE_EVERY_N_FRAMES = 3      # ~10fps from 30fps source
MIN_JOINT_VIS         = 0.5
MIN_VISIBLE_JOINTS    = 5
MIN_SEQ_LEN           = 30
WINDOW_LEN            = 90
WINDOW_STRIDE         = 45
EFFECTIVE_FPS         = 10.0  # after downsampling

# ── Side-on camera filter ────────────────────────────────────────────────────
# In a side-on view the left and right shoulders are separated horizontally.
# Head-on and overhead shots have near-zero horizontal separation.
MIN_SHOULDER_X_SEP    = 0.15   # normalised [0,1] coords
MIN_SIDE_ON_FRACTION  = 0.60   # discard sequence if < 60% of frames pass


# ════════════════════════════════════════════════════════════════════════════
#  Angle utilities
# ════════════════════════════════════════════════════════════════════════════

def _angle_at_joint(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> np.ndarray:
    """
    Compute angle at joint B (vertex) given points A, B, C.
    a/b/c: (..., 2) arrays of (x, y) coordinates.
    Returns angle in degrees, same leading shape.
    """
    ba = a - b
    bc = c - b
    cos_angle = (ba * bc).sum(axis=-1) / (
        np.linalg.norm(ba, axis=-1) * np.linalg.norm(bc, axis=-1) + 1e-9
    )
    return np.degrees(np.arccos(np.clip(cos_angle, -1.0, 1.0)))


# ════════════════════════════════════════════════════════════════════════════
#  Pose extraction
# ════════════════════════════════════════════════════════════════════════════

def _is_side_on_frame(kp: np.ndarray) -> bool:
    """
    Return True if a single (13, 3) keypoint frame looks like a side-on view.

    Criterion: the horizontal (x) distance between left and right shoulders
    must exceed MIN_SHOULDER_X_SEP in normalised [0,1] coordinates.
    Both shoulders must also have sufficient visibility.
    """
    l_vis = kp[L_SHOULDER, 2]
    r_vis = kp[R_SHOULDER, 2]
    if l_vis < MIN_JOINT_VIS or r_vis < MIN_JOINT_VIS:
        return False
    return abs(kp[L_SHOULDER, 0] - kp[R_SHOULDER, 0]) > MIN_SHOULDER_X_SEP


def extract_pose_sequence(video_path: str) -> Optional[np.ndarray]:
    """
    Extract pose sequence from a video using MediaPipe PoseLandmarker (Tasks API).

    Returns:
        np.ndarray of shape (T, 13, 3) — float32 (x, y, visibility)
        or None if video cannot be read or yields < MIN_SEQ_LEN valid frames.
    """
    if not os.path.isfile(video_path):
        return None

    # Build landmarker (IMAGE running mode — we pass one frame at a time)
    base_opts = mp_python.BaseOptions(model_asset_path=MODEL_PATH)
    opts = PoseLandmarkerOptions(
        base_options=base_opts,
        running_mode=VisionTaskRunningMode.IMAGE,
        num_poses=1,
        min_pose_detection_confidence=0.4,
        min_pose_presence_confidence=0.4,
        min_tracking_confidence=0.4,
    )
    landmarker = PoseLandmarker.create_from_options(opts)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        return None

    original_fps = cap.get(cv2.CAP_PROP_FPS)
    if original_fps <= 0:
        original_fps = 30.0

    # Compute how many frames to skip to achieve ~10 fps
    skip = max(1, round(original_fps / EFFECTIVE_FPS))

    frames_seen = 0
    valid_frames = []

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frames_seen % skip != 0:
            frames_seen += 1
            continue
        frames_seen += 1

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)

        try:
            result = landmarker.detect(mp_image)
        except Exception:
            continue

        kp = np.zeros((N_JOINTS, 3), dtype=np.float32)
        if result.pose_landmarks and len(result.pose_landmarks) > 0:
            lms = result.pose_landmarks[0]  # first pose
            for j, mp_idx in enumerate(MP_INDICES):
                if mp_idx < len(lms):
                    lm = lms[mp_idx]
                    kp[j] = [lm.x, lm.y, lm.visibility if hasattr(lm, 'visibility') else 1.0]

        # Count joints with sufficient visibility
        n_visible = (kp[:, 2] > MIN_JOINT_VIS).sum()
        if n_visible >= MIN_VISIBLE_JOINTS:
            valid_frames.append(kp)

    cap.release()
    landmarker.close()

    if len(valid_frames) < MIN_SEQ_LEN:
        return None

    all_frames = np.stack(valid_frames, axis=0).astype(np.float32)  # (T, 13, 3)

    # ── Side-on filter ───────────────────────────────────────────────────────
    side_on_mask = np.array([_is_side_on_frame(f) for f in all_frames])
    side_on_fraction = side_on_mask.mean()
    if side_on_fraction < MIN_SIDE_ON_FRACTION:
        return None  # not a side-on video — drop it

    # Keep only frames that pass the side-on check
    filtered = all_frames[side_on_mask]
    if len(filtered) < MIN_SEQ_LEN:
        return None

    return filtered


# ════════════════════════════════════════════════════════════════════════════
#  Auto-labeling (geometric rules matching datagen.py logic)
# ════════════════════════════════════════════════════════════════════════════

def _count_peaks_half_per_minute(signal: np.ndarray, fps: float = EFFECTIVE_FPS) -> float:
    """Count peaks in a 1-D signal and return rate per minute."""
    if len(signal) < 4:
        return 0.0
    # Normalise to [0,1] so height threshold is relative
    sig_norm = (signal - signal.min()) / (np.ptp(signal) + 1e-9)
    peaks, _ = find_peaks(sig_norm, height=0.3, distance=max(1, int(fps * 0.15)))
    duration_min = len(signal) / fps / 60.0
    return len(peaks) / (duration_min + 1e-9)


def auto_label(kp_window: np.ndarray, fps: float = EFFECTIVE_FPS,
               zero_body_sag: bool = False) -> np.ndarray:
    """
    Apply geometric rules to a (T, 13, 3) pose window.

    Args:
        kp_window:     (T, 13, 3) pose keypoints
        fps:           frames per second of the sequence
        zero_body_sag: if True, always set body_sag = 0 regardless of geometry
                       (used for real sequences where y=0 is top-of-frame and
                       non-side-on cameras make the angle meaningless)

    Returns:
        label: (10,) float32 binary vector
    """
    T = kp_window.shape[0]
    label = np.zeros(N_LABELS, dtype=np.float32)

    xy = kp_window[:, :, :2]  # (T, 13, 2)

    # ── Elbow angles ────────────────────────────────────────────────────────
    # Left: shoulder → elbow → wrist
    l_elbow_ang = _angle_at_joint(
        xy[:, L_SHOULDER], xy[:, L_ELBOW], xy[:, L_WRIST]
    )  # (T,)
    r_elbow_ang = _angle_at_joint(
        xy[:, R_SHOULDER], xy[:, R_ELBOW], xy[:, R_WRIST]
    )

    # Elbow overextension: mean angle < 150°
    # (matches datagen._inject_elbow_overextension, which collapses angle)
    # NOTE: in datagen "overextension" label fires when the arm is nearly
    # straight.  The base pose has ~120° bend; overextension pushes toward
    # 175°.  So MEAN ANGLE > 150° → overextension.
    if l_elbow_ang.mean() > 150.0:
        label[0] = 1.0  # left_elbow_overextension
    if r_elbow_ang.mean() > 150.0:
        label[1] = 1.0  # right_elbow_overextension

    # Elbow collapse: MAX angle > 160° (arm flattened out too much through pull)
    # datagen._inject_elbow_collapse brings wrist toward shoulder → very acute angle.
    # Collapse = sharp bend → mean angle < 80°
    if l_elbow_ang.mean() < 80.0:
        label[2] = 1.0  # left_elbow_collapse
    if r_elbow_ang.mean() < 80.0:
        label[3] = 1.0  # right_elbow_collapse

    # ── Knee angles ─────────────────────────────────────────────────────────
    l_knee_ang = _angle_at_joint(xy[:, L_HIP], xy[:, L_KNEE], xy[:, L_ANKLE])
    r_knee_ang = _angle_at_joint(xy[:, R_HIP], xy[:, R_KNEE], xy[:, R_ANKLE])

    if l_knee_ang.mean() < 150.0:
        label[4] = 1.0  # left_knee_overbend
    if r_knee_ang.mean() < 150.0:
        label[5] = 1.0  # right_knee_overbend

    # ── Body sag ────────────────────────────────────────────────────────────
    # Angle of shoulder-midpoint → hip-midpoint vector from horizontal
    shoulder_mid = (xy[:, L_SHOULDER] + xy[:, R_SHOULDER]) / 2.0  # (T,2)
    hip_mid      = (xy[:, L_HIP] + xy[:, R_HIP]) / 2.0
    delta = hip_mid - shoulder_mid  # (T,2)  positive y = downward in image coords
    # In image coords y increases downward; body sag means hips lower than shoulders
    # Angle from horizontal:
    body_tilt = np.degrees(np.arctan2(np.abs(delta[:, 1]), np.abs(delta[:, 0]) + 1e-9))
    if body_tilt.mean() > 15.0:
        label[6] = 1.0  # body_sag

    # ── Stroke asymmetry ────────────────────────────────────────────────────
    # Detect peaks in wrist Y trajectories
    l_wrist_y = xy[:, L_WRIST, 1]
    r_wrist_y = xy[:, R_WRIST, 1]
    l_peaks, _ = find_peaks(l_wrist_y, distance=max(1, int(fps * 0.2)))
    r_peaks, _ = find_peaks(r_wrist_y, distance=max(1, int(fps * 0.2)))
    total_strokes = len(l_peaks) + len(r_peaks)
    if total_strokes > 2:
        asym = abs(len(l_peaks) - len(r_peaks)) / (total_strokes + 1e-9)
        if asym > 0.3:
            label[7] = 1.0  # stroke_asymmetry
    else:
        # Not enough motion to count strokes — treat as asymmetric (no data)
        label[7] = 0.0

    # ── Kick rate ────────────────────────────────────────────────────────────
    # Average ankle Y oscillation rate
    l_ankle_y = xy[:, L_ANKLE, 1]
    r_ankle_y = xy[:, R_ANKLE, 1]
    l_kick_rate = _count_peaks_half_per_minute(l_ankle_y, fps)
    r_kick_rate = _count_peaks_half_per_minute(r_ankle_y, fps)
    kick_rate = (l_kick_rate + r_kick_rate) / 2.0

    if kick_rate < 60.0:
        label[8] = 1.0   # low_kick_rate
    elif kick_rate > 180.0:
        label[9] = 1.0   # excessive_kick_rate
    # (mutually exclusive — only one can fire)

    # ── Override body_sag for real sequences ─────────────────────────────────
    # MediaPipe y=0 is top-of-frame (not bottom), so the hip/shoulder tilt
    # angle is meaningless for real videos.  Force it to 0; body_sag labels
    # come only from synthetic data where coordinates are fully controlled.
    if zero_body_sag:
        label[6] = 0.0  # body_sag

    return label


# ════════════════════════════════════════════════════════════════════════════
#  Windowing
# ════════════════════════════════════════════════════════════════════════════

def sequence_to_tcn_windows(kp_seq: np.ndarray, fps: float = EFFECTIVE_FPS,
                            zero_body_sag: bool = False):
    """
    Slide a 90-frame window (stride 45) over (T, 13, 3) pose sequence.

    Args:
        kp_seq:        (T, 13, 3) pose sequence
        fps:           effective frames per second
        zero_body_sag: passed through to auto_label — set True for real sequences

    Returns list of (X_window, y_label) where:
        X_window: (39, 90) float32 — ready for TCN
        y_label:  (10,)   float32
    """
    T = kp_seq.shape[0]
    results = []
    start = 0
    while start + WINDOW_LEN <= T:
        window = kp_seq[start : start + WINDOW_LEN]  # (90, 13, 3)
        label  = auto_label(window, fps=fps, zero_body_sag=zero_body_sag)
        # Reshape to (39, 90): transpose (13, 3, 90) → then reshape
        x = window.transpose(1, 2, 0).reshape(N_JOINTS * 3, WINDOW_LEN)
        results.append((x.astype(np.float32), label))
        start += WINDOW_STRIDE
    return results


# ════════════════════════════════════════════════════════════════════════════
#  Main
# ════════════════════════════════════════════════════════════════════════════

def main():
    video_dir = "/tmp/swim_raw"
    output_path = "/tmp/swim_dataset_v2.npz"

    videos = sorted(glob.glob(os.path.join(video_dir, "*.mp4")))
    print(f"Found {len(videos)} videos in {video_dir}")

    real_X = []
    real_y = []

    failed_videos = []    # (path, reason)
    filtered_videos = []  # videos discarded by side-on filter
    seq_counts = []       # windows per video
    n_survived = 0        # videos that passed the side-on filter

    for i, vpath in enumerate(videos):
        vname = os.path.basename(vpath)
        print(f"\n[{i+1}/{len(videos)}] {vname}")
        t0 = time.time()
        try:
            kp_seq = extract_pose_sequence(vpath)
        except Exception as e:
            reason = f"extraction error: {e}"
            print(f"  SKIP — {reason}")
            failed_videos.append((vname, reason))
            continue

        if kp_seq is None:
            # Could be: not enough valid frames, or failed side-on filter
            reason = "< MIN_SEQ_LEN valid frames OR failed side-on filter"
            print(f"  SKIP — {reason}")
            filtered_videos.append((vname, reason))
            continue

        # Use zero_body_sag=True: body_sag only comes from synthetic data
        windows = sequence_to_tcn_windows(kp_seq, zero_body_sag=True)
        if not windows:
            reason = "sequence too short for any 90-frame window"
            print(f"  SKIP — {reason}")
            failed_videos.append((vname, reason))
            continue

        for x_win, y_win in windows:
            real_X.append(x_win)
            real_y.append(y_win)

        n_survived += 1
        seq_counts.append(len(windows))
        elapsed = time.time() - t0
        print(f"  {kp_seq.shape[0]} side-on frames → {len(windows)} windows  ({elapsed:.1f}s)")

    n_real = len(real_X)
    print(f"\n{'='*60}")
    print(f"Videos processed: {len(videos)}")
    print(f"Videos that survived side-on filter: {n_survived}")
    print(f"Videos filtered out (not side-on or too short): {len(filtered_videos)}")
    print(f"Real windows collected: {n_real}")

    if n_real > 0:
        real_X_arr = np.stack(real_X, axis=0)   # (N_real, 39, 90)
        real_y_arr = np.stack(real_y, axis=0)   # (N_real, 10)

        print("\nReal data label distribution:")
        for i, name in enumerate(LABEL_NAMES):
            pos = real_y_arr[:, i].sum()
            print(f"  {name:<32} {pos:4.0f} / {n_real} ({pos/n_real*100:.1f}%)")
    else:
        real_X_arr = np.zeros((0, 39, WINDOW_LEN), dtype=np.float32)
        real_y_arr = np.zeros((0, N_LABELS), dtype=np.float32)

    # ── Generate synthetic data ─────────────────────────────────────────────
    print(f"\nGenerating 5000 synthetic samples…")
    sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
    from ml.datagen import generate_dataset
    X_syn, y_syn = generate_dataset(n_samples=5000, seed=42)
    print(f"  Synthetic: {X_syn.shape}")

    # ── Combine ─────────────────────────────────────────────────────────────
    X_all = np.concatenate([X_syn, real_X_arr], axis=0).astype(np.float32)
    y_all = np.concatenate([y_syn, real_y_arr], axis=0).astype(np.float32)
    N = len(X_all)
    print(f"\nCombined dataset: {N} samples  (shape {X_all.shape})")

    print("\nCombined label distribution:")
    for i, name in enumerate(LABEL_NAMES):
        pos = y_all[:, i].sum()
        print(f"  {name:<32} {pos:5.0f} / {N} ({pos/N*100:.1f}%)")

    np.savez(output_path, X=X_all, y=y_all)
    print(f"\nSaved dataset → {output_path}")

    # ── Summary of failures ─────────────────────────────────────────────────
    if filtered_videos:
        print(f"\nFiltered out by side-on filter or insufficient frames ({len(filtered_videos)}):")
        for vname, reason in filtered_videos:
            print(f"  {vname}: {reason}")
    if failed_videos:
        print(f"\nFailed / unusable videos ({len(failed_videos)}):")
        for vname, reason in failed_videos:
            print(f"  {vname}: {reason}")

    print("\nDone.")


if __name__ == "__main__":
    main()
