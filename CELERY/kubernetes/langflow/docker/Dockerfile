ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir "gunicorn>=21" "uvicorn[standard]>=0.30" "httptools" "uvloop" "celery[redis]>=5"

USER user
