# Overview

These notes are a summary of the more in-depth, internal documentation [here](https://app.nuclino.com/Stackable/Engineering/Certification-Process-a8cf57d0-bd41-4d56-b505-f59af4159a56).

# Prerequisites

- an [OpenShift](https://developers.redhat.com/products/openshift-local/overview) cluster with the `stackable-operators` namespace
- [opm](https://github.com/operator-framework/operator-registry/)
- docker and kubectl
- `kubeadmin` access: once logged in to an openshift cluster a secret is needed
```
export KUBECONFIG=~/.kube/config
oc create secret generic kubeconfig --from-file=kubeconfig=$KUBECONFIG --namespace stackable-operators
```
- [tkn](https://github.com/tektoncd/cli)
- a secret for `pyxis_api_key`: a token giving access to Redhat Connect 
- a secret for `github-api-token`: a token giving access to the RH repo

# Deployment

Stackable operators can be deployed to Openshift in one of three ways:

- Helm: either natively, or by using stackablectl
- Operator Catalog
- Certified Operators

The latter two require an operator to be deployed to an Openshift cluster, from where the operator (and its dependencies, if these have been defined) can be installed from the console UI. Both pathways use version-specific manifest files which are created in the [Stackable repository](https://github.com/stackabletech/openshift-certified-operators) that is forked from [here](https://github.com/redhat-openshift-ecosystem/certified-operators). These manifests are largely based on the templates used by helm, with the addition of Openshift-specific items (such as a ClusterServiceVersion manifest).

## Build the bundle

An operator bundle and catalog can be built and deployed using the `build-bundle.sh` script e.g.

```
./olm/build-bundles.sh -r 23.4.1 -b secret-23.4.1 -o secret-operator -d
```

Where:
- `-r <release>`: the release number (mandatory). This must be a semver-compatible value to patch-level e.g. 23.1.0.
- `-b <branch>`: the branch name (mandatory) in the (stackable forked) openshift-certified-operators repository.
- `-o <operator-name>`: the operator name (mandatory) e.g. airflow-operator.
- `-d <deploy>`: optional flag for catalog deployment.

The script creates a catalog specific to an operator. A catalog can contain bundles for multiple operators, but a 1:1 deployment makes it easier to deploy and test operators independently. Testing with a deployed catalog is essential as the certification pipeline should only be used for stable operators, and a certified operator can only be changed if a new version is specified.

## Use the CI pipeline

### Testing

This should either be called from the stackable-utils root folder, or the `volumeClaimTemplateFile` path should be changed accordingly.

```
export GIT_REPO_URL=https://github.com/stackabletech/openshift-certified-operators
export BUNDLE_PATH=operators/stackable-commons-operator/23.4.1
export LOCAL_BRANCH=commons-23.4.1

tkn pipeline start operator-ci-pipeline \
  --namespace stackable-operators \
  --param git_repo_url=$GIT_REPO_URL \
  --param git_branch=$LOCAL_BRANCH \
  --param bundle_path=$BUNDLE_PATH \
  --param env=prod \
  --param kubeconfig_secret_name=kubeconfig \
  --workspace name=pipeline,volumeClaimTemplateFile=olm/templates/workspace-template.yml \
  --showlog
```

### Certifying

This callout is identical to the previous one, with the addition of the last two parameters `upstream_repo_name` and `submit=true`:

```
export GIT_REPO_URL=https://github.com/stackabletech/openshift-certified-operators
export BUNDLE_PATH=operators/stackable-commons-operator/23.4.1
export LOCAL_BRANCH=commons-23.4.1

tkn pipeline start operator-ci-pipeline \
  --namespace stackable-operators \
  --param git_repo_url=$GIT_REPO_URL \
  --param git_branch=$LOCAL_BRANCH \
  --param bundle_path=$BUNDLE_PATH \
  --param env=prod \
  --param kubeconfig_secret_name=kubeconfig \
  --workspace name=pipeline,volumeClaimTemplateFile=olm/templates/workspace-template.yml \
  --showlog \
  --param upstream_repo_name=redhat-openshift-ecosystem/certified-operators \
  --param submit=true
```

A successful callout will result in a PR being opened in the Redhat repository, from where progress can be tracked.

