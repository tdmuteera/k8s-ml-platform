"""Tests for the volume seed helper."""

from pathlib import Path

from inference.seed import seed_model


def test_seed_copies_and_then_leaves_an_existing_file(tmp_path: Path):
    baked = tmp_path / "baked.joblib"
    baked.write_bytes(b"model")
    dest = tmp_path / "models" / "model.joblib"
    assert seed_model(baked, dest) is True
    assert dest.read_bytes() == b"model"
    baked.write_bytes(b"newer")
    assert seed_model(baked, dest) is False
    assert dest.read_bytes() == b"model"


def test_seed_rejects_a_missing_baked_model(tmp_path: Path):
    try:
        seed_model(tmp_path / "missing.joblib", tmp_path / "model.joblib")
    except FileNotFoundError:
        return
    raise AssertionError("A missing baked model should fail.")
