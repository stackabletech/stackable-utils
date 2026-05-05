#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

parse_inputs() {
	RELEASE_TAG=""
	PUSH=false
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

	RELEASE_TAG="$(strip_quotes "$RELEASE_TAG")"

	INITIAL_DIR="$PWD"
	derive_tag_vars "$RELEASE_TAG"

	echo "Settings: ${PR_BRANCH}: Push: $PUSH:"
}

merge_single_operator() {
	local operator="$1"

	echo "Operator: $operator"
	if $PUSH; then
		STATE=$(gh pr view "${PR_BRANCH}" -R stackabletech/"${operator}" --jq '.state' --json state)
	else
		echo "Dry-run: pretending the PR exists and is open"
		STATE="OPEN"
	fi
	if [[ "$STATE" == "OPEN" ]]; then
		echo "Processing ${operator} in branch ${PR_BRANCH} with state ${STATE}"
		if $PUSH; then
			echo "Reviewing..."
			echo "Merging..."
			gh pr merge "${PR_BRANCH}" --delete-branch --squash -R stackabletech/"${operator}"
		else
			echo "Dry-run: not reviewing/merging..."
			echo
			echo "Please checkout the release branch, and manually run git merge ${PR_BRANCH}"
		fi
	else
		echo "Skipping ${operator}, PR already closed"
	fi
}

merge_operators() {
	read -p "Ask someone to approve all of the operator PRs, then press Enter"
	for_each_operator merge_single_operator
}

merge_products() {
	echo "Products: $DOCKER_IMAGES_REPO"
	if $PUSH; then
		STATE=$(gh pr view "${PR_BRANCH}" -R stackabletech/"${DOCKER_IMAGES_REPO}" --jq '.state' --json state)
	else
		echo "Dry-run: pretending the PR exists and is open"
		STATE="OPEN"
	fi
	if [[ "$STATE" == "OPEN" ]]; then
		echo "Processing ${DOCKER_IMAGES_REPO} in branch ${PR_BRANCH} with state ${STATE}"
		if $PUSH; then
			echo "Reviewing..."
			read -p "Ask someone to approve the PR, then press Enter"
			echo "Merging..."
			gh pr merge "${PR_BRANCH}" --delete-branch --squash -R stackabletech/"${DOCKER_IMAGES_REPO}"
		else
			echo "Dry-run: not reviewing/merging..."
			echo
			echo "Please checkout the release branch, and manually run git merge ${PR_BRANCH}"
		fi
	else
		echo "Skipping ${DOCKER_IMAGES_REPO}, PR already closed"
	fi
}

merge() {
	if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		merge_products
	fi
	if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		merge_operators
	fi
}

main() {
	parse_inputs "$@"

	if [ -z "${RELEASE_TAG}" ]; then
		>&2 echo "Usage: merge-release-candidate.sh -t <tag> [-p] [-w products|operators|all]"
		exit 1
	fi

	validate_what "$WHAT" products operators all
	validate_tag "$RELEASE_TAG" "$TAG_REGEX"

	check_basic_dependencies
	merge
}

main "$@"
