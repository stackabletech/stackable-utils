#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

# TODO: Consider moving validation (validate_tag, validate_what) into parse_inputs
parse_inputs() {
	RELEASE_TAG=""
	PUSH=false
	PR_BRANCH=""
	WHAT=""

	while [[ "$#" -gt 0 ]]; do
		case $1 in
		-t | --tag)
			RELEASE_TAG="$2"
			shift
			;;
		-w | --what)
			WHAT="$2"
			shift
			;;
		-p | --push) PUSH=true ;;
		*)
			>&2 echo "Unknown parameter passed: $1"
			exit 1
			;;
		esac
		shift
	done

	RELEASE_TAG="$(strip_double_quotes "$RELEASE_TAG")"

	INITIAL_DIR="$PWD"
	derive_tag_vars "$RELEASE_TAG"

	echo "Settings: ${PR_BRANCH}: Push: $PUSH:"
}

# Merge the release candidate PR of a repository. Pass --ask-approval as the
# second argument to wait for someone to approve the PR before merging.
merge_repo() {
	local repo="$1"
	local ask_approval="${2:-}"
	echo "Repository: $repo"
	if $PUSH; then
		STATE=$(gh pr view "${PR_BRANCH}" -R stackabletech/"${repo}" --jq '.state' --json state)
	else
		echo "Dry-run: skipping PR existence check for ${repo}"
		STATE="OPEN"
	fi
	if [[ "$STATE" == "OPEN" ]]; then
		echo "Processing ${repo} in branch ${PR_BRANCH} with state ${STATE}"
		if $PUSH; then
			echo "Reviewing..."
			if [[ "$ask_approval" == "--ask-approval" ]]; then
				read -p "Ask someone to approve the PR, then press Enter"
			fi
			# TODO (@NickLarsenNZ): Check if the review is merged, else loop the following
			# TODO (@NickLarsenNZ): Allow review if the PR author is not the current `gh` user, otherwise wait.
			# gh pr review "${PR_BRANCH}" --approve -R stackabletech/"${repo}"
			echo "Merging..."
			gh pr merge "${PR_BRANCH}" --delete-branch --squash -R stackabletech/"${repo}"
		else
			echo "Dry-run: not reviewing/merging..."
			echo
			echo "Please checkout the release branch, and manually run git merge ${PR_BRANCH}"
		fi
	else
		echo "Skipping ${repo}, PR already closed"
	fi
}

merge_operators() {
	read -p "Ask someone to approve all of the operator PRs, then press Enter"
	for_each_operator merge_repo
}

merge() {
	case "$WHAT" in
		products) merge_repo "$DOCKER_IMAGES_REPO" --ask-approval ;;
		operators) merge_operators ;;
		cockpit) merge_repo "$COCKPIT_REPO" --ask-approval ;;
		all)
			merge_repo "$DOCKER_IMAGES_REPO" --ask-approval
			merge_operators
			merge_repo "$COCKPIT_REPO" --ask-approval
			;;
	esac
}

check_dependencies() {
	check_common_dependencies
}

main() {
	parse_inputs "$@"

	if [ -z "${RELEASE_TAG}" ]; then
		>&2 echo "Usage: merge-release-candidate.sh -t <tag> [-p] [-w products|operators|cockpit|all]"
		exit 1
	fi

	validate_tag "$RELEASE_TAG"
	validate_what "$WHAT" "products" "operators" "cockpit" "all"
	check_dependencies
	merge
}

main "$@"
