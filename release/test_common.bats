#!/usr/bin/env bats
#
# Tests for release/common.sh
#
# Run with: bats release/test_common.bats
#
# Note: bats is included in the nix shell, you can run `nix-shell --run zsh` to
# load dependencies.

COMMON_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/common.sh"

# Source common.sh in a subshell to avoid the direct-execution guard
# killing the test runner. BATS sets BASH_SOURCE[0] != $0, so the
# guard passes naturally when we source it.
setup() {
	source "$COMMON_SH"

	# Ignore global/system git config so tests don't depend on the
	# user's environment (e.g., GPG signing, aliases, etc.)
	export GIT_CONFIG_GLOBAL=/dev/null
	export GIT_CONFIG_NOSYSTEM=1
	export GIT_AUTHOR_NAME="Test"
	export GIT_AUTHOR_EMAIL="test@test"
	export GIT_COMMITTER_NAME="Test"
	export GIT_COMMITTER_EMAIL="test@test"
}

# --- for_each_operator ---

@test "for_each_operator: calls function for each operator" {
	INITIAL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && cd .. && pwd)"
	collected=()
	collect_operator() { collected+=("$1"); }
	for_each_operator collect_operator
	[ "${#collected[@]}" -gt 0 ]
	[[ " ${collected[*]} " == *" airflow-operator "* ]]
}

@test "for_each_operator: passes extra arguments" {
	INITIAL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && cd .. && pwd)"
	results=()
	collect_with_extra() { results+=("$1:$2"); }
	for_each_operator collect_with_extra "extra"
	[[ " ${results[*]} " == *" airflow-operator:extra "* ]]
}

# --- strip_double_quotes ---

@test "strip_double_quotes: removes surrounding quotes" {
	run strip_double_quotes '"hello"'
	[ "$output" == 'hello' ]
}

@test "strip_double_quotes: leaves unquoted string unchanged" {
	run strip_double_quotes 'hello'
	[ "$output" == 'hello' ]
}

@test "strip_double_quotes: handles empty string" {
	run strip_double_quotes ''
	[ "$output" == '' ]
}

# --- validate_what ---

@test "validate_what: accepts valid value" {
	run validate_what "products" "products" "operators" "all"
	[ "$status" -eq 0 ]
}

@test "validate_what: accepts last valid value" {
	run validate_what "all" "products" "operators" "all"
	[ "$status" -eq 0 ]
}

@test "validate_what: rejects invalid value" {
	run validate_what "prodcts" "products" "operators" "all"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Invalid -w/--what value: 'prodcts'"* ]]
}

@test "validate_what: rejects value not in allowed set for this script" {
	run validate_what "demos" "products" "operators" "all"
	[ "$status" -eq 1 ]
	[[ "$output" == *"Invalid -w/--what value: 'demos'"* ]]
}

@test "validate_what: rejects empty value" {
	run validate_what "" "products" "operators" "all"
	[ "$status" -eq 1 ]
	[[ "$output" == *"-w/--what is required"* ]]
}

# --- validate_tag ---

@test "validate_tag: accepts final release tag" {
	run validate_tag "26.3.0"
	[ "$status" -eq 0 ]
}

@test "validate_tag: accepts RC tag" {
	run validate_tag "26.3.0-rc1"
	[ "$status" -eq 0 ]
}

@test "validate_tag: accepts multi-digit RC" {
	run validate_tag "25.11.1-rc12"
	[ "$status" -eq 0 ]
}

@test "validate_tag: accepts month 12" {
	run validate_tag "25.12.0"
	[ "$status" -eq 0 ]
}

@test "validate_tag: rejects month 0" {
	run validate_tag "25.0.0"
	[ "$status" -eq 1 ]
	[[ "$output" == *"does not match CalVer format"* ]]
}

@test "validate_tag: rejects month 13" {
	run validate_tag "25.13.0"
	[ "$status" -eq 1 ]
}

@test "validate_tag: rejects leading zero on month" {
	run validate_tag "25.03.0"
	[ "$status" -eq 1 ]
}

@test "validate_tag: rejects missing patch" {
	run validate_tag "26.3"
	[ "$status" -eq 1 ]
}

@test "validate_tag: rejects empty tag" {
	run validate_tag ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"release tag is required"* ]]
}

@test "validate_tag: rejects missing hyphen in rc" {
	run validate_tag "26.3.0rc1"
	[ "$status" -eq 1 ]
}

