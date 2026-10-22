"""Shared fixtures for the inference service tests."""

import pytest
from fastapi.testclient import TestClient

from inference.main import create_app
from inference.train import build_bundle, save_bundle


@pytest.fixture(scope="session")
def bundle_path(tmp_path_factory):
    path = tmp_path_factory.mktemp("model") / "model.joblib"
    save_bundle(build_bundle(), path)
    return path


@pytest.fixture
def client(bundle_path, monkeypatch):
    monkeypatch.setenv("MODEL_PATH", str(bundle_path))
    monkeypatch.setenv("API_KEY", "test-key")
    monkeypatch.setenv("PREDICT_REPEATS", "1")
    with TestClient(create_app()) as test_client:
        yield test_client
