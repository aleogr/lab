ARG BUILDER_IMG=cgr.dev/chainguard/go:latest
ARG RELEASE_IMG=cgr.dev/chainguard/static:latest-glibc

FROM ${BUILDER_IMG} AS builder
ENV CGO_ENABLED=0
ENV GOOS=linux
WORKDIR /build
COPY . .
RUN go mod tidy
RUN go mod download
RUN go build -C cmd/app1/

FROM ${RELEASE_IMG} AS release
WORKDIR /usr/local/bin
COPY --from=builder /build/cmd/app1/app1 .
ENTRYPOINT [ "/usr/local/bin/app1" ]
