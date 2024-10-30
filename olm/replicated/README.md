# OKD on replicated

## Troubleshooting guide

### OLM

#### "community-operators" Pods are crashing due to "cache requires rebuild" error

Disable the community-operator catalog source which is enabled by default.
This is a source of problems such as [this](https://access.redhat.com/solutions/7049642)
and it prevents the Stackable ops from installation.

To disable the community-operators catalog source run:

```bash
kubectl patch operatorhubs/cluster --type merge --patch '{"spec":{"sources":[{"disabled": true,"name": "community-operators"}]}}'
```
