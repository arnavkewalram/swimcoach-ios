"""Tests for features/motion.py"""
import numpy as np
import pytest
from features.motion import (
    compute_wrist_velocity,
    compute_ankle_velocity,
    detect_stroke_cycles,
    detect_kick_frequency,
    compute_motion_features,
)
from pose.keypoints import KEYPOINT_NAMES, N_KEYPOINTS


def make_keypoints(n_frames=60, value=0.0):
    return np.full((n_frames, N_KEYPOINTS, 3), value, dtype=np.float32)


def set_kp(kp_arr, frame, name, x, y, conf=1.0):
    idx = KEYPOINT_NAMES.index(name)
    kp_arr[frame, idx] = [x, y, conf]


def inject_oscillation(kp_arr, joint_name, axis=1, amplitude=0.1, freq_hz=1.0, fps=30.0):
    """Inject a sinusoidal oscillation into a joint's y (or x) coordinate."""
    idx = KEYPOINT_NAMES.index(joint_name)
    n = kp_arr.shape[0]
    t = np.arange(n) / fps
    kp_arr[:, idx, axis] = 0.5 + amplitude * np.sin(2 * np.pi * freq_hz * t)


class TestWristVelocity:
    def test_output_keys(self):
        kp = make_keypoints(10)
        result = compute_wrist_velocity(kp, fps=30.0)
        assert "left_wrist_speed" in result
        assert "right_wrist_speed" in result

    def test_static_wrist_zero_velocity(self):
        kp = make_keypoints(10, value=0.5)  # constant position
        result = compute_wrist_velocity(kp, fps=30.0)
        assert np.allclose(result["left_wrist_speed"][1:], 0.0)

    def test_moving_wrist_nonzero_velocity(self):
        kp = make_keypoints(10)
        lw_idx = KEYPOINT_NAMES.index("left_wrist")
        kp[:, lw_idx, 0] = np.linspace(0, 1, 10)  # moves 0→1 over 10 frames
        result = compute_wrist_velocity(kp, fps=10.0)
        # speed ≈ (1/9) * 10 ≈ 1.11 per frame
        assert np.all(result["left_wrist_speed"][1:] > 0)

    def test_output_length(self):
        n = 25
        kp = make_keypoints(n)
        result = compute_wrist_velocity(kp, fps=30.0)
        assert len(result["left_wrist_speed"]) == n
        assert len(result["right_wrist_speed"]) == n

    def test_first_frame_is_zero(self):
        kp = make_keypoints(10)
        result = compute_wrist_velocity(kp, fps=30.0)
        assert result["left_wrist_speed"][0] == 0.0
        assert result["right_wrist_speed"][0] == 0.0

    def test_single_frame_no_error(self):
        kp = make_keypoints(1)
        result = compute_wrist_velocity(kp, fps=30.0)
        assert len(result["left_wrist_speed"]) == 1


class TestDetectStrokeCycles:
    def test_no_oscillation_zero_strokes(self):
        kp = make_keypoints(60, value=0.5)
        result = detect_stroke_cycles(kp, fps=30.0)
        # Flat signal → no peaks
        assert result["stroke_count"] == 0.0

    def test_oscillating_wrist_detects_strokes(self):
        kp = make_keypoints(90)
        inject_oscillation(kp, "left_wrist", freq_hz=1.5, fps=30.0)
        inject_oscillation(kp, "right_wrist", freq_hz=1.5, fps=30.0)
        result = detect_stroke_cycles(kp, fps=30.0)
        assert result["stroke_count"] > 0

    def test_stroke_rate_units(self):
        """Stroke rate should be in SPM (strokes per minute), not per second."""
        kp = make_keypoints(120)
        inject_oscillation(kp, "left_wrist", freq_hz=1.0, fps=30.0)
        result = detect_stroke_cycles(kp, fps=30.0)
        # 1 Hz * 60 = ~60 spm
        assert result["left_stroke_rate_spm"] > 10  # sanity: not near 1

    def test_output_keys_present(self):
        kp = make_keypoints(30)
        result = detect_stroke_cycles(kp, fps=30.0)
        for k in ("left_stroke_frames", "right_stroke_frames",
                  "left_stroke_rate_spm", "right_stroke_rate_spm", "stroke_count"):
            assert k in result

    def test_empty_video_no_crash(self):
        kp = make_keypoints(1)
        result = detect_stroke_cycles(kp, fps=30.0)
        assert result["stroke_count"] == 0.0


