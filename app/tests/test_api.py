"""HTTP tests for the inference service."""

import pytest

CPU = {
    "gpu_count": 0,
    "cpu_cores": 4,
    "memory_gb": 8,
    "runtime_hours": 24,
    "priority": "low",
    "framework": "other",
}
GPU = {
    "gpu_count": 2,
    "cpu_cores": 16,
    "memory_gb": 64,
    "runtime_hours": 2,
    "priority": "high",
    "framework": "pytorch",
}
PREEMPTIBLE = {
    "gpu_count": 4,
    "cpu_cores": 8,
    "memory_gb": 32,
    "runtime_hours": 24,
    "priority": "low",
    "framework": "jax",
}


def test_health_ready_and_root(client):
    assert client.get("/healthz").json() == {"status": "ok"}
    assert client.get("/readyz").status_code == 200
    body = client.get("/").json()
    assert body["service"] == "ml-inference"
    assert body["model_version"] == "1"


def test_predict_requires_a_valid_key(client):
    missing = client.post("/predict", json=CPU)
    assert missing.status_code == 401
    wrong = client.post("/predict", json=CPU, headers={"X-API-Key": "nope"})
    assert wrong.status_code == 401


def test_predict_queues(client):
    headers = {"X-API-Key": "test-key"}
    assert client.post("/predict", json=CPU, headers=headers).json()["queue"] == "cpu"
    assert client.post("/predict", json=GPU, headers=headers).json()["queue"] == "gpu"
    preemptible = client.post("/predict", json=PREEMPTIBLE, headers=headers).json()
    assert preemptible["queue"] == "gpu-preemptible"
    assert set(preemptible["scores"]) == {"cpu", "gpu", "gpu-preemptible"}
    assert preemptible["model_version"] == "1"


def test_validation_error(client):
    response = client.post(
        "/predict",
        json={**CPU, "gpu_count": 99},
        headers={"X-API-Key": "test-key"},
    )
    assert response.status_code == 422


def test_metrics_include_the_request_counter(client):
    client.post("/predict", json=CPU, headers={"X-API-Key": "test-key"})
    body = client.get("/metrics").text
    assert "inference_requests_total" in body
    assert "inference_model_info" in body


def test_missing_model_fails_startup(monkeypatch, tmp_path):
    monkeypatch.setenv("MODEL_PATH", str(tmp_path / "missing.joblib"))
    monkeypatch.setenv("API_KEY", "test-key")
    from fastapi.testclient import TestClient

    from inference.main import create_app

    with pytest.raises(FileNotFoundError):
        with TestClient(create_app()):
            pass
