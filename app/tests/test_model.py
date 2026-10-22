"""Tests for the labelling rules and the trained forest."""

import pytest

from inference.features import FRAMEWORKS, JobSample, encode, label_for
from inference.scoring import score
from inference.train import build_bundle


def _sample(**overrides) -> JobSample:
    values = {
        "gpu_count": 0,
        "cpu_cores": 4,
        "memory_gb": 8,
        "runtime_hours": 1,
        "priority": "normal",
        "framework": "pytorch",
    }
    values.update(overrides)
    return JobSample(**values)


def test_label_rules():
    assert label_for(_sample(gpu_count=0, runtime_hours=48, priority="low")) == "cpu"
    assert label_for(_sample(gpu_count=1, runtime_hours=1, priority="high")) == "gpu"
    assert label_for(_sample(gpu_count=4, runtime_hours=12, priority="low")) == "gpu-preemptible"
    assert label_for(_sample(gpu_count=8, runtime_hours=11, priority="low")) == "gpu"
    assert label_for(_sample(gpu_count=8, runtime_hours=24, priority="normal")) == "gpu"


def test_encode_shape_and_names():
    vector = encode(_sample(framework="jax"))
    assert len(vector) == 5 + len(FRAMEWORKS)
    assert vector[0] == 0
    assert vector[5 + FRAMEWORKS.index("jax")] == 1


def test_encode_rejects_unknown_values():
    with pytest.raises(ValueError):
        encode(_sample(priority="urgent"))
    with pytest.raises(ValueError):
        encode(_sample(framework="mxnet"))


def test_forest_recovers_the_rules_outside_the_training_grid():
    bundle = build_bundle()
    assert bundle["training_accuracy"] == 1.0
    cases = [
        (_sample(gpu_count=0, cpu_cores=7, memory_gb=13, runtime_hours=30, priority="low"), "cpu"),
        (_sample(gpu_count=2, cpu_cores=6, memory_gb=20, runtime_hours=3, priority="high"), "gpu"),
        (
            _sample(
                gpu_count=1,
                cpu_cores=9,
                memory_gb=40,
                runtime_hours=18,
                priority="low",
                framework="tensorflow",
            ),
            "gpu-preemptible",
        ),
        (
            _sample(gpu_count=3, cpu_cores=12, memory_gb=15, runtime_hours=11.5, priority="low"),
            "gpu",
        ),
    ]
    for sample, expected in cases:
        assert score(bundle, sample).queue == expected
        assert score(bundle, sample).version == "1"
