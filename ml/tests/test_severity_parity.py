"""Cross-platform parity guard for base issue severity.

Base severity per fault label is declared twice, in two languages that cannot
import each other:

  * Python — ``_SEVERITY`` in ``ml/detector_ml.py``
  * Swift  — ``catalog`` in ``iOS/SwimCoach/Core/FeedbackEngine.swift``

Both feed the same score formula (minor 5 / moderate 15 / major 25 — see
``analysis/feedback.py`` ``_SEVERITY_PENALTY`` and ``BiomechanicsEngine.score``),
so one label drifting silently makes the CLI and the app grade the same clip
differently. That is exactly how ``body_sag`` diverged (Python "moderate" vs
iOS ``.major``, a 10-point gap on every clip that flags it below the 0.8
escalation threshold).

``EXPECTED_SEVERITY`` below is the pinned contract; both sides are checked
against it. Sources are read with ``ast``/regex rather than imported:
``ml.detector_ml`` pulls in torch, which CI deliberately does not install.
"""

import ast
import re
from pathlib import Path

_ML_ROOT = Path(__file__).resolve().parents[1]           # …/ml
_REPO_ROOT = _ML_ROOT.parent
_DETECTOR_PY = _ML_ROOT / "ml" / "detector_ml.py"
_FEEDBACK_SWIFT = _REPO_ROOT / "iOS" / "SwimCoach" / "Core" / "FeedbackEngine.swift"

# The contract: fault label → base severity, in probability (ISSUE_LABELS) order.
# Changing a value here is a deliberate product decision that must land in
# ml/detector_ml.py (_SEVERITY) and FeedbackEngine.swift (catalog) together.
EXPECTED_SEVERITY = {
    "left_elbow_overextension":  "moderate",
    "right_elbow_overextension": "moderate",
    "left_elbow_collapse":       "moderate",
    "right_elbow_collapse":      "moderate",
    "left_knee_overbend":        "minor",
    "right_knee_overbend":       "minor",
    "body_sag":                  "major",
    "stroke_asymmetry":          "moderate",
    "low_kick_rate":             "minor",
    "excessive_kick_rate":       "minor",
}

_FIX_HINT = (
    "Base severity must be identical on both platforms — it drives the score "
    "(minor 5 / moderate 15 / major 25) in analysis/feedback.py and "
    "BiomechanicsEngine.score. Update _SEVERITY in ml/detector_ml.py, the "
    "catalog in iOS/SwimCoach/Core/FeedbackEngine.swift, and EXPECTED_SEVERITY "
    "in this file together — never just one."
)

# Matches a catalog entry head: ("name", "Display", .severity,
_SWIFT_ENTRY = re.compile(
    r'\(\s*"(?P<name>\w+)"\s*,\s*"[^"]*"\s*,\s*\.(?P<severity>minor|moderate|major)\s*,'
)


def _python_severity() -> dict[str, str]:
    """``_SEVERITY`` from ml/detector_ml.py, read without importing torch."""
    tree = ast.parse(_DETECTOR_PY.read_text(), filename=str(_DETECTOR_PY))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == "_SEVERITY" for t in node.targets
        ):
            return ast.literal_eval(node.value)
    raise AssertionError(f"No module-level _SEVERITY dict found in {_DETECTOR_PY}")


def _swift_severity() -> dict[str, str]:
    """Base severities from the ``catalog`` literal in FeedbackEngine.swift."""
    source = _FEEDBACK_SWIFT.read_text()
    start = source.find("catalog")
    assert start != -1, f"No `catalog` declaration found in {_FEEDBACK_SWIFT}"
    end = source.find("\n    ]", start)
    assert end != -1, f"Could not find the end of `catalog` in {_FEEDBACK_SWIFT}"
    return {
        m.group("name"): m.group("severity")
        for m in _SWIFT_ENTRY.finditer(source[start:end])
    }


def _report(side: str, source: Path, actual: dict[str, str]) -> str:
    """Per-label divergence report naming the offending labels."""
    lines = []
    for label, expected in EXPECTED_SEVERITY.items():
        if label not in actual:
            lines.append(f"  {label}: MISSING in {side} — contract says '{expected}'")
        elif actual[label] != expected:
            lines.append(
                f"  {label}: {side} says '{actual[label]}', "
                f"contract says '{expected}'"
            )
    for label in actual:
        if label not in EXPECTED_SEVERITY:
            lines.append(f"  {label}: EXTRA in {side}, not in the contract")
    if not lines:
        return ""
    return (
        f"Severity parity broken in {source}:\n"
        + "\n".join(lines)
        + f"\n{_FIX_HINT}"
    )


class TestSeverityParity:

    def test_python_severity_matches_contract(self):
        actual = _python_severity()
        assert actual == EXPECTED_SEVERITY, _report(
            "Python (_SEVERITY)", _DETECTOR_PY, actual
        )

    def test_swift_catalog_matches_contract(self):
        assert _FEEDBACK_SWIFT.exists(), (
            f"{_FEEDBACK_SWIFT} not found — the iOS half of the severity "
            "contract cannot be verified from this checkout."
        )
        actual = _swift_severity()
        assert actual == EXPECTED_SEVERITY, _report(
            "iOS (FeedbackEngine.catalog)", _FEEDBACK_SWIFT, actual
        )

    def test_label_order_matches_across_platforms(self):
        # Probability order is itself a contract: probs[i] is decoded by
        # catalog[i] on iOS and ISSUE_LABELS[i] in Python.
        expected_order = list(EXPECTED_SEVERITY)
        assert list(_python_severity()) == expected_order, (
            f"_SEVERITY key order in {_DETECTOR_PY} no longer matches "
            f"probability order.\n{_FIX_HINT}"
        )
        assert list(_swift_severity()) == expected_order, (
            f"catalog order in {_FEEDBACK_SWIFT} no longer matches "
            f"probability order.\n{_FIX_HINT}"
        )
