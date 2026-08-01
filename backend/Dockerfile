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
