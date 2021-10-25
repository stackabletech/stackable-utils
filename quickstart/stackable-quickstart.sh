#!/bin/bash
# Install a single node deployment of Stackable

# This is the list of currently supported operators for Stackable Quickstart
# Don't edit this list unless you know what you're doing. If you get an error
# that you're attempting to install an unsupported operator then check the
# OPERATORS list for typos.
ALLOWED_OPERATORS=(zookeeper kafka nifi spark hive trino)

# Do you want to use the dev or release repository?
REPO_TYPE=dev

# List of operators to install
OPERATORS=(zookeeper kafka nifi spark hive trino)

if [ $UID != 0 ]
then
  echo "This script must be run as root, exiting."
  exit 1
fi

BASEDIR=$(dirname $0)
CONFDIR=$BASEDIR/conf

function print_r {
  /usr/bin/echo -e "\e[0;31m${1}\e[m"
}
function print_y {
  /usr/bin/echo -e "\e[0;33m${1}\e[m"
}
function print_g {
  /usr/bin/echo -e "\e[0;32m${1}\e[m"
}

# This is a dirty hack to get two K8s nodes running on a single machine.
# Use the shortname if hostname returns the FQDN or vice versa.
if [ "$(hostname -s)" = "$(hostname -f)" ]; then
  print_r "Shortname matches FQDN. Host must have a dot in its hostname."
  exit 1
fi

if [ "$(hostname)" = "$(hostname -f)" ]; then
  K8S_HOSTNAME=`/usr/bin/hostname -s`
else
  K8S_HOSTNAME=`/usr/bin/hostname -f`
fi

GPG_KEY_URL="https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xce45c7a0a3e41385acd4358916dd12f5c7a6d76a"

function install_prereqs {
  . /etc/os-release

  if [ "$ID" = "centos" ] || [ "$ID" = "redhat" ]; then
    if [ "$VERSION_ID" = "8" ] || [ "$VERSION_ID" = "7" ]; then
      print_g "$ID $VERSION found"
      REPO_URL="https://repo.stackable.tech/repository/rpm-${REPO_TYPE}/el${VERSION_ID}"
      INSTALLER=/usr/bin/yum
      install_prereqs_redhat
    else
      print_r "Only Redhat/CentOS 7 & 8 are supported. This host is running $VERSION_ID."
      exit 1
    fi
  elif [ "$ID" = "ubuntu" ]; then
    if [ "$VERSION_ID" = "20.04" ]; then
      print_g "$ID $VERSION_ID found"
      REPO_URL="https://repo.stackable.tech/repository/deb-${REPO_TYPE}"
      INSTALLER=apt
      install_prereqs_ubuntu
    else
      print_r "Only Ubuntu 20.04 LTS is supported. This host is running $ID $VERSION_ID."
      exit 1
    fi
  elif [ "$ID" = "debian" ]; then
    if [ "$VERSION_ID" = "10" ]; then
      print_g "$ID $VERSION_ID found"
      REPO_URL="https://repo.stackable.tech/repository/deb-${REPO_TYPE}"
      INSTALLER=apt
      install_prereqs_debian
    else
      print_r "Only Debian 10 is supported. This host is running $ID $VERSION_ID."
      exit 1
    fi
  else
    print_r "Unsupported operating system detected: $ID $VERSION_ID"
    exit 1
  fi
}

function install_prereqs_redhat {
  print_g "Installing Stackable YUM repo"

  if [ -z $REPO_URL ]; then
    print_r "No YUM repo URL found, exiting."
    exit 1
  fi

  # Download the Stackable GPG key used for package signing
  /usr/bin/yum -y install gnupg2 java-11-openjdk curl python
  /usr/bin/curl -s "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xce45c7a0a3e41385acd4358916dd12f5c7a6d76a" > /etc/pki/rpm-gpg/RPM-GPG-KEY-stackable
  /usr/bin/rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-stackable

  # Create YUM repo configuration file
  # TODO: Enable GPG checking on Stackable repo
  /usr/bin/echo "[stackable]
name=Stackable ${REPO_TYPE} repo
baseurl=${REPO_URL}
enabled=1
gpgcheck=0" > /etc/yum.repos.d/stackable.repo
  /usr/bin/yum clean all
}

function install_prereqs_debian {
  print_g "Installing Stackable APT repo"

  if [ -z $REPO_URL ]; then
    print_r "No APT repo URL found, exiting."
    exit 1
  fi

  apt-get -y install gnupg openjdk-11-jdk curl python
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 16dd12f5c7a6d76a
  echo "deb $REPO_URL buster main" > /etc/apt/sources.list.d/stackable.list
  apt clean
  apt update
}

