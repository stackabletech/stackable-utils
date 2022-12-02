#!/usr/bin/env bash
#
# Usage: create-release-tag.sh <release-tag> [-d]
#
# <release-tag> : e.g. "23.01.42"
# [-d]: dry run
#
# What this script does:
# - Adapt versions in all cargo.toml to <release-tag> argument
# - Adapt versions in all helm charts to <release-tag> argument
# - Bump the changelog
set -e
#set -x

RELEASE_TAG=$1
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+$"

#DOCKER_IMAGES_REPO="git@github.com:stackabletech/docker-images.git"
DOCKER_IMAGES_REPO="git@github.com:stackabletech/test-platform-release-images.git"
TEMP_RELEASE_FOLDER="/tmp/stackable-release-$RELEASE_TAG"

update_changelog() {
  local RELEASE_VERSION=$1;

  TODAY=$(date +'%Y-%m-%d')

  sed -i "s/^.*unreleased.*/## [Unreleased]\n\n## [$RELEASE_VERSION] - $TODAY/I" CHANGELOG.md
}

clone_repo() {
  mkdir -p "$TEMP_RELEASE_FOLDER" && cd "$TEMP_RELEASE_FOLDER"
  git clone "$DOCKER_IMAGES_REPO"
}

main() {
  # check if tag argument provided
  if [ -z ${RELEASE_TAG+x} ]; then
    echo "Usage: create-release-tag.sh <tag>"
    exit -1
  fi
  # check if argument matches our tag regex
  if [[ ! $RELEASE_TAG =~ $TAG_REGEX ]]; then
    echo "Provided tag [$RELEASE_TAG] does not match the required tag regex pattern [$TAG_REGEX]"
    exit -1
  fi

  echo "Cloning docker images to [$TEMP_RELEASE_FOLDER]"
  clone_repo
  git switch


  cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
  git tag $RELEASE_TAG

  echo "Cleaning up"
  rm -rf "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
}

main $@
