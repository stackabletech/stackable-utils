#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#   "pyyaml",
# ]
# ///
"""
(Re)Generate Stackable operator manifests for the Operator Lifecycle Manager (OLM).

The script renders the Helm chart, looks up image digests on quay.io, and writes a
complete OLM bundle to <repo-certified-operators>/operators/stackable-<op>/<release>/.

Ensure the operator repository is checked out at the release tag before running this.

Usage:

    uv run --script olm/build-manifests.py \
        --release 26.7.0 \
        --openshift-versions v4.18-v4.22 \
        --repo-operator ~/repo/stackable/airflow-operator \
        --repo-certified-operators ~/repo/stackable/openshift-certified-operators

    # Or directly with python3 (PyYAML must be installed):
    python3 olm/build-manifests.py --release 26.7.0 --openshift-versions v4.18-v4.22 \
        --repo-operator ~/repo/stackable/airflow-operator

Requirements:
    - uv    (https://docs.astral.sh/uv/) — installs PyYAML automatically
    - helm  (https://helm.sh)
"""

import argparse
import json
import logging
import os
import pathlib
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

import yaml

__version__ = "0.0.1"

# Quay.io repository that hosts the operator images. Since SDP 26.7.0 the images live
# under the "sdp" path, e.g. quay.io/stackable/sdp/hbase-operator.
QUAY_REPO = "stackable/sdp"

HUB_API = "https://hub.stackable.tech/api/v1"


