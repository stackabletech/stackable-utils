#!/bin/bash
# Install a single node deployment of Stackable

# This is a dirty hack to get two K8s nodes running on a single machine.
# Use the shortname if hostname returns the FQDN or vice versa.
if [ "$(hostname -s)" = "$(hostname -f)" ]; then
  echo "Shortname matches FQDN. Host must have a dot in its hostname."
  exit 1
fi

if [ "$(hostname)" = "$(hostname -f)" ]; then
  K8S_HOSTNAME=`/usr/bin/hostname -s`
else
  K8S_HOSTNAME=`/usr/bin/hostname -f`
fi

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
    if [ "$VERSION_ID" = "8" ] || [ "$VERSION_ID" = "7" ]; then
      echo "$ID $VERSION found"
      REPO_URL="https://repo.stackable.tech/repository/rpm-${REPO_TYPE}/el${VERSION_ID}"
      INSTALLER=/usr/bin/yum
      install_prereqs_redhat
    else
      echo "Only Redhat/CentOS 7 & 8 are supported. This host is running $VERSION_ID."
      exit 1
    fi
  elif [ "$ID" = "ubuntu" ]; then
    if [ "$VERSION_ID" = "20.04" ]; then
      echo "$ID $VERSION_ID found"
      REPO_URL="https://repo.stackable.tech/repository/deb-${REPO_TYPE}"
      INSTALLER=apt
      install_prereqs_ubuntu
    else
      echo "Only Ubuntu 20.04 LTS is supported. This host is running $ID $VERSION_ID."
      exit 1
    fi
  elif [ "$ID" = "debian" ]; then
    if [ "$VERSION_ID" = "10" ]; then
      echo "$ID $VERSION_ID found"
      REPO_URL="https://repo.stackable.tech/repository/deb-${REPO_TYPE}"
      INSTALLER=apt
      install_prereqs_debian
    else
      echo "Only Debian 10 is supported. This host is running $ID $VERSION_ID."
      exit 1
    fi
  else
    echo "Unsupported operating system detected: $ID $VERSION_ID"
    exit 1
  fi
}

function install_prereqs_redhat {
  /usr/bin/echo "Installing Stackable YUM repo"

  if [ -z $REPO_URL ]; then
    /usr/bin/echo "No YUM repo URL found, exiting."
    exit 1
  fi

  # Download the Stackable GPG key used for package signing
  /usr/bin/yum -y install gnupg2 java-11-openjdk curl
  /usr/bin/curl -s "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xce45c7a0a3e41385acd4358916dd12f5c7a6d76a" > /etc/pki/rpm-gpg/RPM-GPG-KEY-stackable
  /usr/bin/rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-stackable

  # Create YUM repo configuration file
  # TODO: Enable GPG checking on Stackable repo
  echo "[stackable]
name=Stackable ${REPO_TYPE} repo
baseurl=${REPO_URL}
enabled=1
gpgcheck=0" > /etc/yum.repos.d/stackable.repo
  /usr/bin/yum clean all
}

function install_prereqs_debian {
  echo "Installing Stackable APT repo"

  if [ -z $REPO_URL ]; then
    /usr/bin/echo "No YUM repo URL found, exiting."
    exit 1
  fi

  apt-get -y install gnupg openjdk-11-jdk curl
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 16dd12f5c7a6d76a
  echo "deb $REPO_URL buster main" > /etc/apt/sources.list.d/stackable.list
  apt clean
  apt update
}

function install_prereqs_ubuntu {
  echo "Installing Stackable APT repo"

  if [ -z $REPO_URL ]; then
    /usr/bin/echo "No YUM repo URL found, exiting."
    exit 1
  fi

  apt-get -y install gnupg openjdk-11-jdk curl
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
  kubectl apply -f - <<EOF
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
  OPERATOR=$1
  PKG_NAME=stackable-${OPERATOR}-operator
  echo "Installing Stackable operator for ${OPERATOR}"

  $INSTALLER -y install ${PKG_NAME}

  /usr/bin/systemctl enable ${PKG_NAME}
  /usr/bin/systemctl start ${PKG_NAME}
}

