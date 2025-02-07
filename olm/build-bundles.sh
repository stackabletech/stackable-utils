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
  local BUNDLE_NAME="$1"
  local INPUT_DIR="$2"
  local OUTPUT_DIR="$3"

  mkdir -p "$OUTPUT_DIR"

  # Generate manifests
  "${OPERATOR_SDK}" generate bundle \
    --deploy-dir "$INPUT_DIR" \
    --output-dir "$OUTPUT_DIR" \
    --package "$BUNDLE_NAME"

  # For whatever reason,tThe generated CSV drops the spec.relatedImages and spec.install properties
  cp "${INPUT_DIR}"/manifests/*.clusterserviceversion.yaml "$OUTPUT_DIR/manifests"

  # Generate metadata
  "${OPERATOR_SDK}" generate bundle \
    --metadata \
    --output-dir "$OUTPUT_DIR" \
    --package "$BUNDLE_NAME" \
    --channels "stable,$CHANNEL" \
    --default-channel "$CHANNEL"

  # The annotations generated by the operator sdk do not include the openshift versions.
  grep com.redhat.openshift "$INPUT_DIR"/metadata/annotations.yaml >> "$OUTPUT_DIR"/metadata/annotations.yaml

  "${OPERATOR_SDK}" bundle validate "$OUTPUT_DIR"

  echo "Bundle built successfully!"
}

bundle-deploy() {
  local BUNDLE_IMAGE="$1"
  local NAMESPACE="${2:-stackable-operators}"

  if $DEPLOY; then

    docker build -t "$BUNDLE_IMAGE" -f bundle.Dockerfile .
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

  CHANNEL="$(echo "$VERSION" | sed 's/\.[^.]*$//')"

  if [ "$OPERATOR" == "spark-k8s" ]; then
    echo "Renaming operator from spark-k8s to spark"
    OPERATOR="spark"
  fi

  BUNDLE_NAME="${OPERATOR}-operator"
  BUNDLE_IMAGE="oci.stackable.tech/sandbox/${OPERATOR}-bundle:${VERSION}"
  INPUT_DIR="${OPENSHIFT_ROOT}/operators/stackable-${OPERATOR}-operator/${VERSION}"
  OUTPUT_DIR="bundle/stackable-${OPERATOR}-operator/${VERSION}"

  # clean up any residual files from previous actions
  bundle-clean "$OUTPUT_DIR"
  bundle-build "$BUNDLE_NAME" "$INPUT_DIR" "$OUTPUT_DIR"
  bundle-deploy "$BUNDLE_IMAGE"
}

main "$@"
