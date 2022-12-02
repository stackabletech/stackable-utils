#!/usr/bin/env bash
#
# Usage: create-release-branch.sh <release-tag> [-p]
#
# <release-tag> : e.g. "23.01"
# [-p]: push changes (otherwise is effectively a dry run)
#
set -e
set -x

RELEASE_TAG=$1
# tags should be semver-compatible e.g. 23.1.1 and not 23.01.1
# this is needed for cargo commands to work properly
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+$"

# remove leading and trailing quotes
RELEASE_TAG="${RELEASE_TAG%\"}"
RELEASE_TAG="${RELEASE_TAG#\"}"

echo ${RELEASE_TAG}

update_code() {
  yq -i ".version = \"${RELEASE_TAG}\"" docs/antora.yml
  yq -i '.prerelease = false' docs/antora.yml
  yq -i ".versions[] = ${RELEASE_TAG}" docs/templating_vars.yaml
}

update_changelog() {
  local RELEASE_VERSION=$1;
  TODAY=$(date +'%Y-%m-%d')
  sed -i "s/^.*unreleased.*/## [Unreleased]\n\n## [$RELEASE_VERSION] - $TODAY/I" CHANGELOG.md
}

main() {
  # check if argument matches our tag regex
  if [[ ! $RELEASE_TAG =~ $TAG_REGEX ]]; then
    echo "Provided tag [$RELEASE_TAG] does not match the required tag regex pattern [$TAG_REGEX]"
    exit -1
  fi

  CARGO_VERSION=$(dirname -- "${BASH_SOURCE[0]}")/cargo-version.py
  echo $CARGO_VERSION

  $CARGO_VERSION --set $RELEASE_TAG

  cargo update --workspace
  make regenerate-charts

  # inserts a single line with tag and date
  update_changelog $RELEASE_TAG
}

main $@
