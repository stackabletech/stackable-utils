#!/bin/bash
# Install a single node deployment of Stackable

HOSTNAME=`/usr/bin/hostname -f`
GPG_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xce45c7a0a3e41385acd4358916dd12f5c7a6d76a"

# This is the list of currently supported operators for Stackable Quickstart
# Don't edit this list unless you know what you're doing. If you get an error
# that you're attempting to install an unsupported operator then check the 
# OPERATORS list for typos.
ALLOWED_OPERATORS=(zookeeper kafka nifi spark)

# Do you want to use the dev or release repository?
REPO_TYPE=dev

# List of operators to install
OPERATORS=(zookeeper kafka nifi spark)

function install_prereqs {
  . /etc/os-release

  if [ "$ID" = "centos" ] || [ "$ID" = "redhat" ]; then
    if [ "$VERSION" = "8" ] || [ "$VERSION" = "7" ]; then
      echo "$ID $VERSION found"
      REPO_URL="https://repo.stackable.tech/repository/rpm-${REPO_TYPE}/el${VERSION}"
      install_prereqs_redhat
    else
      echo "Only Redhat/CentOS 7 & 8 are supported. This host is running $VERSION."
    fi
  elif [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
    REPO_URL="https://repo.stackable.tech/repository/deb-${REPO_TYPE}"
    install_prereqs_debian
  fi
}

function install_prereqs_redhat {
  /usr/bin/echo "Installing Stackable YUM repo"

  if [ -z $REPO_URL ]; then
    /usr/bin/echo "No YUM repo URL found, exiting."
    exit 1
  fi

  # Download the Stackable GPG key used for package signing
  /usr/bin/yum -y install gnupg2 java-1.8.0-openjdk
  /usr/bin/curl -s "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xce45c7a0a3e41385acd4358916dd12f5c7a6d76a" > /etc/pki/rpm-gpg/RPM-GPG-KEY-stackable
  /usr/bin/rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-stackable

  # Create YUM repo configuration file
  # TODO: Enable GPG checking on Stackable repo
  /usr/bin/yum-config-manager --add-repo=$REPO_URL
  /usr/bin/yum clean all
}


function install_prereqs_debian {
  echo "Installing Stackable APT repo"

  if [ -z $REPO_URL ]; then
    /usr/bin/echo "No YUM repo URL found, exiting."
    exit 1
  fi

  apt-get install gnupg openjdk-8-jdk -y
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 16dd12f5c7a6d76a
  echo "deb $REPO_URL buster main" > /etc/apt/sources.list.d/stackable.list
  apt update
}


function install_k8s {
  echo "Installing K8s"
  /usr/bin/curl -sfL https://get.k3s.io | /bin/sh -
  /usr/local/bin/kubectl cluster-info

  echo "Copying K8s configuration to /root/.kube/config"
  /usr/bin/mkdir -p /root/.kube
  /usr/bin/cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
}

function install_crds {
  # TODO: Install the CRDs based on the list of operators to install
  echo "Installing Stackable CRDs"
  curl -s -S https://raw.githubusercontent.com/stackabletech/zookeeper-operator/main/deploy/crd/zookeepercluster.crd.yaml | kubectl apply -f -
  curl -s -S https://raw.githubusercontent.com/stackabletech/kafka-operator/main/deploy/crd/kafkacluster.crd.yaml | kubectl apply -f -
  curl -s -S https://raw.githubusercontent.com/stackabletech/spark-operator/main/deploy/crd/sparkcluster.crd.yaml | kubectl apply -f -
  curl -s -S https://raw.githubusercontent.com/stackabletech/spark-operator/main/deploy/crd/start.command.crd.yaml | kubectl apply -f -
  curl -s -S https://raw.githubusercontent.com/stackabletech/spark-operator/main/deploy/crd/stop.command.crd.yaml | kubectl apply -f -
  curl -s -S https://raw.githubusercontent.com/stackabletech/spark-operator/main/deploy/crd/restart.command.crd.yaml | kubectl apply -f -
  curl -s -S https://raw.githubusercontent.com/stackabletech/agent/main/deploy/crd/repository.crd.yaml | kubectl apply -f -
  curl -s -S https://raw.githubusercontent.com/stackabletech/nifi-operator/main/deploy/crd/nificluster.crd.yaml | kubectl apply -f -
}

function install_stackable_k8s_repo {
  echo Installing Stackable package repo
  cat <<EOF | kubectl apply -f -
apiVersion: "stable.stackable.de/v1"
kind: Repository
metadata:
  name: stackablepublic
spec:
  repo_type: StackableRepo
  properties:
    url: https://repo.stackable.tech/repository/packages/
EOF
}

function check_operator_list {
  for OPERATOR in ${OPERATORS[@]}; do
    if [[ ! " ${ALLOWED_OPERATORS[@]} " =~ " ${OPERATOR} " ]]; then
      echo "Operator $OPERATOR is not in the allowed operator list."
      exit 1
    fi
  done
  echo "List of operators checked"
}

function install_operator {
  operator=$1

  if [ "$ID" == "redhat" ] || [ "$ID" == "centos" ]; then
    /usr/bin/yum -y install stackable
  fi
}

function install_stackable_operators {
  echo "Installing Stackable operators"
#  for OPERATOR in ${OPERATORS[@]}; do
#    install_operator($OPERATOR)
#  done 

  apt install -y stackable-spark-operator-server stackable-zookeeper-operator-server stackable-kafka-operator-server stackable-nifi-operator-server
  systemctl enable stackable-spark-operator-server
  systemctl enable stackable-kafka-operator-server
  systemctl enable stackable-zookeeper-operator-server
  systemctl enable stackable-nifi-operator-server
  systemctl start stackable-spark-operator-server
  systemctl start stackable-kafka-operator-server
  systemctl start stackable-zookeeper-operator-server
  systemctl start stackable-nifi-operator-server
}

# MAIN
# Check the list of operators to deploy against the allowed list
check_operator_list

# Install the prerequisite OS-dependant repos and packages
install_prereqs

# Install the K3s Kubernetes distribution
install_k8s
exit

install_stackable_k8s_repo
install_stackable_operators

echo Installing Stackable agent
apt install -y stackable-agent
echo "--hostname=$HOSTNAME" > /etc/stackable/stackable-agent/agent.conf
systemctl enable stackable-agent
systemctl start stackable-agent
kubectl certificate approve ${HOSTNAME}-tls
kubectl get nodes

echo Deploying Apache Zookeeper
kubectl apply -f - <<EOF
apiVersion: zookeeper.stackable.tech/v1
kind: ZookeeperCluster
metadata:
  name: simple
spec:
  version: 3.4.14
  servers:
    selectors:
      default:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${HOSTNAME}
        instances: 1
        instancesPerNode: 1
EOF

echo Deploying Apache Kafka
kubectl apply -f - <<EOF
apiVersion: kafka.stackable.tech/v1
kind: KafkaCluster
metadata:
  name: simple
spec:
  version:
    kafka_version: 2.8.0
  zookeeperReference:
    namespace: default
    name: simple
  opaReference:
    namespace: default
    name: simple-opacluster
  brokers:
    selectors:
      default:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${HOSTNAME}
        instances: 1
        instancesPerNode: 1
EOF

echo Deploying Apache Spark
kubectl apply -f - <<EOF
apiVersion: spark.stackable.tech/v1
kind: SparkCluster
metadata:
  name: simple
spec:
  version: "3.0.1"
  masters:
    selectors:
      default:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${HOSTNAME}
        instances: 1
        instancesPerNode: 1
        config:
          masterPort: 7078
          masterWebUiPort: 8081
  workers:
    selectors:
      2core2g:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${HOSTNAME}
        instances: 1
        instancesPerNode: 1
        config:
          cores: 2
          memory: "2g"
          workerPort: 3031
          workerWebUiPort: 8083
  historyServers:
    selectors:
      default:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${HOSTNAME}
        instances: 1
        instancesPerNode: 1
        config:
          historyWebUiPort: 18081
EOF

echo Deploying Apache Nifi
kubectl apply -f - <<EOF
apiVersion: nifi.stackable.tech/v1
kind: NifiCluster
metadata:
  name: simple-nificluster
spec:
  version: "1.13.2"
  zookeeperReference:
    name: simple
    namespace: default
    chroot: /nifi
  nodes:
    selectors:
      default:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${HOSTNAME}
        instances: 1
        instancesPerNode: 1
        config:
          httpPort: 10000
          nodeProtocolPort: 10443
          nodeLoadBalancingPort: 6342
EOF

# TODO: Create TLS certificate
# TODO: Create Spark client configuration
# TODO: Install Python
# TODO: Write output to a log file an tidy up the user feedback


# TODO: Install OpenLDAP and boostrap with default creds
# kubectl create secret generic openldap --from-literal=adminpassword=adminpassword \
# --from-literal=users=user01,user02 \
# --from-literal=passwords=password01,password02
