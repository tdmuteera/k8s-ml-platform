"""Train the laboratory model and write it to disk.

The labels are a deterministic function of GPU count, priority, and runtime.
The forest is trained to recover that function. Framework, CPU count, and
memory are included so the request shape looks like a real job, and they do
not change the label.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
from sklearn.ensemble import RandomForestClassifier

from inference.features import (
    FEATURE_NAMES,
    FRAMEWORKS,
    MODEL_VERSION,
    PRIORITIES,
    QUEUES,
    JobSample,
    encode,
    label_for,
)


def iter_training_rows():
    """Yield a balanced grid that contains every queue."""

    for gpu_count in range(9):
        for runtime_hours in (0.5, 1.0, 2.0, 4.0, 8.0, 11.0, 12.0, 24.0, 48.0):
            for priority in PRIORITIES:
                for framework in FRAMEWORKS:
                    for cpu_cores in (4, 32):
                        for memory_gb in (8.0, 128.0):
                            sample = JobSample(
                                gpu_count=gpu_count,
                                cpu_cores=cpu_cores,
                                memory_gb=memory_gb,
                                runtime_hours=runtime_hours,
                                priority=priority,
                                framework=framework,
                            )
                            yield encode(sample), label_for(sample)


def build_bundle(seed: int = 7) -> dict:
    """Fit a forest on the synthetic grid and return the saved bundle."""

    rows = list(iter_training_rows())
    vectors = [row[0] for row in rows]
    labels = [row[1] for row in rows]
    model = RandomForestClassifier(
        n_estimators=40,
        max_depth=4,
        max_features=1.0,
        random_state=seed,
        n_jobs=1,
    )
    model.fit(vectors, labels)
    found = {str(label) for label in model.classes_}
    if found != set(QUEUES):
        raise RuntimeError(f"Unexpected model classes: {sorted(found)}")
    accuracy = float(model.score(vectors, labels))
    return {
        "model": model,
        "version": MODEL_VERSION,
        "feature_names": list(FEATURE_NAMES),
        "frameworks": list(FRAMEWORKS),
        "priorities": dict(PRIORITIES),
        "training_rows": len(rows),
        "training_accuracy": accuracy,
    }


def save_bundle(bundle: dict, path: Path) -> None:
    """Write a bundle to ``path``, creating parent directories."""

    path.parent.mkdir(parents=True, exist_ok=True)
    joblib.dump(bundle, path)


def main() -> None:
    parser = argparse.ArgumentParser(description="Train the laboratory queue model.")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()
    bundle = build_bundle(seed=args.seed)
    save_bundle(bundle, args.output)
    print(
        json.dumps(
            {
                "event": "trained",
                "path": str(args.output),
                "version": bundle["version"],
                "rows": bundle["training_rows"],
                "accuracy": round(bundle["training_accuracy"], 4),
            }
        ),
        flush=True,
    )


if __name__ == "__main__":
    main()
