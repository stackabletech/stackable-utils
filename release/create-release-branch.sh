#!/usr/bin/env bash
#
# Usage: create-release-branch.sh <release-tag> [-p]
#
# <release-tag> : e.g. "23.1"
# [-p]: push changes (otherwise is effectively a dry run)
#
set -e
set -x

BASE_BRANCH="main"
REPOSITORY="origin"

RELEASE_TAG=$1
# tags should be semver-compatible e.g. 23.1 and not 23.01
# this is needed for cargo commands to work properly: although it is not strictly needed
# for the name of the release branch, the branch naming will be consistent with the cargo versioning.
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])$"
# remove leading and trailing quotes
RELEASE_TAG="${RELEASE_TAG%\"}"
RELEASE_TAG="${RELEASE_TAG#\"}"

RELEASE_BRANCH="release-$RELEASE_TAG"
echo ${RELEASE_BRANCH}

ensure_release_branch() {
  local STATUS=$(git status -s | grep -v '??')

  if [ "$STATUS" != "" ]; then
    >&2 echo "ERROR Dirty working copy found! Stop."
    exit 1
  fi

  git switch -c ${RELEASE_BRANCH} ${BASE_BRANCH}
}

update_antora() {
  yq -i ".version = \"${RELEASE_TAG}\"" docs/antora.yml
  yq -i '.prerelease = false' docs/antora.yml
  yq -i ".versions[] = ${RELEASE_TAG}" docs/templating_vars.yaml
}

main() {
  # check if tag argument provided
  if [ -z ${RELEASE_TAG+x} ]; then
    echo "Usage: create-release-branch.sh <tag>"
    exit -1
  fi
  # check if argument matches our tag regex
  if [[ ! $RELEASE_TAG =~ $TAG_REGEX ]]; then
    echo "Provided tag [$RELEASE_TAG] does not match the required tag regex pattern [$TAG_REGEX]"
    exit -1
  fi

  ensure_release_branch
  update_antora

  git commit -am "release $RELEASE_TAG"

  if [ "$#" -eq  "2" ]; then
    if [[ $2 == '-p' ]]; then
      echo "Pushing changes..."
      git push ${REPOSITORY} ${RELEASE_BRANCH}
      git switch main
    fi
   fi
}

main $@
