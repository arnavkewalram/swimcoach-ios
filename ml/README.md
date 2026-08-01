# swim-analyzer

ML-powered swimming technique analysis CLI.

## Architecture

```
pose/extractor.py        — MediaPipe Pose, 13 joints, returns (n_frames, 13, 3)
features/angles.py       — Elbow, knee, body alignment angles
features/motion.py       — Wrist/ankle velocity, stroke cycles, kick frequency
analysis/issues.py       — TechniqueIssue dataclass
analysis/feedback.py     — Score 0-100, grade A-F, coaching tips
ml/model.py              — SwimTCN: Temporal 1D-CNN, 4 dilated residual blocks
ml/datagen.py            — Synthetic labeled training data generator
ml/train.py              — Training script
ml/detector_ml.py        — SwimTCN-based issue detection (the only detection path)
visualization/overlay.py — Annotated video output
main.py                  — CLI entry point
```

## ML Model

- **Architecture:** Temporal 1D-CNN, input (B, 39, T) → 10-label multi-label classifier
- **Training:** 6000 synthetic samples, 25 epochs
- **Accuracy:** 94.2% exact-match on validation set
- **Labels:** left/right elbow overextension, elbow collapse, knee overbend, body sag, stroke asymmetry, low/high kick rate
- **Note:** SwimTCN is the only detection path (no rule-based fallback); torch is a required dependency

## Usage

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python main.py <video_path> --output-dir output
```

## Requirements

Python 3.12 (mediapipe incompatible with 3.14+). Use `.venv/`.