class ManifestException(Exception):
    pass


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Parse command line args."""
    parser = argparse.ArgumentParser(
        description="Generate OLM bundle manifests for Stackable operators.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
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

    parser.add_argument(
        "--channel",
        help="Channel name to use for the OLM bundle. Default: <major>.<minor> from the release number or 'alpha' for '0.0.0-dev'",
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
            f"Operator '{args.op_name}' is not supported by this script. "
            f"Use 'scripts/generate-olm.py' in the {args.op_name} repository instead."
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

    ### Set bundle default channel
    if not args.channel:
        if args.release == "0.0.0-dev":
            args.channel = "alpha"
        else:
            args.channel = ".".join(args.release.split(".")[:2])
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
        # patch the annotation image of the operator deployment with the quay.io image
        try:
            if op_deployment["spec"]["template"]["metadata"]["annotations"][
                "internal.stackable.tech/image"
            ]:
                op_deployment["spec"]["template"]["metadata"]["annotations"][
                    "internal.stackable.tech/image"
                ] = related_images[0]["image"]
        except KeyError:
            pass

    # Generate the CSV
    csv = generate_csv(
        args,
        cluster_permissions,
        deployments,
        related_images,
    )

    logging.debug("finish generate_manifests")
    return [csv, *manifests]


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

        # The following objects are written as separate files:
        # - cluster service version
        # - cluster roles
        # - services
        # - config maps
        # The other objects are embedded in the CSV. These are:
        # - the operator cluster role (N.B. some products have more than one cluster role e.g. HDFS)
        # - the operator deployment
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
            elif m["kind"] in ["ClusterRole", "ConfigMap", "Service"]:
                kind = m["kind"].lower()
                name = m["metadata"]["name"]
                # Some objects contain the kind in their name already while others (looking at you webhook service) do not.
                # To avoid conflicting file names we append the kind if it's not already part of the object name.
                if kind not in m['metadata']['name']:
                    name = f"{name}-{kind}"

                dest_file = (
                    args.dest_dir / "manifests" / f"{name}.yaml"
                )

            if dest_file:
                logging.info(f"Writing {dest_file}")
                if dest_file.exists():
                    raise ManifestException(
                        f"Manifest file '{dest_file}' already exists"
                    )
                dest_file.write_text(yaml.dump(m))

    except FileExistsError:
        raise ManifestException("Destintation directory already exists")

def generate_csv(
    args: argparse.Namespace,
    cluster_permissions: list[tuple[str, dict]],
    deployments: list[dict],
    related_images: list[dict[str, str]],
) -> dict:
    logging.debug(
        f"start generate_csv for operator {args.op_name} and version {args.release}"
    )

    result = load_resource("csv.yaml")

    # In case of spark, -k8s is still in the product name but the bundle name
    # in the certification repository is without -k8s. See previous comment on this.
    csv_name = (
        "spark-operator" if args.op_name == "spark-k8s-operator" else args.op_name
    )

    chart = load_chart(args)
    listing = CSV_LISTING[args.product]

    result["spec"]["version"] = args.release
    result["spec"]["displayName"] = listing["display_name"]
    result["spec"]["description"] = chart["description"]
    # Charts from before SDP 26.11 carry no keywords.
    result["spec"]["keywords"] = chart.get("keywords", [args.product])
    result["spec"]["links"] = csv_links(chart)
    result["spec"]["minKubeVersion"] = min_kube_version(args.release)
    result["metadata"]["name"] = f"{csv_name}.v{args.release}"
    result["metadata"]["annotations"]["containerImage"] = related_images[0]["image"]
    result["metadata"]["annotations"]["description"] = chart["description"]
    result["metadata"]["annotations"]["capabilities"] = listing["capabilities"]
    result["metadata"]["annotations"]["categories"] = listing["categories"]
    result["metadata"]["annotations"]["repository"] = (
        f"https://github.com/stackabletech/{args.op_name}"
    )

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


def load_chart(args: argparse.Namespace) -> dict:
    chart_path = args.repo_operator / "deploy" / "helm" / args.op_name / "Chart.yaml"
    return yaml.load(chart_path.read_text(), Loader=yaml.SafeLoader)


def csv_links(chart: dict) -> list[dict[str, str]]:
    """Turn the chart's Artifact Hub links into CSV links.

    >>> links = "[{name: Documentation, url: https://docs.stackable.tech}, {name: support, url: https://github.com}]"
    >>> csv_links({"annotations": {"artifacthub.io/links": links}})
    [{'name': 'Documentation', 'url': 'https://docs.stackable.tech'}, {'name': 'Support', 'url': 'https://github.com'}]

    Charts without the annotation get no links:

    >>> csv_links({"description": "An older chart"})
    []
    """
    links = yaml.load(
        chart.get("annotations", {}).get("artifacthub.io/links", "[]"),
        Loader=yaml.SafeLoader,
    )
    # Artifact Hub only highlights a link named exactly "support"; the console shows names as-is.
    return [
        {
            "name": "Support" if link["name"] == "support" else link["name"],
            "url": link["url"],
        }
        for link in links
    ]


def hub_release_name(release: str) -> str:
    """Return the name the Stackable Hub uses for a release.

    >>> hub_release_name("26.11.0")
    '26.11'
    >>> hub_release_name("26.7.1")
    '26.7'
    >>> hub_release_name("0.0.0-dev")
    'latest'
    """
    if release == "0.0.0-dev":
        return "latest"
    return ".".join(release.split(".")[:2])


def lowest_kube_version(platforms: list[dict]) -> str:
    """Return the lowest Kubernetes version in the Hub's platform list, as a full version.

    Versions compare numerically, so 1.9 is lower than 1.10:

    >>> lowest_kube_version([
    ...     {"name": "OpenShift", "versions": ["4.20", "4.21"]},
    ...     {"name": "Kubernetes", "versions": ["1.10", "1.9", "1.11"]},
    ... ])
    '1.9.0'
    """
    versions = next(p["versions"] for p in platforms if p["name"] == "Kubernetes")
    lowest = min(versions, key=lambda v: tuple(int(x) for x in v.split(".")))
    return f"{lowest}.0"


def min_kube_version(release: str) -> str:
    """Return the lowest Kubernetes version the release supports, according to the Stackable Hub."""
    hub_release = hub_release_name(release)
    url = f"{HUB_API}/releases/{hub_release}"
    try:
        with urllib.request.urlopen(url) as response:
            platforms = json.load(response)["platforms"]
    except urllib.error.HTTPError as e:
        raise ManifestException(f"Could not read release {hub_release} from {url}: {e}")
    return lowest_kube_version(platforms)


def generate_helm_templates(args: argparse.Namespace) -> list[dict]:
    logging.debug(f"start generate_helm_templates for {args.repo_operator}")
    template_path = args.repo_operator / "deploy" / "helm" / args.repo_operator.name
    # Path to the default values.yaml used in the operator Helm charts.
    helm_values_path = template_path / "values.yaml"
    # Path to the custom values for OLM.
    olm_values_path = pathlib.Path(__file__).parent / "resources" / "values" / args.repo_operator.name / "values.yaml"
    # Since SDP 26.7.0 the charts no longer define image.repository in values.yaml. It is
    # supplied by a per-registry overlay instead. OLM bundles must reference quay.io, and
    # the overlay also drives the IMAGE_REPOSITORY env var that tells the operator where to
    # pull product images from. Without it the chart fails to render.
    registry_values_path = template_path / "values" / "quay.io.yaml"
    if not registry_values_path.exists():
        raise ManifestException(
            f"Registry values overlay not found: {registry_values_path}"
        )
    helm_template_cmd = ["helm", "template", args.op_name,
                         # Advertise the OpenShift API so that the charts render the
                         # securitycontextconstraints rules guarded by
                         # '.Capabilities.APIVersions.Has "security.openshift.io/v1"'.
                         # Some operators gate more than one cluster role this way
                         # (spark has three, opa has two), so relying on the chart is both
                         # more complete and more deterministic than patching a single role
                         # here.
                         "--api-versions", "security.openshift.io/v1",
                         "--values", helm_values_path,
                         "--values", olm_values_path,
                         "--values", registry_values_path,
                         template_path]
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


def quay_image(images: list[tuple[str, str]]) -> list[dict[str, str]]:
    """Get the images for the operator from quay.io. See: https://docs.quay.io/api/swagger"""
    logging.debug("start op_image")
    result = []
    for image, release in images:
        release_tag = urllib.parse.urlencode({"specificTag": release})
        tag_url = (
            f"https://quay.io/api/v1/repository/{QUAY_REPO}/{image}/tag/?{release_tag}"
        )
        logging.debug(f"Fetching image manifest from {tag_url}")
        with urllib.request.urlopen(tag_url) as response:
            data = json.load(response)
            if not data["tags"]:
                raise ManifestException(
                    f"Could not find manifest digest for release '{release}' on quay.io. Pass '--use-helm-images' to use oci.stackable.tech instead."
                )

            manifest_digest = [
                t["manifest_digest"]
                for t in data["tags"]
                if t["name"] == release and t["is_manifest_list"] == True
            ]

            if len(manifest_digest) == 0:
                raise ManifestException(f"No manifest list for {image}:{release} found")

            if len(manifest_digest) > 1:
                raise ManifestException(
                    f"Multiple manifest lists for {image}:{release} found but only one expected"
                )

            result.append(
                {
                    "name": image,
                    "image": f"quay.io/{QUAY_REPO}/{image}@{manifest_digest[0]}",
                }
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

        bundle_package_name = (
            "spark-operator" if args.op_name == "spark-k8s-operator" else args.op_name
        )

        annos["annotations"]["operators.operatorframework.io.bundle.package.v1"] = (
            f"stackable-{bundle_package_name}"
        )
        annos["annotations"]["com.redhat.openshift.versions"] = args.openshift_versions

        annos["annotations"][
            "operators.operatorframework.io.bundle.channel.default.v1"
        ] = args.channel
        annos["annotations"]["operators.operatorframework.io.bundle.channels.v1"] = (
            f"stable,{args.channel}"
        )

        anno_file = metadata_dir / "annotations.yaml"
        logging.info(f"Writing {anno_file}")
        anno_file.write_text(yaml.dump(annos))
    except yaml.YAMLError:
        raise ManifestException("Failed to load annotations template")

    logging.debug("finish write_metadata")


def main(argv) -> int:
    opts = parse_args(argv[1:])
    logging.basicConfig(encoding="utf-8", level=opts.log_level)

    manifests = generate_manifests(opts)

    logging.info(f"Removing directory {opts.dest_dir}")
    if opts.dest_dir.exists():
        shutil.rmtree(opts.dest_dir)

    write_manifests(opts, manifests)
    write_metadata(opts)
    return 0


# OLM-only listing values.
# Everything else the listing shows comes from the operator's Chart.yaml.
#   * capabilities: https://sdk.operatorframework.io/docs/overview/operator-capabilities/
#   * categories: comma-separated, from the list in https://github.com/operator-framework/api/blob/3d2cbf67cb0990b1b28956bd6eeb21054ca33d0a/pkg/validation/internal/standardcategories.go
CSV_LISTING = {
    "airflow": {
        "display_name": "Stackable Operator for Apache Airflow",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data, Integration & Delivery",
    },
    "commons": {
        "display_name": "Stackable Commons Operator",
        "capabilities": "Basic Install",
        "categories": "Big Data",
    },
    "druid": {
        "display_name": "Stackable Operator for Apache Druid",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data, Database",
    },
    "hbase": {
        "display_name": "Stackable Operator for Apache HBase",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data, Database",
    },
    "hdfs": {
        "display_name": "Stackable Operator for Apache Hadoop HDFS",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data",
    },
    "hive": {
        "display_name": "Stackable Operator for Apache Hive",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data, Database",
    },
    "kafka": {
        "display_name": "Stackable Operator for Apache Kafka",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data, Streaming & Messaging",
    },
    "nifi": {
        "display_name": "Stackable Operator for Apache NiFi",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data, Integration & Delivery",
    },
    "opa": {
        "display_name": "Stackable Operator for the Open Policy Agent",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data, Security",
    },
    "opensearch": {
        "display_name": "Stackable Operator for OpenSearch",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data",
    },
    "spark-k8s": {
        "display_name": "Stackable Operator for Apache Spark",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data, Integration & Delivery",
    },
    "superset": {
        "display_name": "Stackable Operator for Apache Superset",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data",
    },
    "trino": {
        "display_name": "Stackable Operator for Trino",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data, Database",
    },
    "zookeeper": {
        "display_name": "Stackable Operator for Apache ZooKeeper",
        "capabilities": "Seamless Upgrades",
        "categories": "Big Data",
    },
}

if __name__ == "__main__":
    sys.exit(main(sys.argv))
