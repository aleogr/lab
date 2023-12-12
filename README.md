# Lab

In this sample a golang written app is packaged and run inside a docker container.

## Requirements

These apps are part of a Go Project, which is defined by a Go Module.
To make this work, place this project inside a [Go Workspace](https://go.dev/doc/tutorial/workspaces).

## Build

### Build docker image

```bash
docker image build \
	--tag ghcr.io/aleogr/lab \
	--file build/docker/Dockerfile \
	.
```

### Push to registry

```bash
docker push \
	ghcr.io/aleogr/lab
```

### Sign image with private key

```bash
cosign sign \
	--key ~/.ssh/cosign.key \
	ghcr.io/aleogr/lab
```

## Run

### Verify image with public key

```bash
cosign verify \
	--key build/docker/cosign.pub \
	ghcr.io/aleogr/lab
```

### Run containerized apps

```bash
docker container run \
	--rm \
	--detach \
	--name lab \
	--publish 8080:8080 \
	ghcr.io/aleogr/lab
```

### Verify docker env

```bash
docker image ls
docker container ps
```