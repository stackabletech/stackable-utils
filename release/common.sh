#!/usr/bin/env bash
#
# Common functions shared across release scripts.
# This file is meant to be sourced, not executed directly.
#
# Usage (from any release script):
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/common.sh"
#

# Guard against direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	>&2 echo "Error: common.sh should be sourced, not executed directly."
	exit 1
fi

# Iterate over operators from config.yaml, calling a function for each.
# Requires $INITIAL_DIR to be set (for reading config.yaml).
#
# Usage:
#   for_each_operator my_function
#   for_each_operator my_function "extra_arg"
#
# The function receives the operator name as its first argument,
# followed by any extra arguments passed to for_each_operator.
for_each_operator() {
	local func="$1"
	shift

	while IFS="" read -r operator || [ -n "$operator" ]; do
		"$func" "$operator" "$@"
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

# Clone a repo from stackabletech if it doesn't already exist locally.
# Must be called from the directory where the clone should be created.
#
# Usage:
#   ensure_clone "airflow-operator"              # clone default branch
#   ensure_clone "airflow-operator" "--branch main"  # clone specific branch
ensure_clone() {
	local repo="$1"
	local clone_args="${2:-}"

	if [ ! -d "$repo" ]; then
		echo "Cloning $repo..."
		# shellcheck disable=SC2086
		git clone $clone_args "git@github.com:stackabletech/${repo}.git" "$repo"
	fi
}

# Ensure the temp release folder exists.
# Requires $TEMP_RELEASE_FOLDER to be set (via derive_tag_vars or derive_branch_vars).
ensure_temp_folder() {
	if [ ! -d "$TEMP_RELEASE_FOLDER" ]; then
		echo "Creating folder: [$TEMP_RELEASE_FOLDER]"
		mkdir -p "$TEMP_RELEASE_FOLDER"
	fi
}

# Strip leading and trailing double quotes from a string.
#
# Usage:
#   VAR="$(strip_double_quotes "$VAR")"
strip_double_quotes() {
	local val="$1"
	val="${val%\"}"
	val="${val#\"}"
	echo "$val"
}

# Validate the -w/--what parameter against a set of allowed values.
#
# Usage:
#   validate_what "$WHAT" "products" "operators" "all"
#
# Exits with an error if $WHAT is empty or not in the allowed list.
validate_what() {
	local what="$1"
	shift
	local allowed=("$@")

	if [ -z "$what" ]; then
		>&2 echo "Error: -w/--what is required. Allowed values: ${allowed[*]}"
		exit 1
	fi

	for valid in "${allowed[@]}"; do
		if [ "$what" == "$valid" ]; then
			return 0
		fi
	done

	>&2 echo "Error: Invalid -w/--what value: '$what'. Allowed values: ${allowed[*]}"
	exit 1
}

# Check common dependencies required by all release scripts:
# - globally configured git user name and email
# - gh (GitHub CLI) authentication
# - yq (YAML processor)
#
# Scripts that need additional dependencies (cargo, jinja2, etc.)
# should call this function first, then check their own extras.
check_common_dependencies() {
	if ! git_user=$(git config --global --includes --get user.name) \
	|| ! git_email=$(git config --global --includes --get user.email); then
		>&2 echo "Error: global git user name/email is not set."
		exit 1
	else
		echo "global git user: $git_user <$git_email>"
		echo "Is this correct? (y/n)"
		read -r response
		if [[ "$response" == "y" || "$response" == "Y" ]]; then
			echo "Proceeding with $git_user <$git_email>"
		else
			>&2 echo "User not accepted. Exiting."
			exit 1
		fi
	fi

	# gh authentication: if this fails you will need to e.g. gh auth login
	gh auth status

	# yq (YAML processor) - https://github.com/mikefarah/yq
	yq --version
}

# CalVer base pattern: YY.M where month is 1-12 without leading zero.
# Used by both tag and branch validation.
CALVER_BASE='[0-9][0-9]\.([1-9]|1[0-2])'

# Validate a release tag in CalVer format.
#
# Accepted formats:
#   YY.M.P       e.g. 26.3.0, 25.11.1
#   YY.M.P-rcN   e.g. 26.3.0-rc1, 25.11.1-rc12
#
# Usage:
#   validate_tag "$RELEASE_TAG"          # accepts both final and RC tags
#   validate_tag --no-rc "$RELEASE_TAG"  # rejects RC tags (for post-release)
#
# Exits with an error if the tag doesn't match.
validate_tag() {
	local no_rc=false
	while [[ "$1" == --* ]]; do
		case "$1" in
		--no-rc) no_rc=true ;;
		*)
			>&2 echo "Error: validate_tag: unknown flag '$1'."
			exit 1
			;;
		esac
		shift
	done
	local tag="$1"

	if [ -z "$tag" ]; then
		>&2 echo "Error: release tag is required."
		exit 1
	fi

	if [ "$#" -gt 1 ]; then
		>&2 echo "Error: validate_tag: unexpected trailing arguments: ${*:2}"
		exit 1
	fi

	local tag_regex="^${CALVER_BASE}\.[0-9]+(-rc[0-9]+)?$"
	if [[ ! $tag =~ $tag_regex ]]; then
		>&2 echo "Error: tag '$tag' does not match CalVer format (e.g. 26.3.0 or 26.3.0-rc1)."
		exit 1
	fi

	if $no_rc && [[ $tag =~ -rc[0-9]+$ ]]; then
		>&2 echo "Error: tag '$tag' is a release candidate. This step is only for final releases (e.g. 26.3.0, not 26.3.0-rc1)."
		exit 1
	fi
}