@test "validate_tag: --no-rc accepts final release" {
	run validate_tag --no-rc "26.3.0"
	[ "$status" -eq 0 ]
}

@test "validate_tag: --no-rc rejects RC tag" {
	run validate_tag --no-rc "26.3.0-rc1"
	[ "$status" -eq 1 ]
	[[ "$output" == *"only for final releases"* ]]
}

@test "validate_tag: rejects unknown flag" {
	run validate_tag --no-r "26.3.0"
	[ "$status" -eq 1 ]
	[[ "$output" == *"unknown flag '--no-r'"* ]]
}

@test "validate_tag: rejects trailing arguments" {
	run validate_tag "26.3.0" "--no-rc"
	[ "$status" -eq 1 ]
	[[ "$output" == *"unexpected trailing arguments"* ]]
}

# --- validate_release_base_version ---

@test "validate_release_base_version: accepts valid version" {
	run validate_release_base_version "26.3"
	[ "$status" -eq 0 ]
}

@test "validate_release_base_version: accepts month 11" {
	run validate_release_base_version "25.11"
	[ "$status" -eq 0 ]
}

@test "validate_release_base_version: rejects version with patch" {
	run validate_release_base_version "26.3.0"
	[ "$status" -eq 1 ]
}

@test "validate_release_base_version: rejects empty" {
	run validate_release_base_version ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"release version is required"* ]]
}

@test "validate_release_base_version: rejects month 0" {
	run validate_release_base_version "26.0"
	[ "$status" -eq 1 ]
}

@test "validate_release_base_version: rejects leading zero" {
	run validate_release_base_version "26.03"
	[ "$status" -eq 1 ]
}

# --- derive_tag_vars ---

@test "derive_tag_vars: sets all variables from a final tag" {
	INITIAL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && cd .. && pwd)"
	derive_tag_vars "26.3.0"
	[ "$RELEASE_BASE" == "26.3" ]
	[ "$RELEASE_BRANCH" == "release-26.3" ]
	[ "$PR_BRANCH" == "pr-26.3.0" ]
	[ "$TEMP_RELEASE_FOLDER" == "/tmp/stackable-release-26.3" ]
	[ -n "$DOCKER_IMAGES_REPO" ]
}

@test "derive_tag_vars: sets all variables from an RC tag" {
	INITIAL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && cd .. && pwd)"
	derive_tag_vars "25.11.1-rc2"
	[ "$RELEASE_BASE" == "25.11" ]
	[ "$RELEASE_BRANCH" == "release-25.11" ]
	[ "$PR_BRANCH" == "pr-25.11.1-rc2" ]
	[ "$TEMP_RELEASE_FOLDER" == "/tmp/stackable-release-25.11" ]
}

# --- derive_branch_vars ---

@test "derive_branch_vars: sets all variables" {
	INITIAL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && cd .. && pwd)"
	derive_branch_vars "26.3"
	[ "$RELEASE_BRANCH" == "release-26.3" ]
	[ "$TEMP_RELEASE_FOLDER" == "/tmp/stackable-release-26.3" ]
	[ -n "$DOCKER_IMAGES_REPO" ]
	[ -n "$DEMOS_REPO" ]
}

# --- assert_cwd_is_repo (needs temp git repo) ---

setup_temp_repo() {
	TEST_REPO=$(mktemp -d)
	git -C "$TEST_REPO" init -b main --quiet
	git -C "$TEST_REPO" commit --allow-empty -m "init" --quiet
}

teardown_temp_repo() {
	rm -rf "$TEST_REPO"
}

@test "assert_cwd_is_repo: passes in a git repo" {
	setup_temp_repo
	cd "$TEST_REPO"
	run assert_cwd_is_repo
	[ "$status" -eq 0 ]
	teardown_temp_repo
}

@test "assert_cwd_is_repo: passes with matching name" {
	setup_temp_repo
	# Rename dir to simulate a known repo name
	local named_repo="${TEST_REPO}-airflow-operator"
	mv "$TEST_REPO" "$named_repo"
	TEST_REPO="$named_repo"
	cd "$named_repo"
	run assert_cwd_is_repo "$(basename "$named_repo")"
	[ "$status" -eq 0 ]
	teardown_temp_repo
}

@test "assert_cwd_is_repo: fails with wrong name" {
	setup_temp_repo
	cd "$TEST_REPO"
	run assert_cwd_is_repo "wrong-name"
	[ "$status" -eq 1 ]
	[[ "$output" == *"expected to be in repo 'wrong-name'"* ]]
	teardown_temp_repo
}

