# syntax=docker/dockerfile:1

# The official package selected by opend_version.json is built for Ubuntu 18.04
# on amd64. Digests below are the linux/amd64 manifests recorded in that file.
FROM --platform=linux/amd64 ubuntu:22.04@sha256:281c5745f657873d78e5531fc5ba8575f46ab7769b94550ac99543f122679986 AS fetch

ARG TARGETARCH
ARG FUTU_OPEND_VER
ARG FUTU_OPEND_SHA256

RUN test "$TARGETARCH" = amd64
WORKDIR /tmp
RUN apt-get update && \
    apt-get install --no-install-recommends -y ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*
COPY script/download_futu_opend.sh /usr/local/bin/download-futu-opend
RUN test -n "$FUTU_OPEND_VER" && \
    test -n "$FUTU_OPEND_SHA256" && \
    download-futu-opend \
      "$FUTU_OPEND_VER" \
      "Futu_OpenD_${FUTU_OPEND_VER}_Ubuntu18.04.tar.gz" \
      "$FUTU_OPEND_SHA256" && \
    tar -xzf "Futu_OpenD_${FUTU_OPEND_VER}_Ubuntu18.04.tar.gz"

# Keep bionic only as a reproducible compatibility baseline for Futu's bionic
# binary. It is out of Ubuntu standard support; migration is deliberately gated
# on binary dependency and no-credential startup validation.
FROM --platform=linux/amd64 ubuntu:18.04@sha256:dca176c9663a7ba4c1f0e710986f5a25e672842963d95b960191e2d9f7185ebe AS runtime

ARG TARGETARCH
ARG FUTU_OPEND_VER
ARG FUTU_UID=10001
ARG FUTU_GID=10001

RUN test "$TARGETARCH" = amd64 && \
    test -n "$FUTU_OPEND_VER" && \
    groupadd --gid "$FUTU_GID" futu && \
    useradd --uid "$FUTU_UID" --gid "$FUTU_GID" --create-home --home-dir /home/futu futu && \
    mkdir -p \
      /.futu \
      /etc/futu-opend \
      /opt/futu-opend \
      /home/futu/.com.futunn.FutuOpenD && \
    chown futu:futu /.futu /home/futu/.com.futunn.FutuOpenD && \
    command -v bash >/dev/null && \
    command -v flock >/dev/null

COPY --from=fetch \
  /tmp/Futu_OpenD_${FUTU_OPEND_VER}_Ubuntu18.04/Futu_OpenD_${FUTU_OPEND_VER}_Ubuntu18.04/ \
  /opt/futu-opend/
COPY --chmod=0755 script/start.sh /usr/local/bin/start-futu-opend
COPY --chmod=0755 script/init-key.sh /usr/local/bin/init-futu-key
COPY --chmod=0644 FutuOpenD.xml /etc/futu-opend/FutuOpenD.xml

ENV HOME=/home/futu \
    FUTU_LOGIN_MODE=remember \
    FUTU_OPEND_VERSION=${FUTU_OPEND_VER} \
    FUTU_OPEND_RSA_FILE_PATH=/.futu/futu.pem \
    FUTU_OPEND_IP=127.0.0.1 \
    FUTU_OPEND_PORT=11111 \
    FUTU_OPEND_TELNET_IP=127.0.0.1 \
    FUTU_OPEND_TELNET_PORT= \
    FUTU_OPEND_BIN=/opt/futu-opend/FutuOpenD \
    FUTU_OPEND_CONFIG_TEMPLATE=/etc/futu-opend/FutuOpenD.xml

LABEL org.opencontainers.image.version="${FUTU_OPEND_VER}" \
      org.opencontainers.image.base.name="ubuntu:18.04" \
      io.futu-opend.platform="linux/amd64"

USER 10001:10001

HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=3 \
  CMD test "$(cat /proc/1/comm)" = FutuOpenD && \
      grep -Fq "<api_port>${FUTU_OPEND_PORT}</api_port>" \
        "${FUTU_OPEND_RUNTIME_CONFIG:-/tmp/FutuOpenD.xml}" || exit 1

ENTRYPOINT ["/usr/local/bin/start-futu-opend"]
