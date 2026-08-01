"""Tests for utils/io.py"""
import json
import os
import tempfile
import numpy as np
import pytest
from utils.io import save_keypoints, load_keypoints, save_report, save_json_summary, ensure_output_dir


class TestSaveLoadKeypoints:
    def test_round_trip(self, tmp_path):
        kp = np.random.rand(50, 13, 3).astype(np.float32)
        path = str(tmp_path / "kp.npy")
        save_keypoints(kp, path)
        loaded = load_keypoints(path)
        np.testing.assert_array_almost_equal(kp, loaded)

    def test_creates_parent_dirs(self, tmp_path):
        kp = np.zeros((5, 13, 3))
        path = str(tmp_path / "subdir" / "deep" / "kp.npy")
        save_keypoints(kp, path)
        assert os.path.exists(path)


class TestSaveReport:
    def test_writes_text(self, tmp_path):
        path = str(tmp_path / "report.txt")
        save_report("Hello coach\nSecond line", path)
        with open(path) as f:
            content = f.read()
        assert "Hello coach" in content

    def test_creates_parent_dirs(self, tmp_path):
        path = str(tmp_path / "a" / "b" / "report.txt")
        save_report("test", path)
        assert os.path.exists(path)


class TestSaveJsonSummary:
    def test_writes_valid_json(self, tmp_path):
        path = str(tmp_path / "summary.json")
        data = {"score": 75, "grade": "C", "issues": []}
        save_json_summary(data, path)
        with open(path) as f:
            loaded = json.load(f)
        assert loaded["score"] == 75

    def test_handles_numpy_types(self, tmp_path):
        path = str(tmp_path / "summary.json")
        data = {
            "score": np.int64(80),
            "arr": np.array([1.0, 2.0, 3.0]),
            "float": np.float32(3.14),
        }
        save_json_summary(data, path)
        with open(path) as f:
            loaded = json.load(f)
        assert loaded["score"] == 80
        assert loaded["arr"] == [1.0, 2.0, 3.0]


class TestEnsureOutputDir:
    def test_creates_dir(self, tmp_path):
        new_dir = str(tmp_path / "outputs" / "run1")
        result = ensure_output_dir(new_dir)
        assert os.path.isdir(new_dir)
        assert result == new_dir

    def test_existing_dir_no_error(self, tmp_path):
        ensure_output_dir(str(tmp_path))  # already exists
        assert os.path.isdir(str(tmp_path))
