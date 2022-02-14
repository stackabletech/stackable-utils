#!/usr/bin/env bash
#
# Usage: release.sh <level>
#
# <level> : "major", "minor" or "patch". Default: "minor".
#
set -e

BASE_BRANCH="main"
REPOSITORY="origin"
NOW_UTC=$(date -u '+%Y%m%d%H%M%S')
RELEASE_BRANCH="release-$NOW_UTC"

CARGO_VERSION=$(dirname -- "${BASH_SOURCE[0]}")/cargo-version.py

ensure_release_branch() {
  local STATUS=$(git status -s | grep -v '??')

  if [ "$STATUS" != "" ]; then
    >&2 echo "ERROR Dirty working copy found! Stop."
    exit 1
  fi

  git switch -c ${RELEASE_BRANCH} ${BASE_BRANCH}
  git push -u ${REPOSITORY} ${RELEASE_BRANCH}
}

maybe_create_github_pr() {
  local MESSAGE=$1
  GH_COMMAND=$(which gh)
  if [ "$GH_COMMAND" != "" ]; then
    gh pr create --base $BASE_BRANCH --head $RELEASE_BRANCH --title $MESSAGE --body $MESSAGE
  fi
}

update_changelog() {
  local RELEASE_VERSION=$1;

  TODAY=$(date +'%Y-%m-%d')

  sed -i "s/^.*unreleased.*/## [Unreleased]\n\n## [$RELEASE_VERSION] - $TODAY/I" CHANGELOG.md
}

main() {

  local NEXT_LEVEL=${1:-"release"}
  local PUSH=${2:-true}

  ensure_release_branch

  if [ "$NEXT_LEVEL" == "release" ]; then
    #
    # Release
    #
    $CARGO_VERSION --release
    cargo update --workspace
    make regenerate-charts
    local RELEASE_VERSION=$($CARGO_VERSION --show)

    update_changelog $RELEASE_VERSION

    MESSAGE="release $RELEASE_VERSION"
    git commit -am $MESSAGE
    git tag -a $RELEASE_VERSION -m "release $RELEASE_VERSION" HEAD

  else
    #
    # Development
    #
    $CARGO_VERSION --next ${NEXT_LEVEL}
    cargo update --workspace
    make regenerate-charts
    local RELEASE_VERSION=$($CARGO_VERSION --show)

    MESSAGE="bump version $RELEASE_VERSION"
    git commit -am $MESSAGE

  fi

  if [ "$PUSH" = "true" ]; then
    git push ${REPOSITORY} ${RELEASE_BRANCH} 
    git push --tags
    maybe_create_github_pr $MESSAGE
    git switch main
  fi
}

main $@
