"""Shared pytest fixtures.

Video fixtures are synthesised at test time rather than committed: `ml/.gitignore`
excludes `*.mp4`, so a checked-in clip would exist only on the machine that made
it and every fresh clone would fail (not skip) the rotation tests.
"""

import struct

import pytest

# --- MP4 track-header (tkhd) display matrix -------------------------------
# The rotation tag a phone writes lives in the 3x3 display matrix of the video
# track's `tkhd` box. Values are fixed-point: a/b/c/d/x/y are 16.16, u/v/w are
# 2.30. OpenCV's ffmpeg backend reads this matrix to derive CAP_PROP_ORIENTATION_META.
_FP_16_16 = 1 << 16
_FP_2_30 = 1 << 30
# tkhd payload up to the matrix: version+flags, times, track id, duration,
# reserved, layer/group/volume. Version 1 widens three time fields to 64-bit.
_TKHD_MATRIX_OFFSET = {0: 48, 1: 60}
_IDENTITY_MATRIX = (_FP_16_16, 0, 0, 0, _FP_16_16, 0, 0, 0, _FP_2_30)

_CLIP_WIDTH = 64
_CLIP_HEIGHT = 32
_CLIP_FPS = 10.0
_CLIP_FRAMES = 10


def _rotation_matrix_90(source_height: int) -> tuple[int, ...]:
    """Display matrix for a quarter turn, as ffmpeg's av_display_rotation_set writes it."""
    return (
        0, _FP_16_16, 0,
        -_FP_16_16, 0, 0,
        source_height * _FP_16_16, 0, _FP_2_30,
    )


def _tag_display_rotation_90(mp4_bytes: bytes, source_height: int) -> bytes:
    """Return `mp4_bytes` with the video track's display matrix set to 90 degrees.

    Walks to the `tkhd` box whose matrix is still the identity that OpenCV's muxer
    wrote, and overwrites just those 36 bytes — the frames themselves are untouched,
    exactly like a phone recording that stores sensor-native frames plus a tag.
    """
    data = bytearray(mp4_bytes)
    search_from = 0
    while True:
        type_at = data.find(b"tkhd", search_from)
        if type_at < 0:
            raise RuntimeError(
                "No tkhd box with an identity display matrix in the generated MP4 — "
                "OpenCV's muxer layout changed; update _tag_display_rotation_90."
            )
        search_from = type_at + 4
        box_start = type_at - 4
        if box_start < 0:
            continue
        version = data[type_at + 4]
        matrix_at = box_start + _TKHD_MATRIX_OFFSET.get(version, -1)
        if matrix_at < box_start or matrix_at + 36 > len(data):
            continue
        if struct.unpack(">9i", data[matrix_at : matrix_at + 36]) != _IDENTITY_MATRIX:
            continue
        data[matrix_at : matrix_at + 36] = struct.pack(
            ">9i", *_rotation_matrix_90(source_height)
        )
        return bytes(data)


@pytest.fixture(scope="session")
def rotated_90_video(tmp_path_factory) -> str:
    """Path to a generated 64x32 landscape clip tagged with a 90-degree rotation.

    Read with the rotation applied it comes out 32 wide by 64 high.
    """
    cv2 = pytest.importorskip("cv2")
    import numpy as np

    path = tmp_path_factory.mktemp("video") / "rotated_90.mp4"
    writer = cv2.VideoWriter(
        str(path),
        cv2.VideoWriter_fourcc(*"mp4v"),
        _CLIP_FPS,
        (_CLIP_WIDTH, _CLIP_HEIGHT),
    )
    if not writer.isOpened():
        pytest.skip("this OpenCV build cannot write mp4v video; cannot build the fixture")
    # Asymmetric content so a quarter turn is a real change, not a no-op.
    frame = np.zeros((_CLIP_HEIGHT, _CLIP_WIDTH, 3), np.uint8)
    frame[:, : _CLIP_WIDTH // 3] = (0, 0, 255)
    for _ in range(_CLIP_FRAMES):
        writer.write(frame)
    writer.release()

    path.write_bytes(_tag_display_rotation_90(path.read_bytes(), _CLIP_HEIGHT))

    # Self-check: without a readable tag the tests below would assert nothing.
    probe = cv2.VideoCapture(str(path))
    detected = probe.get(cv2.CAP_PROP_ORIENTATION_META)
    probe.release()
    if detected != 90:
        raise RuntimeError(
            f"Generated fixture reports rotation {detected}, expected 90 — "
            "the display matrix was not written where OpenCV reads it."
        )
    return str(path)
