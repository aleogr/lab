# [Pod](https://kubernetes.io/docs/concepts/workloads/pods/)

## Create cluster

```bash
kind create cluster \
    --config cluster.yaml
```

## Create NGINX Ingress Controller

```bash
kubectl apply \
    -f ingress-controller.yaml
```

## Create and set default namespace

```bash
kubectl apply \
    -f namespace.yaml

kubectl config set-context \
    --current \
    --namespace=system
```

## Create resources

```bash
kubectl apply \
    -f resources/secret.yaml

kubectl apply \
    -f resources/configmap.yaml

kubectl apply \
    -f resources/deployment.yaml

kubectl apply \
    -f resources/hpa.yaml

kubectl apply \
    -f resources/service.yaml

kubectl apply \
    -f resources/ingress.yaml
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
