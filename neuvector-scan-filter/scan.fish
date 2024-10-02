#!/usr/bin/env fish

set images \
    docker.stackable.tech/k8s/csi-node-driver-registrar:v2.11.1 \
    docker.stackable.tech/k8s/csi-provisioner:v5.0.1 \
    docker.stackable.tech/stackable/airflow-operator:0.0.0-dev \
    docker.stackable.tech/stackable/commons-operator:0.0.0-dev \
    docker.stackable.tech/stackable/hbase-operator:0.0.0-dev \
    docker.stackable.tech/stackable/hive-operator:0.0.0-dev \
    docker.stackable.tech/stackable/kafka-operator:0.0.0-dev \
    docker.stackable.tech/stackable/listener-operator:0.0.0-dev \
    docker.stackable.tech/stackable/opa-operator:0.0.0-dev \
    docker.stackable.tech/stackable/secret-operator:0.0.0-dev \
    docker.stackable.tech/stackable/spark-k8s-operator:0.0.0-dev \
    docker.stackable.tech/stackable/superset-operator:0.0.0-dev \
    docker.stackable.tech/stackable/zookeeper-operator:0.0.0-dev \
    docker.stackable.tech/stackable/airflow:2.9.3-stackable0.0.0-dev \
    docker.stackable.tech/stackable/hbase:2.6.0-stackable0.0.0-dev \
    docker.stackable.tech/stackable/hive:3.1.3-stackable0.0.0-dev \
    docker.stackable.tech/stackable/kafka:3.8.0-stackable0.0.0-dev \
    docker.stackable.tech/stackable/opa:0.67.1-stackable0.0.0-dev \
    docker.stackable.tech/stackable/spark-k8s:3.5.2-stackable0.0.0-dev \
    docker.stackable.tech/stackable/superset:4.0.2-stackable0.0.0-dev \
    docker.stackable.tech/stackable/zookeeper:3.9.2-stackable0.0.0-dev

rm --recursive scan_results
rm result.csv

mkdir --parents scan_results

for image in $images
    set scan_result_file "scan_results/"(string replace --all : _ "$image" | string replace --all / _)

    docker pull $image-amd64
    docker run --name neuvector neuvector/scanner -i $image-amd64
    docker cp neuvector:/var/neuvector/scan_result.json "$scan_result_file"
    docker stop neuvector
    docker rm neuvector

    ./filter.py "$scan_result_file" >> result.csv
end
