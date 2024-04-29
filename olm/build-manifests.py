#!/bin/env python
# vim: filetype=python syntax=python tabstop=4 expandtab

import argparse
import json
import logging
import os
import pathlib
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request

try:
    import yaml
except ModuleNotFoundError:
    print(
        "Module 'pyyaml' not found. Install using: pip install -r olm/requirements.txt"
    )
    sys.exit(1)

__version__ = "0.0.1"

DESCRIPTION = """
(Re)Generate manifests for the Operator Lifecycle Manager (OLM).

Example:
  ./olm/build-manifests.py --release 24.3.0 --repo-operator ~/repo/stackable/airflow-operator
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
        "--quay-release",
        help="Use this release tag for quay images. Defaults to --release if not provided. Useful when issuing patch releases that use existing images.",
        type=cli_parse_release,
    )

    parser.add_argument(
        "--replaces",
        help="CSV version that is replaced by this release. Example: 23.11.0",
        type=cli_parse_release,
    )

    parser.add_argument(
        "--skips",
        nargs="*",
        help="CSV versions that are skipped by this release. Example: 24.3.0",
        default=list(),
        type=cli_parse_release,
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

    parser.add_argument(
        "--openshift-versions",
        help="OpenShift target versions. Example: v4.11-v4.13",
        type=cli_validate_openshift_range,
        required=True,
    )

    parser.add_argument(
        "--use-helm-images",
        help="Use op image from the Helm chart. Do not resolve it from quay.io.",
        action="store_true",
    )

    args = parser.parse_args(argv)

    # Default to the actual release if no quay release is given
    if not args.quay_release:
        args.quay_release = args.release

    if not args.repo_certified_operators:
        args.repo_certified_operators = (
            args.repo_operator.parent / "openshift-certified-operators"
        )

    # Get the product name from the operator path. This removes -operator from the product name.
    args.product = args.repo_operator.name.rsplit("-", maxsplit=1)[0]
    args.op_name = args.repo_operator.name

    if args.op_name in {"secret-operator", "listener-operator"}:
        raise ManifestException(
            f"Operator '{args.op_name}' is not supported by this script. Use the 'build-manifests.sh' for it."
        )

    args.op_name = args.repo_operator.name

    # In case of spark, -k8s is still in the product name but the target directory
    # in the certification repository is without -k8s.
    # This has historical reasons and because it's impossible to rename the path of an existing operator
    # in the certification repository we need to rename the target directory here.
    dir_name = (
        "spark-operator" if args.product == "spark-k8s" else f"{args.product}-operator"
    )
    args.dest_dir = (
        args.repo_certified_operators
        / "operators"
        / f"stackable-{dir_name}"
        / args.release
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


def cli_validate_openshift_range(cli_arg: str) -> str:
    if not re.match(r"^v4\.\d{2}-v4\.\d{2}$", cli_arg):
        raise argparse.ArgumentTypeError(
            "Invalid OpenShift version range. Example: v4.11-v4.13"
        )
    return cli_arg


def cli_parse_release(cli_arg: str) -> str:
    if re.match(r"^\d{2}\.([1-9]|1[0-2])\.\d+(-\d*)?$", cli_arg) or re.match(
        r"^0\.0\.0-dev$", cli_arg
    ):
        return cli_arg
    raise argparse.ArgumentTypeError(
        "Invalid version provided for release or replacement"
    )


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


def load_resource(file_name: str) -> dict:
    res_path = pathlib.Path(__file__).parent / "resources" / file_name
    try:
        return yaml.load(res_path.read_text(), Loader=yaml.SafeLoader)
    except FileNotFoundError:
        raise ManifestException(f"Resource file '{res_path}' not found")
    except yaml.YAMLError as e:
        raise ManifestException(f"Error while loading resource file '{res_path}': {e}")


def generate_csv_related_images(
    args: argparse.Namespace, containers: list[dict]
) -> list[dict]:
    if args.use_helm_images:
        return [
            {"name": args.op_name, "image": c["image"]}
            for c in containers
            if c["name"] == args.op_name
        ]
    else:
        return quay_image([(args.op_name, args.quay_release)])


def generate_manifests(args: argparse.Namespace) -> list[dict]:
    logging.debug("start generate_manifests")
    # Parse CRDs as generated by Rust serde.
    crds = generate_crds(args.repo_operator)

    # Parse Helm manifests
    manifests = generate_helm_templates(args)

    #
    # Prepare various pieces for the CSV
    #
    op_cluster_role, op_service_account, op_deployment = filter_op_objects(
        args, manifests
    )
    cluster_permissions = [(op_service_account["metadata"]["name"], op_cluster_role)]
    deployments = [op_deployment]

    related_images = generate_csv_related_images(
        args, op_deployment["spec"]["template"]["spec"]["containers"]
    )

    if not args.use_helm_images:
        # patch the image of the operator container with the quay.io image
        for c in op_deployment["spec"]["template"]["spec"]["containers"]:
            if c["name"] == args.op_name:
                c["image"] = related_images[0]["image"]
        # patch the annotation image of the operator deployment the quay.io image
        try:
            if op_deployment["spec"]["template"]["metadata"]["annotations"][
                "internal.stackable.tech/image"
            ]:
                op_deployment["spec"]["template"]["metadata"]["annotations"][
                    "internal.stackable.tech/image"
                ] = related_images[0]["image"]
        except KeyError:
            pass

    owned_crds = to_owned_crds(crds)

    # Generate the CSV
    csv = generate_csv(
        args,
        owned_crds,
        cluster_permissions,
        deployments,
        related_images,
    )

    logging.debug("finish generate_manifests")
    return [csv, *crds, *manifests]


def filter_op_objects(args: argparse.Namespace, manifests) -> tuple[dict, dict, dict]:
    """Extracts a tuple containing three objects that need to be embedded in the CSV.
    These are:
        * the operator cluster role
        * the operator service account
        * the operator deployment.
    """
    logging.debug("start filter_op_objects")
    names = [
        f"{args.op_name}-clusterrole",
        f"{args.op_name}-serviceaccount",
        f"{args.op_name}-deployment",
    ]

    result = []
    for name in names:
        try:
            result.append(
                next(filter(lambda m: m["metadata"]["name"] == name, manifests))
            )
        except StopIteration:
            raise ManifestException(f"Could not find '{name}' in Helm templates")

    logging.debug("finish filter_op_objects")
    return tuple(result)


def write_manifests(args: argparse.Namespace, manifests: list[dict]) -> None:
    """Write the manifests to the certification repository."""
    try:
        manifests_dir = args.dest_dir / "manifests"
        logging.info(f"Creating directory {manifests_dir}")
        os.makedirs(manifests_dir)

        for m in manifests:
            dest_file = None
            if m["kind"] == "ClusterServiceVersion":
                dest_file = (
                    args.dest_dir
                    / "manifests"
                    / f"stackable-{args.op_name}.v{args.release}.clusterserviceversion.yaml"
                )
            elif m["kind"] == "CustomResourceDefinition":
                dest_file = (
                    args.dest_dir
                    / "manifests"
                    / f"{m['metadata']['name']}.customresourcedefinition.yaml"
                )
            # Only the product cluster role and the product configmap are dumped as individual files
            # The other objects are embedded in the CSV. These are:
            # - the operator cluster role
            # - the operator deployment
            elif (
                m["kind"] == "ClusterRole"
                and m["metadata"]["name"] == f"{args.product}-clusterrole"
            ):
                dest_file = (
                    args.dest_dir / "manifests" / f"{m['metadata']['name']}.yaml"
                )
            elif (
                m["kind"] == "ConfigMap"
                and m["metadata"]["name"] == f"{args.op_name}-configmap"
            ):
                dest_file = (
                    args.dest_dir / "manifests" / f"{m['metadata']['name']}.yaml"
                )

            if dest_file:
                logging.info(f"Writing {dest_file}")
                dest_file.write_text(yaml.dump(m))

    except FileExistsError:
        raise ManifestException("Destintation directory already exists")


def to_owned_crds(crds: list[dict]) -> list[dict]:
    logging.debug("start to_owned_crds")
    owned_crd_dicts = []
    for c in crds:
        for v in c["spec"]["versions"]:
            ### Extract CRD description from different properties
            description = "No description available"
            try:
                # we use this field instead of schema.openAPIV3Schema.description
                # because that one is not set by the Rust->CRD serialization
                description = v["schema"]["openAPIV3Schema"]["properties"]["spec"][
                    "description"
                ]
            except KeyError:
                pass
            try:
                # The OPA CRD has this field set
                description = v["schema"]["openAPIV3Schema"]["description"]
            except KeyError:
                pass

            owned_crd_dicts.append(
                {
                    "name": c["metadata"]["name"],
                    "displayName": c["metadata"]["name"],
                    "kind": c["spec"]["names"]["kind"],
                    "version": v["name"],
                    "description": description,
                }
            )

    logging.debug("finish to_owned_crds")
    return owned_crd_dicts


def generate_csv(
    args: argparse.Namespace,
    owned_crds: list[dict],
    cluster_permissions: list[tuple[str, dict]],
    deployments: list[dict],
    related_images: list[dict[str, str]],
) -> dict:
    logging.debug(
        f"start generate_csv for operator {args.op_name} and version {args.release}"
    )

    result = load_resource("csv.yaml")

    csv_name = (
        "spark-operator" if args.op_name == "spark-k8s-operator" else args.op_name
    )

    result["spec"]["version"] = args.release
    result["spec"]["replaces"] = (
        f"{csv_name}.v{args.replaces}" if args.replaces else None
    )
    result["spec"]["skips"] = [f"{csv_name}.v{v}" for v in args.skips]
    result["spec"]["keywords"] = [args.product]
    result["spec"]["displayName"] = CSV_DISPLAY_NAME[args.product]
    result["metadata"]["name"] = f"{csv_name}.v{args.release}"
    result["metadata"]["annotations"]["containerImage"] = related_images[0]["image"]
    result["metadata"]["annotations"]["description"] = CSV_DISPLAY_NAME[args.product]
    result["metadata"]["annotations"]["repository"] = (
        f"https://github.com/stackabletech/{args.op_name}"
    )

    ### 1. Add list of owned crds
    result["spec"]["customresourcedefinitions"]["owned"] = owned_crds

    ### 2. Add list of related images
    result["spec"]["relatedImages"] = related_images

    ### 3. Add cluster permissions
    result["spec"]["install"]["spec"]["clusterPermissions"] = [
        {
            "serviceAccountName": service_account,
            "rules": cluster_role["rules"],
        }
        for service_account, cluster_role in cluster_permissions
    ]
    ### 4. Add deployments
    result["spec"]["install"]["spec"]["deployments"] = [
        {
            "name": dplmt["metadata"]["name"],
            "spec": dplmt["spec"],
        }
        for dplmt in deployments
    ]

    logging.debug("finish generate_csv")

    return result


def generate_helm_templates(args: argparse.Namespace) -> list[dict]:
    logging.debug(f"start generate_helm_templates for {args.repo_operator}")
    template_path = args.repo_operator / "deploy" / "helm" / args.repo_operator.name
    helm_template_cmd = ["helm", "template", args.op_name, template_path]
    try:
        logging.debug("start generate_helm_templates")
        logging.info(f"Running {helm_template_cmd}")
        completed_proc = subprocess.run(
            helm_template_cmd,
            capture_output=True,
            check=True,
        )
        manifests = list(
            filter(
                lambda x: x,  # filter out empty objects
                yaml.load_all(
                    completed_proc.stdout.decode("utf-8"), Loader=yaml.SafeLoader
                ),
            )
        )
        for man in manifests:
            try:
                del man["metadata"]["labels"]["app.kubernetes.io/managed-by"]
                del man["metadata"]["labels"]["helm.sh/chart"]
            except KeyError:
                pass

            ### Patch the product cluster role with the SCC rule
            if (
                man["kind"] == "ClusterRole"
                and man["metadata"]["name"] == f"{args.product}-clusterrole"
            ):
                man["rules"].append(
                    {
                        "apiGroups": ["security.openshift.io"],
                        "resources": ["securitycontextconstraints"],
                        "resourceNames": ["stackable-products-scc"],
                        "verbs": ["use"],
                    }
                )
            ### Patch the version label
            try:
                if (
                    crv := man["metadata"]["labels"]["app.kubernetes.io/version"]
                ) != args.release:
                    logging.warning(
                        f"Version mismatch for '{man['metadata']['name']}'. Replacing '{crv}' with '{args.release}'"
                    )
                    man["metadata"]["labels"]["app.kubernetes.io/version"] = (
                        args.release
                    )
            except KeyError:
                pass

        logging.debug("finish generate_helm_templates")

        return manifests

    except subprocess.CalledProcessError as e:
        logging.error(e.stderr.decode("utf-8"))
        raise ManifestException(
            f'Failed to generate helm templates for "{args.op_name}" from "{template_path}"'
        )
    except yaml.YAMLError as e:
        logging.error(e)
        raise ManifestException(
            f'Failed to generate helm templates for "{args.op_name}" from "{template_path}"'
        )


def generate_crds(repo_operator: pathlib.Path) -> list[dict]:
    logging.debug(f"start generate_crds for {repo_operator}")
    crd_path = (
        repo_operator / "deploy" / "helm" / repo_operator.name / "crds" / "crds.yaml"
    )

    logging.info(f"Reading CRDs from {crd_path}")
    crds = list(yaml.load_all(crd_path.read_text(), Loader=yaml.SafeLoader))
    for crd in crds:
        if crd["kind"] == "CustomResourceDefinition":
            # Remove the helm.sh/resource-policy annotation
            del crd["metadata"]["annotations"]["helm.sh/resource-policy"]
        else:
            raise ManifestException(
                f'Expected "CustomResourceDefinition" but found kind "{crd['kind']}" in CRD file "{crd_path}"'
            )
    logging.debug("finish generate_crds")
    return crds


def quay_image(images: list[tuple[str, str]]) -> list[dict[str, str]]:
    """Get the images for the operator from quay.io. See: https://docs.quay.io/api/swagger"""
    logging.debug("start op_image")
    result = []
    for image, release in images:
        release_tag = urllib.parse.urlencode({"specificTag": release})
        tag_url = (
            f"https://quay.io/api/v1/repository/stackable/{image}/tag?{release_tag}"
        )
        with urllib.request.urlopen(tag_url) as response:
            data = json.load(response)
            if not data["tags"]:
                raise ManifestException(
                    f"Could not find manifest digest for release '{release}' on quay.io. Pass '--use-helm-images' to use docker.stackable.tech instead."
                )

            manifest_digest = [
                t["manifest_digest"] for t in data["tags"] if t["name"] == release
            ][0]

            result.append(
                {"name": image, "image": f"quay.io/stackable/{image}@{manifest_digest}"}
            )
    logging.debug("finish op_image")
    return result


