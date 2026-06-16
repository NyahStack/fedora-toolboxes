# NyahStack Fedora Toolboxes

[![build-gts](https://github.com/NyahStack/fedora-toolboxes/actions/workflows/build-gts.yml/badge.svg)](https://github.com/NyahStack/fedora-toolboxes/actions/workflows/build-gts.yml)
[![build-latest](https://github.com/NyahStack/fedora-toolboxes/actions/workflows/build-latest.yml/badge.svg)](https://github.com/NyahStack/fedora-toolboxes/actions/workflows/build-latest.yml)
[![build-beta](https://github.com/NyahStack/fedora-toolboxes/actions/workflows/build-beta.yml/badge.svg)](https://github.com/NyahStack/fedora-toolboxes/actions/workflows/build-beta.yml)

Versioned Fedora toolbox images for Distrobox/Toolbox, built with a `ublue-os/main` style pipeline.

## Why This Exists

`ublue-os/main` and `ublue-os/bazzite` emphasize reproducible, continuously rebuilt images with clear release lanes and signed outputs.

`ublue-os/toolboxes` is excellent for breadth across many toolbox/app images, but its Fedora toolbox flow is primarily single-track (`latest`) and less strict about lane-based version control.

This repository exists to keep Fedora toolbox images on a stricter update model:

- Explicit release lanes (`gts`, `latest`, `beta`)
- Digest-pinned upstream inputs in `image-versions.yaml`
- CI that rebuilds when pinned upstream digests or relevant repo content changes
- Signed GHCR outputs for a NyahStack-maintained toolbox track

## How To Use These Images

If you are unsure which variant to use, start with `-main` on `:latest`:

- `ghcr.io/nyahstack/fedora-toolbox-main:latest`

All images are published in release lanes:

- `gts` -> Fedora 43
- `latest` -> Fedora 44
- `beta` -> reserved for Fedora 45 once it is in testing

So you pick:
1. an image variant (main or systemd-main)
2. a lane tag (`gts`, `latest`, or `beta`)

Image naming pattern:

- `ghcr.io/nyahstack/fedora-toolbox<SUFFIX>:<lane>`

## Variant Suffixes

### `-main`

Why it exists:
- Provide a default toolbox that includes the desktop-adjacent runtime pieces many apps expect.
- Reduce "missing library/runtime" friction so app containers and downloaded binaries (`tar.gz`, etc.) work out of the box more often.

What it provides:
- Base image: `registry.fedoraproject.org/fedora-toolbox:<fedora-version>` (pinned by digest in `image-versions.yaml`).
- Shared package set from `packages.json` (`all.include.all`, currently 97 packages), including common desktop/runtime dependencies used by GUI and multimedia apps.
- Distrobox integration tooling (`distrobox-host-exec` + `host-spawn`) from `build_files/install.sh`.
- For non-systemd images, `/usr/bin/flatpak` is symlinked to `distrobox-host-exec` during build.

### `-systemd`

Why it exists:
- Support a more isolated container model that still integrates with important desktop behavior.

What it provides:
- Everything from `-main`, plus systemd-specific package additions from `packages.json`:
  `dbus-daemon`, `flatpak`, `podman`, `systemd`.
- Systemd-specific filesystem overlay from `sys_files/systemd/fedora-toolbox-systemd`.
- Enabled system services in build: `host-timezone-sync.service` and `podman-subids-setup.service`.
- Flathub remote file provisioning at `/etc/flatpak/remotes.d/flathub.flatpakrepo`.
- Design intent: feel closer to a separate host while remaining part of the same desktop experience.
- Intended runtime mode is `distrobox create --init`.

Suffixes combine as follows:

- `-main`: default toolbox variant
- `-systemd-main`: systemd variant

`main` in the image name distinguishes the default toolbox variant from the release lane.

## Build and CI Model

Workflows:

- [`build-gts.yml`](./.github/workflows/build-gts.yml)
- [`build-latest.yml`](./.github/workflows/build-latest.yml)
- [`build-beta.yml`](./.github/workflows/build-beta.yml)

`build-gts.yml` and `build-latest.yml` call [`reusable-build.yml`](./.github/workflows/reusable-build.yml), which:

- Resolves lane aliases from `Justfile`
- Compares pinned digests from `image-versions.yaml`
- Forces rebuilds if non-digest content changed
- Builds with `just`, pushes to GHCR, and signs with cosign

## Downstream Use

This repository is intended to be consumed by downstream image projects that want stable, versioned Fedora toolbox bases.

Downstreams can track lane tags (`gts`, `latest`) or specific dated/version tags from this repo and rebuild on their own cadence. The `beta` lane is currently parked until Fedora 45 enters testing.

Example downstream:

- [`NyahStack/lair`](https://github.com/NyahStack/lair)

## Distrobox Examples

Run these on the host.

```bash
# Main image (latest lane)
distrobox create --name nyah-fedora-main --image ghcr.io/nyahstack/fedora-toolbox-main:latest
distrobox enter nyah-fedora-main

# Systemd image (latest lane, requires --init for systemd as PID 1)
distrobox create --name nyah-fedora-systemd --image ghcr.io/nyahstack/fedora-toolbox-systemd-main:latest --init
distrobox enter nyah-fedora-systemd
```

To use a different lane, replace `:latest` with `:gts`. The `:beta` lane is currently parked.

## Local Usage

Requirements:

- `podman`
- `just`
- `jq`
- `yq`
- `cosign`

Examples:

```bash
# Build latest main variant
just build fedora-toolbox latest main

# Beta lane is currently parked until Fedora 45 enters testing

# Run a built container
just run fedora-toolbox latest main
```

## Verification

Images are signed. Verify with:

```bash
cosign verify --key cosign.pub ghcr.io/nyahstack/fedora-toolbox-main:latest
```

If you are verifying without cloning this repository, use the hosted public key:

```bash
cosign verify --key https://raw.githubusercontent.com/NyahStack/fedora-toolboxes/main/cosign.pub ghcr.io/nyahstack/fedora-toolbox-main:latest
```

## Build Your Own Fork

1. Fork this repository.
2. Generate your own cosign key pair.
3. Add your private key as GitHub Actions secret: `COSIGN_PRIVATE_KEY`.
4. Replace `cosign.pub` in your fork with your public key.
5. Enable GitHub Actions in your fork.

### Repo Identity (Chronicle/Forks)

If you run this from a different org/repo name (for example a Chronicle-managed repo), update the identity values in [`Justfile`](./Justfile):

- `org := "..."`
- `repo := "..."`

These values drive image labels and registry naming (`IMAGE_REGISTRY`), so they should match your actual GitHub org/repo.

Also update any README badge URLs so they point at the correct repository.

## Renovate

This repo includes project-level Renovate rules in [`.github/renovate.json5`](./.github/renovate.json5), including digest tracking for:

- `registry.fedoraproject.org/*`

Note: the digest update workflow in this project depends on a self-hosted Renovate setup with org-level inherited config. It does not behave the same way with the official hosted Renovate app.

For self-hosted runner setup examples, org inheritance, and merge-queue/automerge requirements, see:

- <https://github.com/NyahStack/renovate-config>
- <https://github.com/ublue-os/renovate-config>

## Upstream References

- [`ublue-os/main`](https://github.com/ublue-os/main)
- [`ublue-os/toolboxes`](https://github.com/ublue-os/toolboxes)
- [`ublue-os/bazzite`](https://github.com/ublue-os/bazzite)
