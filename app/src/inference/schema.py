"""Request and response models for the predict endpoint."""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class PredictRequest(BaseModel):
    """A small description of an ML job that needs a queue."""

    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "gpu_count": 2,
                    "cpu_cores": 16,
                    "memory_gb": 64,
                    "runtime_hours": 4,
                    "priority": "normal",
                    "framework": "pytorch",
                }
            ]
        }
    )

    gpu_count: int = Field(ge=0, le=16)
    cpu_cores: int = Field(ge=1, le=256)
    memory_gb: float = Field(gt=0, le=2048)
    runtime_hours: float = Field(gt=0, le=168)
    priority: Literal["low", "normal", "high"]
    framework: Literal["pytorch", "tensorflow", "jax", "other"]


class PredictResponse(BaseModel):
    """The queue chosen by the model, with class scores."""

    queue: str
    confidence: float
    model_version: str
    scores: dict[str, float]
