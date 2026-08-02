"""
Pose extraction using MediaPipe Pose.
Extracts keypoints for each frame of a video.
"""

import cv2
import mediapipe as mp
import numpy as np
from typing import Optional

from pose.keypoints import KEYPOINT_INDICES, KEYPOINT_NAMES, N_KEYPOINTS


def open_video_capture(video_path: str) -> "cv2.VideoCapture":
    """Open a video with rotation metadata applied.

    Phone recordings store sensor-native frames plus a rotation tag.
    OpenCV's ffmpeg backend detects the tag but (in the pip wheels we
    ship with) does NOT apply it by default — MediaPipe would see
    sideways frames. CAP_PROP_ORIENTATION_AUTO makes it explicit and
    backend-independent. Mirrors the iOS fix in VideoTransform.swift.
    """
    cap = cv2.VideoCapture(video_path)
    cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1)
    return cap


def extract_keypoints_from_video(
    video_path: str,
    frame_sample_rate: int = 1,
    min_detection_confidence: float = 0.5,
    min_tracking_confidence: float = 0.5,
) -> tuple[np.ndarray, list[np.ndarray], float]:
    """
    Extract pose keypoints from every Nth frame of a video.

    Args:
        video_path: Path to the input video file.
        frame_sample_rate: Process every Nth frame (1 = all frames).
        min_detection_confidence: MediaPipe detection threshold.
        min_tracking_confidence: MediaPipe tracking threshold.

    Returns:
        keypoints: np.ndarray of shape (n_frames, N_KEYPOINTS, 3)
                   where the 3 channels are (x, y, confidence).
                   x and y are normalized [0,1] relative to frame size.
        frames: list of BGR frames (sampled).
        fps: original video FPS.
    """
    mp_pose = mp.solutions.pose

    cap = open_video_capture(video_path)
    if not cap.isOpened():
        raise ValueError(f"Cannot open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f"Video: {total_frames} frames @ {fps:.1f} FPS")

    keypoints_list = []
    frames_list = []
    frame_idx = 0

    with mp_pose.Pose(
        min_detection_confidence=min_detection_confidence,
        min_tracking_confidence=min_tracking_confidence,
        model_complexity=1,
        smooth_landmarks=True,
    ) as pose:
        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            if frame_idx % frame_sample_rate != 0:
                frame_idx += 1
                continue

            # Convert BGR to RGB for MediaPipe
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            rgb.flags.writeable = False
            results = pose.process(rgb)
            rgb.flags.writeable = True

            # Extract our keypoints; use zeros if not detected
            kp = np.zeros((N_KEYPOINTS, 3), dtype=np.float32)
            if results.pose_landmarks:
                for i, name in enumerate(KEYPOINT_NAMES):
                    lm_idx = KEYPOINT_INDICES[name]
                    lm = results.pose_landmarks.landmark[lm_idx]
                    kp[i] = [lm.x, lm.y, lm.visibility]

            keypoints_list.append(kp)
            frames_list.append(frame.copy())
            frame_idx += 1

    cap.release()

    keypoints = np.array(keypoints_list)  # (n_frames, N_KEYPOINTS, 3)
    print(f"Extracted keypoints from {len(keypoints_list)} frames")
    return keypoints, frames_list, fps
