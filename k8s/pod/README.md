# [Pod](https://kubernetes.io/docs/concepts/workloads/pods/)

## Set namespace to current k8s context

```bash
kubectl config set-context \
    --current \
    --namespace=system
```

## Debug pod's container

```bash
kubectl debug $POD \
    --namespace system \
    --image busybox \
    --stdin --tty \
    --share-processes \
    --copy-to $POD-debug
```

## Rolling restart of a deployment

```bash
kubectl rollout restart \
    --namespace system \
    deployment/deployment-system
```
