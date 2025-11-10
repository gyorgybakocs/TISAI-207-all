ARG IMAGE_FROM_REGISTRY
FROM ${IMAGE_FROM_REGISTRY}

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# First: Install pip into venv using ensurepip
RUN /app/.venv/bin/python -m ensurepip --upgrade || \
    curl -sS https://bootstrap.pypa.io/get-pip.py | /app/.venv/bin/python

# Now pip is available in venv, install packages
RUN /app/.venv/bin/python -m pip install --no-cache-dir \
    "gunicorn>=21" \
    "uvicorn[standard]>=0.30" \
    "httptools" \
    "uvloop" \
    "celery[redis]>=5"

# Verify
RUN /app/.venv/bin/python -c "import celery; print('Celery OK:', celery.__version__)"

USER user