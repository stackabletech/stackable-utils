#!/usr/bin/env bash
#
# This scripts generates the OLM bundles from existing manifests.
#
# Usage
#
#   ./olm/build-bundles.sh [options]
#
# Options
#
#   -c <location of the RH cert operators repo>
#   -r <release>: the release number (mandatory). This must be a semver-compatible value to patch-level e.g. 23.1.0.
#   -o <operator-name>: the operator name (mandatory) e.g. airflow. Without the "-operator" suffix!
#   -d <deploy>: optional flag for operator deployment.
#
# Example
#
#   ./olm/build-bundles.sh \
#       -r 23.4.1 \
#       -o secret \
#       -c $HOME/repo/stackable/openshift-certified-operators \
#       -d

set -euo pipefail
set -x

SCRIPT_NAME=$(basename "$0")

parse_inputs() {
  VERSION=""
  OPERATOR=""
  DEPLOY=false

  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -r | --release)
      VERSION="$2"
      shift
      ;;
    -c)
      OPENSHIFT_ROOT="$2"
      shift
      ;;
    -o | --operator)
      OPERATOR="$2"
      shift
      ;;
    -d | --deploy) DEPLOY=true ;;
    *)
      echo "Unknown parameter passed: $1"
      exit 1
      ;;
    esac
    shift
  done
}

bundle-clean() {
  local OUTPUT_DIR="$1"
  rm -rf "$OUTPUT_DIR"
  rm -rf "bundle.Dockerfile"
}

bundle-build() {
  local OPERATOR="$1"
  local VERSION="$2"
  local INPUT_DIR="$3"
  local OUTPUT_DIR="$4"

  local BUNDLE_NAME="stackable-${OPERATOR}-operator"

  local CHANNEL="$(echo "$VERSION" | sed 's/\.[^.]*$//')"

  mkdir -p "$OUTPUT_DIR"
  cp -r "${INPUT_DIR}/manifests/" "$OUTPUT_DIR/manifests"
  cp -r "${INPUT_DIR}/metadata/" "$OUTPUT_DIR/metadata"

  cat > "${OUTPUT_DIR}/bundle.Dockerfile" <<BUNDLE_DOCKERFILE
FROM scratch

# Core bundle labels.
LABEL operators.operatorframework.io.bundle.mediatype.v1=registry+v1
LABEL operators.operatorframework.io.bundle.manifests.v1=manifests/
LABEL operators.operatorframework.io.bundle.metadata.v1=metadata/
LABEL operators.operatorframework.io.bundle.package.v1=stackable-${OPERATOR}-operator
LABEL operators.operatorframework.io.bundle.channels.v1=stable,${CHANNEL}
LABEL operators.operatorframework.io.bundle.channel.default.v1=${CHANNEL}
LABEL operators.operatorframework.io.metrics.builder=operator-sdk-v1.39.1
LABEL operators.operatorframework.io.metrics.mediatype.v1=metrics+v1
LABEL operators.operatorframework.io.metrics.project_layout=unknown

# Copy files to locations specified by labels.
COPY manifests /manifests/
COPY metadata /metadata/
BUNDLE_DOCKERFILE

  "${OPERATOR_SDK}" bundle validate "$OUTPUT_DIR"

  echo "Bundle built successfully!"
}

bundle-deploy() {
  local OPERATOR="$1"
  local VERSION="$2"
  local OUTPUT_DIR="$3"

  local BUNDLE_IMAGE="oci.stackable.tech/sandbox/${OPERATOR}-bundle:${VERSION}"

  local NAMESPACE="stackable-operators"

  if $DEPLOY; then

    docker build -t "$BUNDLE_IMAGE" -f "${OUTPUT_DIR}/bundle.Dockerfile" "${OUTPUT_DIR}"
    docker push "$BUNDLE_IMAGE"

    kubectl describe namespace "$NAMESPACE" || kubectl create namespace "$NAMESPACE"
    "$OPERATOR_SDK" run bundle "$BUNDLE_IMAGE" --namespace stackable-operators 
  else
    echo "Skip operator deployment!"
  fi
}

ensure_operator_sdk() {
  local OPERATOR_SDK_VERSION=v1.39.1
  OPERATOR_SDK="$HOME/.local/bin/operator-sdk"

	set +e
	which operator-sdk 2>/dev/null
	if [ "$?" != "0" ]; then
	  if [ ! -f "$OPERATOR_SDK" ]; then
	    mkdir -p $(dirname $OPERATOR_SDK)
	    OS=$(go env GOOS)
	    ARCH=$(go env GOARCH)
	    curl -sSLo "$OPERATOR_SDK" "https://github.com/operator-framework/operator-sdk/releases/download/${OPERATOR_SDK_VERSION}/operator-sdk_${OS}_${ARCH}"
	    chmod +x "$OPERATOR_SDK"
	  fi
	else
    OPERATOR_SDK=$(which operator-sdk)
	fi

	set -e
}

main() {
  ensure_operator_sdk

  parse_inputs "$@"
  if [ -z "${VERSION}" ] || [ -z "${OPENSHIFT_ROOT}" ] || [ -z "${OPERATOR}" ]; then
    echo "Usage: $SCRIPT_NAME -r <release> -o <operator> -c <path-to-openshift-repo>"
    exit 1
  fi

  if [ "$OPERATOR" == "spark-k8s" ]; then
    echo "Renaming operator from spark-k8s to spark"
    OPERATOR="spark"
  fi

  INPUT_DIR="${OPENSHIFT_ROOT}/operators/stackable-${OPERATOR}-operator/${VERSION}"
  OUTPUT_DIR="/tmp/bundle/stackable-${OPERATOR}-operator/${VERSION}"

  bundle-clean "$OUTPUT_DIR"
  bundle-build "$OPERATOR" "$VERSION" "$INPUT_DIR" "$OUTPUT_DIR"
  bundle-deploy "$OPERATOR" "$VERSION" "$OUTPUT_DIR"
}

main "$@"
