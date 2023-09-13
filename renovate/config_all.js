module.exports = {
    repositories: [
        ".github",
        "airflow-operator",
        "beku.py",
        "ci",
        "commons-operator",
        "community",
        "configurator",
        "datenplatform",
        "docker-images",
        "docker_action_test",
        "documentation",
        "documentation-ui",
        "druid-opa-authorizer",
        "druid-operator",
        "edc-operator",
        "fc-service",
        "feature-tracker",
        "hadoop-opa-groupmapper",
        "hbase-normalizer",
        "hbase-operator",
        "hdfs-operator",
        "hello-world-operator",
        "hive-operator",
        "hive_migration_blog",
        "issues",
        "kafka-operator",
        "listener-operator",
        "merge-queue-test",
        "nifi-opa-authorizer",
        "nifi-operator",
        "nifi-rs",
        "nifi-webhook-authorizer",
        "ny-tlc-report",
        "opa-bundle-builder",
        "opa-operator",
        "operator-rs",
        "operator-skeleton",
        "operator-templating",
        "product-config",
        "product-config-demo",
        "release",
        "release-summarizer",
        "roadmap",
        "secret-operator",
        "spark-k8s-operator",
        "stackable-cockpit",
        "stackable-lib",
        "stackable-training",
        "stackable-utils",
        "stackablectl",
        "superset-operator",
        "t2",
        "test",
        "tokio-zookeeper",
        "trino-opa-authorizer",
        "trino-operator",
        "value-size",
        "zookeeper-operator",
    ],
    gitAuthor: "\"Stacky McStackface\" <serviceaccounts@stackable.tech>",
    includeForks: true,
    logFileLevel: 'debug',
    logLevel: 'debug',
    recreateClosed: 'true',
    force: {
      schedule: [],
      prCreation: "immediate",
    }
  };