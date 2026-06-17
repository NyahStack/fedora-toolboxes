ARG IMAGE_NAME="${IMAGE_NAME:-fedora-toolbox}"
ARG SOURCE_IMAGE="${SOURCE_IMAGE:-fedora-toolbox}"
ARG SOURCE_ORG="${SOURCE_ORG}"
ARG SOURCE_REGISTRY="${SOURCE_REGISTRY:-registry.fedoraproject.org}"
ARG BASE_IMAGE="${SOURCE_REGISTRY}/${SOURCE_ORG:+$SOURCE_ORG/}${SOURCE_IMAGE}"
ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-42}"
ARG IMAGE_REGISTRY=ghcr.io/nyahstack
ARG SOURCE_IMAGE_DIGEST=""
ARG CHUNKAH_IMAGE="quay.io/coreos/chunkah"
ARG CHUNKAH_IMAGE_DIGEST=""
ARG CHUNK_SOURCE_IMAGE="scratch"

FROM ${CHUNK_SOURCE_IMAGE} AS chunk_source

FROM ${CHUNKAH_IMAGE}:latest@sha256:ff8b8b466a942ec6000445d4001fc661e2fc5a952ad9ee29b4de9ab09d1d1708${CHUNKAH_IMAGE_DIGEST:+@${CHUNKAH_IMAGE_DIGEST}} AS chunkah

ARG SOURCE_DATE_EPOCH
ARG OCI_IMAGE_TITLE
ARG OCI_IMAGE_VERSION
ARG OCI_IMAGE_DESCRIPTION
ARG OCI_IMAGE_SOURCE
ARG OCI_IMAGE_README_URL
ARG OCI_IMAGE_LOGO_URL
ENV SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}

RUN --mount=from=chunk_source,src=/,target=/chunkah,ro \
    --mount=type=bind,target=/run/src,rw \
    chunkah build \
    --max-layers 64 \
    --label=com.github.containers.toolbox=true \
    --label=usage="This image is meant to be used with the toolbox or distrobox command" \
    --label="org.opencontainers.image.title=${OCI_IMAGE_TITLE}" \
    --label="org.opencontainers.image.version=${OCI_IMAGE_VERSION}" \
    --label="org.opencontainers.image.description=${OCI_IMAGE_DESCRIPTION}" \
    --label="org.opencontainers.image.source=${OCI_IMAGE_SOURCE}" \
    --label="io.artifacthub.package.readme-url=${OCI_IMAGE_README_URL}" \
    --label="io.artifacthub.package.logo-url=${OCI_IMAGE_LOGO_URL}" \
    --output oci:/run/src/.chunkah-out

FROM oci:.chunkah-out AS chunked

FROM scratch AS ctx
COPY /sys_files /sys_files
COPY /build_files /
COPY packages.json /

FROM ${BASE_IMAGE}:${FEDORA_MAJOR_VERSION}${SOURCE_IMAGE_DIGEST:+@${SOURCE_IMAGE_DIGEST}} as main

ARG IMAGE_NAME="${IMAGE_NAME:-fedora-toolbox}"
ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-42}"

RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=secret,id=GITHUB_TOKEN,required=false \
    if [[ -f /run/secrets/GITHUB_TOKEN ]]; then export GITHUB_TOKEN="$(cat /run/secrets/GITHUB_TOKEN)"; fi && \
    rm -f /usr/bin/chsh && \
    rm -f /usr/bin/lchsh && \
    /ctx/install.sh && \
    /ctx/post-install.sh
