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
  CARGO_VERSION=$(dirname -- "${BASH_SOURCE[0]}")/cargo-version.py
  echo $CARGO_VERSION

  $CARGO_VERSION --set $RELEASE_TAG

  cargo update --workspace
  make regenerate-charts

  # inserts a single line with tag and date
  update_changelog $RELEASE_TAG
}

main $@
