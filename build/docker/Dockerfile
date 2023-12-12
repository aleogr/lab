FROM cgr.dev/chainguard/go AS builder
ENV CGO_ENABLED=0
ENV GOOS=linux
WORKDIR /build
COPY . .
RUN go mod tidy
RUN go mod download
RUN go build -C cmd/app1/

FROM cgr.dev/chainguard/static:latest-glibc AS release
LABEL org.opencontainers.image.source https://github.com/aleogr/lab
WORKDIR /usr/local/bin
COPY --from=builder /build/cmd/app1/app1 .
EXPOSE 8080
ENTRYPOINT [ "/usr/local/bin/app1" ]
