# Release tools

## Install requirements

### Python 3

A working python 3 installation is required by the cargo-version.py script.

Install required packages:

    pip install -r release/requirements.txt

### Update PATH

Add the `release` folder to your `PATH`.

### Optional: GitHub CLI

Optionally, if you want to have a GitHub Pull-Request automatically created, you need the GitHib command line tools installed and properly configured. See https://cli.github.com/.

## Usage

Go to the folder containing a Cargo workspace or crate and run:

    release.sh [major|minor|patch] [false]

This pushes two commits in a newly created release branch. When merging, __do not squash them__.

Examples:

    # Perform release raise the minor version
    $ release.sh

    # Perform a release but do not push anything to origin
    $ release.sh minor false

    # Perform a release and raise the major version
    $ release.sh major

## Description

The release process performs the following steps:
0. Create a release branch from `main`.
1. Update the release version in the cargo workspace by dropping the "-nightly" token.
2. Update `Cargo.lock` with the new version.
3. Commit and tag the release.
4. Set the version to the next development version by increasing the 'minor' (by default) part and adding the '-nightly' prerelease token.
5. Update `Cargo.lock` with the new version.
6. Commit the next release.
7. Push the two commits
8. __Optional__: if the GitHub cli is installed, a PR is created.

## Future development

Automatically update the change log and readme files.
