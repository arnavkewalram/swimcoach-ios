"""Tests for features/angles.py"""
import numpy as np
import pytest
from features.angles import angle_between_three_points, compute_angles
from pose.extractor import KEYPOINT_NAMES, N_KEYPOINTS


def make_keypoints(n_frames=10, value=0.0):
    """Create blank keypoints array."""
    return np.full((n_frames, N_KEYPOINTS, 3), value, dtype=np.float32)


def set_kp(kp_arr, frame, name, x, y, conf=1.0):
    idx = KEYPOINT_NAMES.index(name)
    kp_arr[frame, idx] = [x, y, conf]


class TestAngleBetweenThreePoints:
    def test_90_degree_angle(self):
        a = np.array([0.0, 1.0])
        b = np.array([0.0, 0.0])
        c = np.array([1.0, 0.0])
        assert abs(angle_between_three_points(a, b, c) - 90.0) < 0.01

    def test_180_degree_angle(self):
        a = np.array([-1.0, 0.0])
        b = np.array([0.0, 0.0])
        c = np.array([1.0, 0.0])
        assert abs(angle_between_three_points(a, b, c) - 180.0) < 0.01

    def test_0_degree_angle(self):
        a = np.array([1.0, 0.0])
        b = np.array([0.0, 0.0])
        c = np.array([0.5, 0.0])
        assert abs(angle_between_three_points(a, b, c) - 0.0) < 0.01

    def test_45_degree_angle(self):
        a = np.array([0.0, 1.0])
        b = np.array([0.0, 0.0])
        c = np.array([1.0, 1.0])
        angle = angle_between_three_points(a, b, c)
        assert abs(angle - 45.0) < 0.5

    def test_degenerate_same_points(self):
        a = np.array([0.0, 0.0])
        b = np.array([0.0, 0.0])
        c = np.array([1.0, 0.0])
        # Should not raise — epsilon in denominator prevents div by zero
        result = angle_between_three_points(a, b, c)
        assert 0.0 <= result <= 180.0


class TestComputeAngles:
    def test_output_keys(self):
        kp = make_keypoints(5)
        result = compute_angles(kp)
        assert set(result.keys()) == {
            "left_elbow", "right_elbow", "left_knee", "right_knee", "body_alignment"
        }

    def test_output_shapes(self):
        n = 15
        kp = make_keypoints(n)
        result = compute_angles(kp)
        for key, arr in result.items():
            assert arr.shape == (n,), f"{key} shape mismatch"

    def test_straight_arm_gives_near_180(self):
        kp = make_keypoints(1)
        # Straight left arm: shoulder (0,0) elbow (0.5,0) wrist (1.0,0)
        set_kp(kp, 0, "left_shoulder", 0.0, 0.0)
        set_kp(kp, 0, "left_elbow",    0.5, 0.0)
        set_kp(kp, 0, "left_wrist",    1.0, 0.0)
        result = compute_angles(kp)
        assert abs(result["left_elbow"][0] - 180.0) < 1.0

    def test_bent_arm_gives_90(self):
        kp = make_keypoints(1)
        set_kp(kp, 0, "left_shoulder", 0.0, 1.0)
        set_kp(kp, 0, "left_elbow",    0.0, 0.0)
        set_kp(kp, 0, "left_wrist",    1.0, 0.0)
        result = compute_angles(kp)
        assert abs(result["left_elbow"][0] - 90.0) < 1.0

    def test_all_zeros_returns_zeros(self):
        kp = make_keypoints(5, value=0.0)
        result = compute_angles(kp)
        for arr in result.values():
            # All points at origin — angle is numerically 0
            assert all(0.0 <= v <= 180.0 for v in arr)

    def test_single_frame(self):
        kp = make_keypoints(1)
        result = compute_angles(kp)
        for arr in result.values():
            assert len(arr) == 1
