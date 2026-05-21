#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail
# set -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

REMOTE="origin"
PR_MSG="> [!CAUTION]
> ## DO NOT MERGE MANUALLY!
> This branch will be merged (and the commit tagged) by stackable-utils once any necessary commits have been cherry-picked to here from the main branch."

# Commit staged release changes and push the PR branch.
# Skips the commit if nothing is staged (idempotent for re-runs).
# Asserts we are on the correct branch before committing and that
# the remote is correct before pushing.
#
# Usage:
#   commit_and_push_rc "$DOCKER_IMAGES_REPO"
#   commit_and_push_rc "$operator"
commit_and_push_rc() {
	local repo="$1"
	assert_on_branch "$PR_BRANCH"
	if git diff --cached --quiet; then
		echo "No changes to commit for $repo (already up to date)"
	else
		git commit -sm "chore: Release $RELEASE_TAG"
		# TODO: Assert we are some commits ahead of the release branch (we just committed)
		assert_clean_index "$repo"
	fi
	assert_remote_exists "$REMOTE" "$repo"
	push_branch
}

rc_branch_products() (
	# assume that the branch exists and has either been pushed or has been created locally
	cd "$DOCKER_IMAGES_REPO"
	assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
	assert_clean_index "$DOCKER_IMAGES_REPO"

	# the PR branch should already exist
	git switch "$PR_BRANCH"
	assert_on_branch "$PR_BRANCH"
	update_changelog ./CHANGELOG.md "$RELEASE_TAG"
	git add CHANGELOG.md
	verify_release "." "$RELEASE_TAG" "$RELEASE_BASE"
	commit_and_push_rc "$DOCKER_IMAGES_REPO"
)

rc_branch_operator() (
	local operator="$1"
	cd "${operator}"
	assert_cwd_is_repo "$operator"
	assert_clean_index "$operator"
	git switch "$PR_BRANCH"
	assert_on_branch "$PR_BRANCH"

	# Update git submodules if needed
	if [ -f .gitmodules ]; then
		git submodule update --recursive --init
	fi

	# set tag version where relevant
	cargo set-version --offline --workspace "$RELEASE_TAG"
	cargo update --workspace
	git add Cargo.toml Cargo.lock

	# Run via nix-shell for the correct dependencies. Makefile already calls
	# nix stuff, so it shouldn't be a problem for non-nix users.
	#
	# LIBGIT2_NO_PKG_CONFIG: Workaround for non-NixOS users. nix-shell provides
	# libgit2 at build time (found via pkg-config), but LD_LIBRARY_PATH may not
	# include the nix store at runtime, causing a crash. This forces libgit2-sys
	# to statically link its bundled copy instead. The proper fix belongs in the
	# operator repos' nix shells.
	LIBGIT2_NO_PKG_CONFIG=1 nix-shell --run 'make regenerate-charts'
	# TODO: These make targets can modify many paths. Ideally we would
	# explicitly add the known output paths instead of staging all changes.
	git add deploy/helm extra/

	nix-shell --run 'make regenerate-nix'
	git add Cargo.nix crate-hashes.json nix/

	update_code "$TEMP_RELEASE_FOLDER/${operator}"
	git add docs/ tests/

	# ensure .j2 changes are resolved
	"$TEMP_RELEASE_FOLDER/${operator}"/scripts/docs_templating.sh
	git add docs/

	# inserts a single line with tag and date
	update_changelog ./CHANGELOG.md "$RELEASE_TAG"
	git add CHANGELOG.md

	verify_release "." "$RELEASE_TAG" "$RELEASE_BASE"
	commit_and_push_rc "$operator"
)

rc_branch_repos() {
	cd "$TEMP_RELEASE_FOLDER"
	case "$WHAT" in
		products) rc_branch_products ;;
		operators) for_each_operator rc_branch_operator ;;
		all)
			rc_branch_products
			for_each_operator rc_branch_operator
			;;
	esac
}


check_products() (
	echo "Checking products"

	ensure_clone "$DOCKER_IMAGES_REPO"
	cd "$DOCKER_IMAGES_REPO"
	assert_cwd_is_repo "$DOCKER_IMAGES_REPO"
	assert_clean_index "$DOCKER_IMAGES_REPO"

	# Need to update here because if we deleted the local state, or someone else continues
	# we might be back on main, or on the release branch without having pulled updates from fixes.
	git fetch && git switch "$RELEASE_BRANCH" && git pull
	assert_on_branch "$RELEASE_BRANCH"

	# The release branch should exist (created in a prior step)
	# NOTE: Do we need to check if the branch exists locally?
	assert_remote_branch_exists "$REMOTE" "$RELEASE_BRANCH"

	# The PR branch should not exist yet, otherwise a duplicate commit will be prepared
	# NOTE: Do we need to check if the branch DOES NOT exist locally?
	assert_remote_branch_not_exists "$REMOTE" "$PR_BRANCH"

	# create a new branch for the PR off of this
	git switch -c "$PR_BRANCH" "$RELEASE_BRANCH"
	assert_on_branch "$PR_BRANCH"

	assert_tag_not_exists "$REMOTE" "$RELEASE_TAG"
)

