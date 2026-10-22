"""Copy the baked model onto the persistent volume when the volume is empty."""

from __future__ import annotations

import json
import os
import shutil
from pathlib import Path


def seed_model(baked: Path, dest: Path) -> bool:
    """Copy ``baked`` to ``dest`` when dest is missing or empty.

    Returns True when a copy was made.
    """

    if not baked.is_file():
        raise FileNotFoundError(f"Baked model not found: {baked}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.is_file() and dest.stat().st_size > 0:
        return False
    shutil.copyfile(baked, dest)
    return True


def main() -> None:
    baked = Path(os.environ.get("BAKED_MODEL_PATH", "/opt/model/model.joblib"))
    dest = Path(os.environ.get("MODEL_PATH", "/models/model.joblib"))
    copied = seed_model(baked, dest)
    print(
        json.dumps({"event": "seed_model", "copied": copied, "path": str(dest)}),
        flush=True,
    )


if __name__ == "__main__":
    main()