def write_metadata(args: argparse.Namespace) -> None:
    logging.debug("start write_metadata")

    try:
        metadata_dir = args.dest_dir / "metadata"
        logging.info(f"Creating directory {metadata_dir}")
        os.makedirs(metadata_dir)

        annos = load_resource("annotations.yaml")

        annos["annotations"]["operators.operatorframework.io.bundle.package.v1"] = (
            f"stackable-{args.op_name}"
        )
        annos["annotations"]["com.redhat.openshift.versions"] = args.openshift_versions

        anno_file = metadata_dir / "annotations.yaml"
        logging.info(f"Writing {anno_file}")
        anno_file.write_text(yaml.dump(annos))
    except yaml.YAMLError:
        raise ManifestException("Failed to load annotations template")

    logging.debug("finish write_metadata")


def main(argv) -> int:
    ret = 0
    try:
        opts = parse_args(argv[1:])
        logging.basicConfig(encoding="utf-8", level=opts.log_level)

        # logging.debug(f"Options: {opts}")

        manifests = generate_manifests(opts)

        logging.info(f"Removing directory {opts.dest_dir}")
        if opts.dest_dir.exists():
            shutil.rmtree(opts.dest_dir)

        write_manifests(opts, manifests)
        write_metadata(opts)
    except Exception as e:
        logging.error(e)
        ret = 1
    return ret


CSV_DISPLAY_NAME = {
    "airflow": "Stackable Operator for Apache Airflow",
    "commons": "Stackable Commons Operator",
    "druid": "Stackable Operator for Apache Druid",
    "hbase": "Stackable Operator for Apache Hbase",
    "hdfs": "Stackable Operator for Apache HDFS",
    "hello-world": "Stackable Hello World Operator",
    "hive": "Stackable Operator for Apache Hive",
    "kafka": "Stackable Operator for Apache Kafka",
    "nifi": "Stackable Operator for Apache Nifi",
    "opa": "Stackable Operator for the Open Policy Agent",
    "spark-k8s": "Stackable Operator for Apache Spark",
    "superset": "Stackable Operator for Apache Superset",
    "trino": "Stackable Operator for Trino",
    "zookeeper": "Stackable Operator for Apache Zookeeper",
}

if __name__ == "__main__":
    sys.exit(main(sys.argv))
