"""Tests for analysis/gating.py — input-quality gate."""

import numpy as np
import pytest

from analysis.gating import (
    validate_footage,
    L_SHOULDER, R_SHOULDER, L_HIP, R_HIP,
)


def make_frames(n, builder):
    kp = np.zeros((n, 13, 3), dtype=np.float32)
    for i in range(n):
        builder(kp[i])
    return kp


def horizontal_swimmer(frame):
    # Shoulders at x≈0.4, hips at x≈0.6, same height → torso horizontal
    frame[:, 2] = 0.9
    frame[L_SHOULDER] = [0.40, 0.50, 0.9]
    frame[R_SHOULDER] = [0.40, 0.54, 0.9]
    frame[L_HIP] = [0.60, 0.50, 0.9]
    frame[R_HIP] = [0.60, 0.54, 0.9]


def standing_person(frame):
    # Hips directly below shoulders → torso vertical (90°)
    frame[:, 2] = 0.9
    frame[L_SHOULDER] = [0.50, 0.30, 0.9]
    frame[R_SHOULDER] = [0.54, 0.30, 0.9]
    frame[L_HIP] = [0.50, 0.60, 0.9]
    frame[R_HIP] = [0.54, 0.60, 0.9]


class TestValidateFootage:

    def test_all_zero_frames_rejected(self):
        kp = np.zeros((100, 13, 3), dtype=np.float32)
        ok, reason, stats = validate_footage(kp)
        assert not ok
        assert "No horizontal swimmer" in reason
        assert stats["swimmer_frames"] == 0

    def test_horizontal_swimmer_accepted(self):
        kp = make_frames(60, horizontal_swimmer)
        ok, reason, stats = validate_footage(kp)
        assert ok
        assert stats["swimmer_frames"] == 60

    def test_standing_people_rejected(self):
        kp = make_frames(60, standing_person)
        ok, reason, _ = validate_footage(kp)
        assert not ok
        assert "No horizontal swimmer" in reason

    def test_low_shoulder_confidence_rejected(self):
        def low_conf(frame):
            horizontal_swimmer(frame)
            frame[L_SHOULDER, 2] = 0.1
            frame[R_SHOULDER, 2] = 0.1
        kp = make_frames(60, low_conf)
        ok, reason, _ = validate_footage(kp)
        assert not ok

    def test_unknown_orientation_accepted(self):
        # Shoulders visible, hips underwater (low vis) — orientation unknown,
        # accepted per the iOS rule (practice footage has no spectators).
        def hips_hidden(frame):
            horizontal_swimmer(frame)
            frame[L_HIP, 2] = 0.05
            frame[R_HIP, 2] = 0.05
        kp = make_frames(60, hips_hidden)
        ok, _, stats = validate_footage(kp)
        assert ok
        assert stats["swimmer_frames"] == 60

    def test_too_few_swimmer_frames_rejected(self):
        kp = np.zeros((100, 13, 3), dtype=np.float32)
        for i in range(5):
            horizontal_swimmer(kp[i])
        ok, reason, stats = validate_footage(kp)
        assert not ok
        assert "Too few swimmer frames" in reason
        assert stats["swimmer_frames"] == 5

    def test_exactly_min_frames_accepted(self):
        kp = np.zeros((100, 13, 3), dtype=np.float32)
        for i in range(10):
            horizontal_swimmer(kp[i])
        ok, _, _ = validate_footage(kp)
        assert ok

    def test_reversed_direction_accepted(self):
        # Swimmer facing the other way: hips at smaller x → angle near 180°
        def reversed_swimmer(frame):
            frame[:, 2] = 0.9
            frame[L_SHOULDER] = [0.60, 0.50, 0.9]
            frame[R_SHOULDER] = [0.60, 0.54, 0.9]
            frame[L_HIP] = [0.40, 0.50, 0.9]
            frame[R_HIP] = [0.40, 0.54, 0.9]
        kp = make_frames(60, reversed_swimmer)
        ok, _, _ = validate_footage(kp)
        assert ok

    def test_tiny_distant_swimmer_rejected(self):
        # Far-field footage: horizontal but torso only ~3% of the frame
        def tiny(frame):
            frame[:, 2] = 0.9
            frame[L_SHOULDER] = [0.49, 0.50, 0.9]
            frame[R_SHOULDER] = [0.49, 0.51, 0.9]
            frame[L_HIP] = [0.52, 0.50, 0.9]
            frame[R_HIP] = [0.52, 0.51, 0.9]
        kp = make_frames(60, tiny)
        ok, reason, _ = validate_footage(kp)
        assert not ok
        assert "too small" in reason

    def test_implausible_geometry_rejected(self):
        # Detector jumping between subjects → nonsense torso spanning the frame
        def sprawling(frame):
            frame[:, 2] = 0.9
            frame[L_SHOULDER] = [0.05, 0.50, 0.9]
            frame[R_SHOULDER] = [0.05, 0.54, 0.9]
            frame[L_HIP] = [0.95, 0.50, 0.9]
            frame[R_HIP] = [0.95, 0.54, 0.9]
        kp = make_frames(60, sprawling)
        ok, reason, _ = validate_footage(kp)
        assert not ok
        assert "implausible" in reason

    def test_stats_always_present(self):
        kp = np.zeros((10, 13, 3), dtype=np.float32)
        _, _, stats = validate_footage(kp)
        assert set(stats) == {"total_frames", "detected_frames",
                              "swimmer_frames", "detection_rate", "median_torso"}
