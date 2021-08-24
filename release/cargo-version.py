#!/usr/bin/env python3
#
# Utility for viewing and managing versions of cargo workspaces and crates.
# For workspaces, it assumes that all crate members use a single shared version.
#
# usage: cargo-version.py [-h] [-p PROJECT] [-b {major,minor,patch,prerelease}] [-n] [-s SET] [-o]
# 
# Change versions of cargo projects.
# 
# optional arguments:
#   -h, --help            show this help message and exit
#   -p PROJECT, --project PROJECT
#                         Project folder
#   -b {major,minor,patch,prerelease}, --bump {major,minor,patch,prerelease}
#                         Level
#   -n, --next            Version
#   -s SET, --set SET     Version
#   -o, --show            Version
# 

import toml
import semver
import argparse

class Crate:
    def __init__(self, path, name, version, dependencies):
        self.path = path
        self.name = name
        self.version = version
        self.dependencies = dependencies

    def with_dependencies(self, names):
        deps = {k:v for k,v in self.dependencies.items() if k in names}
        return Crate(self.path, self.name, self.version, deps)

    @classmethod
    def bump_level(cls, version, level):
        v = semver.VersionInfo.parse(version)
        if level == 'major':
            return str(v.bump_major())
        elif level == 'minor':
            return str(v.bump_minor())
        elif level == 'patch':
            return str(v.bump_patch())
        else:
            return str(v.bump_prerelease('nightly'))

    def bump_version(self, level):
        return Crate(self.path, self.name, Crate.bump_level(self.version, level), self.dependencies.copy())

    def set_version(self, version):
        return Crate(self.path, self.name, version, self.dependencies.copy())

    def next_version(self):
        return Crate(self.path, self.name, str(semver.VersionInfo.parse(self.version).next_version('prerelease', 'nightly')), self.dependencies.copy())

    def show_version(self):
        return self.version

    def save(self, previous):
        contents = []
        cargo_file = f"{self.path}/Cargo.toml"
        with open(cargo_file, 'r') as r:
            for line in r.readlines():
                if line.startswith("version"):
                    line = line.replace(previous.version, self.version)
                else:
                    for dname, dversion in self.dependencies.items():
                        if line.startswith(dname):
                            line = line.replace(previous.dependencies[dname], dversion)
                contents.append(line)

        with open(cargo_file, 'w') as w:
            w.write(''.join(contents))

    def __str__(self):
        return f'Crate({self.path}, {self.name}, {self.version}, {self.dependencies})'

class Workspace:
    def __init__(self, crates):
        names = set([c.name for c in crates])
        self.crates = {c.name: c.with_dependencies(names) for c in crates}

    def bump_version(self, level):
        crates = {c.name: c.bump_version(level) for c in self.crates.values()}
        return Workspace(Workspace.update_dependencies(crates).values())

    def set_version(self, version):
        crates = {c.name: c.set_version(version) for c in self.crates.values()}
        return Workspace(Workspace.update_dependencies(crates).values())

    def next_version(self):
        crates = {c.name: c.next_version() for c in self.crates.values()}
        return Workspace(Workspace.update_dependencies(crates).values())

    def show_version(self):
        for c in self.crates.values():
            return c.show_version()
        return "0.0.0"

    @classmethod
    def update_dependencies(cls, crate_dict):
        for crate in crate_dict.values():
            for dep in crate.dependencies.keys():
                crate.dependencies[dep] = crate_dict[dep].version
        return crate_dict

    def __str__(self):
        return f'Workspace({[str(c) for c in self.crates.values()]})'

    def save(self, previous):
        for cn in self.crates.keys():
            self.crates[cn].save(previous.crates[cn])

def load(root):
    r = toml.load(f"{root}/Cargo.toml")
    if "workspace" in r:
        return Workspace([load(f"{root}/{path}") for path in r["workspace"]["members"]]) 
    else:
        return Crate(path=root, name=r["package"]["name"], version=r["package"]["version"], dependencies={dn: r["dependencies"][dn]["version"] for dn in r["dependencies"] if "version" in r["dependencies"][dn]})

def parse_args():
    parser = argparse.ArgumentParser(description="Change versions of cargo projects.")
    parser.add_argument("-p", "--project", help="Project folder", default=".")
    parser.add_argument("-b", "--bump", help="Level", choices=['major', 'minor', 'patch', 'prerelease'])
    parser.add_argument("-n", "--next", help="Version", action="store_true")
    parser.add_argument("-s", "--set", help="Version" )
    parser.add_argument("-o", "--show", help="Version", action="store_true")
    return parser.parse_args()

if __name__ == "__main__":
    args = parse_args()

    old = load(args.project.rstrip('/'))

    if args.bump:
        new = old.bump_version(args.bump)
        new.save(old)
    elif args.next:
        new = old.next_version()
        new.save(old)
    elif args.set:
        # sanity check
        semver.VersionInfo.parse(args.set)
        new = old.set_version(args.set)
        new.save(old)
    elif args.show:
        print(old.show_version())


