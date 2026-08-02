# Build from the REPO ROOT so the canonical ml/ package is in context:
#   docker build -f backend/Dockerfile .
FROM python:3.12-slim

WORKDIR /app

# System deps for MediaPipe (bookworm: libgl1, not libgl1-mesa-glx)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Canonical pipeline (includes ml/ml/swim_tcn.pt weights)
COPY ml/ ml/
COPY backend/main.py .

ENV PYTHONPATH=/app/ml
EXPOSE 8080

CMD ["python", "main.py"]

# Fail the image build if model weights are missing — a server must
# never boot weightless (startup would fail) or train inside a request.
RUN test -f ml/ml/swim_tcn.pt || (echo "ERROR: ml/ml/swim_tcn.pt missing from build context" && exit 1)
