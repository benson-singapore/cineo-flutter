#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "error: run this helper inside a Git repository" >&2
  exit 1
}
cd "${ROOT_DIR}"

requested_tag=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      requested_tag="${2:-}"
      shift 2
      ;;
    -h|--help)
      printf '%s\n' \
        'Usage: git-release-context.sh [--tag TAG]' \
        'Print read-only Git evidence for the newest or selected release tag.'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

tags=()
while IFS= read -r tag_name; do
  [[ -n "${tag_name}" ]] && tags+=("${tag_name}")
done < <(git tag --sort=-v:refname)
if [[ ${#tags[@]} -eq 0 ]]; then
  echo "error: no Git tags found" >&2
  exit 1
fi

tag="${requested_tag:-${tags[0]}}"
tag_index=-1
for index in "${!tags[@]}"; do
  if [[ "${tags[index]}" == "${tag}" ]]; then
    tag_index="${index}"
    break
  fi
done
if [[ "${tag_index}" -lt 0 ]]; then
  echo "error: tag not found: ${tag}" >&2
  exit 1
fi

previous_tag=""
if [[ $((tag_index + 1)) -lt ${#tags[@]} ]]; then
  previous_tag="${tags[$((tag_index + 1))]}"
fi

tag_commit="$(git rev-list -n 1 "${tag}")"
tag_date="$(git for-each-ref --format='%(creatordate:iso-strict)' "refs/tags/${tag}")"
if [[ -z "${tag_date}" ]]; then
  tag_date="$(git show -s --format='%aI' "${tag_commit}")"
fi
tag_subject="$(git show -s --format='%s' "${tag_commit}")"

printf 'TAG=%s\n' "${tag}"
printf 'TAG_COMMIT=%s\n' "${tag_commit}"
printf 'TAG_DATE=%s\n' "${tag_date}"
printf 'TAG_SUBJECT=%s\n' "${tag_subject}"
printf 'PREVIOUS_TAG=%s\n' "${previous_tag}"
if [[ -n "${previous_tag}" ]]; then
  printf 'RANGE=%s..%s\n' "${previous_tag}" "${tag}"
  printf 'INITIAL_RELEASE=false\n'
else
  printf 'RANGE=all history reachable from %s\n' "${tag}"
  printf 'INITIAL_RELEASE=true\n'
fi

printf '\n[COMMITS]\n'
if [[ -n "${previous_tag}" ]]; then
  git log --format='%h%x09%aI%x09%s' "${previous_tag}..${tag}"
else
  git log --format='%h%x09%aI%x09%s' "${tag}"
fi

printf '\n[STAT]\n'
if [[ -n "${previous_tag}" ]]; then
  git diff --stat "${previous_tag}..${tag}"
else
  empty_tree="4b825dc642cb6eb9a060e54bf8d69288fbee4904"
  git diff --stat "${empty_tree}" "${tag}"
fi
