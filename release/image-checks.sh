#!/usr/bin/env bash

# Usage:
# 1. Update the product and SDP versions at the end of the scripts
# 2. ./release/image-checks.sh
# 3. Check for missing artifacts in the output (it should be an obvious change in the pattern)
#
# It could be improved in future to assert things exist, and provide a clear error message when they don't.

# This is a handy utility for checking the existance of images.
# It does currently reqiure manually choosing product versions to check,
# but this list could be automated through conf.py
read -p "Be sure to update the versions in this script before running. Press Enter to continue"

# prepend a string to each line of stdout
# Usage:
#   echo "patch written to: $PATCH" | prepend "\t"
function prepend {
  while read -r line; do
    echo -e "${1}${line}"
  done
}

if [ -z "$HARBOR_TOKEN" ]; then
  read -s -p "Harbor Token (find it in the web UI): " HARBOR_TOKEN
fi

HARBOR_AUTH_HEADER="Authorization: Bearer $HARBOR_TOKEN"
TAGS_JQ_QUERY='.tags[] | select(. == $tag)'

# Check that per-arch images and a manifests exist for an operator.
# Usage:
#   check_tags_for_operator airflow-operator 25.7.0
#   check_tags_for_operator airflow-operator 25.7.0 sandbox
check_tags_for_operator() {
    local operator="$1"
    local sdp_version="$2"
    local project="${3:-sdp}"

    echo "Checking $operator for SDP $sdp_version"
    local tags_url="https://oci.stackable.tech/v2/$project/$operator/tags/list"

    curl -sSL -H "$HARBOR_AUTH_HEADER" "$tags_url" | jq -re "$TAGS_JQ_QUERY" --arg tag "$sdp_version-arm64" | prepend "\t"
    curl -sSL -H "$HARBOR_AUTH_HEADER" "$tags_url" | jq -re "$TAGS_JQ_QUERY" --arg tag "$sdp_version-amd64" | prepend "\t"
    curl -sSL -H "$HARBOR_AUTH_HEADER" "$tags_url" | jq -re "$TAGS_JQ_QUERY" --arg tag "$sdp_version" | prepend "\t"
}


# this could use some work to handle products under stackable instead of sdp
# Check that per-arch images and a manifests exist for a product.
# Usage:
#   check_tags_for_product spark-k8s 3.5.6 25.7.0-rc1
#   check_tags_for_product spark-connect-client 3.5.6 25.7.0 stackable
check_tags_for_product() {
    local product_name="$1"
    local product_version="$2"
    local sdp_version="$3"
    local project="${4:-sdp}"

    echo "Checking $project/$product_name@$product_version for SDP $sdp_version"
    local tags_url="https://oci.stackable.tech/v2/$project/$product_name/tags/list"

    curl -sSL -H "$HARBOR_AUTH_HEADER" "$tags_url" | jq -re "$TAGS_JQ_QUERY" --arg tag "$product_version-stackable$sdp_version-arm64" | prepend "\t"
    curl -sSL -H "$HARBOR_AUTH_HEADER" "$tags_url" | jq -re "$TAGS_JQ_QUERY" --arg tag "$product_version-stackable$sdp_version-amd64" | prepend "\t"
    curl -sSL -H "$HARBOR_AUTH_HEADER" "$tags_url" | jq -re "$TAGS_JQ_QUERY" --arg tag "$product_version-stackable$sdp_version" | prepend "\t"
}

# How it was run for the previous release:
SDP_RELEASE=25.7.0
check_tags_for_operator airflow-operator "$SDP_RELEASE"
check_tags_for_operator commons-operator "$SDP_RELEASE"
check_tags_for_operator druid-operator "$SDP_RELEASE"
check_tags_for_operator hbase-operator "$SDP_RELEASE"
check_tags_for_operator hdfs-operator "$SDP_RELEASE"
check_tags_for_operator hive-operator "$SDP_RELEASE"
check_tags_for_operator kafka-operator "$SDP_RELEASE"
check_tags_for_operator listener-operator "$SDP_RELEASE"
check_tags_for_operator nifi-operator "$SDP_RELEASE"
check_tags_for_operator opa-operator "$SDP_RELEASE"
check_tags_for_operator secret-operator "$SDP_RELEASE"
check_tags_for_operator spark-k8s-operator "$SDP_RELEASE"
check_tags_for_operator superset-operator "$SDP_RELEASE"
check_tags_for_operator trino-operator "$SDP_RELEASE"
check_tags_for_operator zookeeper-operator "$SDP_RELEASE"

# Be sure to check the product versions for the release you a checking for.
# This list was hand generated. It could be improved by evaluating conf.py.
check_tags_for_product airflow 2.9.3 "$SDP_RELEASE"
check_tags_for_product airflow 2.10.4 "$SDP_RELEASE"
check_tags_for_product airflow 2.10.5 "$SDP_RELEASE"
check_tags_for_product airflow 3.0.1 "$SDP_RELEASE"
check_tags_for_product druid 30.0.1 "$SDP_RELEASE"
check_tags_for_product druid 31.0.1 "$SDP_RELEASE"
check_tags_for_product druid 33.0.0 "$SDP_RELEASE"
check_tags_for_product hadoop 3.3.6 "$SDP_RELEASE"
check_tags_for_product hadoop 3.4.1 "$SDP_RELEASE"
check_tags_for_product hbase 2.6.1 "$SDP_RELEASE"
check_tags_for_product hbase 2.6.2 "$SDP_RELEASE"
check_tags_for_product hive 3.1.3 "$SDP_RELEASE"
check_tags_for_product hive 4.0.0 "$SDP_RELEASE"
check_tags_for_product hive 4.0.1 "$SDP_RELEASE"
check_tags_for_product kafka-testing-tools 1.0.0 "$SDP_RELEASE"
check_tags_for_product kafka 3.7.2 "$SDP_RELEASE"
check_tags_for_product kafka 3.9.0 "$SDP_RELEASE"
check_tags_for_product kafka 3.9.1 "$SDP_RELEASE"
check_tags_for_product kafka 4.0.0 "$SDP_RELEASE"
check_tags_for_product krb5 1.21.1 "$SDP_RELEASE"
check_tags_for_product nifi 1.27.0 "$SDP_RELEASE"
check_tags_for_product nifi 1.28.1 "$SDP_RELEASE"
check_tags_for_product nifi 2.4.0 "$SDP_RELEASE"
check_tags_for_product omid 1.1.2 "$SDP_RELEASE"
check_tags_for_product omid 1.1.3 "$SDP_RELEASE"
check_tags_for_product opa 1.4.2 "$SDP_RELEASE"
check_tags_for_product opa 1.0.1 "$SDP_RELEASE"
check_tags_for_product spark-connect-client 3.5.6 "$SDP_RELEASE" stackable
check_tags_for_product spark-k8s 3.5.5 "$SDP_RELEASE"
check_tags_for_product spark-k8s 3.5.6 "$SDP_RELEASE"
check_tags_for_product superset 4.0.2 "$SDP_RELEASE"
check_tags_for_product superset 4.1.1 "$SDP_RELEASE"
check_tags_for_product superset 4.1.2 "$SDP_RELEASE"
check_tags_for_product tools 1.0.0 "$SDP_RELEASE"
check_tags_for_product trino 451 "$SDP_RELEASE"
check_tags_for_product trino 470 "$SDP_RELEASE"
check_tags_for_product trino 476 "$SDP_RELEASE"
check_tags_for_product vector 0.49.0 "$SDP_RELEASE"
check_tags_for_product zookeeper 3.9.3 "$SDP_RELEASE"
