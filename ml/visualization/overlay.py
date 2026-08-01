"""
Draw skeleton overlay and technique annotations on video frames.
"""

import cv2
import numpy as np
from pose.extractor import KEYPOINT_NAMES, N_KEYPOINTS

# Skeleton connections: (joint_a, joint_b)
SKELETON_CONNECTIONS = [
    ("left_shoulder", "right_shoulder"),
    ("left_shoulder", "left_elbow"),
    ("left_elbow", "left_wrist"),
    ("right_shoulder", "right_elbow"),
    ("right_elbow", "right_wrist"),
    ("left_shoulder", "left_hip"),
    ("right_shoulder", "right_hip"),
    ("left_hip", "right_hip"),
    ("left_hip", "left_knee"),
    ("left_knee", "left_ankle"),
    ("right_hip", "right_knee"),
    ("right_knee", "right_ankle"),
    ("nose", "left_shoulder"),
    ("nose", "right_shoulder"),
]

# BGR colors
COLOR_SKELETON = (0, 255, 128)     # green
COLOR_KEYPOINT = (255, 255, 255)   # white
COLOR_ISSUE = (0, 80, 255)         # red-orange
COLOR_METRIC = (255, 220, 0)       # cyan-ish
COLOR_BG = (0, 0, 0)               # black for text bg


def _to_pixel(x: float, y: float, w: int, h: int) -> tuple[int, int]:
    return int(x * w), int(y * h)


def draw_skeleton(
    frame: np.ndarray,
    keypoints_frame: np.ndarray,
    confidence_threshold: float = 0.3,
) -> np.ndarray:
    """
    Draw skeleton connections and keypoint dots on a single frame.

    Args:
        frame: BGR image (H, W, 3)
        keypoints_frame: (N_KEYPOINTS, 3) — x, y, confidence (normalized)
        confidence_threshold: skip joints below this visibility score

    Returns:
        Annotated frame (in-place modification, also returned).
    """
    h, w = frame.shape[:2]
    name_to_idx = {name: i for i, name in enumerate(KEYPOINT_NAMES)}

    # Draw connections
    for a_name, b_name in SKELETON_CONNECTIONS:
        if a_name not in name_to_idx or b_name not in name_to_idx:
            continue
        a_idx = name_to_idx[a_name]
        b_idx = name_to_idx[b_name]
        ax, ay, ac = keypoints_frame[a_idx]
        bx, by, bc = keypoints_frame[b_idx]
        if ac < confidence_threshold or bc < confidence_threshold:
            continue
        pt_a = _to_pixel(ax, ay, w, h)
        pt_b = _to_pixel(bx, by, w, h)
        cv2.line(frame, pt_a, pt_b, COLOR_SKELETON, 2, cv2.LINE_AA)

    # Draw keypoints
    for i, name in enumerate(KEYPOINT_NAMES):
        x, y, conf = keypoints_frame[i]
        if conf < confidence_threshold:
            continue
        pt = _to_pixel(x, y, w, h)
        cv2.circle(frame, pt, 4, COLOR_KEYPOINT, -1, cv2.LINE_AA)
        cv2.circle(frame, pt, 5, COLOR_SKELETON, 1, cv2.LINE_AA)

    return frame


def draw_metrics_hud(
    frame: np.ndarray,
    frame_idx: int,
    angles_frame: dict[str, float],
    motion_summary: dict[str, object],
    issue_names: list[str],
) -> np.ndarray:
    """
    Overlay a HUD in the top-left corner with current angles and active issues.
    """
    lines = [
        f"Frame: {frame_idx}",
        f"L Elbow: {angles_frame.get('left_elbow', 0):.0f}°",
        f"R Elbow: {angles_frame.get('right_elbow', 0):.0f}°",
        f"L Knee:  {angles_frame.get('left_knee', 0):.0f}°",
        f"R Knee:  {angles_frame.get('right_knee', 0):.0f}°",
        f"Body:    {angles_frame.get('body_alignment', 0):.0f}°",
    ]

    if motion_summary.get("stroke_count"):
        lines.append(f"Strokes: {motion_summary['stroke_count']}")
    if motion_summary.get("kick_rate_per_min"):
        lines.append(f"Kick: {motion_summary['kick_rate_per_min']:.0f}/min")

    if issue_names:
        lines.append("Issues:")
        for name in issue_names[:3]:
            lines.append(f"  ! {name.replace('_', ' ')}")

    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.45
    thickness = 1
    padding = 4
    line_h = 16

    # Background box
    box_w = 180
    box_h = len(lines) * line_h + padding * 2
    overlay = frame.copy()
    cv2.rectangle(overlay, (5, 5), (5 + box_w, 5 + box_h), (0, 0, 0), -1)
    cv2.addWeighted(overlay, 0.55, frame, 0.45, 0, frame)

    for idx, line in enumerate(lines):
        y = 5 + padding + (idx + 1) * line_h
        color = COLOR_ISSUE if line.startswith("  !") else COLOR_METRIC
        cv2.putText(frame, line, (10, y), font, font_scale, color, thickness, cv2.LINE_AA)

    return frame


def annotate_issue_frames(
    frame: np.ndarray,
    active_issue_names: list[str],
) -> np.ndarray:
    """Draw a red border and issue label when a technique issue is active this frame."""
    if not active_issue_names:
        return frame

    h, w = frame.shape[:2]
    cv2.rectangle(frame, (0, 0), (w - 1, h - 1), (0, 60, 220), 3)

    font = cv2.FONT_HERSHEY_SIMPLEX
    for i, name in enumerate(active_issue_names[:2]):
        label = name.replace("_", " ").upper()
        cv2.putText(
            frame, label,
            (10, h - 15 - i * 20),
            font, 0.5, (0, 80, 255), 1, cv2.LINE_AA,
        )
    return frame


def render_annotated_video(
    frames: list[np.ndarray],
    keypoints: np.ndarray,
    angles: dict[str, np.ndarray],
    motion: dict[str, object],
    issues,
    output_path: str,
    fps: float,
) -> None:
    """
    Write an annotated video to output_path with skeleton overlay,
    HUD metrics, and issue highlights.

    Args:
        frames: list of BGR frames (same length as keypoints axis 0)
        keypoints: (n_frames, N_KEYPOINTS, 3)
        angles: dict of angle arrays, each shape (n_frames,)
        motion: motion feature dict
        issues: list of TechniqueIssue
        output_path: where to save (e.g. "output/annotated.mp4")
        fps: playback frame rate
    """
    if not frames:
        print("No frames to write.")
        return

    import imageio

    # Build per-frame issue sets
    frame_issues: list[list[str]] = [[] for _ in range(len(frames))]
    for issue in issues:
        for fi in issue.affected_frames:
            if fi < len(frame_issues):
                frame_issues[fi].append(issue.name)

    angle_keys = list(angles.keys())
    out_frames = []

    for i, frame in enumerate(frames):
        out = frame.copy()

        # Skeleton
        if i < len(keypoints):
            draw_skeleton(out, keypoints[i])

        # Per-frame angles
        angles_frame = {k: float(angles[k][i]) for k in angle_keys if i < len(angles[k])}

        # HUD
        draw_metrics_hud(out, i, angles_frame, motion, frame_issues[i])

        # Issue border
        annotate_issue_frames(out, frame_issues[i])

        # Convert BGR -> RGB for imageio
        out_frames.append(out[:, :, ::-1])

    imageio.mimwrite(output_path, out_frames, fps=fps, macro_block_size=1)
    print(f"Annotated video saved: {output_path}")