@test "assert_cwd_is_repo: fails outside a git repo" {
	cd /tmp
	run assert_cwd_is_repo
	[ "$status" -eq 1 ]
	[[ "$output" == *"not inside a git repository"* ]]
}

# --- assert_on_branch (needs temp git repo) ---

@test "assert_on_branch: passes on correct branch" {
	setup_temp_repo
	cd "$TEST_REPO"
	git checkout -b "release-26.3" --quiet
	run assert_on_branch "release-26.3"
	[ "$status" -eq 0 ]
	teardown_temp_repo
}

@test "assert_on_branch: fails on wrong branch" {
	setup_temp_repo
	cd "$TEST_REPO"
	run assert_on_branch "release-26.3"
	[ "$status" -eq 1 ]
	[[ "$output" == *"expected to be on branch 'release-26.3', but currently on 'main'"* ]]
	teardown_temp_repo
}

@test "assert_on_branch: fails with empty argument" {
	run assert_on_branch ""
	[ "$status" -eq 1 ]
	[[ "$output" == *"expected branch name is required"* ]]
}

# --- assert_remote_exists (needs temp git repo with remote) ---

setup_temp_repo_with_remote() {
	setup_temp_repo
	cd "$TEST_REPO"
}

@test "assert_remote_exists: passes with SSH URL" {
	setup_temp_repo_with_remote
	git remote add origin "git@github.com:stackabletech/airflow-operator.git"
	run assert_remote_exists "origin" "airflow-operator"
	[ "$status" -eq 0 ]
	teardown_temp_repo
}

@test "assert_remote_exists: passes with HTTPS URL" {
	setup_temp_repo_with_remote
	git remote add origin "https://github.com/stackabletech/airflow-operator.git"
	run assert_remote_exists "origin" "airflow-operator"
	[ "$status" -eq 0 ]
	teardown_temp_repo
}

@test "assert_remote_exists: passes without .git suffix" {
	setup_temp_repo_with_remote
	git remote add origin "git@github.com:stackabletech/airflow-operator"
	run assert_remote_exists "origin" "airflow-operator"
	[ "$status" -eq 0 ]
	teardown_temp_repo
}

@test "assert_remote_exists: fails with wrong repo name" {
	setup_temp_repo_with_remote
	git remote add origin "git@github.com:stackabletech/druid-operator.git"
	run assert_remote_exists "origin" "airflow-operator"
	[ "$status" -eq 1 ]
	[[ "$output" == *"expected github.com/stackabletech/airflow-operator"* ]]
	teardown_temp_repo
}

@test "assert_remote_exists: fails with wrong org" {
	setup_temp_repo_with_remote
	git remote add origin "git@github.com:someoneelse/airflow-operator.git"
	run assert_remote_exists "origin" "airflow-operator"
	[ "$status" -eq 1 ]
	teardown_temp_repo
}

@test "assert_remote_exists: fails with nonexistent remote" {
	setup_temp_repo_with_remote
	run assert_remote_exists "upstream" "airflow-operator"
	[ "$status" -eq 1 ]
	[[ "$output" == *"does not exist"* ]]
	teardown_temp_repo
}

# --- assert_tag_not_exists ---

@test "assert_tag_not_exists: passes when tag does not exist" {
	setup_temp_repo
	cd "$TEST_REPO"
	run assert_tag_not_exists "26.3.0"
	[ "$status" -eq 0 ]
	teardown_temp_repo
}

@test "assert_tag_not_exists: fails when tag exists" {
	setup_temp_repo
	cd "$TEST_REPO"
	git tag "26.3.0"
	run assert_tag_not_exists "26.3.0"
	[ "$status" -eq 1 ]
	[[ "$output" == *"already exists"* ]]
	teardown_temp_repo
}

@test "assert_tag_not_exists: does not match partial tag names" {
	setup_temp_repo
	cd "$TEST_REPO"
	git tag "26.3.0-rc1"
	run assert_tag_not_exists "26.3.0"
	[ "$status" -eq 0 ]
	teardown_temp_repo
}

# --- remote_branch_exists / assert_remote_branch_exists / assert_remote_branch_not_exists ---

