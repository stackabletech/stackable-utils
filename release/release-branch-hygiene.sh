#!/usr/bin/env bash
#
# See README.adoc
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Temp file to collect PR entries across subshells.
# Each line: "<repo>|<title>|<url>"
PR_LOG_FILE=""

update_products() {
  ( # subshell to isolate cd
    ensure_clone "$DOCKER_IMAGES_REPO"
    cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

    require_release_branch "$DOCKER_IMAGES_REPO"
    git switch "${RELEASE_BRANCH}" && git pull

    git switch -c "${WORK_BRANCH}"

    echo "Pls manually bump the UBI base images in $TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
    echo 'Tip: I found the following images when searching for "registry.access.redhat.com/ubi" in Dockerfiles:'
    grep -r 'FROM registry.access.redhat.com/ubi' **/Dockerfile

    read -r -p "Press Enter once you have updated the UBI base images (or Ctrl+C to abort)... "

    if ! git diff --quiet || ! git diff --cached --quiet; then
      echo "Staging and committing UBI base image bumps..."
      git add --update
      git commit -m "chore: UBI base image bumps"
    fi

    raise_pr "$DOCKER_IMAGES_REPO" "chore: UBI base image bumps"

    echo
    echo "Check $TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  )
}

update_single_operator() {
  local operator="$1"
  ( # subshell to isolate cd
    echo ">>> Now working on ${operator}"

    ensure_clone "$operator"
    cd "$TEMP_RELEASE_FOLDER/${operator}"

    require_release_branch "$operator"
    git switch "${RELEASE_BRANCH}" && git pull

    git switch -c "${WORK_BRANCH}"

    cargo update
    make regenerate-nix

    git add Cargo.lock Cargo.nix
    git diff --cached --quiet && echo "No changes to commit for ${operator}" && return
    git commit -m "chore: Rust dependency patch level updates"

    echo "FYI, these are the major/minor bumps we didn't do:"
    cargo +nightly -Z unstable-options update --breaking --dry-run

    raise_pr "$operator" "chore: Rust dependency patch level updates"
  )
}

update_repos() {
  if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    update_products
  fi
  if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    for_each_operator update_single_operator
  fi
}

raise_pr() {
  local repo="$1"
  local pr_title="$2"

  local commits_ahead
  commits_ahead=$(git rev-list --count "${RELEASE_BRANCH}..${WORK_BRANCH}")
  if [ "$commits_ahead" -eq 0 ]; then
    echo "No commits on ${WORK_BRANCH} relative to ${RELEASE_BRANCH} for ${repo}, skipping push and PR creation"
    return
  fi

  if $PUSH; then
    echo "Pushing ${WORK_BRANCH} to ${repo}"
    git push -u "$REMOTE" "$WORK_BRANCH"
    echo "Creating PR ${WORK_BRANCH} -> ${RELEASE_BRANCH} on ${repo}"
    local pr_url
    pr_url=$(gh pr create \
      --base "$RELEASE_BRANCH" \
      --head "$WORK_BRANCH" \
      --title "$pr_title" \
      --body "Patch level maintenance updates for \`${RELEASE_BRANCH}\` (created by release-branch-hygiene.sh).")
    echo "${repo}|${pr_title}|${pr_url}" >> "$PR_LOG_FILE"
  else
    echo "Dry-run: not pushing ${WORK_BRANCH} or creating PR for ${repo}"
    git push --dry-run -u "$REMOTE" "$WORK_BRANCH"
  fi
}

print_summary() {
  echo
  echo "================ PR Summary ================"
  if [ ! -s "$PR_LOG_FILE" ]; then
    if $PUSH; then
      echo "No PRs were created."
    else
      echo "Dry-run: no PRs were created (re-run with --push to actually open PRs)."
    fi
    return
  fi
  local count
  count=$(wc -l < "$PR_LOG_FILE")
  echo "Created ${count} PR(s):"
  while IFS='|' read -r repo title url; do
    echo "  - ${repo}: ${title}"
    echo "      ${url}"
  done < "$PR_LOG_FILE"
}

parse_inputs() {
  RELEASE=""
  PUSH=false
  CLEANUP=false
  WHAT=""

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -b|--branch) RELEASE="$2"; shift ;;
          -w|--what) WHAT="$2"; shift ;;
          -p|--push) PUSH=true ;;
          -c|--cleanup) CLEANUP=true ;;
          *) >&2 echo "Unknown parameter passed: $1"; exit 1 ;;
      esac
      shift
  done

  RELEASE="$(strip_quotes "$RELEASE")"

  INITIAL_DIR="$PWD"
  derive_branch_vars "$RELEASE"
  WORK_BRANCH="${RELEASE_BRANCH}-maintenance-$(date +%s)"

  echo "Settings: ${RELEASE_BRANCH}: Work branch: ${WORK_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
  parse_inputs "$@"

  if [ -z "${RELEASE}" ]; then
    >&2 echo "Usage: release-branch-hygiene.sh -b <branch> [-p] [-c] [-w products|operators|all]"
    exit 1
  fi

  validate_what "$WHAT" products operators all
  validate_release "$RELEASE"

  ensure_temp_folder
  check_basic_dependencies

  PR_LOG_FILE=$(mktemp)
  trap 'rm -f "$PR_LOG_FILE"' EXIT

  update_repos
  cleanup
  print_summary
}

main "$@"
