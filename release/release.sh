#!/usr/bin/env sh
#
# Usage: release.sh <level>
#
# <level> : "major", "minor" or "patch". Default: "minor".
#
BASE_BRANCH="main"
REPOSITORY="origin"
NOW_UTC=$(date -u '+%Y%m%d%H%M%S')
RELEASE_BRANCH="release-$NOW_UTC"

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
  local TAG=$1
  GH_COMMAND=$(which gh)
  if [ "$GH_COMMAND" != "" ]; then
    gh pr create --base $BASE_BRANCH --head $RELEASE_BRANCH --reviewer "@stackabletech/rust-developers" --title "Release $TAG" --body "Release $TAG. DO NOT SQUASH MERGE!"
  fi
}

main() {

  local NEXT_LEVEL=${1:-minor}
  local PUSH=${2:-true}

  ensure_release_branch

  #
  # Release
  #
  cargo-version.py --release
  cargo update --workspace
  local TAG=$(cargo-version.py --show)
  git commit -am "bump version $TAG"
  git tag -a $TAG -m "release $TAG" HEAD

  #
  # Development
  #
  cargo-version.py --next ${NEXT_LEVEL}
  cargo update --workspace
  local NEXT_TAG=$(cargo-version.py --show)
  git commit -am "bump version $NEXT_TAG"

  if [ "$PUSH" = "true" ]; then
    git push ${REPOSITORY} ${RELEASE_BRANCH} 
    git push --tags
    maybe_create_github_pr $TAG
  fi
}

main $@
