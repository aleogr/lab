# Docker Lab

## Requirements

These containerized apps are part of a Go Project, which is defined by a Go Module.

To make this work, place this project inside a [Go Workspace](https://go.dev/doc/tutorial/workspaces).

## Build

### Build docker image

```bash
docker image build \
	--tag ghcr.io/aleogr/k8s-app \
	--file build/docker/Dockerfile \
	.
```

### Push to registry

```bash
docker push \
	ghcr.io/aleogr/k8s-app
```

### Sign image with private key

```bash
cosign sign \
	--key ~/.ssh/cosign.key \
	ghcr.io/aleogr/k8s-app
```

## Run

### Verify image with public key

```bash
cosign verify \
	--key build/docker/cosign.pub \
	ghcr.io/aleogr/k8s-app
```

### Run containerized apps

```bash
docker container run \
	--rm \
	--detach \
	--name k8s-app \
	--publish 8080:8080 \
	ghcr.io/aleogr/k8s-app
```

### Verify docker env

```bash
docker image ls
docker container ps
```
