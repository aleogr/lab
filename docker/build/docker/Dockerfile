FROM cgr.dev/chainguard/go AS builder
ENV CGO_ENABLED=0
ENV GOOS=linux
WORKDIR /build
COPY . .
RUN go mod tidy
RUN go mod download
RUN go build -C cmd/app1/

FROM cgr.dev/chainguard/static:latest-glibc AS release
LABEL org.opencontainers.image.title Docker Lab
LABEL org.opencontainers.image.description Good practices for dockerized apps
LABEL org.opencontainers.image.authors Alexandre Ogrodovski <contact@aleogr.dev>
LABEL org.opencontainers.image.source https://github.com/aleogr/lab
LABEL org.opencontainers.image.created 2023-12-12T03:49:15Z
LABEL org.opencontainers.image.licenses MIT
LABEL org.opencontainers.image.version latest
WORKDIR /usr/local/bin
COPY --from=builder /build/cmd/app1/app1 .
EXPOSE 8080
ENTRYPOINT [ "/usr/local/bin/app1" ]
