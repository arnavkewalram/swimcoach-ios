"""
SwimCoach Cloud Run backend.
Wraps the ml/ swim-analyzer pipeline (the canonical copy in this monorepo)
in a FastAPI server. Deploy: ./backend/deploy.sh from the repo root.

Runs with PYTHONPATH pointing at ml/ so imports match the CLI exactly.
"""

import os
import tempfile
import time
import uuid
from pathlib import Path

import httpx
import numpy as np
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from pose.extractor import extract_keypoints_from_video
from features.angles import compute_angles
from features.motion import compute_motion_features
from analysis.feedback import generate_report
from analysis.gating import validate_footage
from ml.detector_ml import detect_issues_ml

app = FastAPI(title="SwimCoach API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["POST", "GET"],
    allow_headers=["*"],
)


class AnalyzeRequest(BaseModel):
    video_url: str
    session_id: str = ""


class AnalyzeResponse(BaseModel):
    session_id: str
    score: int
    grade: str
    summary: str
    n_frames: int
    fps: float
    issues: list
    tips: list
    motion: dict
    stats: dict
    analyzed_at: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze(req: AnalyzeRequest):
    session_id = req.session_id or str(uuid.uuid4())

    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            r = await client.get(req.video_url)
            if r.status_code != 200:
                raise HTTPException(status_code=400, detail="Could not download video")
            Path(tmp_path).write_bytes(r.content)

        keypoints, frames, fps = extract_keypoints_from_video(
            tmp_path, frame_sample_rate=1
        )
        if len(frames) == 0:
            raise HTTPException(status_code=422, detail="No frames extracted from video")

        # Input-quality gate — same rules as the iOS app and CLI. Garbage
        # footage gets a 422 with actionable guidance, never a fake report.
        gate_ok, gate_reason, _ = validate_footage(keypoints)
        if not gate_ok:
            raise HTTPException(status_code=422, detail=gate_reason)

        angles = compute_angles(keypoints)
        motion = compute_motion_features(keypoints, fps)
        # SwimTCN is the only detection path (windowed, fps-aware)
        issues_raw = detect_issues_ml(keypoints, motion, angles, fps=fps)
        report = generate_report(issues_raw, motion, angles, fps, len(frames))

        issues_json = [
            {
                "name": iss.name,
                "severity": iss.severity,
                "observed": round(iss.observed_value, 1),
                "threshold": iss.threshold,
                "description": iss.description,
                "n_affected_frames": len(iss.affected_frames),
            }
            for iss in issues_raw
        ]

        motion_json = {
            k: (float(v) if isinstance(v, (np.floating, float)) else
                int(v) if isinstance(v, (np.integer, int)) else
                str(v))
            for k, v in motion.items()
            if not isinstance(v, np.ndarray) and not isinstance(v, list)
        }
        for k in ("left_stroke_frames", "right_stroke_frames", "kick_frames"):
            if k in motion:
                motion_json[k] = [int(x) for x in motion[k]]

        return AnalyzeResponse(
            session_id=session_id,
            score=report.overall_score,
            grade=report.grade,
            summary=report.summary,
            n_frames=len(frames),
            fps=fps,
            issues=issues_json,
            tips=report.tips,
            motion=motion_json,
            stats={k: str(v) for k, v in report.stats.items()},
            analyzed_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        )

    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
