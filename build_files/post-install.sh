#!/usr/bin/bash

set -ouex pipefail

# Remove dnf5 versionlocks
dnf5 versionlock clear

# Fix cjk fonts
if [[ -d "/usr/share/fonts/google-noto-sans-cjk-fonts" ]]; then
    ln -sf "/usr/share/fonts/google-noto-sans-cjk-fonts" "/usr/share/fonts/noto-cjk"
fi

# Remove coprs only if they are enabled
if dnf5 repolist --enabled | grep -q 'ublue-os-staging'; then
    dnf5 -y copr remove ublue-os/staging || true
fi
if dnf5 repolist --enabled | grep -q 'ublue-os-packages'; then
    dnf5 -y copr remove ublue-os/packages || true
fi
