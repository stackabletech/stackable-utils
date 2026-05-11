#!/usr/bin/env bash
#
# See README.adoc
#
set -euo pipefail
# set -x

REMOTE="origin"
#----------------------------------------------------------------------------------------------------
# tags should be semver-compatible e.g. 23.1 and not 23.01
# this is needed for cargo commands to work properly: although it is not strictly needed
# for the name of the release branch, the branch naming will be consistent with the cargo versioning.
#----------------------------------------------------------------------------------------------------
RELEASE_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])$"

update_products() {
  if [ -d "$BASE_DIR/$DOCKER_IMAGES_REPO" ]; then
    echo "Directory exists. Switching to ${RELEASE_BRANCH} branch and Updating..."
    cd "$BASE_DIR/$DOCKER_IMAGES_REPO"
    git switch "${RELEASE_BRANCH}" && git pull
  else
    echo "Repo directory ($BASE_DIR/$DOCKER_IMAGES_REPO) doesn't exist. Cloning and switching to ${RELEASE_BRANCH} branch"
    git clone --branch ${RELEASE_BRANCH} --depth 1 "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$BASE_DIR/$DOCKER_IMAGES_REPO"
    cd "$BASE_DIR/$DOCKER_IMAGES_REPO"
    # try to switch to the release branch (if continuing from someone else), or create it
    git switch "${RELEASE_BRANCH}" 2> /dev/null || git switch -c "${RELEASE_BRANCH}"
  fi

  # Create the work branch from the release branch so changes go through a PR
  # rather than being pushed directly to the release branch.
  git switch -c "${WORK_BRANCH}"

  echo "Pls manually bump the UBI base images in $BASE_DIR/$DOCKER_IMAGES_REPO"
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

  raise_pr "$DOCKER_IMAGES_REPO" "chore: UBI base image bumps"

  echo
  echo "Check $BASE_DIR/$DOCKER_IMAGES_REPO"
}

update_operators() {
  while IFS="" read -r operator || [ -n "$operator" ]
  do
    echo ">>> Now working on ${operator}"

    if [ -d "$BASE_DIR/${operator}" ]; then
      echo "Directory exists. Switching to ${RELEASE_BRANCH} branch and Updating..."
      cd "$BASE_DIR/${operator}"
      git switch "${RELEASE_BRANCH}" && git pull
    else
      echo "Repo directory ($BASE_DIR/$operator) doesn't exist. Cloning and switching to ${RELEASE_BRANCH} branch"
      git clone --branch ${RELEASE_BRANCH} --depth 1 "git@github.com:stackabletech/${operator}.git" "$BASE_DIR/${operator}"
      cd "$BASE_DIR/${operator}"
      # try to switch to the release branch (if continuing from someone else), or create it
      git switch "${RELEASE_BRANCH}" || git switch -c "${RELEASE_BRANCH}"
    fi

    # Create the work branch from the release branch so changes go through a PR
    # rather than being pushed directly to the release branch.
    git switch -c "${WORK_BRANCH}"

    cargo update
    # cargo test # Will be done by CI and takes too long
    make regenerate-nix
    # We are explicitly not regenerating the CRDs, as we don't want CRD changes to sneak in.
    # We rather let the CI checks fail and inspect manually.
    git add Cargo.lock Cargo.nix
    git commit -m "chore: Rust dependency patch level updates"

    echo "FYI, these are the major/minor bumps we did't do:"
    cargo +nightly -Z unstable-options update --breaking --dry-run

    raise_pr "$operator" "chore: Rust dependency patch level updates"
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

update_repos() {
  local BASE_DIR="$1";

  if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    update_products
  fi
  if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
    update_operators
  fi
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
    gh pr create \
      --base "$RELEASE_BRANCH" \
      --head "$WORK_BRANCH" \
      --title "$PR_TITLE" \
      --body "Patch level maintenance updates for \`${RELEASE_BRANCH}\` (created by release-branch-hygiene.sh)."
  else
    echo "Dry-run: not pushing ${WORK_BRANCH} or creating PR for ${REPOSITORY}"
    git push --dry-run -u "$REMOTE" "$WORK_BRANCH"
  fi
}

cleanup() {
  local BASE_DIR="$1";

  if $CLEANUP; then
    echo "Cleaning up..."
    rm -rf "$BASE_DIR"
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
  #-----------------------------------------------------------
  # remove leading and trailing quotes
  #-----------------------------------------------------------
  RELEASE="${RELEASE%\"}"
  RELEASE="${RELEASE#\"}"
  RELEASE_BRANCH="release-$RELEASE"
  # A single timestamp is shared across all repos in this run so the work
  # branches are easy to correlate.
  WORK_BRANCH="${RELEASE_BRANCH}-maintenance-$(date +%s)"

  INITIAL_DIR="$PWD"
  DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
  TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

  echo "Settings: ${RELEASE_BRANCH}: Work branch: ${WORK_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
  parse_inputs "$@"
  #-----------------------------------------------------------
  # check if tag argument provided
  #-----------------------------------------------------------
  if [ -z "${RELEASE}" ]; then
    echo "Usage: create-release-branch.sh -b <branch> [-p] [-c] [-w products|operators|demos|all]"
    exit 1
  fi
  #-----------------------------------------------------------
  # check if argument matches our tag regex
  #-----------------------------------------------------------
  if [[ ! $RELEASE =~ $RELEASE_REGEX ]]; then
    echo "Provided branch name [$RELEASE] does not match the required regex pattern [$RELEASE_REGEX]"
    exit 1
  fi

  echo "Creating temporary working directory if it doesn't exist [$TEMP_RELEASE_FOLDER]"
  mkdir -p "$TEMP_RELEASE_FOLDER"
  update_repos "$TEMP_RELEASE_FOLDER"
  cleanup "$TEMP_RELEASE_FOLDER"
}

main "$@"
