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
