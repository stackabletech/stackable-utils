#!/usr/bin/env fish

set product_versions \
    9:airflow-operator:0.0.0-dev \
    10:commons-operator:0.0.0-dev \
    13:hbase-operator:0.0.0-dev \
    39:hdfs-operator:0.0.0-dev \
    15:hive-operator:0.0.0-dev \
    16:kafka-operator:0.0.0-dev \
    17:listener-operator:0.0.0-dev \
    19:opa-operator:0.0.0-dev \
    20:secret-operator:0.0.0-dev \
    21:spark-k8s-operator:0.0.0-dev \
    22:superset-operator:0.0.0-dev \
    24:zookeeper-operator:0.0.0-dev \
    25:airflow:2.8.1-stackable0.0.0-dev \
    27:hadoop:3.3.4-stackable0.0.0-dev \
    28:hbase:2.4.17-stackable0.0.0-dev \
    29:hive:3.1.3-stackable0.0.0-dev \
    30:kafka:3.6.1-stackable0.0.0-dev \
    33:opa:0.61.0-stackable0.0.0-dev \
    34:spark-k8s:3.5.1-stackable0.0.0-dev \
    35:superset:3.1.0-stackable0.0.0-dev \
    38:zookeeper:3.9.2-stackable0.0.0-dev

rm --recursive vex
mkdir vex

for product_version in $product_versions
    set parsed (string split ":" $product_version)
    set product_id $parsed[1]
    set product $parsed[2]
    set branch $parsed[3]
    set prefix "$product-$branch"

    set request "{\"product\":$product_id,\"vulnerability_names\":[],\"id_namespace\":\"https://openvex.dev/docs/stackabletech/\",\"document_id_prefix\":\"$prefix\",\"author\":\"mailto:security@stackable.tech\",\"role\":\"Document Creator\",\"branch_names\":[\"$branch\"]}"

    curl "https://secobserve-backend.stackable.tech/api/vex/openvex_document/create/" \
        --header "Authorization: Bearer $BEARER_TOKEN" \
        --header "Content-type: application/json" \
        --data-raw "$request" \
        --output-dir vex \
        --remote-name \
        --remote-header-name
end
