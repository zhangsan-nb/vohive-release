# syntax=docker/dockerfile:1
FROM alpine:3.22

ARG TARGETARCH
ARG TARGETVARIANT

LABEL org.opencontainers.image.title="VoHive"
LABEL org.opencontainers.image.version="v1.5.5-10-gf9eb85d"
LABEL org.opencontainers.image.source="https://github.com/zhangsan-nb/vohive-release"

WORKDIR /app

RUN set -eux; \
    apk add --no-cache ca-certificates curl tzdata; \
    detected_arch="${TARGETARCH:-$(apk --print-arch)}"; \
    case "${detected_arch}" in \
      amd64|x86_64) \
        asset_arch="amd64"; \
        expected_sha256="841d117d4921718b2627a6485b09c62d858c088e42e6e55468ae0f3e0ece1bdd" \
        ;; \
      arm64|aarch64) \
        asset_arch="arm64"; \
        expected_sha256="4cbfcec06b719609f3d88714b4df63c420e1cf958fbad0b4851a3c495c595661" \
        ;; \
      arm|armv7|armv7l) \
        if [ -n "${TARGETVARIANT:-}" ] && [ "${TARGETVARIANT}" != "v7" ]; then \
          echo "不支持的 ARM 变体: ${TARGETVARIANT}" >&2; \
          exit 1; \
        fi; \
        asset_arch="armv7"; \
        expected_sha256="682f3dc02a59bbbdb7128e71f212ca0a0c2d1825efa27e35bbf1537496625766" \
        ;; \
      *) \
        echo "不支持的 Docker 架构: ${detected_arch}" >&2; \
        exit 1 \
        ;; \
    esac; \
    asset="vohive_v1.5.5-10-gf9eb85d_linux_${asset_arch}"; \
    url="https://github.com/zhangsan-nb/vohive-release/releases/download/v1.5.5-10-gf9eb85d/${asset}"; \
    curl -fL --retry 3 "${url}" -o /app/vohive; \
    echo "${expected_sha256}  /app/vohive" | sha256sum -c -; \
    chmod 0755 /app/vohive; \
    mkdir -p /app/config /app/data /app/logs

ENV TZ=Asia/Shanghai
EXPOSE 7575
STOPSIGNAL SIGTERM

ENTRYPOINT ["/app/vohive"]
CMD ["-c", "/app/config/config.yaml"]
