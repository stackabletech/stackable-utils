#!/usr/bin/env fish

set images \
    docker.stackable.tech/k8s/sig-storage/csi-node-driver-registrar:v2.10.1 \
    docker.stackable.tech/k8s/sig-storage/csi-provisioner:v4.0.1 \
    docker.stackable.tech/stackable/airflow-operator:0.0.0-dev \
    docker.stackable.tech/stackable/commons-operator:0.0.0-dev \
    docker.stackable.tech/stackable/hbase-operator:0.0.0-dev \
    docker.stackable.tech/stackable/hdfs-operator:0.0.0-dev \
    docker.stackable.tech/stackable/hive-operator:0.0.0-dev \
    docker.stackable.tech/stackable/kafka-operator:0.0.0-dev \
    docker.stackable.tech/stackable/listener-operator:0.0.0-dev \
    docker.stackable.tech/stackable/opa-operator:0.0.0-dev \
    docker.stackable.tech/stackable/secret-operator:0.0.0-dev \
    docker.stackable.tech/stackable/spark-k8s-operator:0.0.0-dev \
    docker.stackable.tech/stackable/superset-operator:0.0.0-dev \
    docker.stackable.tech/stackable/zookeeper-operator:0.0.0-dev \
    docker.stackable.tech/stackable/airflow:2.8.1-stackable0.0.0-dev \
    docker.stackable.tech/stackable/hadoop:3.3.4-stackable0.0.0-dev \
    docker.stackable.tech/stackable/hbase:2.4.17-stackable0.0.0-dev \
    docker.stackable.tech/stackable/hive:3.1.3-stackable0.0.0-dev \
    docker.stackable.tech/stackable/kafka:3.6.1-stackable0.0.0-dev \
    docker.stackable.tech/stackable/opa:0.61.0-stackable0.0.0-dev \
    docker.stackable.tech/stackable/spark-k8s:3.5.1-stackable0.0.0-dev \
    docker.stackable.tech/stackable/superset:3.1.0-stackable0.0.0-dev \
    docker.stackable.tech/stackable/zookeeper:3.9.2-stackable0.0.0-dev

rm --recursive scan_results
rm result.csv

mkdir --parents scan_results

for image in $images
    set scan_result_file "scan_results/"(string replace --all : _ "$image" | string replace --all / _)

    docker run --name neuvector neuvector/scanner -i $image-amd64
    docker cp neuvector:/var/neuvector/scan_result.json "$scan_result_file"
    docker stop neuvector
    docker rm neuvector

    ./filter.py "$scan_result_file" >> result.csv
end
