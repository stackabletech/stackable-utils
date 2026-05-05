#!/usr/bin/env bash
#
# See README.md
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

PR_MSG="> [!CAUTION]
> ## DO NOT MERGE MANUALLY!
> This branch will be merged (and the commit tagged) by stackable-utils once any necessary commits have been cherry-picked to here from the main branch."

rc_branch_products() {
	( # subshell to isolate cd
		cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

		git switch "$PR_BRANCH"
		update_changelog ./CHANGELOG.md "$RELEASE_TAG"

		verify_release "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO" "$RELEASE_TAG" "$RELEASE"

		git add CHANGELOG.md
		git diff --cached --quiet && echo "No changes to commit for products" && return
		git commit -sm "chore: Release $RELEASE_TAG"
		push_branch
	)
}

rc_branch_operators() {
	for_each_operator rc_branch_single_operator
}

rc_branch_single_operator() {
	local operator="$1"
	( # subshell to isolate cd
		cd "${TEMP_RELEASE_FOLDER}/${operator}"
		git switch "$PR_BRANCH"

		if [ -f .gitmodules ]; then
			git submodule update --recursive --init
		fi

		cargo set-version --offline --workspace "$RELEASE_TAG"
		cargo update --workspace
		# LIBGIT2_NO_PKG_CONFIG forces libgit2-sys to statically link its bundled
		# libgit2, avoiding a runtime crash where nix provides the library for
		# compilation but not on LD_LIBRARY_PATH at runtime.
		LIBGIT2_NO_PKG_CONFIG=1 nix-shell --run 'make regenerate-charts'
		nix-shell --run 'make regenerate-nix'

		update_code "$TEMP_RELEASE_FOLDER/${operator}"

		"$TEMP_RELEASE_FOLDER/${operator}"/scripts/docs_templating.sh

		update_changelog "$TEMP_RELEASE_FOLDER/${operator}/CHANGELOG.md" "$RELEASE_TAG"

		verify_release "$TEMP_RELEASE_FOLDER/${operator}" "$RELEASE_TAG" "$RELEASE"

		git add Cargo.toml Cargo.lock Cargo.nix \
			deploy/helm/ extra/ \
			docs/ tests/ \
			CHANGELOG.md
		git diff --cached --quiet && echo "No changes to commit for ${operator}" && return
		git commit -sm "chore: Release $RELEASE_TAG"
		push_branch
	)
}

rc_branch_repos() {
	if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		rc_branch_products
	fi
	if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		rc_branch_operators
	fi
}

check_products() {
	( # subshell to isolate cd
		echo "Checking products"

		ensure_clone "$DOCKER_IMAGES_REPO"
		cd "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"

		require_release_branch "$DOCKER_IMAGES_REPO"
		git switch "$RELEASE_BRANCH" && git pull

		if local_or_remote_branch_exists "$PR_BRANCH"; then
			echo "PR branch already exists, switching to it (resuming prior run)"
			git switch "$PR_BRANCH"
		else
			git switch -c "$PR_BRANCH" "$RELEASE_BRANCH"
		fi

		check_tag_is_valid "$RELEASE_TAG" "$TEMP_RELEASE_FOLDER/$DOCKER_IMAGES_REPO"
	)
}

check_single_operator() {
	local operator="$1"
	( # subshell to isolate cd
		echo "Operator: $operator"
		ensure_clone "$operator"
		cd "$TEMP_RELEASE_FOLDER/${operator}"

		require_release_branch "$operator"
		git switch "$RELEASE_BRANCH" && git pull

		if local_or_remote_branch_exists "$PR_BRANCH"; then
			echo "PR branch already exists for ${operator}, switching to it (resuming prior run)"
			git switch "$PR_BRANCH"
		else
			git switch -c "$PR_BRANCH" "$RELEASE_BRANCH"
		fi

		check_tag_is_valid "$RELEASE_TAG" "$TEMP_RELEASE_FOLDER/${operator}"
	)
}

checks() {
	if [ "products" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		check_products
	fi
	if [ "operators" == "$WHAT" ] || [ "all" == "$WHAT" ]; then
		for_each_operator check_single_operator
	fi
}

update_code() {
	if [ -d "$1/docs" ]; then
		echo "Updating antora docs for $1"

		yq -i ".version = \"${RELEASE}\"" "$1/docs/antora.yml"
		yq -i '.prerelease = false' "$1/docs/antora.yml"

		if [ -f "$1/docs/templating_vars.yaml" ]; then
			yq -i "(.versions.[] | select(. == \"*dev\")) |= \"${RELEASE_TAG}\"" "$1/docs/templating_vars.yaml"
			yq -i "(.versions.[] | select(. == \"${RELEASE}*\")) |= \"${RELEASE_TAG}\"" "$1/docs/templating_vars.yaml"
			yq -i ".helm.repo_name |= sub(\"stackable-dev\", \"stackable-stable\")" "$1/docs/templating_vars.yaml"
			yq -i ".helm.repo_url |= sub(\"helm-dev\", \"helm-stable\")" "$1/docs/templating_vars.yaml"
		fi

		for file in $(find "$1/docs" -name "*.adoc"); do
			sed -i "s/nightly@home/home/g" "$file"
		done
	else
		echo "No docs found under $1."
	fi

	yq -i ".releases.tests.products[].operatorVersion |= sub(\"0.0.0-dev\", \"${RELEASE_TAG}\")" "$1/tests/release.yaml"
	yq -i "(.releases.tests.products[].operatorVersion | select(. == \"${RELEASE}*\")) |= \"${RELEASE_TAG}\"" "$1/tests/release.yaml"

	find "$1/tests/templates/kuttl" -type f -print0 | xargs -0 sed -E -i "s#(app\.kubernetes\.io/version: \".*-stackable)[^\"]*#\1$RELEASE_TAG#"
}

push_branch() {
	if $PUSH; then
		echo "Pushing changes..."
		git push -u "$REMOTE" "$PR_BRANCH"
		gh pr create --reviewer stackabletech/developers --base "${RELEASE_BRANCH}" --head "${PR_BRANCH}" --title "chore: Release ${RELEASE_TAG}" --body "${PR_MSG}"
	else
		echo "Dry-run: not pushing changes..."
		git push --dry-run -u "$REMOTE" "$PR_BRANCH"
		gh pr create --reviewer stackabletech/developers --dry-run --base "${RELEASE_BRANCH}" --head "${PR_BRANCH}" --title "chore: Release ${RELEASE_TAG}" --body "${PR_MSG}"
	fi
}

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

	RELEASE_TAG="$(strip_quotes "$RELEASE_TAG")"

	INITIAL_DIR="$PWD"
	derive_tag_vars "$RELEASE_TAG"

	echo "Settings: ${RELEASE_BRANCH}: Push: $PUSH: Cleanup: $CLEANUP"
}

main() {
	parse_inputs "$@"

	if [ -z "${RELEASE_TAG}" ]; then
		>&2 echo "Usage: create-release-candidate-branch.sh -t <tag> [-p] [-c] [-w products|operators|all]"
		exit 1
	fi

	validate_what "$WHAT" products operators all
	validate_tag "$RELEASE_TAG" "$TAG_REGEX"

	ensure_temp_folder
	check_build_dependencies

	checks

	echo "Cloning docker-images and/or operators to [$TEMP_RELEASE_FOLDER]"
	rc_branch_repos
	cleanup
}

main "$@"
