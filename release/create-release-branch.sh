#!/usr/bin/env bash
#----------------------------------------------------------------------------------------------------
# Usage: create-release-branch.sh -b <release-branch> -x <create|update> [-p]
#
# -b <release-branch> : e.g. "23.1"
# [-p]: push changes (otherwise is effectively a dry run)
# This script requires https://github.com/mikefarah/yq (not to be confused with https://github.com/kislyuk/yq)
#
# What this script does:
# - checks that the release argument is valid (e.g. semver-compatible, just major/minor levels)
# - strips this argument of any leading or trailing quote marks
# - for docker images:
#   - creates a new folder in a temporary folder and clones the images repository
#   - creates a new branch (and pushes it if the push argument is provided)
# - for operators:
#   - iterates over a list of operator repository names (config.yaml), and for each one:
#   - creates a new folder in a temporary folder and clones the operator repository
#   - creates a new branch
#   - creates a one-off commit in the branch (i.e. the changes are valid for the branch lifetime)
#   - pushes the commit if the push argument is provided
#----------------------------------------------------------------------------------------------------
set -euo pipefail
set -x

BASE_BRANCH="main"
REPOSITORY="origin"
#----------------------------------------------------------------------------------------------------
# tags should be semver-compatible e.g. 23.1 and not 23.01
# this is needed for cargo commands to work properly: although it is not strictly needed
# for the name of the release branch, the branch naming will be consistent with the cargo versioning.
#----------------------------------------------------------------------------------------------------
RELEASE_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])$"

clone_repos() {
  local BASE_DIR="$1";

  git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git" "$BASE_DIR/$DOCKER_IMAGES_REPO"
  cd "$BASE_DIR/$DOCKER_IMAGES_REPO"
  git switch -c "${RELEASE_BRANCH}" "${BASE_BRANCH}"
  push_branch "$DOCKER_IMAGES_REPO"

  while IFS="" read -r operator || [ -n "$operator" ]
  do
    echo "Cloning ${operator}..."
    git clone "git@github.com:stackabletech/${operator}.git" "$BASE_DIR/${operator}"

    cd "$BASE_DIR/${operator}"

    git switch -c "${RELEASE_BRANCH}" "${BASE_BRANCH}"
    push_branch "$operator"
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

update_repos() {
  local BASE_DIR="$1";
  cd "$BASE_DIR/$DOCKER_IMAGES_REPO"
  git switch "${RELEASE_BRANCH}"

  while IFS="" read -r operator || [ -n "$operator" ]
  do
    cd "$BASE_DIR/${operator}"

    git switch "${RELEASE_BRANCH}"
    update_antora "$BASE_DIR/${operator}"
    git commit -am "release $RELEASE"
    push_branch "$operator"
  done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

push_branch() {
  local REMOTE="$1";
  if $PUSH; then
    echo "Pushing to $REMOTE"
    git push -u "${REPOSITORY}" "${RELEASE_BRANCH}"
    #git switch main
  else
    echo "Dry run pushing to $REMOTE"
    git push --dry -u "${REPOSITORY}" "${RELEASE_BRANCH}"
  fi
}

cleanup() {
  local BASE_DIR="$1";

  if $CLEANUP; then
    echo "Cleaning up..."
    rm -rf "$BASE_DIR"
  fi
}

update_antora() {
  echo "Updating antora docs for $1"
  yq -i ".version = \"${RELEASE}\"" "$1/docs/antora.yml"
  yq -i '.prerelease = false' "$1/docs/antora.yml"
  # Not all operators have a getting started guide
  # that's why we verify if templating_vars.yaml exists.
  if [ -f "$1/docs/templating_vars.yaml" ]; then
    yq -i ".versions[] = ${RELEASE}" "$1/docs/templating_vars.yaml"
  fi
}

parse_inputs() {
  RELEASE="xxx"
  PUSH=false
  CLEANUP=false
  EXECUTE="create"

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          -b|--branch) RELEASE="$2"; shift ;;
          -x|--execute) EXECUTE="$2"; shift ;;
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

  INITIAL_DIR="$PWD"
  DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
  TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"

  echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
  parse_inputs "$@"
  #-----------------------------------------------------------
  # check if tag argument provided
  #-----------------------------------------------------------
  if [ -z ${RELEASE+x} ]; then
    echo "Usage: create-release-branch.sh <tag>"
    exit 1
  fi
  #-----------------------------------------------------------
  # check if argument matches our tag regex
  #-----------------------------------------------------------
  if [[ ! $RELEASE =~ $RELEASE_REGEX ]]; then
    echo "Provided tag [$RELEASE] does not match the required tag regex pattern [$RELEASE_REGEX]"
    exit 1
  fi

  echo "Cloning docker images and operators to [$TEMP_RELEASE_FOLDER]"
  if [ "$EXECUTE" == "create" ]; then
    mkdir -p "$TEMP_RELEASE_FOLDER"
    clone_repos "$TEMP_RELEASE_FOLDER"
  elif [ "$EXECUTE" == "update" ]; then
    update_repos "$TEMP_RELEASE_FOLDER"
  else
    echo "Unknown command: $EXECUTE"
    exit 1
  fi

  cleanup "$TEMP_RELEASE_FOLDER"
}

main "$@"
