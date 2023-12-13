# Docker Lab

This lab is intended to experiment good practices related to dockerized apps building.

Here you'll find:
* Docker image naming convention
* Signing and verifying published image with [cosign](https://github.com/sigstore/cosign)
* Publishing public ssh-key alongside source code
* Allow List strategy for .dockerignore file (exception for denials)
* Build context handling for a subdir hosted Dockerfile
* Multi-stage building with lean base images
* Pre-Defined Annotation Keys from [image-spec](https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys)


## Requirements

These containerized apps are part of a Go Project, which is defined by a Go Module.

To make this work, place this project inside a [Go Workspace](https://go.dev/doc/tutorial/workspaces).

## Build

### Build docker image

```bash
docker image build \
	--tag ghcr.io/aleogr/docker \
	--file build/docker/Dockerfile \
	.
```

### Push to registry

```bash
docker push \
	ghcr.io/aleogr/docker
```

### Sign image with private key

```bash
cosign sign \
	--key ~/.ssh/cosign.key \
	ghcr.io/aleogr/docker
```

## Run

### Verify image with public key

```bash
cosign verify \
	--key build/docker/cosign.pub \
	ghcr.io/aleogr/docker
```

### Run containerized apps

```bash
docker container run \
	--rm \
	--detach \
	--name lab \
	--publish 8080:8080 \
	ghcr.io/aleogr/docker
```

### Verify docker env

```bash
docker image ls
docker container ps
```