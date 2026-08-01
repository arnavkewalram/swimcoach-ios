## What

<!-- One or two sentences: what changes and why. -->

## Verification

- [ ] `cd ml && .venv/bin/python -m pytest tests/ -q` passes locally
- [ ] iOS tests pass (`xcodebuild test`, simulator) if Swift/model files changed
- [ ] If `ml/ml/datagen.py` or `ml/ml/model.py` changed: retrained, reconverted
      (`coreml_convert.py`), and regenerated `RealFootageFixtures.swift`
- [ ] If `iOS/project.yml` changed: ran `xcodegen generate` and committed the pbxproj

## Model impact

<!-- Delete if not applicable: does this change model behavior?
     Include per-label F1 from training output and real-footage spot checks. -->
