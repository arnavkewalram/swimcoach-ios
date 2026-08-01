#!/usr/bin/env python3
"""
swim-analyzer — end-to-end swimming technique analysis CLI

Usage:
    python main.py <video_path> [options]

Options:
    --output-dir DIR      Directory for outputs (default: ./output)
    --sample-rate N       Process every Nth frame (default: 1)
    --no-video            Skip writing the annotated output video
    --save-keypoints      Save raw keypoints as .npy file
    --quiet               Suppress progress output
"""

import argparse
import os
import sys
import time
from pathlib import Path

import numpy as np

from pose.extractor import extract_keypoints_from_video
from features.angles import compute_angles
from features.motion import compute_motion_features
from analysis.feedback import generate_report
try:
    from ml.detector_ml import detect_issues_ml
except ImportError as e:
    print(
        f"Error: the ML detector could not be loaded ({e}).\n"
        "SwimTCN is the only detection path — install dependencies with:\n"
        "    pip install -r requirements.txt",
        file=sys.stderr,
    )
    sys.exit(1)
from visualization.overlay import render_annotated_video
from utils.io import save_keypoints, save_report, save_json_summary, ensure_output_dir


def parse_args():
    p = argparse.ArgumentParser(
        description="Analyze swimming technique from a video file."
    )
    p.add_argument("video", help="Path to the input swimming video")
    p.add_argument("--output-dir", default="output", help="Output directory")
    p.add_argument(
        "--sample-rate", type=int, default=1,
        help="Process every Nth frame (1 = all frames, 2 = every other, etc.)"
    )
    p.add_argument(
        "--no-video", action="store_true",
        help="Skip rendering the annotated output video"
    )
    p.add_argument(
        "--save-keypoints", action="store_true",
        help="Save raw keypoints as a .npy file"
    )
    p.add_argument(
        "--quiet", action="store_true",
        help="Suppress progress output"
    )
    return p.parse_args()


def main():
    args = parse_args()

    video_path = args.video
    if not Path(video_path).exists():
        print(f"Error: video file not found: {video_path}", file=sys.stderr)
        sys.exit(1)

    output_dir = ensure_output_dir(args.output_dir)
    video_stem = Path(video_path).stem

    t0 = time.time()

    # ── 1. Extract pose keypoints ──────────────────────────────────────
    if not args.quiet:
        print(f"\n[1/5] Extracting pose keypoints from: {video_path}")

    keypoints, frames, fps = extract_keypoints_from_video(
        video_path,
        frame_sample_rate=args.sample_rate,
    )
    n_frames = len(frames)

    if n_frames == 0:
        print("Error: no frames extracted from video.", file=sys.stderr)
        sys.exit(1)

    if not args.quiet:
        print(f"      → {n_frames} frames, {fps:.1f} fps")

    # Optionally save keypoints
    if args.save_keypoints:
        kp_path = os.path.join(output_dir, f"{video_stem}_keypoints.npy")
        save_keypoints(keypoints, kp_path)

    # ── 2. Compute biomechanical angles ────────────────────────────────
    if not args.quiet:
        print("[2/5] Computing joint angles...")

    angles = compute_angles(keypoints)

    # ── 3. Compute motion features ─────────────────────────────────────
    if not args.quiet:
        print("[3/5] Computing motion features...")

    motion = compute_motion_features(keypoints, fps)

    if not args.quiet:
        print(
            f"      → Strokes: {motion['stroke_count']}  "
            f"| Kick rate: {motion['kick_rate_per_min']} kicks/min"
        )

    # ── 4. Detect technique issues ─────────────────────────────────────
    if not args.quiet:
        print("[4/5] Detecting technique issues...")

    issues = detect_issues_ml(keypoints, motion, angles, fps=fps)

    if not args.quiet:
        if issues:
            for iss in issues:
                print(f"      [{iss.severity.upper()}] {iss.name}")
        else:
            print("      No issues detected.")

    # ── 5. Generate coaching report ────────────────────────────────────
    if not args.quiet:
        print("[5/5] Generating coaching report...")

    report = generate_report(issues, motion, angles, fps, n_frames)

    # Print to terminal
    print()
    print(report.to_text())

    # Save text report
    report_path = os.path.join(output_dir, f"{video_stem}_report.txt")
    save_report(report.to_text(), report_path)

    # Save JSON summary
    json_summary = {
        "video": video_path,
        "n_frames": n_frames,
        "fps": fps,
        "score": report.overall_score,
        "grade": report.grade,
        "summary": report.summary,
        "stats": report.stats,
        "issues": [
            {
                "name": i.name,
                "severity": i.severity,
                "observed": i.observed_value,
                "threshold": i.threshold,
                "n_affected_frames": len(i.affected_frames),
            }
            for i in issues
        ],
        "motion": {
            k: v for k, v in motion.items()
            if not isinstance(v, np.ndarray)
        },
    }
    json_path = os.path.join(output_dir, f"{video_stem}_summary.json")
    save_json_summary(json_summary, json_path)

    # ── Render annotated video ─────────────────────────────────────────
    if not args.no_video:
        video_out = os.path.join(output_dir, f"{video_stem}_annotated.mp4")
        if not args.quiet:
            print(f"\nRendering annotated video → {video_out}")
        render_annotated_video(
            frames, keypoints, angles, motion, issues, video_out, fps
        )

    elapsed = time.time() - t0
    print(f"\nDone in {elapsed:.1f}s. Outputs in: {output_dir}/")


if __name__ == "__main__":
    main()
