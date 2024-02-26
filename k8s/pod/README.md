# [Pod](https://kubernetes.io/docs/concepts/workloads/pods/)

## Debug

### Debug pod's container

```bash
kubectl debug $POD \
    --namespace system \
    --image busybox \
    --stdin --tty \
    --share-processes \
    --copy-to $POD-debug
```
