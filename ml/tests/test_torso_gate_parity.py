"""Cross-platform parity guard for the swimmer-size gate.

Plausible on-screen swimmer size — the normalized distance from the shoulder
midpoint to the hip midpoint — is declared twice, in two languages that cannot
import each other:

  * Python — ``MIN_MEDIAN_TORSO`` / ``MAX_MEDIAN_TORSO`` in
    ``ml/analysis/gating.py`` (bounds on the median over a whole clip)
  * Swift  — ``minTorsoLength`` / ``maxTorsoLength`` in
    ``iOS/SwimCoach/Core/PoseAnalyzer.swift`` (bounds per candidate body)

The two sides apply the bounds at different layers on purpose — see the
DELIBERATE DEVIATION note in ``PoseAnalyzer.isPlausiblySized`` — but the
*numbers* are one calibration, taken from the same validation clip set, and
they must stay identical. The measurement transfers exactly: both platforms
normalize x by frame width and y by frame height on an orientation-corrected
frame, and the Vision(y-up)→MediaPipe(y-down) flip cancels inside a distance.

Drift here is silent. The CLI would reject a clip the app happily grades, or
the app would start dropping frames the CLI keeps, with nothing failing — the
exact failure mode this repo's other parity guard was written for.

Sources are read with ``ast``/regex rather than imported: ``analysis.gating``
is importable in CI, but the Swift half never is, so both halves are parsed
the same way and the guard keeps working on a numpy-only runner.
"""

import ast
import re
from pathlib import Path

_ML_ROOT = Path(__file__).resolve().parents[1]           # …/ml
_REPO_ROOT = _ML_ROOT.parent
_GATING_PY = _ML_ROOT / "analysis" / "gating.py"
_POSE_SWIFT = _REPO_ROOT / "iOS" / "SwimCoach" / "Core" / "PoseAnalyzer.swift"

# The contract: normalized shoulder-midpoint→hip-midpoint distance.
# Calibrated in gating.py against the validation clip set — legitimate 3–6 m
# footage measures 0.095–0.19, archival far-field race footage 0.084, crowd
# shots where the detector stitches two people together 1.06. Changing a value
# here is a deliberate product decision that must land in ml/analysis/gating.py
# and iOS/SwimCoach/Core/PoseAnalyzer.swift together.
EXPECTED_BOUNDS = {"min": 0.09, "max": 0.60}

_PYTHON_NAMES = {"min": "MIN_MEDIAN_TORSO", "max": "MAX_MEDIAN_TORSO"}
_SWIFT_NAMES = {"min": "minTorsoLength", "max": "maxTorsoLength"}

_FIX_HINT = (
    "The torso-size bounds are one calibration shared by both platforms: "
    f"{_PYTHON_NAMES['min']}/{_PYTHON_NAMES['max']} in ml/analysis/gating.py and "
    f"{_SWIFT_NAMES['min']}/{_SWIFT_NAMES['max']} in "
    "iOS/SwimCoach/Core/PoseAnalyzer.swift. Update both files and "
    "EXPECTED_BOUNDS in this file together — never just one. A one-sided edit "
    "makes the CLI and the app disagree about which footage is analyzable, "
    "and nothing else in the suite will notice."
)


def _python_bounds() -> dict[str, float]:
    """Torso bounds from ml/analysis/gating.py, read without importing it."""
    tree = ast.parse(_GATING_PY.read_text(), filename=str(_GATING_PY))
    by_name = {
        target.id: node.value
        for node in tree.body
        if isinstance(node, ast.Assign)
        for target in node.targets
        if isinstance(target, ast.Name)
    }
    found = {}
    for key, name in _PYTHON_NAMES.items():
        assert name in by_name, (
            f"No module-level {name} found in {_GATING_PY} — the Python half "
            f"of the torso-size contract is gone.\n{_FIX_HINT}"
        )
        found[key] = float(ast.literal_eval(by_name[name]))
    return found


def _swift_bounds() -> dict[str, float]:
    """Torso bounds from the `static let` declarations in PoseAnalyzer.swift."""
    source = _POSE_SWIFT.read_text()
    found = {}
    for key, name in _SWIFT_NAMES.items():
        match = re.search(
            rf"static\s+let\s+{name}\s*:\s*Float\s*=\s*(-?\d+(?:\.\d+)?)", source
        )
        assert match, (
            f"No `static let {name}: Float` found in {_POSE_SWIFT} — the iOS "
            f"half of the torso-size contract is gone.\n{_FIX_HINT}"
        )
        found[key] = float(match.group(1))
    return found


def _report(side: str, source: Path, names: dict[str, str],
            actual: dict[str, float]) -> str:
    """Per-bound divergence report naming the offending constants."""
    lines = [
        f"  {names[key]}: {side} says {actual[key]}, contract says {expected}"
        for key, expected in EXPECTED_BOUNDS.items()
        if actual[key] != expected
    ]
    if not lines:
        return ""
    return f"Torso-size parity broken in {source}:\n" + "\n".join(lines) + f"\n{_FIX_HINT}"


class TestTorsoGateParity:

    def test_python_bounds_match_contract(self):
        actual = _python_bounds()
        assert actual == EXPECTED_BOUNDS, _report(
            "Python (gating.py)", _GATING_PY, _PYTHON_NAMES, actual
        )

    def test_swift_bounds_match_contract(self):
        assert _POSE_SWIFT.exists(), (
            f"{_POSE_SWIFT} not found — the iOS half of the torso-size "
            "contract cannot be verified from this checkout."
        )
        actual = _swift_bounds()
        assert actual == EXPECTED_BOUNDS, _report(
            "iOS (PoseAnalyzer.swift)", _POSE_SWIFT, _SWIFT_NAMES, actual
        )

    def test_both_platforms_agree(self):
        # The headline check: even if someone edits EXPECTED_BOUNDS above to
        # match one platform, the two sources still have to agree with each other.
        python, swift = _python_bounds(), _swift_bounds()
        assert python == swift, (
            f"The CLI and the app disagree about swimmer size:\n"
            f"  {_GATING_PY}: min={python['min']}, max={python['max']}\n"
            f"  {_POSE_SWIFT}: min={swift['min']}, max={swift['max']}\n"
            f"{_FIX_HINT}"
        )

    def test_bounds_are_a_usable_band(self):
        bounds = _python_bounds()
        assert 0 < bounds["min"] < bounds["max"], (
            f"Torso bounds in {_GATING_PY} do not describe a usable band: "
            f"{bounds}.\n{_FIX_HINT}"
        )
