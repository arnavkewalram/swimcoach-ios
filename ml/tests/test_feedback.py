"""Tests for analysis/feedback.py"""
import numpy as np
import pytest
from analysis.feedback import generate_report, CoachingReport
from analysis.issues import TechniqueIssue


def make_issue(name="test_issue", severity="moderate", n_frames=20):
    return TechniqueIssue(
        name=name,
        severity=severity,
        affected_frames=list(range(n_frames)),
        metric_name="test_metric",
        observed_value=90.0,
        threshold=130.0,
        description="Test issue description. Fix by doing X.",
    )


def make_angles(n=30):
    return {
        "left_elbow":     np.full(n, 120.0),
        "right_elbow":    np.full(n, 120.0),
        "left_knee":      np.full(n, 155.0),
        "right_knee":     np.full(n, 155.0),
        "body_alignment": np.full(n, 165.0),
    }


def make_motion():
    return {
        "stroke_count": 8.0,
        "left_stroke_rate_spm": 48.0,
        "right_stroke_rate_spm": 48.0,
        "kick_rate_per_min": 90.0,
    }


class TestGenerateReport:
    def test_no_issues_perfect_score(self):
        report = generate_report([], make_motion(), make_angles(), fps=30.0, n_frames=300)
        assert report.overall_score == 100
        assert report.grade == "A"

    def test_score_decreases_with_issues(self):
        issues = [make_issue(severity="major")]  # -25
        report = generate_report(issues, make_motion(), make_angles(), fps=30.0, n_frames=300)
        assert report.overall_score == 75

    def test_multiple_major_issues_low_score(self):
        issues = [make_issue(f"issue_{i}", "major") for i in range(5)]  # -125 → 0
        report = generate_report(issues, make_motion(), make_angles(), fps=30.0, n_frames=300)
        assert report.overall_score == 0

    def test_grade_boundaries(self):
        cases = [
            (0, "F"), (55, "D"), (70, "C"), (80, "B"), (90, "A"), (100, "A")
        ]
        for score, expected_grade in cases:
            penalty = 100 - score
            n_major = penalty // 25
            n_moderate = (penalty % 25) // 15
            issues = (
                [make_issue(f"m{i}", "major") for i in range(n_major)] +
                [make_issue(f"mod{i}", "moderate") for i in range(n_moderate)]
            )
            report = generate_report(issues, make_motion(), make_angles(), fps=30.0, n_frames=300)
            assert report.grade == expected_grade, f"Score {report.overall_score} → expected {expected_grade}, got {report.grade}"

    def test_returns_coaching_report(self):
        report = generate_report([], make_motion(), make_angles(), fps=30.0, n_frames=300)
        assert isinstance(report, CoachingReport)

    def test_stats_present(self):
        report = generate_report([], make_motion(), make_angles(), fps=30.0, n_frames=300)
        assert "stroke_count" in report.stats
        assert "kick_rate" in report.stats

    def test_tips_not_empty(self):
        report = generate_report([], make_motion(), make_angles(), fps=30.0, n_frames=300)
        assert len(report.tips) > 0

    def test_tips_max_6(self):
        issues = [make_issue(f"i{n}", "moderate") for n in range(10)]
        report = generate_report(issues, make_motion(), make_angles(), fps=30.0, n_frames=300)
        assert len(report.tips) <= 6

    def test_to_text_contains_score(self):
        report = generate_report([], make_motion(), make_angles(), fps=30.0, n_frames=300)
        text = report.to_text()
        assert "100/100" in text
        assert "SWIM TECHNIQUE ANALYSIS REPORT" in text

    def test_to_text_contains_issues(self):
        issues = [make_issue("left_knee_overbend", "major")]
        report = generate_report(issues, make_motion(), make_angles(), fps=30.0, n_frames=300)
        text = report.to_text()
        assert "left_knee_overbend" in text.lower() or "Left Knee Overbend" in text

    def test_summary_reflects_issue_count(self):
        issues = [make_issue(f"i{n}", "major") for n in range(3)]
        report = generate_report(issues, make_motion(), make_angles(), fps=30.0, n_frames=300)
        assert "3" in report.summary

    def test_duration_calculated_correctly(self):
        report = generate_report([], make_motion(), make_angles(), fps=30.0, n_frames=300)
        assert "10.0s" in report.stats["video_duration"]  # 300 / 30 = 10s