# Validate a release base version in CalVer format (YY.M).
# This is the base from which branch names (release-YY.M) and
# tags (YY.M.P, YY.M.P-rcN) are derived.
#
# Accepted format:
#   YY.M   e.g. 26.3, 25.11
#
# Usage:
#   validate_release_base_version "$RELEASE_BASE"
#
# Exits with an error if the version doesn't match.
validate_release_base_version() {
	local version="$1"

	if [ -z "$version" ]; then
		>&2 echo "Error: release version is required."
		exit 1
	fi

	local version_regex="^${CALVER_BASE}$"
	if [[ ! $version =~ $version_regex ]]; then
		>&2 echo "Error: release version '$version' does not match CalVer format (e.g. 26.3 or 25.11)."
		exit 1
	fi
}

# Derive common variables from a release tag.
# Requires $INITIAL_DIR to be set (for reading config.yaml).
#
# Sets: RELEASE_BASE, RELEASE_BRANCH, PR_BRANCH, DOCKER_IMAGES_REPO, TEMP_RELEASE_FOLDER
#
# Usage:
#   INITIAL_DIR="$PWD"
#   derive_tag_vars "$RELEASE_TAG"
derive_tag_vars() {
	local tag="$1"

	RELEASE_BASE="$(cut -d'.' -f1,2 <<< "$tag")" # e.g., 26.3 from 26.3.0-rc1
	RELEASE_BRANCH="release-$RELEASE_BASE"      # e.g., release-26.3
	PR_BRANCH="pr-$tag"                          # e.g., pr-26.3.0-rc1
	DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
	TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"
}

# Derive common variables from a release base version (YY.M).
# Requires $INITIAL_DIR to be set (for reading config.yaml).
#
# Sets: RELEASE_BRANCH, DOCKER_IMAGES_REPO, DEMOS_REPO, TEMP_RELEASE_FOLDER
#
# Usage:
#   INITIAL_DIR="$PWD"
#   derive_branch_vars "$RELEASE_BASE"
derive_branch_vars() {
	local release_base="$1" # e.g., 26.3

	RELEASE_BRANCH="release-$release_base"                # e.g., release-26.3
	DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
	DEMOS_REPO=$(yq '... comments="" | .demos-repo ' "$INITIAL_DIR"/release/config.yaml)
	TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"
}

# Assert that the current directory is inside a git repository.
# Optionally checks that the repository name matches an expected value.
#
# Usage:
#   assert_cwd_is_repo                     # just checks we're in a git repo
#   assert_cwd_is_repo "airflow-operator"  # also checks the repo name
#
# Exits with an error if the check fails.
assert_cwd_is_repo() {
	local expected_name="${1:-}"

	local repo_root
	if ! repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
		>&2 echo "Error: current directory ($(pwd)) is not inside a git repository."
		exit 1
	fi

	if [ -n "$expected_name" ]; then
		local actual_name
		actual_name=$(basename "$repo_root")
		if [ "$actual_name" != "$expected_name" ]; then
			>&2 echo "Error: expected to be in repo '$expected_name', but current repo is '$actual_name'."
			exit 1
		fi
	fi
}

# Assert that the current git branch matches the expected name.
# Uses exact string comparison - no regex.
#
# Usage:
#   assert_on_branch "release-26.3"
#   assert_on_branch "$PR_BRANCH"
#
# Exits with an error if the current branch doesn't match.
assert_on_branch() {
	local expected="$1"

	if [ -z "$expected" ]; then
		>&2 echo "Error: assert_on_branch: expected branch name is required."
		exit 1
	fi

	local actual
	actual=$(git branch --show-current)

	if [ "$actual" != "$expected" ]; then
		>&2 echo "Error: expected to be on branch '$expected', but currently on '$actual'."
		exit 1
	fi
}

