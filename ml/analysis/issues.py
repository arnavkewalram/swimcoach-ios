"""Shared TechniqueIssue type produced by the ML detector and consumed by
feedback/report generation and visualization."""

from dataclasses import dataclass


@dataclass
class TechniqueIssue:
    name: str
    severity: str          # "minor", "moderate", "major"
    affected_frames: list[int]
    metric_name: str
    observed_value: float
    threshold: float
    description: str