setup_temp_repo_with_remote_branch() {
	# Create a bare remote repo and a local clone with a branch
	TEST_REMOTE=$(mktemp -d)
	git -C "$TEST_REMOTE" init --bare --quiet
	TEST_REPO=$(mktemp -d)
	git clone "$TEST_REMOTE" "$TEST_REPO" --quiet
	cd "$TEST_REPO"
	git commit --allow-empty -m "init" --quiet
	git push --quiet
	git checkout -b "release-26.3" --quiet
	git push -u origin "release-26.3" --quiet
}

teardown_temp_repo_with_remote_branch() {
	rm -rf "$TEST_REPO" "$TEST_REMOTE"
}

@test "remote_branch_exists: returns 0 for existing branch" {
	setup_temp_repo_with_remote_branch
	run remote_branch_exists "origin" "release-26.3"
	[ "$status" -eq 0 ]
	teardown_temp_repo_with_remote_branch
}

@test "remote_branch_exists: returns 1 for missing branch" {
	setup_temp_repo_with_remote_branch
	run remote_branch_exists "origin" "release-99.9"
	[ "$status" -eq 1 ]
	teardown_temp_repo_with_remote_branch
}

@test "remote_branch_exists: does not match partial names" {
	setup_temp_repo_with_remote_branch
	run remote_branch_exists "origin" "release-26"
	[ "$status" -eq 1 ]
	teardown_temp_repo_with_remote_branch
}

@test "assert_remote_branch_exists: passes for existing branch" {
	setup_temp_repo_with_remote_branch
	run assert_remote_branch_exists "origin" "release-26.3"
	[ "$status" -eq 0 ]
	teardown_temp_repo_with_remote_branch
}

@test "assert_remote_branch_exists: fails for missing branch" {
	setup_temp_repo_with_remote_branch
	run assert_remote_branch_exists "origin" "release-99.9"
	[ "$status" -eq 1 ]
	[[ "$output" == *"does not exist on remote"* ]]
	teardown_temp_repo_with_remote_branch
}

@test "assert_remote_branch_not_exists: passes for missing branch" {
	setup_temp_repo_with_remote_branch
	run assert_remote_branch_not_exists "origin" "pr-26.3.0-rc1"
	[ "$status" -eq 0 ]
	teardown_temp_repo_with_remote_branch
}

@test "assert_remote_branch_not_exists: fails for existing branch" {
	setup_temp_repo_with_remote_branch
	run assert_remote_branch_not_exists "origin" "release-26.3"
	[ "$status" -eq 1 ]
	[[ "$output" == *"already exists on remote"* ]]
	teardown_temp_repo_with_remote_branch
}

# --- assert_clean_index (needs temp git repo) ---

@test "assert_clean_index: passes on clean repo" {
	setup_temp_repo
	cd "$TEST_REPO"
	run assert_clean_index
	[ "$status" -eq 0 ]
	teardown_temp_repo
}

@test "assert_clean_index: fails on staged changes" {
	setup_temp_repo
	cd "$TEST_REPO"
	echo "change" > tracked_file.txt
	git add tracked_file.txt
	git commit -m "add file" --quiet
	echo "modified" > tracked_file.txt
	git add tracked_file.txt
	run assert_clean_index
	[ "$status" -eq 1 ]
	[[ "$output" == *"dirty git index"* ]]
	teardown_temp_repo
}

@test "assert_clean_index: fails on unstaged changes" {
	setup_temp_repo
	cd "$TEST_REPO"
	echo "change" > tracked_file.txt
	git add tracked_file.txt
	git commit -m "add file" --quiet
	echo "modified" > tracked_file.txt
	run assert_clean_index
	[ "$status" -eq 1 ]
	[[ "$output" == *"dirty git index"* ]]
	teardown_temp_repo
}

@test "assert_clean_index: warns on untracked files, continues with y" {
	setup_temp_repo
	cd "$TEST_REPO"
	echo "new" > untracked_file.txt
	run bash -c 'source "'"$COMMON_SH"'" && echo y | assert_clean_index'
	[ "$status" -eq 0 ]
	[[ "$output" == *"untracked files found"* ]]
	[[ "$output" == *"untracked_file.txt"* ]]
	teardown_temp_repo
}

@test "assert_clean_index: warns on untracked files, aborts with n" {
	setup_temp_repo
	cd "$TEST_REPO"
	echo "new" > untracked_file.txt
	run bash -c 'source "'"$COMMON_SH"'" && echo n | assert_clean_index'
	[ "$status" -eq 1 ]
	[[ "$output" == *"Aborting due to untracked files"* ]]
	teardown_temp_repo
}
