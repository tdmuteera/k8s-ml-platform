"""Feature encoding and the labelling rules for the laboratory model."""

from __future__ import annotations

from dataclasses import dataclass

MODEL_VERSION = "1"
FRAMEWORKS = ("pytorch", "tensorflow", "jax", "other")
PRIORITIES = {"low": 0, "normal": 1, "high": 2}
QUEUES = ("cpu", "gpu", "gpu-preemptible")
FEATURE_NAMES = (
    "gpu_count",
    "cpu_cores",
    "memory_gb",
    "runtime_hours",
    "priority",
    *(f"framework_{name}" for name in FRAMEWORKS),
)


@dataclass(frozen=True)
class JobSample:
    """One ML job request presented to the model."""

    gpu_count: int
    cpu_cores: int
    memory_gb: float
    runtime_hours: float
    priority: str
    framework: str


def label_for(sample: JobSample) -> str:
    """Return the queue a perfect model would choose for this request.

    A request with no GPU goes to the CPU queue. A GPU request with low
    priority and a runtime of 12 hours or more goes to the preemptible GPU
    queue. Every other GPU request goes to the GPU queue.
    """

    if sample.gpu_count <= 0:
        return "cpu"
    if sample.priority == "low" and sample.runtime_hours >= 12:
        return "gpu-preemptible"
    return "gpu"


def encode(sample: JobSample) -> list[float]:
    """Turn a request into the numeric vector the forest was trained on."""

    if sample.priority not in PRIORITIES:
        raise ValueError(f"Unknown priority: {sample.priority}")
    if sample.framework not in FRAMEWORKS:
        raise ValueError(f"Unknown framework: {sample.framework}")
    features = [
        float(sample.gpu_count),
        float(sample.cpu_cores),
        float(sample.memory_gb),
        float(sample.runtime_hours),
        float(PRIORITIES[sample.priority]),
    ]
    features.extend(1.0 if sample.framework == name else 0.0 for name in FRAMEWORKS)
    return features
