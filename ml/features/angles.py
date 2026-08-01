"""
Compute joint angles from pose keypoints.
"""

import numpy as np
from pose.extractor import KEYPOINT_NAMES


def _kp_idx(name: str) -> int:
    return KEYPOINT_NAMES.index(name)


def angle_between_three_points(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """
    Compute the angle at point B formed by A-B-C.
    Returns angle in degrees.
    """
    ba = a - b
    bc = c - b
    cosine = np.dot(ba, bc) / (np.linalg.norm(ba) * np.linalg.norm(bc) + 1e-9)
    cosine = np.clip(cosine, -1.0, 1.0)
    return np.degrees(np.arccos(cosine))


def compute_angles(keypoints: np.ndarray) -> dict[str, np.ndarray]:
    """
    Compute biomechanical angles for each frame.

    Args:
        keypoints: (n_frames, N_KEYPOINTS, 3) array.

    Returns:
        dict mapping angle name → 1D array of shape (n_frames,).
    """
    n_frames = keypoints.shape[0]

    angles = {
        "left_elbow": np.zeros(n_frames),
        "right_elbow": np.zeros(n_frames),
        "left_knee": np.zeros(n_frames),
        "right_knee": np.zeros(n_frames),
        "body_alignment": np.zeros(n_frames),  # shoulder–hip–ankle
    }

    ls = _kp_idx("left_shoulder")
    rs = _kp_idx("right_shoulder")
    le = _kp_idx("left_elbow")
    re = _kp_idx("right_elbow")
    lw = _kp_idx("left_wrist")
    rw = _kp_idx("right_wrist")
    lh = _kp_idx("left_hip")
    rh = _kp_idx("right_hip")
    lk = _kp_idx("left_knee")
    rk = _kp_idx("right_knee")
    la = _kp_idx("left_ankle")
    ra = _kp_idx("right_ankle")

    for i in range(n_frames):
        kp = keypoints[i, :, :2]  # use x,y only

        # Elbow angles
        angles["left_elbow"][i] = angle_between_three_points(kp[ls], kp[le], kp[lw])
        angles["right_elbow"][i] = angle_between_three_points(kp[rs], kp[re], kp[rw])

        # Knee angles
        angles["left_knee"][i] = angle_between_three_points(kp[lh], kp[lk], kp[la])
        angles["right_knee"][i] = angle_between_three_points(kp[rh], kp[rk], kp[ra])

        # Body alignment: midpoint shoulder → midpoint hip → midpoint ankle
        mid_shoulder = (kp[ls] + kp[rs]) / 2
        mid_hip = (kp[lh] + kp[rh]) / 2
        mid_ankle = (kp[la] + kp[ra]) / 2
        angles["body_alignment"][i] = angle_between_three_points(
            mid_shoulder, mid_hip, mid_ankle
        )

    return angles
