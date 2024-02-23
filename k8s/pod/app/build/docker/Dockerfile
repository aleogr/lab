ARG BUILDER_IMG_VERSION=latest
ARG RELEASE_IMG_VERSION=latest-glibc

FROM cgr.dev/chainguard/go:${BUILDER_IMG_VERSION} AS builder
ENV CGO_ENABLED=0
ENV GOOS=linux
WORKDIR /build
COPY . .
RUN go mod tidy
RUN go mod download
RUN go build -C cmd/app1/

FROM cgr.dev/chainguard/static:${RELEASE_IMG_VERSION} AS release
WORKDIR /usr/local/bin
COPY --from=builder /build/cmd/app1/app1 .
ENTRYPOINT [ "/usr/local/bin/app1" ]
