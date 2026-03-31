#!/usr/bin/bash

usage() {
  echo "Usage: $0 --operator OPERATOR --version VERSION --submit SUBMIT"
  echo ""
  echo "  --operator  Operator name (e.g. opa, opensearch)"
  echo "  --version   Release version (e.g. 26.3.0)"
  echo "  --submit    Whether to submit the pipeline for certification upstream (true|false)"
  echo "  --help      Show this help message"
  exit 0
}

SUBMIT=
OPERATOR=
VERSION=

while [[ $# -gt 0 ]]; do
  case $1 in
    --submit)   SUBMIT="$2";   shift 2 ;;
    --operator) OPERATOR="$2"; shift 2 ;;
    --version)  VERSION="$2";  shift 2 ;;
    --help)     usage ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$OPERATOR" || -z "$VERSION" || -z "$SUBMIT" ]]; then
  echo "Error: --operator, --version, and --submit are required."
  echo ""
  usage
fi

GIT_REPO_URL=https://github.com/stackabletech/openshift-certified-operators
BUNDLE_PATH=operators/stackable-${OPERATOR}-operator/${VERSION}
GIT_BRANCH=stackable-${OPERATOR}-${VERSION}
GIT_USER=StackableOpenShift

PIPELINE_OUTPUT=$(tkn pipeline start operator-ci-pipeline \
--namespace stackable-operators \
--use-param-defaults \
--param git_repo_url=$GIT_REPO_URL \
--param git_branch=$GIT_BRANCH \
--param git_username=$GIT_USER \
--param bundle_path=$BUNDLE_PATH \
--param upstream_repo_name=redhat-openshift-ecosystem/certified-operators \
--param submit=$SUBMIT \
--param env=prod \
--workspace name=pipeline,volumeClaimTemplateFile=olm/templates/workspace-template.yml \
--showlog 2>&1 | tee /dev/stderr)

if [[ "$SUBMIT" == "true" ]]; then
  PR_URL=$(echo "$PIPELINE_OUTPUT" | grep -oP '(?<=\[open-pull-request : open-pull-request\] )https://\S+')
  if [[ -n "$PR_URL" ]]; then
    echo ""
    echo "Upstream PR: $PR_URL"
  else
    echo ""
    echo "Warning: could not find upstream PR URL in pipeline output."
  fi
else
  echo ""
  echo "No upstream PR (--submit is false)."
fi
