#!/usr/bin/env bash
set -euo pipefail

CREDS_FILE="${1:-dockerhub-creds.yml}"
CONTEXT="${2:-.}"
DOCKERFILE="${3:-docker/magic-stick-cli/Dockerfile}"
TAG_VERSION="${4:-latest}"

if [[ ! -f "$CREDS_FILE" ]]; then
    echo "Credentials file '$CREDS_FILE' not found." >&2
    exit 1
fi

if [[ "$TAG_VERSION" == "latest" && -f "VERSION" ]]; then
    TAG_VERSION="$(head -n 1 VERSION | tr -d '[:space:]')"
fi

USER=$(grep '^  username:' "$CREDS_FILE" | sed 's/^  username: //; s/^ *//; s/ *$//; s/^"//; s/"$//')
TOKEN=$(grep '^  token:' "$CREDS_FILE" | sed 's/^  token: //; s/^ *//; s/ *$//; s/^"//; s/"$//')

if [[ -z "${USER:-}" || -z "${TOKEN:-}" ]]; then
    echo "Docker Hub credentials incomplete in $CREDS_FILE" >&2
    exit 1
fi

echo "$TOKEN" | docker login -u "$USER" --password-stdin docker.io

REPO="${USER}/magic-stick-cli"
docker buildx build --push \
    --file "$DOCKERFILE" \
    --tag "${REPO}:${TAG_VERSION}" \
    --tag "${REPO}:latest" \
    "$CONTEXT"

echo "Pushed ${REPO}:${TAG_VERSION} and ${REPO}:latest"
