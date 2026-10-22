#!/usr/bin/env python3
"""Send concurrent prediction traffic and report whether the autoscaler adds pods."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

PAYLOADS = [
    {
        "gpu_count": 0,
        "cpu_cores": 4,
        "memory_gb": 8,
        "runtime_hours": 1,
        "priority": "normal",
        "framework": "other",
    },
    {
        "gpu_count": 2,
        "cpu_cores": 16,
        "memory_gb": 64,
        "runtime_hours": 2,
        "priority": "high",
        "framework": "pytorch",
    },
    {
        "gpu_count": 4,
        "cpu_cores": 8,
        "memory_gb": 32,
        "runtime_hours": 24,
        "priority": "low",
        "framework": "jax",
    },
]


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = round((pct / 100) * (len(ordered) - 1))
    return ordered[index]


def kubectl(*args: str) -> subprocess.CompletedProcess[str]:
    binary = shutil.which("kubectl")
    if binary is None:
        raise SystemExit("kubectl is not on PATH. Run make tools and try again.")
    return subprocess.run([binary, *args], check=False, capture_output=True, text=True)


def wait_for_metrics(namespace: str) -> None:
    deadline = time.time() + 180
    while time.time() < deadline:
        result = kubectl("top", "pods", "-n", namespace, "--no-headers")
        if result.returncode == 0 and any(token.endswith("m") for token in result.stdout.split()):
            print(result.stdout.strip())
            return
        time.sleep(5)
    print("Pod metrics are not available yet. The load test will continue.")


def current_replicas(namespace: str) -> int | None:
    result = kubectl(
        "get",
        "hpa",
        "inference",
        "-n",
        namespace,
        "-o",
        "jsonpath={.status.currentReplicas}",
    )
    text = result.stdout.strip()
    if result.returncode != 0 or not text.isdigit():
        return None
    return int(text)


def main() -> int:
    base = os.environ.get("API_URL", "http://127.0.0.1:18080").rstrip("/")
    api_key = os.environ.get("API_KEY", "")
    namespace = os.environ.get("NAMESPACE", "ml-inference")
    seconds = int(os.environ.get("LOAD_SECONDS", "120"))
    workers = int(os.environ.get("LOAD_CONCURRENCY", "8"))
    if not api_key:
        raise SystemExit("API_KEY is empty. Run this target with make load.")

    print(f"Waiting for metrics in namespace {namespace}.")
    wait_for_metrics(namespace)
    print(f"Sending load to {base}/predict for {seconds} seconds with {workers} workers.")

    latencies: list[float] = []
    errors = 0
    lock = threading.Lock()
    stop = time.time() + seconds
    max_replicas = current_replicas(namespace) or 1
    counter = 0

    def one_request() -> None:
        nonlocal errors, counter
        with lock:
            index = counter
            counter += 1
        payload = PAYLOADS[index % len(PAYLOADS)]
        request = urllib.request.Request(
            f"{base}/predict",
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json", "X-API-Key": api_key},
            method="POST",
        )
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                response.read()
                if response.status != 200:
                    raise RuntimeError(f"HTTP {response.status}")
        except Exception:
            with lock:
                errors += 1
            return
        elapsed = time.perf_counter() - started
        with lock:
            latencies.append(elapsed)

    def worker() -> None:
        while time.time() < stop:
            one_request()

    def poll() -> None:
        nonlocal max_replicas
        while time.time() < stop:
            replicas = current_replicas(namespace)
            if replicas is not None:
                max_replicas = max(max_replicas, replicas)
            time.sleep(10)

    poller = threading.Thread(target=poll, daemon=True)
    poller.start()
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(worker) for _ in range(workers)]
        while time.time() < stop:
            time.sleep(10)
            with lock:
                done = len(latencies)
                failed = errors
            print(f"requests_ok={done} errors={failed} replicas={max_replicas}")
        for future in futures:
            future.result()
    poller.join(timeout=1)

    total = len(latencies) + errors
    error_rate = (errors / total) if total else 1
    print(
        json.dumps(
            {
                "ok": len(latencies),
                "errors": errors,
                "error_rate": round(error_rate, 4),
                "p50_seconds": round(percentile(latencies, 50), 4),
                "p95_seconds": round(percentile(latencies, 95), 4),
                "max_replicas": max_replicas,
            }
        )
    )
    described = kubectl("get", "hpa", "-n", namespace)
    print(described.stdout)
    if error_rate > 0.05 or not latencies:
        print("The service did not answer enough requests.")
        return 1
    if max_replicas < 2:
        print("The autoscaler did not add a pod. Check kubectl top pods and the HPA events.")
        described = kubectl("describe", "hpa", "inference", "-n", namespace)
        print(described.stdout)
        print(described.stderr)
        return 2
    print("The autoscaler added pods.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
