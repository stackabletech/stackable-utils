#!/usr/bin/env bash
#
# Shared library for release scripts.
# Source this file — do not execute it directly.
#

set -euo pipefail

REMOTE="origin"

# Tag with optional RC suffix (e.g. 26.3.0, 26.3.1-rc1)
TAG_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+(-rc[0-9]+)?$"

# Tag without RC suffix — used by post-release which only applies to final releases
TAG_REGEX_FINAL="^[0-9][0-9]\.([1-9]|[1][0-2])\.[0-9]+$"

# Release branch format (e.g. 26.3)
RELEASE_REGEX="^[0-9][0-9]\.([1-9]|[1][0-2])$"

# Validate the -w parameter. Pass the valid options as arguments.
# Usage: validate_what "$WHAT" products operators all
#    or: validate_what "$WHAT" products operators demos all
validate_what() {
	local value="$1"
	shift
	local valid=("$@")

	if [ -z "$value" ]; then
		>&2 echo "Error: -w is required ($(IFS='|'; echo "${valid[*]}"))"
		exit 1
	fi

	for v in "${valid[@]}"; do
		if [ "$value" == "$v" ]; then
			return 0
		fi
	done

	>&2 echo "Error: invalid -w value '$value' (expected: $(IFS='|'; echo "${valid[*]}"))"
	exit 1
}

validate_tag() {
	local tag="$1"
	local regex="$2"

	if [ -z "$tag" ]; then
		>&2 echo "Error: tag is required"
		exit 1
	fi

	if [[ ! $tag =~ $regex ]]; then
		>&2 echo "Provided tag [$tag] does not match the required regex pattern [$regex]"
		exit 1
	fi
}

validate_release() {
	local release="$1"

	if [ -z "$release" ]; then
		>&2 echo "Error: release branch name is required"
		exit 1
	fi

	if [[ ! $release =~ $RELEASE_REGEX ]]; then
		>&2 echo "Provided branch name [$release] does not match the required regex pattern [$RELEASE_REGEX]"
		exit 1
	fi
}

# Derive common variables from a release tag.
# Sets: RELEASE, RELEASE_BRANCH, PR_BRANCH, DOCKER_IMAGES_REPO, TEMP_RELEASE_FOLDER
derive_tag_vars() {
	local tag="$1"

	RELEASE="$(cut -d'.' -f1,2 <<< "$tag")"
	RELEASE_BRANCH="release-$RELEASE"
	PR_BRANCH="pr-$tag"
	DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
	TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"
}

# Derive common variables from a release branch name (major.minor only).
# Sets: RELEASE_BRANCH, DOCKER_IMAGES_REPO, DEMOS_REPO, TEMP_RELEASE_FOLDER
derive_branch_vars() {
	local release="$1"

	RELEASE_BRANCH="release-$release"
	DOCKER_IMAGES_REPO=$(yq '... comments="" | .images-repo ' "$INITIAL_DIR"/release/config.yaml)
	DEMOS_REPO=$(yq '... comments="" | .demos-repo ' "$INITIAL_DIR"/release/config.yaml)
	TEMP_RELEASE_FOLDER="/tmp/stackable-$RELEASE_BRANCH"
}

# Check git user and gh auth. Prompts for confirmation.
check_git_user() {
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
}

check_gh_auth() {
	gh auth status
}

# Full dependency check for scripts that do code modifications.
check_build_dependencies() {
	check_git_user
	check_gh_auth
	yq --version
	python --version
	cargo --version
	cargo set-version --version
	jinja2 --version
	python -m pip show pyyaml
}

# Lightweight dependency check for scripts that only do git/gh operations.
check_basic_dependencies() {
	check_git_user
	check_gh_auth
}

# Check if a branch exists on the remote.
# Must be called with cwd inside the target git repo.
# Uses ls-remote to avoid modifying local refs (#19).
remote_branch_exists() {
	local branch="$1"
	git ls-remote --exit-code --heads "$REMOTE" "refs/heads/${branch}" > /dev/null 2>&1
}

# Check if a branch exists locally or in remote tracking refs.
local_or_remote_branch_exists() {
	local branch="$1"
	git branch -a | grep -qE "(^[* ] |remotes/${REMOTE}/)${branch}$"
}

