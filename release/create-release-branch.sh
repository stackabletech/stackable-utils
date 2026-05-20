#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

REMOTE="origin"

update_products() {
  ensure_clone "$DOCKER_IMAGES_REPO" "--branch main"
  pushd "$DOCKER_IMAGES_REPO" > /dev/null
  assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
  assert_clean_index "$DOCKER_IMAGES_REPO"
  git pull && git switch "${RELEASE_BRANCH}" 2> /dev/null || git switch -c "${RELEASE_BRANCH}"
  assert_on_branch "$RELEASE_BRANCH"

  assert_remote_exists "$REMOTE" "$DOCKER_IMAGES_REPO"
  push_branch "$DOCKER_IMAGES_REPO"

  echo
  echo "Check $BASE_DIR/$DOCKER_IMAGES_REPO"
  popd > /dev/null
}

update_operator() {
  local operator="$1"
  ensure_clone "$operator" "--branch main"
  pushd "${operator}" > /dev/null
  assert_cwd_is_repo "$operator"
  assert_clean_index "$operator"
  git pull && git switch "${RELEASE_BRANCH}" 2> /dev/null || git switch -c "${RELEASE_BRANCH}"
  assert_on_branch "$RELEASE_BRANCH"
  assert_remote_exists "$REMOTE" "$operator"
  push_branch "$operator"
  popd > /dev/null
}

update_demos() {
  ensure_clone "$DEMOS_REPO" "--branch main"
  pushd "$DEMOS_REPO" > /dev/null
  assert_cwd_is_repo "$DEMOS_REPO"
  assert_clean_index "$DEMOS_REPO"
  git pull && git switch "${RELEASE_BRANCH}" 2> /dev/null || git switch -c "${RELEASE_BRANCH}"
  assert_on_branch "$RELEASE_BRANCH"

  # Search and replace known references to stackableRelease, container images, branch references.
  # https://github.com/stackabletech/demos/blob/main/.scripts/update_refs.sh
  .scripts/update_refs.sh commit

  assert_remote_exists "$REMOTE" "$DEMOS_REPO"
  push_branch "$DEMOS_REPO"
  popd > /dev/null
}

update_repos() {
  local BASE_DIR="$1";
  cd "$BASE_DIR"

  case "$WHAT" in
    products) update_products ;;
    operators) for_each_operator update_operator ;;
    demos) update_demos ;;
    all)
      update_products
      for_each_operator update_operator
      update_demos
      ;;
  esac
}

push_branch() {
  local REPOSITORY="$1";
  if $PUSH; then
    echo "Pushing changes to $REPOSITORY"
    git push -u "$REMOTE" "$RELEASE_BRANCH"
  else
    echo "Dry-run: not pushing changes to $REPOSITORY"
    git push --dry-run -u "$REMOTE" "$RELEASE_BRANCH"
  fi
}

cleanup() {
  local BASE_DIR="$1";

  if $CLEANUP; then
    echo "Cleaning up..."
    rm -rf "$BASE_DIR"
  fi
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

  echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
  parse_inputs "$@"

  if [ -z "${RELEASE_BASE}" ]; then
    >&2 echo "Usage: create-release-branch.sh -b <branch> [-p] [-c] [-w products|operators|demos|all]"
    exit 1
  fi

  validate_release_base_version "$RELEASE_BASE"
  validate_what "$WHAT" "products" "operators" "demos" "all"
  check_common_dependencies

  echo "Creating temporary working directory if it doesn't exist [$TEMP_RELEASE_FOLDER]"
  mkdir -p "$TEMP_RELEASE_FOLDER"
  update_repos "$TEMP_RELEASE_FOLDER"
  cleanup "$TEMP_RELEASE_FOLDER"
}

main "$@"
