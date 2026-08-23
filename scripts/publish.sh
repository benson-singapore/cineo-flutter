#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

REQUESTED_VERSION="${VERSION:-}"
VERSION="${REQUESTED_VERSION}"
REQUESTED_BUILD_NUMBER="${BUILD_NUMBER:-}"
BUILD_NUMBER="${REQUESTED_BUILD_NUMBER}"
REBUILD="${REBUILD:-0}"
BRANCH="${BRANCH:-main}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: VERSION must use X.Y.Z, for example 1.2.0" >&2
  exit 2
fi
if [[ -n "${BUILD_NUMBER}" && ! "${BUILD_NUMBER}" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: BUILD_NUMBER must be a positive integer" >&2
  exit 2
fi
if [[ "${REBUILD}" != "0" && "${REBUILD}" != "1" ]]; then
  echo "error: REBUILD must be 0 or 1" >&2
  exit 2
fi

if [[ "$(git branch --show-current)" != "${BRANCH}" ]]; then
  echo "error: checkout branch '${BRANCH}' before running make publish" >&2
  exit 1
fi

# A publish may include the intentional VERSION edit in Makefile. All other
# changes must already be committed so the artifact represents a known revision.
dirty_paths="$(git status --porcelain=v1 | sed -E 's/^.. //; s/ -> .*//')"
while IFS= read -r path; do
  [[ -z "${path}" ]] && continue
  if [[ "${path}" != "Makefile" ]]; then
    if [[ "${path}" != pubspec.yaml && "${path}" != docs/update/*.md ]]; then
      echo "error: uncommitted change found outside Makefile, pubspec.yaml, or docs/update: ${path}" >&2
      echo "Commit or remove it before running make publish." >&2
      exit 1
    fi
  fi
done <<< "${dirty_paths}"

makefile_stash=""
if ! git diff --quiet -- Makefile || ! git diff --cached --quiet -- Makefile; then
  makefile_stash="publish-version-$(date +%s)"
  git stash push --quiet --keep-index --message "${makefile_stash}" -- Makefile
fi

restore_makefile() {
  if [[ -n "${makefile_stash}" ]]; then
    git stash pop --quiet || {
      echo "error: could not restore the edited Makefile after syncing Git." >&2
      exit 1
    }
  fi
}
trap restore_makefile EXIT

git fetch origin "${BRANCH}" --tags
git pull --rebase origin "${BRANCH}"

# Restore the user's VERSION line before comparing it with pubspec.yaml.
if [[ -n "${makefile_stash}" ]]; then
  git stash pop --quiet
  makefile_stash=""
  trap - EXIT
else
  # When no version was explicitly requested, use the version from the newly
  # synced branch instead of a value expanded by make before the pull.
  if [[ -z "${REQUESTED_VERSION}" ]]; then
    VERSION="$(perl -ne 'if (/^VERSION\s*:=\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$/) { print "$1\n" }' Makefile)"
  fi
  if [[ -z "${REQUESTED_BUILD_NUMBER}" ]]; then
    BUILD_NUMBER="$(perl -ne 'if (/^BUILD_NUMBER\s*:=\s*([1-9][0-9]*)\s*$/) { print "$1\n" }' Makefile)"
  fi
fi

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: VERSION must use X.Y.Z, for example 1.2.0" >&2
  exit 2
fi

current_version="$(perl -ne 'if (/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$/) { print "$1 $2\n" }' pubspec.yaml)"
if [[ -z "${current_version}" ]]; then
  echo "error: cannot read version from pubspec.yaml" >&2
  exit 1
fi
read -r current_name current_build <<<"${current_version}"
if [[ -z "${BUILD_NUMBER}" ]]; then
  BUILD_NUMBER="${current_build}"
fi
if [[ ! "${BUILD_NUMBER}" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: BUILD_NUMBER must be a positive integer" >&2
  exit 2
fi

if [[ "${current_name}" != "${VERSION}" || "${current_build}" != "${BUILD_NUMBER}" ]]; then
  ./scripts/update_version.sh --version "${VERSION}" --build-number "${BUILD_NUMBER}"
fi

TAG="v${VERSION}"
tag_exists="false"
if git rev-parse --verify --quiet "refs/tags/${TAG}" >/dev/null || \
   git ls-remote --exit-code --quiet origin "refs/tags/${TAG}" >/dev/null 2>&1; then
  tag_exists="true"
fi
if [[ "${tag_exists}" == "true" && "${REBUILD}" != "1" ]]; then
  echo "error: tag ${TAG} already exists; use make publish REBUILD=1 to rebuild it" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  git add Makefile pubspec.yaml docs/update
  git commit -m "chore: publish Cineo ${VERSION}"
fi

# Push the newest branch revision first, then create or deliberately move the version tag.
git push origin "${BRANCH}"
if [[ "${tag_exists}" == "true" ]]; then
  git tag -fa "${TAG}" -m "Cineo ${VERSION}" HEAD
  git push origin "refs/tags/${TAG}" --force
else
  git tag -a "${TAG}" -m "Cineo ${VERSION}" HEAD
  git push origin "refs/tags/${TAG}"
fi

echo "Published ${TAG}. GitHub Actions will build Android APK and unsigned iOS IPA from this tag."
