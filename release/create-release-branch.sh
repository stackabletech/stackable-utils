#!/usr/bin/env bash
#----------------------------------------------------------------------------------------------------
# Usage: create-release-branch.sh <release-tag> [-p]
#
# <release-tag> : e.g. "23.1"
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
#   - iterates over a list of operator repository names (operators_to_release.txt), and for each one:
#   - creates a new folder in a temporary folder and clones the operator repository
#   - creates a new branch
#   - creates a one-off commit in the branch (i.e. the changes are valid for the branch lifetime)
#   - pushes the commit if the push argument is provided
#----------------------------------------------------------------------------------------------------
set -euo pipefail
set -x

BASE_BRANCH="main"
REPOSITORY="origin"
RELEASE=$1
#----------------------------------------------------------------------------------------------------
# tags should be semver-compatible e.g. 23.1 and not 23.01
# this is needed for cargo commands to work properly: although it is not strictly needed
# for the name of the release branch, the branch naming will be consistent with the cargo versioning.
#----------------------------------------------------------------------------------------------------
RELEASE_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])$"
#-----------------------------------------------------------
# remove leading and trailing quotes
#-----------------------------------------------------------
RELEASE="${RELEASE%\"}"
RELEASE="${RELEASE#\"}"
RELEASE_BRANCH="release-$RELEASE"
echo "Working release branch: ${RELEASE_BRANCH}"

#DOCKER_IMAGES_REPO="docker-images"
DOCKER_IMAGES_REPO="test-platform-release-images"
TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"
INITIAL_DIR="$PWD"

clone_repos() {
  mkdir -p "$TEMP_RELEASE_FOLDER" && cd "$TEMP_RELEASE_FOLDER"
  git clone "git@github.com:stackabletech/${DOCKER_IMAGES_REPO}.git"
  cd "$DOCKER_IMAGES_REPO"
  git switch -c "${RELEASE_BRANCH}" "${BASE_BRANCH}"
  push_branch "$@"

  cd "$TEMP_RELEASE_FOLDER"

  while IFS="" read -r operator || [ -n "$operator" ]
  do
    echo "Cloning ${operator}..."
    git clone "git@github.com:stackabletech/${operator}.git"
    cd "$operator"
    git switch -c "${RELEASE_BRANCH}" "${BASE_BRANCH}"
    update_antora "$TEMP_RELEASE_FOLDER/${operator}"
    git commit -am "release $RELEASE"
    push_branch "$@"
  done < "$INITIAL_DIR"/release/operators_to_release.txt
}

push_branch() {
  if [ "$#" -eq  "2" ]; then
    if [[ $2 == '-p' ]]; then
      echo "Pushing changes..."
      git push "${REPOSITORY}" "${RELEASE_BRANCH}"
      git switch main
    fi
  else
    echo "(Dry-run: not pushing...)"
  fi
}

update_antora() {
  echo "Updating from: $1"
  yq -i ".version = \"${RELEASE}\"" "$1/docs/antora.yml"
  yq -i '.prerelease = false' "$1/docs/antora.yml"
  yq -i ".versions[] = ${RELEASE}" "$1/docs/templating_vars.yaml"
}

main() {
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
  clone_repos "$@"
}

main "$@"
