#!/bin/bash
# Deploy the SwimCoach backend to Google Cloud Run.
# Prerequisites: gcloud CLI authenticated, project set.
set -e

cd "$(dirname "$0")/.."   # repo root — Docker context must include ml/

PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
SERVICE_NAME="swim-analyzer"
IMAGE="gcr.io/$PROJECT_ID/$SERVICE_NAME"

echo "Building and deploying to Cloud Run..."
echo "Project: $PROJECT_ID | Region: $REGION"

gcloud builds submit --config backend/cloudbuild.yaml .

gcloud run deploy "$SERVICE_NAME" \
  --image "$IMAGE" \
  --region "$REGION" \
  --memory 2Gi \
  --cpu 2 \
  --timeout 300 \
  --allow-unauthenticated

echo "Deployed."
