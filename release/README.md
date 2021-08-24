# Release tools

## Install requirements

Install Python 3 and required packages:

    pip install -r release/requirements.txt

Add the `release` folder to your `PATH`.

## Usage

Go to the folder containing a Cargo workspace or crate and run:

    release.sh [major|minor|patch]

This pushes two commits in a newly created release branch. When merging, __do not squash them__.


