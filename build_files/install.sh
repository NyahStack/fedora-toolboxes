#!/usr/bin/bash

set -ouex pipefail

# Shared pinned versions
source /ctx/versions.env

# Copy shared system files onto root
rsync -rvK /ctx/sys_files/shared/ /

# Copy system files for the current image when present.
if [[ -n "${IMAGE_NAME:-}" ]] && [[ -d "/ctx/sys_files/systemd/${IMAGE_NAME}" ]]; then
    rsync -rvK "/ctx/sys_files/systemd/${IMAGE_NAME}/" /
fi

# make root's home
mkdir -p /var/roothome

# Install dnf5 if not installed
if ! rpm -q dnf5 >/dev/null; then
    dnf -y install dnf5 dnf5-plugins
fi

# mitigate upstream packaging bug: https://bugzilla.redhat.com/show_bug.cgi?id=2332429
# swap the incorrectly installed OpenCL-ICD-Loader for ocl-icd, the expected package
dnf5 -y swap --repo='fedora' \
    OpenCL-ICD-Loader ocl-icd

# Add COPRs only if not already enabled
if ! dnf5 repolist --enabled | grep -q 'ublue-os-packages'; then
    dnf5 -y copr enable ublue-os/packages
fi
if ! dnf5 repolist --enabled | grep -q 'ublue-os-staging'; then
    dnf5 -y copr enable ublue-os/staging
fi

# Install ublue-os packages, fedora archives,and zstd
dnf5 -y install \
    ublue-os-just \
    ublue-os-signing \
    fedora-repos-archive \
    zstd

# use negativo17 for 3rd party packages with higher priority than default
if ! grep -q fedora-multimedia <(dnf5 repolist); then
    # Enable or Install Repofile
    dnf5 config-manager setopt fedora-multimedia.enabled=1 ||
        dnf5 config-manager addrepo --from-repofile="https://negativo17.org/repos/fedora-multimedia.repo"
fi
# Set higher priority
dnf5 config-manager setopt fedora-multimedia.priority=90

# Replace podman provided policy.json with ublue-os one when present.
if [[ -f /usr/etc/containers/policy.json ]]; then
    mv /usr/etc/containers/policy.json /etc/containers/policy.json
fi

# use override to replace mesa and others with less crippled versions
OVERRIDES=(
    "intel-gmmlib"
    "intel-mediasdk"
    "intel-vpl-gpu-rt"
    "libheif"
    "libva"
    "libva-intel-media-driver"
    "mesa-dri-drivers"
    "mesa-filesystem"
    "mesa-libEGL"
    "mesa-libGL"
    "mesa-libgbm"
    "mesa-va-drivers"
    "mesa-vulkan-drivers"
)

dnf5 distro-sync --skip-unavailable -y --repo='fedora-multimedia' "${OVERRIDES[@]}"
dnf5 versionlock add "${OVERRIDES[@]}"

# Remove Fedora Flatpak and related packages
dnf5 remove -y \
    fedora-flathub-remote

# fedora-third-party has a trojan horse via plasma-discover requiring it in its spec, replace it with a dummy package.
dnf5 swap -y \
    fedora-third-party ublue-os-flatpak

# Add Flathub only for systemd variant where flatpak is installed natively.
if [[ "${IMAGE_NAME:-}" == "fedora-toolbox-systemd" ]]; then
    mkdir -p /etc/flatpak/remotes.d/
    curl --retry 3 --fail -Lo /etc/flatpak/remotes.d/flathub.flatpakrepo https://dl.flathub.org/repo/flathub.flatpakrepo
fi

# Ensure jq is available for package parsing
if ! rpm -q jq >/dev/null; then
    dnf5 -y install jq
fi

# run common packages script
/ctx/packages.sh

# Enable rootless podman subid bootstrap for systemd variant.
if [[ "${IMAGE_NAME:-}" == "fedora-toolbox-systemd" ]]; then
    systemctl enable podman-subids-setup.service
fi

# Distrobox Integration
git clone --depth=1 --branch "${DISTROBOX_REF}" https://github.com/89luca89/distrobox.git --single-branch /tmp/distrobox
cp /tmp/distrobox/distrobox-host-exec /usr/bin/distrobox-host-exec
if [[ "${IMAGE_NAME:-}" != "fedora-toolbox-systemd" ]]; then
    ln -s /usr/bin/distrobox-host-exec /usr/bin/flatpak
fi
HOST_SPAWN_VERSION="$(grep -oE 'host_spawn_version="[^"]+"' /tmp/distrobox/distrobox-host-exec | cut -d '"' -f 2)"
/ctx/ghcurl "https://github.com/1player/host-spawn/releases/download/${HOST_SPAWN_VERSION}/host-spawn-$(uname -m)" -o /usr/bin/host-spawn
chmod +x /usr/bin/host-spawn
rm -drf /tmp/distrobox

## install packages direct from github
/ctx/github-release-install.sh sigstore/cosign x86_64