# Require that a release branch exists on the remote.
# Exits with an error if missing.
require_release_branch() {
	local label="$1"
	if ! remote_branch_exists "$RELEASE_BRANCH"; then
		>&2 echo "Expected release branch is missing: ${label}/${RELEASE_BRANCH}"
		exit 1
	fi
}

# Check the working tree is clean. Exits if dirty.
require_clean_worktree() {
	local label="$1"
	if ! git diff-index --quiet HEAD --; then
		>&2 echo "Dirty git index for $label. Check working tree or staged changes. Exiting."
		exit 2
	fi
}

# Check that a tag does not already exist on the remote.
# Uses ls-remote to avoid modifying local refs (#19).
check_tag_is_valid() {
	local tag="$1"
	local repo_dir="$2"

	cd "$repo_dir"

	if git ls-remote --tags "$REMOTE" "refs/tags/${tag}" | grep -q "refs/tags/${tag}"; then
		>&2 echo "Tag $tag already exists on remote!"
		exit 1
	fi
}

# Ensure the temp release folder exists.
ensure_temp_folder() {
	if [ ! -d "$TEMP_RELEASE_FOLDER" ]; then
		echo "Creating folder: [$TEMP_RELEASE_FOLDER]"
		mkdir -p "$TEMP_RELEASE_FOLDER"
	fi
}

# Clone a repo if not already present in the temp folder.
ensure_clone() {
	local repo="$1"

	if [ ! -d "$TEMP_RELEASE_FOLDER/$repo" ]; then
		echo "Cloning: $TEMP_RELEASE_FOLDER/$repo"
		git clone "git@github.com:stackabletech/${repo}.git" "$TEMP_RELEASE_FOLDER/$repo"
	fi
}

# Clean up the temp folder if CLEANUP is true.
cleanup() {
	if "${CLEANUP:-false}"; then
		echo "Cleaning up..."
		rm -rf "$TEMP_RELEASE_FOLDER"
	fi
}

# Iterate over operators from config.yaml, calling a function for each.
# Usage: for_each_operator my_function
for_each_operator() {
	local func="$1"
	shift

	while IFS="" read -r operator || [ -n "$operator" ]; do
		"$func" "$operator" "$@"
	done < <(yq '... comments="" | .operators[] ' "$INITIAL_DIR"/release/config.yaml)
}

# Idempotent changelog update — skips if the tag is already present.
update_changelog() {
	local changelog="$1"
	local tag="$2"

	if grep -q "## \[$tag\]" "$changelog"; then
		echo "Changelog already contains $tag, skipping"
		return
	fi

	local today
	today=$(date +'%Y-%m-%d')
	sed -i "s/^.*unreleased.*/## [Unreleased]\n\n## [$tag] - $today/I" "$changelog"
}

