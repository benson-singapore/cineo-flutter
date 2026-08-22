#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBSPEC="${ROOT_DIR}/pubspec.yaml"

usage() {
  echo "Usage: $0 --version X.Y.Z[+BUILD] | --bump major|minor|patch [--build-number N]" >&2
  exit 2
}

version=""
bump=""
build_number=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) version="${2:-}"; shift 2 ;;
    --bump) bump="${2:-}"; shift 2 ;;
    --build-number) build_number="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

if [[ -n "${version}" && -n "${bump}" ]]; then
  echo "error: use --version or --bump, not both" >&2
  exit 2
fi

current="$(perl -ne 'if (/^version: ([0-9]+\.[0-9]+\.[0-9]+)(\+[0-9]+)?$/) { print "$1 $2\n" }' "${PUBSPEC}")"
if [[ -z "${current}" ]]; then
  echo "error: cannot read version from pubspec.yaml" >&2
  exit 1
fi
read -r current_name current_suffix <<<"${current}"
current_build="${current_suffix#+}"
current_build="${current_build:-1}"

if [[ -n "${bump}" ]]; then
  IFS=. read -r major minor patch <<<"${current_name}"
  case "${bump}" in
    major) major=$((major + 1)); minor=0; patch=0 ;;
    minor) minor=$((minor + 1)); patch=0 ;;
    patch) patch=$((patch + 1)) ;;
    *) echo "error: bump must be major, minor, or patch" >&2; exit 2 ;;
  esac
  version="${major}.${minor}.${patch}"
  build_number=$((current_build + 1))
fi

if [[ -z "${version}" ]]; then
  usage
fi

if [[ "${version}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(\+([0-9]+))?$ ]]; then
  version_name="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  version_build="${BASH_REMATCH[5]:-${build_number:-${current_build}}}"
else
  echo "error: version must be X.Y.Z or X.Y.Z+BUILD" >&2
  exit 2
fi

if [[ -n "${build_number}" && ! "${build_number}" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: build number must be a positive integer" >&2
  exit 2
fi
if [[ -n "${build_number}" ]]; then version_build="${build_number}"; fi

if [[ ! "${version_build}" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: build number must be a positive integer" >&2
  exit 2
fi

VERSION_LINE="version: ${version_name}+${version_build}"
VERSION_LINE="${VERSION_LINE}" PUBSPEC="${PUBSPEC}" python3 - <<'PY'
import os
import re
from pathlib import Path

pubspec = Path(os.environ["PUBSPEC"])
text = pubspec.read_text()
replacement = os.environ["VERSION_LINE"]
updated, count = re.subn(r"^version: .*?$", replacement, text, count=1, flags=re.MULTILINE)
if count != 1:
    raise SystemExit("error: pubspec.yaml must contain exactly one version line")
pubspec.write_text(updated)
PY

echo "Updated ${PUBSPEC} to ${version_name}+${version_build}"
