"""Rotation-metadata handling in the video reader.

Phone recordings carry a rotation tag over sensor-native frames; the
reader must apply it or MediaPipe sees sideways swimmers. The fixture is
a 64x32 landscape clip tagged with a 90-degree display rotation — read
correctly it comes out 32x64 portrait.

Skips when cv2 isn't installed (CI runs the numpy/scipy-only suite).
"""

from pathlib import Path

import pytest

FIXTURE = Path(__file__).parent / "fixtures" / "rotated_90.mp4"


def test_open_video_capture_applies_rotation_metadata():
    cv2 = pytest.importorskip("cv2")
    from pose.extractor import open_video_capture

    cap = open_video_capture(str(FIXTURE))
    assert cap.isOpened()
    ok, frame = cap.read()
    cap.release()
    assert ok
    # Portrait after rotation: taller than wide (64 high, 32 wide)
    assert frame.shape[:2] == (64, 32)


def test_default_capture_would_be_sideways():
    """Documents WHY open_video_capture exists: the raw default reader
    yields landscape frames for the same portrait-tagged file."""
    cv2 = pytest.importorskip("cv2")

    cap = cv2.VideoCapture(str(FIXTURE))
    ok, frame = cap.read()
    cap.release()
    assert ok
    if frame.shape[:2] == (64, 32):
        pytest.skip("this OpenCV build autorotates by default — helper is a no-op here")
    assert frame.shape[:2] == (32, 64)
