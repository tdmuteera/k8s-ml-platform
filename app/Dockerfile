FROM python:3.12-slim AS build

ENV PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY src ./src
ENV PYTHONPATH=/build/src
RUN python -m inference.train --output /opt/model/model.joblib

FROM python:3.12-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:${PATH}" \
    PYTHONPATH=/app/src \
    BAKED_MODEL_PATH=/opt/model/model.joblib \
    MODEL_PATH=/models/model.joblib \
    HOME=/tmp \
    XDG_CACHE_HOME=/tmp \
    JOBLIB_TEMP_FOLDER=/tmp

RUN apt-get update \
    && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 1000 --create-home --shell /usr/sbin/nologin app \
    && mkdir -p /opt/model /models \
    && chown -R app:app /opt/model /models

COPY --from=build /opt/venv /opt/venv
COPY --from=build /opt/model/model.joblib /opt/model/model.joblib
COPY src /app/src

USER 1000:1000
WORKDIR /app
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz')"]

CMD ["uvicorn", "inference.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1"]
