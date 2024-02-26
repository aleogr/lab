# [Pod](https://kubernetes.io/docs/concepts/workloads/pods/)

## Create cluster

```bash
kind create cluster \
    --config yaml/cluster.yaml
```

## Create NGINX Ingress Controller

```bash
kubectl apply \
    -f yaml/ingress-controller.yaml
```

## Create and set default namespace

```bash
kubectl apply \
    -f yaml/namespace.yaml

kubectl config set-context \
    --current \
    --namespace=system
```

## Create resources

```bash
kubectl apply \
    -f yaml/secret.yaml

kubectl apply \
    -f yaml/configmap.yaml

kubectl apply \
    -f yaml/deployment.yaml

kubectl apply \
    -f yaml/hpa.yaml

kubectl apply \
    -f yaml/service.yaml

kubectl apply \
    -f yaml/ingress.yaml
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
