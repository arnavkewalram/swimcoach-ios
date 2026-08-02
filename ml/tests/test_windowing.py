"""Tests for ml/windowing.py — model-timebase window construction."""

import numpy as np

from ml.windowing import (
    prediction_windows, resample_frames,
    MODEL_FPS, WINDOW_LEN, WINDOW_STRIDE, MIN_TIMEBASE_FRAMES,
)


def kp(n):
    return np.random.default_rng(0).random((n, 13, 3)).astype(np.float32)


class TestResampleFrames:

    def test_identity_length_returns_copy(self):
        src = kp(90)
        out = resample_frames(src, 90)
        assert np.array_equal(out, src)
        out[0, 0, 0] = 99.0
        assert src[0, 0, 0] != 99.0  # defensive copy, no aliasing

    def test_upsample_and_downsample_lengths(self):
        assert resample_frames(kp(45), 90).shape == (90, 13, 3)
        assert resample_frames(kp(300), 90).shape == (90, 13, 3)

    def test_endpoints_preserved(self):
        src = kp(30)
        out = resample_frames(src, 90)
        assert np.allclose(out[0], src[0])
        assert np.allclose(out[-1], src[-1])


class TestPredictionWindows:

    def test_native_fps_long_clip_windows(self):
        wins = prediction_windows(kp(300), MODEL_FPS)
        assert all(len(w) == WINDOW_LEN for w in wins)
        # final window flush with clip end
        assert len(wins) == len(range(0, 300 - WINDOW_LEN + 1, WINDOW_STRIDE)) + (
            1 if (300 - WINDOW_LEN) % WINDOW_STRIDE else 0)

    def test_25fps_clip_resampled_to_model_timebase(self):
        # 328 frames @ 25fps ≈ 394 model-timebase frames → 8 windows
        wins = prediction_windows(kp(328), 25.0)
        assert len(wins) == 8
        assert all(len(w) == WINDOW_LEN for w in wins)

    def test_short_clip_single_window(self):
        wins = prediction_windows(kp(60), MODEL_FPS)
        assert len(wins) == 1
        assert len(wins[0]) == 60

    def test_degenerate_high_fps_clip_rejected(self):
        # 12 frames tagged 240fps → ~1.5 model-timebase frames: no real
        # temporal signal, must NOT be stretched into a fake window
        assert prediction_windows(kp(12), 240.0) == []

    def test_below_min_timebase_frames_rejected(self):
        assert prediction_windows(kp(MIN_TIMEBASE_FRAMES - 1), MODEL_FPS) == []

    def test_zero_fps_assumed_model_fps(self):
        # fps=0 (missing metadata) is treated as already-at-model-fps
        wins = prediction_windows(kp(90), 0.0)
        assert len(wins) == 1
        assert len(wins[0]) == 90

    def test_exact_window_length(self):
        wins = prediction_windows(kp(WINDOW_LEN), MODEL_FPS)
        assert len(wins) == 1
        assert len(wins[0]) == WINDOW_LEN
