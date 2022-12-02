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
  yq -i ".prerelease = false" docs/antora.yml
  yq -i ".versions[] = \"${RELEASE_TAG}\"" docs/templating_vars.yaml
  yq -i ".helm.repo_name |= sub(\"stackable-dev\", \"stackable-stable\")" docs/templating_vars.yaml
  yq -i ".helm.repo_url |= sub(\"helm-dev\", \"helm-stable\")" docs/templating_vars.yaml

  # TODO: just for docs/modules/getting_started/examples/code or can we do this more globally e.g. also for
  # - docs/modules/ROOT/examples/
  # - docs/modules/ROOT/pages/?
  # Replace spec.version for *.stackable.tech documents
  #find *.yaml -exec yq e -i '.apiVersion | select(. | contains("stackable.tech")) | parent | .spec | select (. | has("version")) | parent' {} \;

  # FIXME this removes empty files!
  find docs/modules/getting_started/examples/code/*.yaml -exec yq -i \
  ".apiVersion | select(. | contains(\"stackable.tech\")) | parent | .spec | select (. | has(\"version\")) | parent | .spec.version = \"${RELEASE_TAG}\"" {} \;

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

  update_code
  # ensure .j2 changes are resolved
  ./scripts/docs_templating.sh

  # inserts a single line with tag and date
  update_changelog $RELEASE_TAG
}

main $@