# Assert that a named git remote exists and points to the expected
# repository under github.com/stackabletech.
#
# Usage:
#   assert_remote_exists "origin" "airflow-operator"
#
# Handles both SSH (git@github.com:stackabletech/...) and
# HTTPS (https://github.com/stackabletech/...) remote URLs.
# The .git suffix is stripped before comparison.
#
# Exits with an error if the remote doesn't exist or points elsewhere.
assert_remote_exists() {
	local remote="$1"
	local expected_repo="$2"

	if [ -z "$remote" ] || [ -z "$expected_repo" ]; then
		>&2 echo "Error: assert_remote_exists requires a remote name and expected repo name."
		exit 1
	fi

	local url
	if ! url=$(git remote get-url "$remote" 2>/dev/null); then
		>&2 echo "Error: git remote '$remote' does not exist."
		exit 1
	fi

	# Strip trailing .git if present
	url="${url%.git}"

	# Match both SSH and HTTPS URL formats
	local expected_pattern="github\.com[:/]stackabletech/${expected_repo}$"
	if [[ ! $url =~ $expected_pattern ]]; then
		>&2 echo "Error: remote '$remote' points to '$url', expected github.com/stackabletech/$expected_repo."
		exit 1
	fi
}

# Assert that a tag does NOT exist in the repository.
# Fetches tags first to ensure we have the latest state.
#
# Usage:
#   assert_tag_not_exists "$RELEASE_TAG"
#
# Exits with an error if the tag already exists.
assert_tag_not_exists() {
	local tag="$1"

	if [ -z "$tag" ]; then
		>&2 echo "Error: assert_tag_not_exists requires a tag name."
		exit 1
	fi

	git fetch --tags --quiet
	if [ -n "$(git tag --list "$tag")" ]; then
		>&2 echo "Error: tag '$tag' already exists!"
		exit 1
	fi
}

# Check whether a remote branch exists.
# Uses `git branch --list -r` with an exact pattern to avoid partial matches.
# Returns 0 if the branch exists, 1 if not. Does not exit on failure.
#
# Usage:
#   if remote_branch_exists "origin" "release-26.3"; then ...
remote_branch_exists() {
	local remote="$1"
	local branch="$2"

	if [ -z "$remote" ] || [ -z "$branch" ]; then
		>&2 echo "Error: remote_branch_exists requires a remote name and branch name."
		exit 1
	fi

	git fetch "$remote" --quiet
	[ -n "$(git branch --list -r "${remote}/${branch}")" ]
}

# Assert that a remote branch exists.
# Exits with an error if the branch is not found on the remote.
#
# Usage:
#   assert_remote_branch_exists "origin" "release-26.3"
assert_remote_branch_exists() {
	if ! remote_branch_exists "$@"; then
		>&2 echo "Error: branch '$2' does not exist on remote '$1'."
		exit 1
	fi
}

# Assert that a remote branch does NOT exist.
# Used to verify we won't collide with an existing branch when creating one.
#
# Usage:
#   assert_remote_branch_not_exists "origin" "pr-26.3.0-rc1"
assert_remote_branch_not_exists() {
	if remote_branch_exists "$@"; then
		>&2 echo "Error: branch '$2' already exists on remote '$1'."
		exit 1
	fi
}

# Assert that the current git working tree has no staged or unstaged
# changes to tracked files. Untracked files trigger a warning and
# a confirmation prompt.
#
# Usage:
#   assert_clean_index [context_message]
#
# The optional context_message is included in error output to help
# identify which repo/step failed (e.g., "airflow-operator").
assert_clean_index() {
	local context="${1:-$(basename "$(pwd)")}"

	# Check for staged or unstaged changes to tracked files
	if ! git diff-index --quiet HEAD --; then
		>&2 echo "Error: dirty git index for $context."
		>&2 echo "Staged or unstaged changes to tracked files:"
		>&2 git diff-index --name-status HEAD --
		exit 1
	fi

	# Check for untracked files
	local untracked
	untracked=$(git ls-files --others --exclude-standard)
	if [ -n "$untracked" ]; then
		echo "Warning: untracked files found in $context:"
		echo "$untracked"
		echo "Continue anyway? (y/n)"
		read -r response
		if [[ "$response" == "y" || "$response" == "Y" ]]; then
			echo "Continuing with untracked files."
		else
			>&2 echo "Aborting due to untracked files."
			exit 1
		fi
	fi
}