check_operator() (
	local operator="$1"
	echo "Operator: $operator"
	ensure_clone "$operator"
	cd "${operator}"
	assert_cwd_is_repo "$operator"
	assert_clean_index "$operator"

	# Need to update here because if we deleted the local state, or someone else continues
	# we might be back on main, or on the release branch without having pulled updates from fixes.
	git fetch && git switch "$RELEASE_BRANCH" && git pull
	assert_on_branch "$RELEASE_BRANCH"
	# The release branch should exist (created in a prior step)
	# NOTE: Do we need to check if the branch exists locally?
	assert_remote_branch_exists "$REMOTE" "$RELEASE_BRANCH"

	# The PR branch should not exist yet, otherwise a duplicate commit will be prepared
	# NOTE: Do we need to check if the branch DOES NOT exist locally?
	assert_remote_branch_not_exists "$REMOTE" "$PR_BRANCH"

	# create a new branch for the PR off of this
	git switch -c "$PR_BRANCH" "$RELEASE_BRANCH"
	assert_on_branch "$PR_BRANCH"

	assert_tag_not_exists "$REMOTE" "$RELEASE_TAG"
)

checks() {
	cd "$TEMP_RELEASE_FOLDER"
	case "$WHAT" in
		products) check_products ;;
		operators)
			echo "Checking operators"
			for_each_operator check_operator
			;;
		all)
			check_products
			echo "Checking operators"
			for_each_operator check_operator
			;;
	esac
}

update_code() {
	if [ -d "$1/docs" ]; then
		echo "Updating antora docs for $1"

		# antora version should be major.minor, not patch level
		yq -i ".version = \"${RELEASE_BASE}\"" "$1/docs/antora.yml"
		yq -i '.prerelease = false' "$1/docs/antora.yml"

		# Not all operators have a getting started guide
		# that's why we verify if templating_vars.yaml exists.
		if [ -f "$1/docs/templating_vars.yaml" ]; then

			# for an initial tag for a given release...
			yq -i "(.versions.[] | select(. == \"*dev\")) |= \"${RELEASE_TAG}\"" "$1/docs/templating_vars.yaml"

			# ...consider for patch releases/release candidates too
			# We assume that the tag (e.g. 23.7.1) is applied to an earlier tag in the same
			# release (e.g. 23.7.0) so search+replace on the major.minor tag will suffice.
			# TODO: this may pick up versions of external components as well.
			yq -i "(.versions.[] | select(. == \"${RELEASE_BASE}*\")) |= \"${RELEASE_TAG}\"" "$1/docs/templating_vars.yaml"

			yq -i ".helm.repo_name |= sub(\"stackable-dev\", \"stackable-stable\")" "$1/docs/templating_vars.yaml"
			yq -i ".helm.repo_url |= sub(\"helm-dev\", \"helm-stable\")" "$1/docs/templating_vars.yaml"
		fi

		# Replace "nightly" link so the documentation refers to the current version
		for file in $(find "$1/docs" -name "*.adoc"); do
			sed -i "s/nightly@home/home/g" "$file"
		done
	else
		echo "No docs found under $1."
	fi

	# Update operator version for the integration tests
	# (used when installing the operators).
	yq -i ".releases.tests.products[].operatorVersion |= sub(\"0.0.0-dev\", \"${RELEASE_TAG}\")" "$1/tests/release.yaml"

	# do this for patch releases/release candidates too.
	# i.e. replace 24.11.0-rc1 with 24.11.0, 24.7.0 with 24.7.1 etc.
	yq -i "(.releases.tests.products[].operatorVersion | select(. == \"${RELEASE_BASE}*\")) |= \"${RELEASE_TAG}\"" "$1/tests/release.yaml"

	# Some tests perform **label** inspection and for (only) these cases specific labels should be updated.
	# N.B. don't do this for all test files as not all images will necessarily exist for the given release tag.
	find "$1/tests/templates/kuttl" -type f -print0 | xargs -0 sed -E -i "s#(app\.kubernetes\.io/version: \".*-stackable)[^\"]*#\1$RELEASE_TAG#"
}

push_branch() {
	if $PUSH; then
		echo "Pushing changes..."
		# the branch must be updated before the PR can be created
		git push -u "$REMOTE" "$PR_BRANCH"
		gh pr create --reviewer stackabletech/developers --base "${RELEASE_BRANCH}" --head "${PR_BRANCH}" --title "chore: Release ${RELEASE_TAG}" --body "${PR_MSG}"
	else
		echo "Dry-run: not pushing changes..."
		git push --dry-run -u "$REMOTE" "$PR_BRANCH"
		gh pr create --reviewer stackabletech/developers --dry-run --base "${RELEASE_BRANCH}" --head "${PR_BRANCH}" --title "chore: Release ${RELEASE_TAG}" --body "${PR_MSG}"
	fi
}

cleanup() {
	if $CLEANUP; then
		echo "Cleaning up..."
		rm -rf "$TEMP_RELEASE_FOLDER"
	fi
}


# TODO: Consider moving validation (validate_tag, validate_what) into parse_inputs
parse_inputs() {
	RELEASE_TAG=""
	PUSH=false
	CLEANUP=false
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
		-c | --cleanup) CLEANUP=true ;;
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

	echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

check_dependencies() {
	check_common_dependencies

	# Additional dependencies for operator RC branch creation
	python --version
	cargo --version
	cargo set-version --version
	# jinja2-cli including pyyaml package (for docs templating)
	jinja2 --version
	python -m pip show pyyaml
}

main() {
	parse_inputs "$@"

	if [ -z "${RELEASE_TAG}" ]; then
		>&2 echo "Usage: create-release-candidate-branch.sh -t <tag> [-p] [-c] [-w products|operators|all]"
		exit 1
	fi

	validate_tag "$RELEASE_TAG"
	validate_what "$WHAT" "products" "operators" "all"

	ensure_temp_folder
	check_dependencies

	# sanity checks before we start: folder, branches etc.
	checks

	echo "Cloning docker-images and/or operators to [$TEMP_RELEASE_FOLDER]"
	rc_branch_repos
	cleanup
}

main "$@"
