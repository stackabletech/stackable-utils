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
#   validate_release_base_version "$RELEASE"
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
