#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

REMOTE="origin"
# Collects "<repo>|<title>|<url>" entries for every PR raised during the run,
# so we can print a consolidated summary at the end.
CREATED_PRS=()

update_products() {
  ensure_clone "$DOCKER_IMAGES_REPO" "--branch $RELEASE_BRANCH"
  pushd "$DOCKER_IMAGES_REPO" > /dev/null
  assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
  assert_clean_index "$DOCKER_IMAGES_REPO"
  git switch "${RELEASE_BRANCH}" && git pull
  assert_on_branch "$RELEASE_BRANCH"

  # Create the work branch from the release branch so changes go through a PR
  # rather than being pushed directly to the release branch.
  git switch -c "${WORK_BRANCH}"
  assert_on_branch "$WORK_BRANCH"

  echo "Pls manually bump the UBI base images in $DOCKER_IMAGES_REPO"
  echo 'Tip: I found the following images when searching for "registry.access.redhat.com/ubi" in Dockerfiles:'
  grep -r 'FROM registry.access.redhat.com/ubi' **/Dockerfile

  read -r -p "Press Enter once you have updated the UBI base images (or Ctrl+C to abort)... "

  # Pick up any edits the user made. Skip if they already committed themselves
  # or if they made no changes at all.
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Staging and committing UBI base image bumps..."
    git add --update
    git commit -m "chore: UBI base image bumps"
  fi

  assert_remote_exists "$REMOTE" "$DOCKER_IMAGES_REPO"
  raise_pr "$DOCKER_IMAGES_REPO" "chore: UBI base image bumps"

  echo
  echo "Check $DOCKER_IMAGES_REPO"
  popd > /dev/null
}

update_operator() {
  local operator="$1"
  echo ">>> Now working on ${operator}"

  ensure_clone "$operator" "--branch $RELEASE_BRANCH"
  pushd "${operator}" > /dev/null
  assert_cwd_is_repo "$operator"
  assert_clean_index "$operator"
  git switch "${RELEASE_BRANCH}" && git pull
  assert_on_branch "$RELEASE_BRANCH"

  # Create the work branch from the release branch so changes go through a PR
  # rather than being pushed directly to the release branch.
  git switch -c "${WORK_BRANCH}"
  assert_on_branch "$WORK_BRANCH"

  cargo update
  # cargo test # Will be done by CI and takes too long
  make regenerate-nix
  # We are explicitly not regenerating the CRDs, as we don't want CRD changes to sneak in.
  # We rather let the CI checks fail and inspect manually.
  git add Cargo.lock Cargo.nix
  git commit -m "chore: Rust dependency patch level updates"

  echo "FYI, these are the major/minor bumps we didn't do:"
  cargo +nightly -Z unstable-options update --breaking --dry-run

  assert_remote_exists "$REMOTE" "$operator"
  raise_pr "$operator" "chore: Rust dependency patch level updates"
  popd > /dev/null
}

update_repos() {
  local BASE_DIR="$1";
  cd "$BASE_DIR"

  case "$WHAT" in
    products) update_products ;;
    operators) for_each_operator update_operator ;;
    all)
      update_products
      for_each_operator update_operator
      ;;
  esac
}

raise_pr() {
  local REPOSITORY="$1";
  local PR_TITLE="$2";

  # Skip when nothing was committed on the work branch (e.g. products flow without manual edits)
  local COMMITS_AHEAD
  COMMITS_AHEAD=$(git rev-list --count "${RELEASE_BRANCH}..${WORK_BRANCH}")
  if [ "$COMMITS_AHEAD" -eq 0 ]; then
    echo "No commits on ${WORK_BRANCH} relative to ${RELEASE_BRANCH} for ${REPOSITORY}, skipping push and PR creation"
    return
  fi

  if $PUSH; then
    echo "Pushing ${WORK_BRANCH} to ${REPOSITORY}"
    git push -u "$REMOTE" "$WORK_BRANCH"
    echo "Creating PR ${WORK_BRANCH} -> ${RELEASE_BRANCH} on ${REPOSITORY}"
    local PR_URL
    PR_URL=$(gh pr create \
      --base "$RELEASE_BRANCH" \
      --head "$WORK_BRANCH" \
      --title "$PR_TITLE" \
      --body "Patch level maintenance updates for \`${RELEASE_BRANCH}\` (created by release-branch-hygiene.sh).")
    CREATED_PRS+=("${REPOSITORY}|${PR_TITLE}|${PR_URL}")
  else
    echo "Dry-run: not pushing ${WORK_BRANCH} or creating PR for ${REPOSITORY}"
    git push --dry-run -u "$REMOTE" "$WORK_BRANCH"
  fi
}

print_summary() {
  echo
  echo "================ PR Summary ================"
  if [ ${#CREATED_PRS[@]} -eq 0 ]; then
    if $PUSH; then
      echo "No PRs were created."
    else
      echo "Dry-run: no PRs were created (re-run with --push to actually open PRs)."
    fi
    return
  fi
  echo "Created ${#CREATED_PRS[@]} PR(s):"
  for entry in "${CREATED_PRS[@]}"; do
    IFS='|' read -r repo title url <<<"$entry"
    echo "  - ${repo}: ${title}"
    echo "      ${url}"
  done
}

# TODO: Consider moving validation (validate_release_base_version, validate_what) into parse_inputs
parse_inputs() {
  RELEASE_BASE="" # e.g., 26.3 (YY.M, no patch level)
  PUSH=false
  CLEANUP=false
  WHAT=""

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -b|--branch) RELEASE_BASE="$2"; shift ;;
          -w|--what) WHAT="$2"; shift ;;
          -p|--push) PUSH=true ;;
          -c|--cleanup) CLEANUP=true ;;
          *) echo "Unknown parameter passed: $1"; exit 1 ;;
      esac
      shift
  done

  RELEASE_BASE="$(strip_double_quotes "$RELEASE_BASE")"

  INITIAL_DIR="$PWD"
  derive_branch_vars "$RELEASE_BASE"
  # A single timestamp is shared across all repos in this run so the work
  # branches are easy to correlate.
  WORK_BRANCH="${RELEASE_BRANCH}-maintenance-$(date +%s)"

  echo "Settings: ${RELEASE_BRANCH}: Work branch: ${WORK_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

cleanup() {
  local BASE_DIR="$1";

  if $CLEANUP; then
    echo "Cleaning up..."
    rm -rf "$BASE_DIR"
  fi
}

main() {
  parse_inputs "$@"

  if [ -z "${RELEASE_BASE}" ]; then
    >&2 echo "Usage: release-branch-hygiene.sh -b <branch> [-p] [-c] [-w products|operators|all]"
    exit 1
  fi

  validate_release_base_version "$RELEASE_BASE"
  validate_what "$WHAT" "products" "operators" "all"
  check_common_dependencies

  ensure_temp_folder
  update_repos "$TEMP_RELEASE_FOLDER"
  cleanup "$TEMP_RELEASE_FOLDER"
  print_summary
}

main "$@"