function install_prereqs_ubuntu {
  print_g "Installing Stackable APT repo"

  if [ -z $REPO_URL ]; then
    print_r "No APT repo URL found, exiting."
    exit 1
  fi

  apt-get -y install gnupg openjdk-11-jdk curl python
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 16dd12f5c7a6d76a
  echo "deb $REPO_URL buster main" > /etc/apt/sources.list.d/stackable.list
  apt update
}

function install_k8s {
  print_g "Installing K8s"
  /usr/bin/curl -sfL https://get.k3s.io | /bin/sh -
  /usr/local/bin/kubectl cluster-info

  print_g "Copying K8s configuration to /root/.kube/config"
  /usr/bin/mkdir -p /root/.kube
  /usr/bin/cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
}

function install_crds {
  # TODO: Install the CRDs based on the list of operators to install
  print_g "Installing Stackable CRDs"
  # Stackable Agent
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/agent/main/deploy/crd/repository.crd.yaml
  # ZooKeeper Operator
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/zookeeper-operator/main/deploy/crd/zookeepercluster.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/zookeeper-operator/main/deploy/crd/start.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/zookeeper-operator/main/deploy/crd/stop.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/zookeeper-operator/main/deploy/crd/restart.crd.yaml
  # Kafka Operator
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/kafka-operator/main/deploy/crd/kafkacluster.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/kafka-operator/main/deploy/crd/start.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/kafka-operator/main/deploy/crd/stop.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/kafka-operator/main/deploy/crd/restart.crd.yaml
  # Spark Operator
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/spark-operator/main/deploy/crd/sparkcluster.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/spark-operator/main/deploy/crd/start.command.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/spark-operator/main/deploy/crd/stop.command.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/spark-operator/main/deploy/crd/restart.command.crd.yaml
  # NiFi Operator
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/nifi-operator/main/deploy/crd/nificluster.crd.yaml
  # Hive Operator
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/hive-operator/main/deploy/crd/databaseconnection.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/hive-operator/main/deploy/crd/hivecluster.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/hive-operator/main/deploy/crd/start.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/hive-operator/main/deploy/crd/stop.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/hive-operator/main/deploy/crd/restart.crd.yaml
  # Trino Operator
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/trino-operator/hackathon/deploy/crd/trinocluster.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/trino-operator/hackathon/deploy/crd/start.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/trino-operator/hackathon/deploy/crd/stop.crd.yaml
  kubectl apply -f https://raw.githubusercontent.com/stackabletech/trino-operator/hackathon/deploy/crd/restart.crd.yaml
}

function install_stackable_k8s_repo {
  print_g Installing Stackable package repo
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
  for OPERATOR in "${OPERATORS[@]}"; do
    if [[ ! " ${ALLOWED_OPERATORS[@]} " =~ " ${OPERATOR} " ]]; then
      print_r "Operator $OPERATOR is not in the allowed operator list."
      exit 1
    fi
  done
  print_g "List of operators checked"
}

function install_operator {
  OPERATOR=$1
  PKG_NAME=stackable-${OPERATOR}-operator
  print_g "Installing Stackable operator for ${OPERATOR}"

  $INSTALLER -y install ${PKG_NAME}

  /usr/bin/systemctl enable ${PKG_NAME}
  /usr/bin/systemctl start ${PKG_NAME}
}

function install_stackable_operators {
  print_g "Installing Stackable operators"
  for OPERATOR in "${OPERATORS[@]}"; do
    install_operator $OPERATOR
  done 
}

function install_stackable_agent {
  print_g "Installing Stackable agent"
  ${INSTALLER} -y install stackable-agent
  echo "--hostname=$K8S_HOSTNAME" > /etc/stackable/stackable-agent/agent.conf
  systemctl enable stackable-agent
  systemctl start stackable-agent
  kubectl certificate approve ${K8S_HOSTNAME}-tls
  kubectl get nodes
}

function deploy_service {
  SERVICE=$1
  CONF=${CONFDIR}/${SERVICE}.yaml
  if [ ! -f $CONF ]
  then
    print_r "Cannot find service configuration file ${CONF} for ${SERVICE}"
    exit 1
  fi

  print_g "Deploying ${SERVICE}"
  kubectl apply -f "${CONF}"
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
for OPERATOR in "${OPERATORS[@]}"; do
  print_g "Deploying ${OPERATOR}"
  deploy_service "${OPERATOR}"
done

# Tested on CentOS 8
# Tested on Ubuntu 20.04
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
