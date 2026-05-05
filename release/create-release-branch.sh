#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

warn_if_branch_exists() {
  local repo="$1"
  ( # subshell to isolate cd
    ensure_clone "$repo"
    cd "$TEMP_RELEASE_FOLDER/$repo"

    if remote_branch_exists "$RELEASE_BRANCH"; then
      >&2 echo "WARNING: Release branch ${RELEASE_BRANCH} already exists in ${repo}."
      >&2 echo "For patch releases, use create-release-candidate-branch.sh instead."
      >&2 echo "Continue anyway? (y/n)"
      read -r response
      if [[ "$response" != "y" && "$response" != "Y" ]]; then
        >&2 echo "Aborting."
        exit 1
      fi
    fi
  )
}

check_existing_branches() {
  if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    warn_if_branch_exists "$DOCKER_IMAGES_REPO"
  fi
  if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    for_each_operator warn_if_branch_exists
  fi
  if [ "demos" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    warn_if_branch_exists "$DEMOS_REPO"
  fi
}

update_products() {
  ( # subshell to isolate cd
    if [ -d "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO" ]; then
      echo "Directory exists. Switching to ${RELEASE_BRANCH} branch and Updating..."
      cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
      require_clean_worktree "$DOCKER_IMAGES_REPO"
      git pull && git switch "${RELEASE_BRANCH}"
    else
      echo "Repo directory ($TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO) doesn't exist. Cloning and switching to ${RELEASE_BRANCH} branch"
      git clone --branch main --depth 1 "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
      cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
      git switch "${RELEASE_BRANCH}" 2> /dev/null || git switch -c "${RELEASE_BRANCH}"
    fi

    push_branch "$DOCKER_IMAGES_REPO"

    echo
    echo "Check $TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  )
}

update_single_operator() {
  local operator="$1"
  ( # subshell to isolate cd
    if [ -d "$TEMP_RELEASE_FOLDER/${operator}" ]; then
      echo "Directory exists. Switching to ${RELEASE_BRANCH} branch and Updating..."
      cd "$TEMP_RELEASE_FOLDER/${operator}"
      require_clean_worktree "$operator"
      git pull && git switch "${RELEASE_BRANCH}"
    else
      echo "Repo directory ($TEMP_RELEASE_FOLDER/$operator) doesn't exist. Cloning and switching to ${RELEASE_BRANCH} branch"
      git clone --branch main --depth 1 "git@github.com:stackabletech/${operator}.git" "$TEMP_RELEASE_FOLDER/${operator}"
      cd "$TEMP_RELEASE_FOLDER/${operator}"
      git switch "${RELEASE_BRANCH}" || git switch -c "${RELEASE_BRANCH}"
    fi
    push_branch "$operator"
  )
}

update_demos() {
  ( # subshell to isolate cd
    if [ -d "$TEMP_RELEASE_FOLDER/$DEMOS_REPO" ]; then
      cd "$TEMP_RELEASE_FOLDER/$DEMOS_REPO"
      require_clean_worktree "$DEMOS_REPO"
      git pull && git switch "${RELEASE_BRANCH}"
    else
      git clone --branch main --depth 1 "git@github.com:stackabletech/${DEMOS_REPO}.git" "$TEMP_RELEASE_FOLDER/$DEMOS_REPO"
      cd "$TEMP_RELEASE_FOLDER/$DEMOS_REPO"
      git switch "${RELEASE_BRANCH}" 2> /dev/null  || git switch -c "${RELEASE_BRANCH}"
    fi

    .scripts/update_refs.sh commit

    push_branch "$DEMOS_REPO"
  )
}

update_repos() {
  if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    update_products
  fi
  if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    for_each_operator update_single_operator
  fi
  if [ "demos" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    update_demos
  fi
}

push_branch() {
  local repository="$1"
  if $PUSH; then
    echo "Pushing changes to $repository"
    git push -u "$REMOTE" "$RELEASE_BRANCH"
  else
    echo "Dry-run: not pushing changes to $repository"
    git push --dry-run -u "$REMOTE" "$RELEASE_BRANCH"
  fi
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
          *) echo "Unknown parameter passed: $1"; exit 1 ;;
      esac
      shift
  done

  RELEASE="$(strip_quotes "$RELEASE")"

  INITIAL_DIR="$PWD"
  derive_branch_vars "$RELEASE"

  echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
  parse_inputs "$@"

  if [ -z "${RELEASE}" ]; then
    echo "Usage: create-release-branch.sh -b <branch> [-p] [-c] [-w products|operators|demos|all]"
    exit 1
  fi

  validate_what "$WHAT" products operators demos all
  validate_release "$RELEASE"

  echo "Creating temporary working directory if it doesn't exist [$TEMP_RELEASE_FOLDER]"
  mkdir -p "$TEMP_RELEASE_FOLDER"
  check_existing_branches
  update_repos
  cleanup
}

main "$@"
