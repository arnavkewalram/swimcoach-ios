"""View-jitter augmentation properties (numpy-only — CI-safe).

The roll component must be a rigid rotation about frame centre: distances
between joints are preserved (up to the later scale step) and coordinates
stay in [0, 1] after clipping.
"""

import numpy as np
import pytest


def _jitter():
    datagen = pytest.importorskip("ml.datagen")
    return datagen._apply_view_jitter


def test_output_stays_normalised():
    apply = _jitter()
    rng = np.random.default_rng(7)
    kp = rng.uniform(0.2, 0.8, size=(90, 13, 3)).astype(np.float32)
    out = apply(kp, rng)
    assert out.shape == kp.shape
    assert out[:, :, :2].min() >= 0.0 and out[:, :, :2].max() <= 1.0


def test_confidence_channel_untouched():
    apply = _jitter()
    rng = np.random.default_rng(11)
    kp = rng.uniform(0.3, 0.7, size=(90, 13, 3)).astype(np.float32)
    conf = kp[:, :, 2].copy()
    out = apply(kp, rng)
    np.testing.assert_array_equal(out[:, :, 2], conf)


def test_rotation_preserves_pairwise_distances_up_to_scale():
    apply = _jitter()
    rng = np.random.default_rng(3)
    # Points well inside the frame so clipping never bites
    kp = rng.uniform(0.42, 0.58, size=(4, 13, 3)).astype(np.float32)
    out = apply(kp.copy(), rng)
    # Distance ratios between joint pairs are invariant under
    # mirror+rotation+uniform scale+shift
    a = kp[0, 0, :2] - kp[0, 5, :2]
    b = kp[0, 2, :2] - kp[0, 9, :2]
    a2 = out[0, 0, :2] - out[0, 5, :2]
    b2 = out[0, 2, :2] - out[0, 9, :2]
    r_before = np.linalg.norm(a) / np.linalg.norm(b)
    r_after = np.linalg.norm(a2) / np.linalg.norm(b2)
    assert r_before == pytest.approx(r_after, rel=1e-4)
