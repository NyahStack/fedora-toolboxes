#!/bin/bash

set -ouex pipefail

FRELEASE="$(rpm -E %fedora)"
: "${AKMODNV_PATH:=/tmp/akmods-rpms}"

# this is only to aid in human understanding of any issues in CI
find "${AKMODNV_PATH}"/

if ! command -v dnf5 >/dev/null; then
    echo "Requires dnf5... Exiting"
    exit 1
fi

# Check if any rpmfusion repos exist before trying to disable them
if dnf5 repolist --all | grep -q rpmfusion; then
    dnf5 config-manager setopt "rpmfusion*".enabled=0
fi

# Always try to disable cisco repo (or add similar check)
dnf5 config-manager setopt fedora-cisco-openh264.enabled=0

## nvidia install steps
dnf5 install -y "${AKMODNV_PATH}"/ublue-os/ublue-os-nvidia-addons-*.rpm

# Install MULTILIB packages from negativo17-multimedia prior to disabling repo

MULTILIB=(
    mesa-dri-drivers.i686
    mesa-filesystem.i686
    mesa-libEGL.i686
    mesa-libGL.i686
    mesa-libgbm.i686
    mesa-vulkan-drivers.i686
)

# F44 does not need this: https://src.fedoraproject.org/rpms/mesa/c/f747343d109d2b691d3abcf4649cd10ad42d6578?branch=f44
dnf5 install -y "${MULTILIB[@]}"
if [ "$FRELEASE" -lt 44 ]; then
    dnf5 install -y mesa-va-drivers.i686
fi

# enable repos provided by ublue-os-nvidia-addons
dnf5 config-manager setopt fedora-nvidia.enabled=1

# Disable Multimedia
NEGATIVO17_MULT_PREV_ENABLED=N
if dnf5 repolist --enabled | grep -q "fedora-multimedia"; then
    NEGATIVO17_MULT_PREV_ENABLED=Y
    echo "disabling negativo17-fedora-multimedia to ensure negativo17-fedora-nvidia is used"
    dnf5 config-manager setopt fedora-multimedia.enabled=0
fi

dnf5 install -y \
    libnvidia-fbc \
    libnvidia-ml.i686 \
    libva-nvidia-driver \
    nvidia-driver-cuda-libs \
    nvidia-driver-cuda-libs.i686 \
    nvidia-driver-libs \
    nvidia-driver-libs.i686

## nvidia post-install steps
# disable repos provided by ublue-os-nvidia-addons
dnf5 config-manager setopt fedora-nvidia.enabled=0 fedora-nvidia-lts.enabled=0

# re-enable negativo17-mutlimedia since we disabled it
if [[ "${NEGATIVO17_MULT_PREV_ENABLED}" = "Y" ]]; then
    dnf5 config-manager setopt fedora-multimedia.enabled=1
fi
