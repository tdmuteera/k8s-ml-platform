"""Load a trained bundle and score one job request."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import joblib

from inference.features import JobSample, encode


@dataclass(frozen=True)
class Score:
    """One scored request."""

    queue: str
    confidence: float
    scores: dict[str, float]
    version: str


def load_bundle(path: Path) -> dict:
    """Load the joblib bundle written at image build time."""

    if not path.is_file():
        raise FileNotFoundError(f"Model file not found: {path}")
    bundle = joblib.load(path)
    if not isinstance(bundle, dict) or "model" not in bundle or "version" not in bundle:
        raise ValueError("The model file does not contain a usable bundle.")
    return bundle


def score(bundle: dict, sample: JobSample, repeats: int = 1) -> Score:
    """Score a request.

    ``repeats`` runs the same prediction more than once. A single prediction
    is too small to move CPU on a laptop, so the service uses this control
    when a load test needs to cross the autoscaler threshold.
    """

    repeats = max(1, min(int(repeats), 500))
    model = bundle["model"]
    vector = [encode(sample)]
    probabilities = None
    for _ in range(repeats):
        probabilities = model.predict_proba(vector)[0]
    if probabilities is None:
        raise RuntimeError("The model did not return probabilities.")
    classes = [str(label) for label in model.classes_]
    pairs = list(zip(classes, (float(value) for value in probabilities), strict=True))
    queue, confidence = max(pairs, key=lambda item: item[1])
    scores = {name: round(value, 4) for name, value in pairs}
    return Score(
        queue=queue,
        confidence=round(confidence, 4),
        scores=scores,
        version=str(bundle["version"]),
    )
