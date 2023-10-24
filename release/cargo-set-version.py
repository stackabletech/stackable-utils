#!/usr/bin/env python3
#
# Utility for viewing and managing versions of cargo workspaces and crates.
# For workspaces, it assumes that all crate members use a single shared version.
#
# usage: cargo-set-version.py [-h] [-p PROJECT] [-s SET]
#
# Change versions of cargo projects.
#
# optional arguments:
#   -h, --help            show this help message and exit
#   -p PROJECT, --project PROJECT
#                         Project folder
#                         Version
#   -s SET, --set SET     Version
#

import toml
import semver
import argparse

def parse_args():
    parser = argparse.ArgumentParser(description="Change versions of cargo projects.")
    parser.add_argument("-p", "--project", help="Project folder", default=".")
    parser.add_argument("-s", "--set", help="Version" )
    return parser.parse_args()

if __name__ == "__main__":
    args = parse_args()

    cargo_file = f"{args.project.rstrip('/')}/Cargo.toml"
    old = toml.load(cargo_file)
    print(f"toml contents: [{old}]")

    if args.set:
        # sanity check
        semver.VersionInfo.parse(args.set)

        old_version=old["workspace"]["package"]["version"]
        new_version=args.set

        contents = []
        with open(cargo_file, 'r') as r:
            for line in r.readlines():
                if line.startswith("version"):
                    line = line.replace(old_version, new_version)
                contents.append(line)
        with open(cargo_file, 'w') as w:
            w.write(''.join(contents))
