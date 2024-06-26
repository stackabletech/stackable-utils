module.exports = {
  repositories: [
    "stackabletech/airflow-operator",
    "stackabletech/beku.py",
    "stackabletech/commons-operator",
    "stackabletech/crddocs",
    "stackabletech/docker-images",
    "stackabletech/documentation",
    "stackabletech/documentation-ui",
    "stackabletech/druid-opa-authorizer",
    "stackabletech/druid-operator",
    "stackabletech/edc-operator",
    "stackabletech/hbase-normalizer",
    "stackabletech/hbase-operator",
    "stackabletech/hdfs-operator",
    "stackabletech/hdfs-topology-provider",
    "stackabletech/hdfs-utils",
    "stackabletech/hello-world-operator",
    "stackabletech/hive-operator",
    "stackabletech/image-tools",
    "stackabletech/kafka-operator",
    "stackabletech/listener-operator",
    "stackabletech/nifi-operator",
    "stackabletech/opa-bundle-builder",
    "stackabletech/opa-operator",
    "stackabletech/operator-rs",
    "stackabletech/operator-templating",
    "stackabletech/product-config",
    "stackabletech/secret-operator",
    "stackabletech/spark-k8s-operator",
    "stackabletech/stackable-cockpit",
    "stackabletech/stackable-utils",
    "stackabletech/superset-operator",
    "stackabletech/t2",
    "stackabletech/tokio-zookeeper",
    "stackabletech/trino-lb",
    "stackabletech/trino-operator",
    "stackabletech/zookeeper-operator",
  ],
  gitAuthor: "\"Stacky McStackface\" <serviceaccounts@stackable.tech>",
  forkProcessing: 'enabled',
  logFileLevel: 'info',
  branchConcurrentLimit: 0,
  prConcurrentLimit: 0,
  prHourlyLimit: 0,
  commitBodyTable: true,
  recreateWhen: "always",
  prCreation: "immediate",
  force: {
    schedule: [],
  }
};
