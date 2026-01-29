#!/usr/bin/env bats
# Tests for provider auto-detection

load 'test_helper'

setup() {
  setup_mocks
}

teardown() {
  teardown_mocks
}

@test "detects GCP Cloud Run from Dockerfile" {
  mkdir -p "$PROJECT_DIR"
  touch "$PROJECT_DIR/Dockerfile"

  source "$PROJECT_ROOT/providers/gcp-cloud-run.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects GCP Cloud Run from service.yaml" {
  mkdir -p "$PROJECT_DIR"
  touch "$PROJECT_DIR/service.yaml"

  source "$PROJECT_ROOT/providers/gcp-cloud-run.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Firebase Functions from firebase.json" {
  mkdir -p "$PROJECT_DIR"
  echo '{}' > "$PROJECT_DIR/firebase.json"

  source "$PROJECT_ROOT/providers/gcp-firebase-functions.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Vercel from vercel.json" {
  mkdir -p "$PROJECT_DIR"
  echo '{}' > "$PROJECT_DIR/vercel.json"

  source "$PROJECT_ROOT/providers/vercel.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Cloudflare Workers from wrangler.toml" {
  mkdir -p "$PROJECT_DIR"
  echo 'name = "my-worker"' > "$PROJECT_DIR/wrangler.toml"

  source "$PROJECT_ROOT/providers/cloudflare-workers.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Railway from railway.json" {
  mkdir -p "$PROJECT_DIR"
  echo '{}' > "$PROJECT_DIR/railway.json"

  source "$PROJECT_ROOT/providers/railway.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Kubernetes from k8s/deployment.yaml" {
  mkdir -p "$PROJECT_DIR/k8s"
  touch "$PROJECT_DIR/k8s/deployment.yaml"

  source "$PROJECT_ROOT/providers/kubernetes.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Kubernetes from kustomization.yaml" {
  mkdir -p "$PROJECT_DIR"
  touch "$PROJECT_DIR/kustomization.yaml"

  source "$PROJECT_ROOT/providers/kubernetes.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects AWS Lambda from serverless.yml" {
  mkdir -p "$PROJECT_DIR"
  echo 'service: my-service' > "$PROJECT_DIR/serverless.yml"

  source "$PROJECT_ROOT/providers/aws-lambda.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects AWS ECS from task-definition.json" {
  mkdir -p "$PROJECT_DIR"
  echo '{}' > "$PROJECT_DIR/task-definition.json"

  source "$PROJECT_ROOT/providers/aws-ecs.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Azure Functions from host.json + local.settings.json" {
  mkdir -p "$PROJECT_DIR"
  echo '{}' > "$PROJECT_DIR/host.json"
  echo '{}' > "$PROJECT_DIR/local.settings.json"

  source "$PROJECT_ROOT/providers/azure-functions.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Heroku from Procfile" {
  mkdir -p "$PROJECT_DIR"
  echo 'web: node server.js' > "$PROJECT_DIR/Procfile"

  source "$PROJECT_ROOT/providers/heroku.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Fly.io from fly.toml" {
  mkdir -p "$PROJECT_DIR"
  echo 'app = "my-app"' > "$PROJECT_DIR/fly.toml"

  source "$PROJECT_ROOT/providers/flyio.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Render from render.yaml" {
  mkdir -p "$PROJECT_DIR"
  echo 'services: []' > "$PROJECT_DIR/render.yaml"

  source "$PROJECT_ROOT/providers/render.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "detects Netlify from netlify.toml" {
  mkdir -p "$PROJECT_DIR"
  echo '[build]' > "$PROJECT_DIR/netlify.toml"

  source "$PROJECT_ROOT/providers/netlify.sh"
  run detect
  [ "$status" -eq 0 ]
}

@test "does not detect Cloud Functions when firebase.json exists" {
  mkdir -p "$PROJECT_DIR"
  echo '{}' > "$PROJECT_DIR/firebase.json"
  touch "$PROJECT_DIR/.gcloudignore"
  touch "$PROJECT_DIR/index.js"

  source "$PROJECT_ROOT/providers/gcp-cloud-functions.sh"
  run detect
  [ "$status" -eq 1 ]  # Should NOT detect - firebase provider takes precedence
}
