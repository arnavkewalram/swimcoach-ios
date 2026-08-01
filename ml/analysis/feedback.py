"""
Generate human-readable coaching feedback from detected issues and metrics.
"""

from dataclasses import dataclass
from typing import Optional
from analysis.issues import TechniqueIssue


@dataclass
class CoachingReport:
    overall_score: int              # 0–100
    grade: str                      # A / B / C / D / F
    summary: str
    issues: list[TechniqueIssue]
    tips: list[str]
    stats: dict[str, object]

    def to_text(self) -> str:
        lines = [
            "=" * 60,
            f"SWIM TECHNIQUE ANALYSIS REPORT",
            "=" * 60,
            f"Overall Score : {self.overall_score}/100  ({self.grade})",
            f"Summary       : {self.summary}",
            "",
        ]

        if self.stats:
            lines.append("── Key Metrics ──────────────────────────────────────")
            for k, v in self.stats.items():
                label = k.replace("_", " ").title()
                lines.append(f"  {label:<30} {v}")
            lines.append("")

        if self.issues:
            lines.append("── Detected Issues ──────────────────────────────────")
            for i, issue in enumerate(self.issues, 1):
                lines.append(
                    f"  {i}. [{issue.severity.upper()}] {issue.name.replace('_', ' ').title()}"
                )
                lines.append(f"     {issue.description}")
                lines.append("")
        else:
            lines.append("  No technique issues detected — great work!")
            lines.append("")

        if self.tips:
            lines.append("── Coaching Tips ────────────────────────────────────")
            for tip in self.tips:
                lines.append(f"  • {tip}")
            lines.append("")

        lines.append("=" * 60)
        return "\n".join(lines)


_SEVERITY_PENALTY = {"minor": 5, "moderate": 15, "major": 25}

_GRADE_THRESHOLDS = [
    (90, "A"),
    (80, "B"),
    (70, "C"),
    (55, "D"),
    (0, "F"),
]

_POSITIVE_TIPS = [
    "Maintain a neutral head position — looking straight down reduces neck strain and keeps hips high.",
    "Rotate your body 45° on each stroke to engage your lats and reduce frontal drag.",
    "Breathe every 3 strokes (bilateral breathing) to keep stroke symmetry.",
    "Finish each pull all the way past your hip before recovery.",
    "On the catch, keep your elbow high and fingertips pointed down for maximum propulsion.",
]


def generate_report(
    issues: list[TechniqueIssue],
    motion: dict[str, object],
    angles: dict[str, object],
    fps: float,
    n_frames: int,
) -> CoachingReport:
    """
    Build a CoachingReport from detected issues and feature data.
    """
    # Score
    penalty = sum(_SEVERITY_PENALTY.get(iss.severity, 10) for iss in issues)
    score = max(0, 100 - penalty)

    grade = "F"
    for threshold, g in _GRADE_THRESHOLDS:
        if score >= threshold:
            grade = g
            break

    # Summary
    if not issues:
        summary = "Excellent technique — no significant issues detected."
    elif score >= 80:
        summary = f"{len(issues)} minor issue(s) detected. Technique is generally solid."
    elif score >= 60:
        summary = (
            f"{len(issues)} issue(s) detected across multiple areas. "
            "Focused drills will help."
        )
    else:
        major_count = sum(1 for i in issues if i.severity == "major")
        summary = (
            f"{len(issues)} issues detected ({major_count} major). "
            "Significant technique improvements needed."
        )

    # Stats
    duration_s = n_frames / fps if fps > 0 else 0
    import numpy as np

    stats: dict[str, object] = {
        "video_duration": f"{duration_s:.1f}s ({n_frames} frames @ {fps:.0f} fps)",
        "stroke_count": motion.get("stroke_count", "—"),
        "left_stroke_rate": f"{motion.get('left_stroke_rate_spm', 0):.0f} spm",
        "right_stroke_rate": f"{motion.get('right_stroke_rate_spm', 0):.0f} spm",
        "kick_rate": f"{motion.get('kick_rate_per_min', 0):.0f} kicks/min",
    }

    if isinstance(angles.get("left_elbow"), np.ndarray):
        stats["avg_left_elbow_angle"] = f"{np.mean(angles['left_elbow']):.1f}°"
        stats["avg_right_elbow_angle"] = f"{np.mean(angles['right_elbow']):.1f}°"
        stats["avg_body_alignment"] = f"{np.mean(angles['body_alignment']):.1f}°"

    # Coaching tips: start with issue-specific advice, pad with general tips
    tips: list[str] = []
    for iss in issues:
        # The description already contains actionable advice — extract the last sentence
        desc_sentences = iss.description.split(". ")
        if len(desc_sentences) > 1:
            tips.append(desc_sentences[-1].strip().rstrip(".") + ".")
    # Add general tips (avoid duplicates)
    for tip in _POSITIVE_TIPS:
        if len(tips) >= 5:
            break
        if tip not in tips:
            tips.append(tip)

    return CoachingReport(
        overall_score=score,
        grade=grade,
        summary=summary,
        issues=issues,
        tips=tips[:6],
        stats=stats,
    )
