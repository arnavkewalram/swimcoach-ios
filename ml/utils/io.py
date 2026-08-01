"""
I/O helpers: save/load keypoints, write reports to disk.
"""

import json
import os
import numpy as np
from pathlib import Path


def save_keypoints(keypoints: np.ndarray, path: str) -> None:
    """Save keypoints array as a .npy file."""
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    np.save(path, keypoints)
    print(f"Keypoints saved: {path}")


def load_keypoints(path: str) -> np.ndarray:
    """Load keypoints from a .npy file."""
    return np.load(path)


def save_report(report_text: str, path: str) -> None:
    """Write the text coaching report to disk."""
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        f.write(report_text)
    print(f"Report saved: {path}")


def save_json_summary(data: dict, path: str) -> None:
    """Save a JSON summary of analysis results."""
    Path(path).parent.mkdir(parents=True, exist_ok=True)

    def _convert(obj):
        if isinstance(obj, np.ndarray):
            return obj.tolist()
        if isinstance(obj, (np.integer,)):
            return int(obj)
        if isinstance(obj, (np.floating,)):
            return float(obj)
        return str(obj)

    with open(path, "w") as f:
        json.dump(data, f, default=_convert, indent=2)
    print(f"JSON summary saved: {path}")


def ensure_output_dir(output_dir: str) -> str:
    """Create output directory if it doesn't exist. Returns the path."""
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    return output_dir