# Verify release transformations are correct before committing.
# Checks whichever files exist — safe to call for both operators and products.
verify_release() {
	local dir="$1"
	local tag="$2"
	local release="$3"
	local errors=0

	echo "Verifying release transformations in $(basename "$dir")..."

	# Cargo.toml workspace version
	if [ -f "$dir/Cargo.toml" ] && grep -q '^\[workspace\.package\]' "$dir/Cargo.toml"; then
		local cargo_ver
		cargo_ver=$(grep -A 20 '^\[workspace\.package\]' "$dir/Cargo.toml" | grep -m1 '^version' | grep -oP '"\K[^"]+' || true)
		if [ -n "$cargo_ver" ] && [ "$cargo_ver" != "$tag" ]; then
			>&2 echo "  FAIL: Cargo.toml workspace version is '$cargo_ver', expected '$tag'"
			errors=$((errors + 1))
		fi
	fi

	# Helm Chart.yaml version and appVersion
	local chart_yaml
	chart_yaml=$(find "$dir/deploy/helm" -maxdepth 2 -name "Chart.yaml" -print -quit 2>/dev/null || true)
	if [ -n "$chart_yaml" ]; then
		local chart_ver chart_app_ver
		chart_ver=$(yq '.version' "$chart_yaml")
		chart_app_ver=$(yq '.appVersion' "$chart_yaml")
		if [ "$chart_ver" != "$tag" ]; then
			>&2 echo "  FAIL: Chart.yaml version is '$chart_ver', expected '$tag'"
			errors=$((errors + 1))
		fi
		if [ "$chart_app_ver" != "$tag" ]; then
			>&2 echo "  FAIL: Chart.yaml appVersion is '$chart_app_ver', expected '$tag'"
			errors=$((errors + 1))
		fi
	fi

	# antora.yml: version should be major.minor, prerelease should be false
	if [ -f "$dir/docs/antora.yml" ]; then
		local antora_ver antora_prerelease
		antora_ver=$(yq '.version' "$dir/docs/antora.yml")
		antora_prerelease=$(yq '.prerelease' "$dir/docs/antora.yml")
		if [ "$antora_ver" != "$release" ]; then
			>&2 echo "  FAIL: antora.yml version is '$antora_ver', expected '$release'"
			errors=$((errors + 1))
		fi
		if [ "$antora_prerelease" != "false" ]; then
			>&2 echo "  FAIL: antora.yml prerelease is '$antora_prerelease', expected 'false'"
			errors=$((errors + 1))
		fi
	fi

	# templating_vars.yaml: no *dev* versions remaining
	if [ -f "$dir/docs/templating_vars.yaml" ]; then
		local dev_entries
		dev_entries=$(yq '.versions | to_entries[] | select(.value | test("dev")) | .key' "$dir/docs/templating_vars.yaml" 2>/dev/null || true)
		if [ -n "$dev_entries" ]; then
			>&2 echo "  FAIL: templating_vars.yaml still has dev versions:"
			>&2 echo "$dev_entries" | sed 's/^/    /'
			errors=$((errors + 1))
		fi
	fi

	# tests/release.yaml: all operatorVersion entries should match the tag
	if [ -f "$dir/tests/release.yaml" ]; then
		local bad_versions
		bad_versions=$(yq '.releases.tests.products[] | select(.operatorVersion != "'"$tag"'") | .operatorVersion' "$dir/tests/release.yaml" 2>/dev/null || true)
		if [ -n "$bad_versions" ]; then
			>&2 echo "  FAIL: tests/release.yaml has non-release operatorVersions:"
			>&2 echo "$bad_versions" | sort -u | sed 's/^/    /'
			errors=$((errors + 1))
		fi
	fi

	# CHANGELOG.md should contain the release tag
	if [ -f "$dir/CHANGELOG.md" ]; then
		if ! grep -q "## \[$tag\]" "$dir/CHANGELOG.md"; then
			>&2 echo "  FAIL: CHANGELOG.md does not contain '## [$tag]'"
			errors=$((errors + 1))
		fi
	fi

	# No nightly@ references remaining in .adoc files
	if [ -d "$dir/docs" ]; then
		local nightly_refs
		nightly_refs=$(grep -rl 'nightly@' "$dir/docs/" 2>/dev/null || true)
		if [ -n "$nightly_refs" ]; then
			>&2 echo "  FAIL: docs still contain 'nightly@' references:"
			>&2 echo "$nightly_refs" | sed 's/^/    /'
			errors=$((errors + 1))
		fi
	fi

	# Workflow trigger: release tag should match at least one on.push.tags pattern
	if [ -f "$dir/.github/workflows/build.yaml" ]; then
		local tag_matched=false
		while IFS= read -r pattern; do
			local regex
			regex=$(echo "$pattern" | sed 's/\./\\./g; s/\*/.*/g')
			if [[ $tag =~ ^${regex}$ ]]; then
				tag_matched=true
				break
			fi
		done < <(yq '.on.push.tags[]' "$dir/.github/workflows/build.yaml" 2>/dev/null)
		if ! $tag_matched; then
			>&2 echo "  FAIL: Tag '$tag' does not match any on.push.tags pattern in build.yaml"
			errors=$((errors + 1))
		fi
	fi

	if [ "$errors" -gt 0 ]; then
		>&2 echo "Verification failed with $errors error(s)"
		return 1
	fi
	echo "Verification passed"
}

# Strip leading and trailing double quotes from a variable value.
strip_quotes() {
	local val="$1"
	val="${val%\"}"
	val="${val#\"}"
	echo "$val"
}
