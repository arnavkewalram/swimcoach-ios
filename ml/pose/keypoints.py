"""Keypoint schema shared across the pipeline.

Kept free of cv2/mediapipe imports so downstream modules (and the test
suite in CI) can use the schema without pulling in heavy vision deps.
"""

# MediaPipe landmark indices we care about
KEYPOINT_INDICES = {
    "nose": 0,
    "left_shoulder": 11,
    "right_shoulder": 12,
    "left_elbow": 13,
    "right_elbow": 14,
    "left_wrist": 15,
    "right_wrist": 16,
    "left_hip": 23,
    "right_hip": 24,
    "left_knee": 25,
    "right_knee": 26,
    "left_ankle": 27,
    "right_ankle": 28,
}

KEYPOINT_NAMES = list(KEYPOINT_INDICES.keys())
N_KEYPOINTS = len(KEYPOINT_NAMES)
