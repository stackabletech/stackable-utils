#!/bin/env python
# vim: filetype=python syntax=python tabstop=4 expandtab

import argparse
import logging
import os
import pathlib
import re
import shutil
import sys

import yaml

__version__ = "0.0.1"

DESCRIPTION = """
(Re)Generate manifests for the Operator Lifecycle Manager (OLM).
"""


class ManifestException(Exception):
    pass


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse command line args."""
    parser = argparse.ArgumentParser(
        description=DESCRIPTION, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--version",
        help="Display application version",
        action="version",
        version=f"%(prog)s {__version__}",
    )

    parser.add_argument(
        "-r",
        "--release",
        help="Platform or operator release. Example: 24.3.0",
        type=cli_parse_release,
        required=True,
    )

    parser.add_argument(
        "-o",
        "--repo-operator",
        help="Path to the root of the operator repository.",
        type=pathlib.Path,
        required=True,
    )

    parser.add_argument(
        "-c",
        "--repo-certified-operators",
        help="Path to the root of the certified operators repository. Default is 'openshift-certified-operators' in the same root as the operator repository.",
        type=pathlib.Path,
        required=False,
    )

    parser.add_argument(
        "--log-level",
        help="Set log level.",
        type=cli_log_level,
        required=False,
        default=logging.INFO,
    )

    args = parser.parse_args(argv)
    if not args.repo_certified_operators:
        args.repo_certified_operators = (
            args.repo_operator.parent / "openshift-certified-operators"
        )

    ### Validate paths
    if not (args.repo_operator / "deploy" / "helm" / args.repo_operator.name).exists():
        raise ManifestException(
            f"Operator repository path not found {args.repo_operator} or missing helm chart"
        )
    if not (
        args.repo_certified_operators / "operators" / "stackable-airflow-operator"
    ).exists():
        raise ManifestException(
            f"Certification repository path not found: {args.repo_certified_operators} or it's not a certified operator repository"
        )

    return args


def cli_parse_release(cli_arg: str) -> str:
    if not re.match(r"^\d{2}\.([1-9]|1[0-2])\.\d+$", cli_arg):
        raise argparse.ArgumentTypeError("Invalid release")
    return cli_arg


def cli_log_level(cli_arg: str) -> int:
    match cli_arg:
        case "debug":
            return logging.DEBUG
        case "info":
            return logging.INFO
        case "error":
            return logging.ERROR
        case "warning":
            return logging.WARNING
        case "critical":
            return logging.CRITICAL
        case _:
            raise argparse.ArgumentTypeError("Invalid log level")


def generate_manifests(args: argparse.Namespace) -> None:
    # Get the product name from the operator path. This removes -operator, -k8s-operator, etc.
    product: str = args.repo_operator.name.split("-")[0]
    # Reassemble the operator path name. In case of spark, the -k8s is dropped for the name.
    # This has historical reasons and because it's impossible to rename the path of an existing operator
    # in the certification repository.
    op_name: str = f"{product}-operator"
    dest_dir: pathlib.Path = (
        args.repo_certified_operators
        / "operators"
        / f"stackable-{op_name}"
        / args.release
    )
    try:
        if dest_dir.exists():
            shutil.rmtree(dest_dir)
        os.makedirs(dest_dir / "manifests")
    except FileExistsError:
        raise ManifestException(f'Directory "{dest_dir}" already exists')

    crd_path = (
        args.repo_operator
        / "deploy"
        / "helm"
        / args.repo_operator.name
        / "crds"
        / "crds.yaml"
    )
    generate_crds(crd_path, dest_dir)


def generate_crds(crd_path: pathlib.Path, dest_dir: pathlib.Path) -> None:
    crds = yaml.load_all(crd_path.read_text(), Loader=yaml.SafeLoader)
    for crd in crds:
        if crd["kind"] == "CustomResourceDefinition":
            crd_name = crd["metadata"]["name"]
            crd_version = crd["spec"]["versions"][0]["name"]
            # Remove the helm.sh/resource-policy annotation
            del crd["metadata"]["annotations"]["helm.sh/resource-policy"]

            crd_dest = dest_dir / "manifests" / f"{crd_name}.{crd_version}.yaml"

            crd_dest.write_text(yaml.dump(crd))
        else:
            raise ManifestException(
                f'Expected "CustomresourceDefinition" but found kind "{crd['kind']}" in CRD file "{crd_path}"'
            )


def main(argv) -> int:
    ret = 0
    try:
        opts = parse_args(argv[1:])
        logging.basicConfig(encoding="utf-8", level=opts.log_level)
        logging.debug(f"Options: {opts}")
        generate_manifests(opts)
    except Exception as e:
        logging.error(e)
        ret = 1
    return ret


if __name__ == "__main__":
    sys.exit(main(sys.argv))
