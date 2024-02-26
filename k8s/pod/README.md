# [Pod](https://kubernetes.io/docs/concepts/workloads/pods/)

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
