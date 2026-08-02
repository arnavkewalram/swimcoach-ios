"""
SwimCoach Cloud Run backend.
Wraps the ml/ swim-analyzer pipeline (the canonical copy in this monorepo)
in a FastAPI server. Deploy: ./backend/deploy.sh from the repo root.

Runs with PYTHONPATH pointing at ml/ so imports match the CLI exactly.
"""

import logging
import os
import tempfile
import time
import uuid
from pathlib import Path
from urllib.parse import urlparse

import httpx
import numpy as np
from fastapi import FastAPI, HTTPException
from fastapi.concurrency import run_in_threadpool
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from pose.extractor import extract_keypoints_from_video
from features.angles import compute_angles
from features.motion import compute_motion_features
from analysis.feedback import generate_report
from analysis.gating import validate_footage, LOW_DETECTION_RATE
from ml.detector_ml import detect_issues_ml, _get_model

log = logging.getLogger("swimcoach.backend")
logging.basicConfig(level=logging.INFO)

MAX_VIDEO_BYTES = 200 * 1024 * 1024  # 200 MB download cap

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
    quality_warning: str | None = None
    summary: str
    n_frames: int
    fps: float
    issues: list
    tips: list
    motion: dict
    stats: dict
    analyzed_at: str


@app.on_event("startup")
def preload_model():
    # Fail fast: a server without weights must never boot (and must never
    # fall into training inside a request).
    _get_model()
    log.info("SwimTCN weights loaded")


@app.get("/health")
def health():
    return {"status": "ok"}


async def _download_video(url: str, dest: str) -> None:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise HTTPException(status_code=400, detail="video_url must be http(s)")
    # NOTE: full SSRF protection (private-IP/metadata blocking) should be
    # enforced at the infrastructure layer (VPC egress rules). This guard
    # covers scheme + size only.
    async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as client:
        async with client.stream("GET", url) as r:
            if r.status_code != 200:
                raise HTTPException(status_code=400, detail="Could not download video")
            received = 0
            with open(dest, "wb") as f:
                async for chunk in r.aiter_bytes():
                    received += len(chunk)
                    if received > MAX_VIDEO_BYTES:
                        raise HTTPException(status_code=413, detail="Video too large (max 200 MB)")
                    f.write(chunk)


def _run_pipeline(tmp_path: str):
    """CPU-heavy synchronous pipeline — must run off the event loop."""
    keypoints, frames, fps = extract_keypoints_from_video(tmp_path, frame_sample_rate=1)
    if len(frames) == 0:
        raise HTTPException(status_code=422, detail="No frames extracted from video")

    gate_ok, gate_reason, gate_stats = validate_footage(keypoints)
    if not gate_ok:
        raise HTTPException(status_code=422, detail=gate_reason)

    angles = compute_angles(keypoints)
    motion = compute_motion_features(keypoints, fps)
    issues = detect_issues_ml(keypoints, motion, angles, fps=fps)
    report = generate_report(issues, motion, angles, fps, len(frames))
    return keypoints, frames, fps, gate_stats, angles, motion, issues, report


@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze(req: AnalyzeRequest):
    session_id = req.session_id or str(uuid.uuid4())

    with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False) as tmp:
        tmp_path = tmp.name

    try:
        await _download_video(req.video_url, tmp_path)

        # The pipeline is CPU-bound and synchronous — off the event loop so
        # /health and concurrent requests stay responsive.
        try:
            (keypoints, frames, fps, gate_stats, angles, motion,
             issues_raw, report) = await run_in_threadpool(_run_pipeline, tmp_path)
        except HTTPException:
            raise
        except ValueError as e:
            # e.g. "Cannot open video" from the extractor on corrupt files
            log.warning("Pipeline rejected input: %s", e)
            raise HTTPException(status_code=422, detail=str(e))
        except Exception:
            log.exception("Pipeline failed")
            raise HTTPException(status_code=500, detail="Analysis failed")

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
            quality_warning=(
                f"Low detection quality ({gate_stats['detection_rate']*100:.0f}% of "
                "frames) — results may be less accurate."
                if gate_stats["detection_rate"] < LOW_DETECTION_RATE else None
            ),
            analyzed_at=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        )

    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
