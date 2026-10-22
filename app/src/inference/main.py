"""HTTP service for the local ML inference laboratory."""

from __future__ import annotations

import hmac
import json
import os
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated

from fastapi import FastAPI, Header, HTTPException, Request, status
from fastapi.responses import Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

from inference.features import JobSample
from inference.schema import PredictRequest, PredictResponse
from inference.scoring import load_bundle, score

REQUESTS = Counter(
    "inference_requests_total",
    "Prediction requests handled by the service.",
    ["status", "queue"],
)
LATENCY = Histogram(
    "inference_request_duration_seconds",
    "Time spent scoring a prediction request.",
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5),
)
MODEL_INFO = Gauge(
    "inference_model_info",
    "Model loaded by this process. The value is always 1.",
    ["version"],
)
KNOWN_QUEUES = {"cpu", "gpu", "gpu-preemptible"}


def _log(event: str, **fields: object) -> None:
    print(json.dumps({"event": event, "service": "inference", **fields}), flush=True)


def _repeats() -> int:
    raw = os.environ.get("PREDICT_REPEATS", "1")
    try:
        value = int(raw)
    except ValueError:
        return 1
    return max(1, min(value, 500))


def _authorized(header: str | None) -> bool:
    expected = os.environ.get("API_KEY", "")
    if not expected or not header:
        return False
    return hmac.compare_digest(header, expected)


def create_app() -> FastAPI:
    """Build the ASGI application."""

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        path = Path(os.environ.get("MODEL_PATH", "/models/model.joblib"))
        bundle = load_bundle(path)
        app.state.bundle = bundle
        app.state.ready = True
        MODEL_INFO.labels(version=str(bundle["version"])).set(1)
        _log("model_loaded", version=str(bundle["version"]), path=str(path))
        yield
        app.state.ready = False

    app = FastAPI(
        title="ML inference service",
        version="1.0.0",
        summary="Queue classifier for a small ML job request.",
        description=(
            "Scores a job request into a CPU queue, a GPU queue, or a preemptible GPU queue. "
            "The model is a scikit-learn forest trained when the container image is built."
        ),
        lifespan=lifespan,
    )

    @app.get("/healthz")
    def healthz() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/readyz")
    def readyz() -> dict[str, str]:
        if not getattr(app.state, "ready", False):
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="The model is not loaded.",
            )
        return {"status": "ready"}

    @app.get("/")
    def root() -> dict[str, str]:
        bundle = app.state.bundle
        return {
            "service": "ml-inference",
            "model_version": str(bundle["version"]),
            "docs": "/docs",
            "predict": "/predict",
        }

    @app.get("/metrics")
    def metrics() -> Response:
        return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

    @app.post("/predict", response_model=PredictResponse)
    def predict(
        payload: PredictRequest,
        request: Request,
        x_api_key: Annotated[str | None, Header()] = None,
    ) -> PredictResponse:
        request_id = request.headers.get("x-request-id", uuid.uuid4().hex)
        if not _authorized(x_api_key):
            REQUESTS.labels(status="unauthorized", queue="none").inc()
            _log("predict_unauthorized", request_id=request_id)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="A valid X-API-Key header is required.",
            )
        started = time.perf_counter()
        try:
            sample = JobSample(
                gpu_count=payload.gpu_count,
                cpu_cores=payload.cpu_cores,
                memory_gb=payload.memory_gb,
                runtime_hours=payload.runtime_hours,
                priority=payload.priority,
                framework=payload.framework,
            )
            result = score(request.app.state.bundle, sample, repeats=_repeats())
        except Exception as exc:
            REQUESTS.labels(status="error", queue="none").inc()
            _log("predict_failed", request_id=request_id, error=type(exc).__name__)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="The request failed.",
            ) from None
        elapsed = time.perf_counter() - started
        LATENCY.observe(elapsed)
        queue_label = result.queue if result.queue in KNOWN_QUEUES else "unknown"
        REQUESTS.labels(status="ok", queue=queue_label).inc()
        _log(
            "predict",
            request_id=request_id,
            queue=result.queue,
            confidence=result.confidence,
            duration_seconds=round(elapsed, 4),
        )
        return PredictResponse(
            queue=result.queue,
            confidence=result.confidence,
            model_version=result.version,
            scores=result.scores,
        )

    return app


app = create_app()
