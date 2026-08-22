#!/usr/bin/env bash
set -euo pipefail

WORKFLOW="${WORKFLOW:-cineo-build.yml}"
REF="${REF:-main}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
REPOSITORY="${GITHUB_REPOSITORY:-}"

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "error: GH_TOKEN is required to trigger GitHub Actions" >&2
  echo "Create a GitHub token with Actions: write permission and run: make dispatch GH_TOKEN=..." >&2
  exit 1
fi

if [[ -z "${REPOSITORY}" ]]; then
  remote="$(git config --get remote.origin.url || true)"
  REPOSITORY="$(printf '%s' "${remote}" | perl -pe 's#^git@github.com:##; s#^https://github.com/##; s#\.git$##')"
fi
if [[ -z "${REPOSITORY}" || "${REPOSITORY}" == "git@github.com:" ]]; then
  echo "error: cannot determine GitHub repository; set GITHUB_REPOSITORY=owner/repo" >&2
  exit 1
fi

if [[ -z "${VERSION}" ]]; then
  VERSION="$(perl -ne 'if (/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$/) { print "$1\n" }' pubspec.yaml)"
fi
if [[ -z "${BUILD_NUMBER}" ]]; then
  BUILD_NUMBER="$(perl -ne 'if (/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$/) { print "$2\n" }' pubspec.yaml)"
fi

payload="$(VERSION="${VERSION}" BUILD_NUMBER="${BUILD_NUMBER}" REF="${REF}" python3 - <<'PY'
import json
import os

print(json.dumps({
    "ref": os.environ["REF"],
    "inputs": {
        "version": os.environ["VERSION"],
        "build_number": os.environ["BUILD_NUMBER"],
    },
}))
PY
)"

curl --fail --silent --show-error \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GH_TOKEN}" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/repos/${REPOSITORY}/actions/workflows/${WORKFLOW}/dispatches" \
  -d "${payload}"

echo "Triggered ${WORKFLOW} for ${REPOSITORY}@${REF} (${VERSION}+${BUILD_NUMBER})"