function install_stackable_operators {
  echo "Installing Stackable operators"
  for OPERATOR in ${OPERATORS[@]}; do
    install_operator $OPERATOR
  done 
}

function install_stackable_agent {
  echo "Installing Stackable agent"
  ${INSTALLER} -y install stackable-agent
  echo "--hostname=$K8S_HOSTNAME" > /etc/stackable/stackable-agent/agent.conf
  systemctl enable stackable-agent
  systemctl start stackable-agent
  kubectl certificate approve ${K8S_HOSTNAME}-tls
  kubectl get nodes
}

function deploy_zookeeper {
  echo "Deploying Apache Zookeeper"
  kubectl apply -f - <<EOF
---
apiVersion: zookeeper.stackable.tech/v1alpha1
kind: ZookeeperCluster
metadata:
  name: simple
spec:
  version: 3.5.8
  servers:
    roleGroups:
      default:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${K8S_HOSTNAME}
        replicas: 3
        config:
          adminPort: 12000
          metricsPort: 9505
EOF
}

function deploy_kafka {
  echo Deploying Apache Kafka
  kubectl apply -f - <<EOF
---
apiVersion: kafka.stackable.tech/v1alpha1
kind: KafkaCluster
metadata:
  name: simple
spec:
  version:
    kafka_version: 2.8.0
  zookeeperReference:
    namespace: default
    name: simple
  brokers:
    roleGroups:
      default:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${K8S_HOSTNAME}
        replicas: 3
        config:
          logDirs: "/tmp/kafka-logs"
          metricsPort: 9606
EOF
}

function deploy_spark {
  echo Deploying Apache Spark
  kubectl apply -f - <<EOF
apiVersion: spark.stackable.tech/v1alpha1
kind: SparkCluster
metadata:
  name: simple
spec:
  version: "3.0.1"
  config:
    logDir: "file:///tmp"
    enableMonitoring: true
  masters:
    roleGroups:
      default:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${K8S_HOSTNAME}
        replicas: 1
        config:
          masterPort: 7078
          masterWebUiPort: 8081
  workers:
    roleGroups:
      2core2g:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${K8S_HOSTNAME}
        replicas: 1
        config:
          cores: 2
          memory: "2g"
          workerPort: 3031
          workerWebUiPort: 8083
  historyServers:
    roleGroups:
      default:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${K8S_HOSTNAME}
        replicas: 1
        config:
          historyWebUiPort: 18081
EOF
}

function deploy_nifi {
echo Deploying Apache Nifi
kubectl apply -f - <<EOF
---
apiVersion: nifi.stackable.tech/v1alpha1
kind: NifiCluster
metadata:
  name: simple
spec:
  metricsPort: 8428
  version: "1.13.2"
  zookeeperReference:
    name: simple
    namespace: default
    chroot: /nifi
  nodes:
    roleGroups:
      default:
        selector:
          matchLabels:
            kubernetes.io/hostname: ${K8S_HOSTNAME}
        replicas: 3
        config:
          nifiWebHttpPort: 10000
          nifiClusterNodeProtocolPort: 10443
          nifiClusterLoadBalancePort: 6342
EOF
}



# MAIN
# Check the list of operators to deploy against the allowed list
check_operator_list

# Install the prerequisite OS-dependant repos and packages
install_prereqs

# Install the K3s Kubernetes distribution
install_k8s

# Install the Stackable CRDs
install_crds

# Install the Stackable operators for the chosen components
install_stackable_operators

# Install the Stackable agent
install_stackable_agent

# Install the Stackable Kubernetes repo
install_stackable_k8s_repo

# Deploy Stackable Components
for OPERATOR in ${OPERATORS[@]}; do
  echo "Deploying ${OPERATOR}"
  deploy_${OPERATOR}
done

# Tested on CentOS 8
# Tested on Ubuntu 20.04
# Testing Debian 9
# Testing Debian 10

# TODO: Create TLS certificate
# TODO: Create Spark client configuration
# TODO: Install Python
# TODO: Write output to a log file an tidy up the user feedback


# TODO: Install OpenLDAP and boostrap with default creds
# kubectl create secret generic openldap --from-literal=adminpassword=adminpassword \
# --from-literal=users=user01,user02 \
# --from-literal=passwords=password01,password02
