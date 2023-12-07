# containerized

In this sample a golang written app is packaged and run inside a docker container.

## Requirements

These apps are part of a Go Project, which is defined by a Go Module.
To make this work, place this project inside a [Go Workspace](https://go.dev/doc/tutorial/workspaces).

## Usage

Execute the following from inside build/docker dir.

### Build docker image

```bash
docker image build \
	--tag aleogr.dev/containerized \
	--file Dockerfile \
	../../.
```

### Run containerized apps

```bash
docker container run \
    --rm \
    --detach \
    --name containerized \
    --publish 8080:8080 \
    aleogr.dev/containerized
```

### Verify docker env

```bash
docker image ls
docker container ps
```