ARG IMAGE_NAME="${IMAGE_NAME:-fedora-toolbox}"
ARG SOURCE_IMAGE="${SOURCE_IMAGE:-fedora-toolbox}"
ARG SOURCE_ORG="${SOURCE_ORG}"
ARG SOURCE_REGISTRY="${SOURCE_REGISTRY:-registry.fedoraproject.org}"
ARG BASE_IMAGE="${SOURCE_REGISTRY}/${SOURCE_ORG:+$SOURCE_ORG/}${SOURCE_IMAGE}"
ARG FEDORA_MAJOR_VERSION="${FEDORA_MAJOR_VERSION:-42}"
ARG IMAGE_REGISTRY=ghcr.io/nyahstack
ARG AKMODS_NVIDIA_REGISTRY="${AKMODS_NVIDIA_REGISTRY:-ghcr.io/ublue-os}"
ARG AKMODS_NVIDIA_IMAGE="${AKMODS_NVIDIA_IMAGE:-akmods-nvidia-open}"
ARG AKMODS_NVIDIA_IMAGE_DIGEST=""
ARG SOURCE_IMAGE_DIGEST=""

FROM scratch AS ctx
COPY /sys_files /sys_files
COPY /build_files /
COPY packages.json /

FROM ${AKMODS_NVIDIA_REGISTRY}/${AKMODS_NVIDIA_IMAGE}:main-${FEDORA_MAJOR_VERSION}${AKMODS_NVIDIA_IMAGE_DIGEST:+@${AKMODS_NVIDIA_IMAGE_DIGEST}} AS akmods_nvidia

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

FROM main as nvidia

RUN --mount=type=bind,from=ctx,src=/,dst=/ctx \
    --mount=type=cache,target=/var/cache \
    --mount=type=cache,target=/var/log \
    --mount=type=tmpfs,target=/tmp \
    --mount=type=bind,from=akmods_nvidia,src=/rpms,dst=/tmp/akmods-nv-rpms \
    rm -f /usr/bin/chsh && \
    rm -f /usr/bin/lchsh && \
    AKMODNV_PATH=/tmp/akmods-nv-rpms /ctx/nvidia-install.sh && \
    /ctx/post-install.sh