class TestDetectKickFrequency:
    def test_no_movement_zero_kicks(self):
        kp = make_keypoints(60, value=0.5)
        result = detect_kick_frequency(kp, fps=30.0)
        assert result["kick_rate_per_min"] == 0.0

    def test_oscillating_ankles_detects_kicks(self):
        kp = make_keypoints(120)
        inject_oscillation(kp, "left_ankle", freq_hz=2.0, fps=30.0)
        inject_oscillation(kp, "right_ankle", freq_hz=2.0, fps=30.0, amplitude=0.12)
        result = detect_kick_frequency(kp, fps=30.0)
        assert result["kick_rate_per_min"] > 0

    def test_kick_frames_are_valid_indices(self):
        kp = make_keypoints(60)
        inject_oscillation(kp, "left_ankle", freq_hz=2.0, fps=30.0)
        result = detect_kick_frequency(kp, fps=30.0)
        for f in result["kick_frames"]:
            assert 0 <= f < 60

    def test_output_keys_present(self):
        kp = make_keypoints(30)
        result = detect_kick_frequency(kp, fps=30.0)
        assert "kick_frames" in result
        assert "kick_rate_per_min" in result


class TestComputeMotionFeatures:
    def test_returns_all_keys(self):
        kp = make_keypoints(30)
        result = compute_motion_features(kp, fps=30.0)
        expected = {
            "left_wrist_speed", "right_wrist_speed",
            "left_ankle_speed", "right_ankle_speed",
            "left_stroke_frames", "right_stroke_frames",
            "left_stroke_rate_spm", "right_stroke_rate_spm",
            "stroke_count", "kick_frames", "kick_rate_per_min",
        }
        assert expected.issubset(set(result.keys()))

    def test_realistic_swimmer_motion(self):
        """Inject realistic freestyle swimming motion and check detection."""
        kp = make_keypoints(180)  # 6 seconds @ 30fps
        # Left and right wrists alternating strokes ~1.2 Hz
        inject_oscillation(kp, "left_wrist", freq_hz=1.2, fps=30.0)
        inject_oscillation(kp, "right_wrist", freq_hz=1.2, fps=30.0, amplitude=0.09)
        # Ankles faster flutter kick ~3 Hz
        inject_oscillation(kp, "left_ankle", freq_hz=3.0, fps=30.0, amplitude=0.05)
        inject_oscillation(kp, "right_ankle", freq_hz=3.0, fps=30.0, amplitude=0.05)
        result = compute_motion_features(kp, fps=30.0)
        assert result["stroke_count"] > 5
        assert result["kick_rate_per_min"] > 60


class TestCrossPlatformSemantics:
    """stroke_count must be the SUM of both arms' strokes (the watch
    convention, matching the iOS app) — not the cycle average."""

    def test_stroke_count_is_sum_of_both_arms(self):
        import numpy as np
        from features.motion import detect_stroke_cycles
        from pose.keypoints import N_KEYPOINTS

        fps = 30.0
        t = np.arange(150) / fps
        kp = np.full((150, N_KEYPOINTS, 3), 0.5, dtype=np.float32)
        # Alternating arm oscillation at ~1 Hz each
        kp[:, 5, 1] = 0.5 + 0.1 * np.sin(2 * np.pi * 1.0 * t)
        kp[:, 6, 1] = 0.5 + 0.1 * np.sin(2 * np.pi * 1.0 * t + np.pi)
        result = detect_stroke_cycles(kp, fps)
        expected = len(result["left_stroke_frames"]) + len(result["right_stroke_frames"])
        assert result["stroke_count"] == expected
        assert result["stroke_count"] > 0
