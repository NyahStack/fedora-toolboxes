set unstable := true

# Tags

gts := "42"
latest := "43"
[private]
beta := "44"

# Defaults

default_version := latest
default_image := "fedora-toolbox"
default_variant := "main"

# Reused Values

org := "NyahStack"
repo := "fedora-toolboxes"
IMAGE_REGISTRY := "ghcr.io" / lowercase(org)

# Upstream

[private]
source_org := ""
source_registry := "registry.fedoraproject.org"
akmods_nvidia_org := "ublue-os"
akmods_nvidia_registry := "ghcr.io" / akmods_nvidia_org

# Image File

[private]
image-file := justfile_dir() / "image-versions.yaml"

# Image Names

[private]
images := '(
    ["fedora-toolbox"]="fedora-toolbox"
    ["fedora-toolbox-systemd"]="fedora-toolbox"
)'

# Fedora Versions

[private]
fedora_versions := '(
    ["gts"]="' + gts + '"
    ["' + gts + '"]="' + gts + '"
    ["latest"]="' + latest + '"
    ["' + latest + '"]="' + latest + '"
    ["beta"]="' + beta + '"
    ["' + beta + '"]="' + beta + '"
)'

# Variants

[private]
variants := '(
    ["main"]="main"
    ["nvidia"]="nvidia"
)'

# Sudo/Podman/Just

[private]
SUDO_DISPLAY := env("DISPLAY", "") || env("WAYLAND_DISPLAY", "")
[private]
SUDOIF := if `id -u` == "0" { "" } else if SUDO_DISPLAY != "" { which("sudo") + " --askpass" } else { which("sudo") }
[private]
just := just_executable()
[private]
PODMAN := which("podman") || require("podman-remote")

# Make things quieter by default

[private]
export SET_X := if `id -u` == "0" { "1" } else { env('SET_X', '') }

# Aliases

alias run := run-container
alias build := build-container

# Package helpers
[private]
packages_file := justfile_dir() / "packages.json"

# Utility

[private]
default-inputs := '
: ${fedora_version:=' + default_version + '}
: ${image_name:=' + default_image + '}
: ${variant:=' + default_variant + '}
'
[private]
get-names := '
declare -a _images="$(' + just + ' image-name-check $image_name $fedora_version $variant)"
if [[ -z ${_images[0]:-} ]]; then
    exit 1
fi
image_name="${_images[0]}"
source_image_name="${_images[1]}"
fedora_version="${_images[2]}"
'
[private]
build-missing := '
cmd="' + just + ' build ${image_name%-*} $fedora_version $variant"
if ! ' + PODMAN + ' image exists "localhost/$image_name:$fedora_version"; then
    echo "' + style('warning') + 'Warning' + NORMAL +': Container Does Not Exist..." >&2
    echo "' + style('warning') + 'Will Run' + NORMAL +': ' + style('command') + '$cmd' + NORMAL +'" >&2
    seconds=5
    while [ $seconds -gt 0 ]; do
        printf "\rTime remaining: ' + style('error') + '%d' + NORMAL + ' seconds to cancel" $seconds >&2
        sleep 1
        (( seconds-- ))
    done
    echo "" >&2
    echo "'+ style('warning') +'Running'+ NORMAL+ ': '+ style('command') +'$cmd'+ NORMAL+ '" >&2
    $cmd
fi
'
[private]
pull-retry := '
function pull-retry() {
    local target="$1"
    local retries=3
    trap "exit 1" SIGINT
    while [ $retries -gt 0 ]; do
        ' + PODMAN + ' pull $target && break
        (( retries-- ))
    done
    if ! (( retries )); then
        echo "' + style('error') +' Unable to pull ${target/@*/}...' + NORMAL +'" >&2
        exit 1
    fi
    trap - SIGINT
}
'

_default:
    @{{ just }} --list

# Run a Container
[group('Container')]
run-container $image_name="" $fedora_version="" $variant="":
    #!/usr/bin/bash
    set -eou pipefail

    {{ default-inputs }}
    {{ get-names }}
    {{ build-missing }}

    echo "{{ style('warning') }}Running:{{ NORMAL }} {{ style('command') }}{{ just }} run -it --rm localhost/$image_name:$fedora_version bash {{ NORMAL }}"
    {{ PODMAN }} run -it --rm "localhost/$image_name:$fedora_version" bash || exit 0

# Build a Container
[group('Container')]
build-container $image_name="" $fedora_version="" $variant="" $github="":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail

    {{ default-inputs }}
    {{ get-names }}
    {{ pull-retry }}

    SOURCE_IMAGE_DIGEST="$(yq -r ".images[] | select(.name == \"${source_image_name}-${fedora_version}\") | .digest" {{ image-file }})"
    AKMODS_NVIDIA_IMAGE_DIGEST="$(yq -r ".images[] | select(.name == \"akmods-nvidia-open-${fedora_version}\") | .digest" {{ image-file }})"

    # Verify Source Containers
    # TODO registry.fedoraproject.org does not sign images
    # {{ just }} verify-container "$source_image_name@$SOURCE_IMAGE_DIGEST" "{{ source_registry }}"
    {{ just }} verify-container \
        "akmods-nvidia-open@$AKMODS_NVIDIA_IMAGE_DIGEST" \
        "{{ akmods_nvidia_registry }}" \
        "https://raw.githubusercontent.com/ublue-os/main/main/cosign.pub" \
        "{{ justfile_dir() }}/build_files/keys/ublue-os-main-cosign.pub"

    # Tags
    declare -A gen_tags="($({{ just }} gen-tags $image_name $fedora_version $variant))"
    if [[ "${github:-}" =~ pull_request ]]; then
        tags=(${gen_tags["COMMIT_TAGS"]})
    else
        tags=(${gen_tags["BUILD_TAGS"]})
    fi
    TIMESTAMP="${gen_tags["TIMESTAMP"]}"
    TAGS=()
    for tag in "${tags[@]}"; do
        TAGS+=("--tag" "localhost/${image_name}:$tag")
    done

    # Labels
    VERSION="$fedora_version.$TIMESTAMP"
    LABELS=(
        "--label" "org.opencontainers.image.title=${image_name}"
        "--label" "org.opencontainers.image.version=${VERSION}"
        "--label" "org.opencontainers.image.description=A base ${image_name%-*} image with batteries included"
        "--label" "org.opencontainers.image.source=https://github.com/{{ org }}/{{ repo }}"
        "--label" "io.artifacthub.package.readme-url=https://raw.githubusercontent.com/{{ org }}/{{ repo }}/main/README.md"
        "--label" "io.artifacthub.package.logo-url=https://avatars.githubusercontent.com/u/120078124?s=200&v=4"
    )

    TARGET="main"
    if [[ "$variant" =~ nvidia ]]; then
        TARGET="nvidia"
    fi

    # Build Arguments
    BUILD_ARGS=(
        "--build-arg" "IMAGE_NAME=${image_name%-*}"
        "--build-arg" "SOURCE_ORG={{ source_org }}"
        "--build-arg" "SOURCE_REGISTRY={{ source_registry }}"
        "--build-arg" "SOURCE_IMAGE=${source_image_name}"
        "--build-arg" "FEDORA_MAJOR_VERSION=$fedora_version"
        "--build-arg" "IMAGE_REGISTRY={{ IMAGE_REGISTRY }}"
        "--build-arg" "AKMODS_NVIDIA_REGISTRY={{ akmods_nvidia_registry }}"
        "--build-arg" "AKMODS_NVIDIA_IMAGE=akmods-nvidia-open"
        "--build-arg" "SOURCE_IMAGE_DIGEST=$SOURCE_IMAGE_DIGEST"
        "--build-arg" "AKMODS_NVIDIA_IMAGE_DIGEST=$AKMODS_NVIDIA_IMAGE_DIGEST"
    )

    # Pull Images with retry
    pull-retry "{{ akmods_nvidia_registry }}/akmods-nvidia-open:main-$fedora_version@$AKMODS_NVIDIA_IMAGE_DIGEST"
    pull-retry "{{ source_registry }}/$source_image_name:$fedora_version@$SOURCE_IMAGE_DIGEST"

    CACHE_IMAGE="{{ IMAGE_REGISTRY }}/$image_name-cache-$fedora_version"
    CACHE_ARGS=(
        "--layers"
        "--cache-from" "$CACHE_IMAGE"
    )
    if [[ -n "${CI:-}" && ! "${github:-}" =~ pull_request ]]; then
        CACHE_ARGS+=("--cache-to" "$CACHE_IMAGE")
    fi

    BUILD_SECRETS=()
    GITHUB_TOKEN_FILE=""
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        GITHUB_TOKEN_FILE="$(mktemp)"
        trap '[[ -n "${GITHUB_TOKEN_FILE:-}" ]] && rm -f "$GITHUB_TOKEN_FILE"' EXIT
        printf '%s' "$GITHUB_TOKEN" > "$GITHUB_TOKEN_FILE"
        chmod 600 "$GITHUB_TOKEN_FILE"
        BUILD_SECRETS+=("--secret" "id=GITHUB_TOKEN,src=$GITHUB_TOKEN_FILE")
    fi

    # Build Image
    {{ PODMAN }} build --target "$TARGET" -f Containerfile "${CACHE_ARGS[@]}" "${BUILD_SECRETS[@]}" "${BUILD_ARGS[@]}" "${LABELS[@]}" "${TAGS[@]}"

    # CI Cleanup
    if [[ -n "${CI:-}" ]]; then
        {{ PODMAN }} rmi -f "{{ akmods_nvidia_registry }}/akmods-nvidia-open:main-$fedora_version@$AKMODS_NVIDIA_IMAGE_DIGEST"
        {{ PODMAN }} rmi -f "{{ source_registry }}/$source_image_name:$fedora_version@$SOURCE_IMAGE_DIGEST"
    fi

# Generate Tags
[group('Utility')]
gen-tags $image_name="" $fedora_version="" $variant="":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail

    {{ default-inputs }}
    {{ get-names }}

    # Generate Timestamp with incrementing version point
    TIMESTAMP="$(date +%Y%m%d)"
    LIST_TAGS="$(mktemp)"
    for i in {1..5}; do
        if skopeo list-tags "docker://{{ IMAGE_REGISTRY }}/$image_name" > "$LIST_TAGS"; then
            break
        fi
        sleep $((5 * i))
    done
    if [[ ! -s "$LIST_TAGS" ]]; then
        echo '{"Tags":[]}' > "$LIST_TAGS"
    fi
    if jq -e --arg tag "$fedora_version-$TIMESTAMP" 'any((.Tags // [])[]; contains($tag))' "$LIST_TAGS" >/dev/null; then
        POINT="1"
        while jq -e --arg tag "$fedora_version-$TIMESTAMP.$POINT" 'any((.Tags // [])[]; contains($tag))' "$LIST_TAGS" >/dev/null
        do
            (( POINT++ ))
        done
    fi

    if [[ -n "${POINT:-}" ]]; then
        TIMESTAMP="$TIMESTAMP.$POINT"
    fi

    # Add a sha tag for tracking builds during a pull request
    SHA_SHORT="$(git rev-parse --short HEAD)"

    # Define Versions
    if [[ "$fedora_version" -eq "{{ gts }}" ]]; then
        COMMIT_TAGS=("$SHA_SHORT-gts")
        BUILD_TAGS=("gts" "gts-$TIMESTAMP")
    elif [[ "$fedora_version" -eq "{{ latest }}" ]]; then
        COMMIT_TAGS=("$SHA_SHORT-latest")
        BUILD_TAGS=("latest" "latest-$TIMESTAMP")
    elif [[ "$fedora_version" -eq "{{ beta }}" ]]; then
        COMMIT_TAGS=("$SHA_SHORT-beta")
        BUILD_TAGS=("beta" "beta-$TIMESTAMP")
    fi

    COMMIT_TAGS+=("$SHA_SHORT-$fedora_version" "$fedora_version")
    BUILD_TAGS+=("$fedora_version" "$fedora_version-$TIMESTAMP")
    declare -A output
    output["BUILD_TAGS"]="${BUILD_TAGS[*]}"
    output["COMMIT_TAGS"]="${COMMIT_TAGS[*]}"
    output["TIMESTAMP"]="$TIMESTAMP"
    echo "${output[@]@K}"

# Check Valid Image Name
[group('Utility')]
image-name-check $image_name $fedora_version $variant:
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    declare -A images={{ images }}

    if [[ "$image_name" =~ -main$|-nvidia$ ]]; then
        image_name="${image_name%-*}"
    fi

    source_image_name="${images[$image_name]:-}"
    if [[ -z "$source_image_name" ]]; then
        echo '{{ style('error') }}Invalid Image Name{{ NORMAL }}' >&2
        exit 1
    fi

    fedora_version="$({{ just }} fedora-version-check $fedora_version || exit 1)"
    variant="$({{ just }} fedora-variant-check $variant || exit 1)"

    echo "($image_name-$variant $source_image_name $fedora_version)"

# Check Valid Fedora Version
[group('Utility')]
fedora-version-check $fedora_version:
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    declare -A fedora_versions={{ fedora_versions }}
    if [[ -z "${fedora_versions[$fedora_version]:-}" ]]; then
        echo "{{ style('error') }}Not a supported version{{ NORMAL }}" >&2
        exit 1
    fi
    echo "${fedora_versions[$fedora_version]}"

# Check Valid Variant
[group('Utility')]
fedora-variant-check $variant:
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail
    declare -A variants={{ variants }}
    if [[ -z "${variants[$variant]:-}" ]]; then
        echo "{{ style('error') }}Not a supported variant{{ NORMAL }}" >&2
        exit 1
    fi
    echo "${variants[$variant]}"

# Check Just Syntax
[group('Just')]
check:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
        echo "Checking syntax: $file" >&2
        {{ just }} --unstable --fmt --check -f $file
    done
    echo "Checking syntax: Justfile" >&2
    {{ just }} --unstable --fmt --check -f Justfile

# List local GitHub Actions jobs using act
[group('Utility')]
act-list:
    #!/usr/bin/env bash
    set ${SET_X:+-x} -eou pipefail
    ACT_BIN="act"
    if ! command -v act >/dev/null 2>&1; then
        if ! command -v mise >/dev/null 2>&1; then
            echo "{{ style('error') }}NOTICE: act is not installed and mise is unavailable.{{ NORMAL }}" >&2
            exit 1
        fi
        ACT_BIN="$(mise which act)"
    fi

    shopt -s nullglob
    for workflow in .github/workflows/*.yml; do
        if ! "$ACT_BIN" --list --workflows "$workflow" --no-recurse; then
            echo "{{ style('warning') }}Warning{{ NORMAL }}: act could not parse $workflow" >&2
        fi
    done

# Run a GitHub Actions workflow locally using act
[group('Utility')]
act-run $workflow=".github/workflows/build-beta.yml" $job="" $event="workflow_dispatch" $platform="ubuntu-latest=ghcr.io/catthehacker/ubuntu:act-latest" $extra="":
    #!/usr/bin/env bash
    set ${SET_X:+-x} -eou pipefail

    if [[ -S "${XDG_RUNTIME_DIR:-}/podman/podman.sock" && -z "${DOCKER_HOST:-}" ]]; then
        export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
    fi

    args=("$event" "-W" "$workflow" "-P" "$platform")
    args+=("--no-recurse")
    args+=("--concurrent-jobs" "1")
    if [[ -n "$job" ]]; then
        args+=("-j" "$job")
    fi
    if [[ -n "$extra" ]]; then
        read -r -a extra_args <<< "$extra"
        args+=("${extra_args[@]}")
    fi

    ACT_BIN="act"
    if ! command -v act >/dev/null 2>&1; then
        if ! command -v mise >/dev/null 2>&1; then
            echo "{{ style('error') }}NOTICE: act is not installed and mise is unavailable.{{ NORMAL }}" >&2
            exit 1
        fi
        ACT_BIN="$(mise which act)"
    fi

    "$ACT_BIN" "${args[@]}"

# Fix Just Syntax
[group('Just')]
fix:
    #!/usr/bin/env bash
    find . -type f -name "*.just" | while read -r file; do
        echo "Checking syntax: $file" >&2
        {{ just }} --unstable --fmt -f $file
    done
    echo "Checking syntax: Justfile" >&2
    {{ just }} --unstable --fmt -f Justfile || { exit 1; }

# Verify Container with Cosign
[group('Utility')]
verify-container $container="" $registry="" $key="" $fallback_key="":
    #!/usr/bin/env bash
    set ${SET_X:+-x} -eou pipefail

    # Defaults: fall back to local registry and repository signing key.
    : "${registry:={{ IMAGE_REGISTRY }}}"
    : "${key:=https://raw.githubusercontent.com/{{ org }}/{{ repo }}/main/cosign.pub}"
    : "${fallback_key:=}"

    default_repo_key="{{ justfile_dir() }}/cosign.pub"
    default_ublue_key="{{ justfile_dir() }}/build_files/keys/ublue-os-main-cosign.pub"

    is_valid_pubkey() {
        local file="$1"
        [[ -s "$file" ]] \
            && grep -q "BEGIN PUBLIC KEY" "$file" \
            && grep -q "END PUBLIC KEY" "$file"
    }

    warn() {
        local msg="$1"
        if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
            echo "::warning::${msg}"
        else
            echo "{{ style('warning') }}Warning{{ NORMAL }}: ${msg}" >&2
        fi
    }

    download_key_url() {
        local url="$1"
        local out="$2"
        local owner repo ref path api_url

        if [[ -n "${GITHUB_TOKEN:-}" && "$url" =~ ^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+)$ ]]; then
            owner="${BASH_REMATCH[1]}"
            repo="${BASH_REMATCH[2]}"
            ref="${BASH_REMATCH[3]}"
            path="${BASH_REMATCH[4]}"
            api_url="https://api.github.com/repos/${owner}/${repo}/contents/${path}?ref=${ref}"

            if curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
                -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.raw" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "$api_url" -o "$out" >/dev/null 2>&1; then
                return 0
            fi

            warn "GitHub API key fetch failed for '$url', retrying without token."
        fi

        if [[ -n "${GITHUB_TOKEN:-}" && "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/raw/([^/]+)/(.+)$ ]]; then
            owner="${BASH_REMATCH[1]}"
            repo="${BASH_REMATCH[2]}"
            ref="${BASH_REMATCH[3]}"
            path="${BASH_REMATCH[4]}"
            api_url="https://api.github.com/repos/${owner}/${repo}/contents/${path}?ref=${ref}"

            if curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
                -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.raw" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "$api_url" -o "$out" >/dev/null 2>&1; then
                return 0
            fi

            warn "GitHub API key fetch failed for '$url', retrying without token."
        fi

        curl --fail --silent --show-error --location --retry 3 --retry-delay 2 "$url" -o "$out"
    }

    if [[ -z "${fallback_key}" ]]; then
        case "$key" in
            "https://raw.githubusercontent.com/{{ org }}/{{ repo }}/main/cosign.pub")
                fallback_key="$default_repo_key"
                ;;
            "https://raw.githubusercontent.com/ublue-os/main/main/cosign.pub")
                fallback_key="$default_ublue_key"
                ;;
            *)
                fallback_key="$default_repo_key"
                ;;
        esac
    fi

    resolved_key="$key"
    tmp_key=""
    verify_log=""
    cleanup() {
        if [[ -n "${tmp_key:-}" && -f "$tmp_key" ]]; then
            rm -f "$tmp_key"
        fi
        if [[ -n "${verify_log:-}" && -f "$verify_log" ]]; then
            rm -f "$verify_log"
        fi
    }
    trap cleanup EXIT

    if [[ "$key" =~ ^https?:// ]]; then
        tmp_key="$(mktemp)"
        if download_key_url "$key" "$tmp_key" && is_valid_pubkey "$tmp_key"; then
            resolved_key="$tmp_key"
            if [[ -f "$fallback_key" ]] && is_valid_pubkey "$fallback_key" && ! cmp -s "$tmp_key" "$fallback_key"; then
                warn "Fallback key '$fallback_key' is out of date with '$key'."
            fi
        elif [[ -f "$fallback_key" ]] && is_valid_pubkey "$fallback_key"; then
            warn "Unable to use signing key URL '$key', falling back to '$fallback_key'."
            resolved_key="$fallback_key"
        else
            echo "{{ style('error') }}NOTICE: Unable to load signing key from '$key' and fallback '$fallback_key' is missing/invalid.{{ NORMAL }}" >&2
            exit 1
        fi
    elif [[ -f "$key" ]] && is_valid_pubkey "$key"; then
        resolved_key="$key"
    elif [[ -f "$fallback_key" ]] && is_valid_pubkey "$fallback_key"; then
        warn "Key '$key' is missing/invalid, falling back to '$fallback_key'."
        resolved_key="$fallback_key"
    else
        echo "{{ style('error') }}NOTICE: Signing key '$key' is missing/invalid and no usable fallback key was found.{{ NORMAL }}" >&2
        exit 1
    fi

    verify_log="$(mktemp)"

    # Verify Container using cosign public key. If the upstream image presents
    # a certificate-based signature instead, retry with the GitHub Actions OIDC
    # identity used by ublue-os.
    if ! cosign verify --key "$resolved_key" "$registry/$container" >/dev/null 2>"$verify_log"; then
        if grep -Fq "expected key signature, not certificate" "$verify_log" \
            && [[ "$registry/$container" == ghcr.io/ublue-os/* ]]; then
            warn "Key verification returned a certificate signature for '$registry/$container'; retrying with GitHub OIDC identity verification."
            if cosign verify \
                --certificate-oidc-issuer https://token.actions.githubusercontent.com \
                --certificate-identity-regexp '^https://github.com/ublue-os/.+' \
                "$registry/$container" >/dev/null; then
                exit 0
            fi
        fi

        cat "$verify_log" >&2
        echo "{{ style('error') }}NOTICE: Verification failed. Please ensure your public key is correct.{{ NORMAL }}" >&2
        exit 1
    fi

[group('CI')]
check-fallback-key $key_url="" $fallback_key="" $label="":
    #!/usr/bin/env bash
    set ${SET_X:+-x} -eou pipefail

    if [[ -z "${key_url}" || -z "${fallback_key}" ]]; then
        echo "{{ style('error') }}NOTICE: check-fallback-key requires key_url and fallback_key.{{ NORMAL }}" >&2
        exit 1
    fi

    : "${label:=${fallback_key}}"

    is_valid_pubkey() {
        local file="$1"
        [[ -s "$file" ]] \
            && grep -q "BEGIN PUBLIC KEY" "$file" \
            && grep -q "END PUBLIC KEY" "$file"
    }

    warn() {
        local msg="$1"
        if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
            echo "::warning::${msg}"
        else
            echo "{{ style('warning') }}Warning{{ NORMAL }}: ${msg}" >&2
        fi
    }

    download_key_url() {
        local url="$1"
        local out="$2"
        local owner repo ref path api_url

        if [[ -n "${GITHUB_TOKEN:-}" && "$url" =~ ^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/(.+)$ ]]; then
            owner="${BASH_REMATCH[1]}"
            repo="${BASH_REMATCH[2]}"
            ref="${BASH_REMATCH[3]}"
            path="${BASH_REMATCH[4]}"
            api_url="https://api.github.com/repos/${owner}/${repo}/contents/${path}?ref=${ref}"
            if curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
                -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.raw" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "$api_url" -o "$out" >/dev/null 2>&1; then
                return 0
            fi
        fi

        if [[ -n "${GITHUB_TOKEN:-}" && "$url" =~ ^https://github\.com/([^/]+)/([^/]+)/raw/([^/]+)/(.+)$ ]]; then
            owner="${BASH_REMATCH[1]}"
            repo="${BASH_REMATCH[2]}"
            ref="${BASH_REMATCH[3]}"
            path="${BASH_REMATCH[4]}"
            api_url="https://api.github.com/repos/${owner}/${repo}/contents/${path}?ref=${ref}"
            if curl --fail --silent --show-error --location --retry 3 --retry-delay 2 \
                -H "Authorization: Bearer ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.raw" \
                -H "X-GitHub-Api-Version: 2022-11-28" \
                "$api_url" -o "$out" >/dev/null 2>&1; then
                return 0
            fi
        fi

        curl --fail --silent --show-error --location --retry 3 --retry-delay 2 "$url" -o "$out"
    }

    if [[ ! -f "${fallback_key}" ]]; then
        warn "Fallback key '${label}' is missing at '${fallback_key}'."
        exit 0
    fi

    if ! is_valid_pubkey "${fallback_key}"; then
        warn "Fallback key '${label}' at '${fallback_key}' is not a valid PEM public key."
        exit 0
    fi

    tmp_key="$(mktemp)"
    cleanup() {
        if [[ -f "${tmp_key}" ]]; then
            rm -f "${tmp_key}"
        fi
    }
    trap cleanup EXIT

    if ! download_key_url "${key_url}" "${tmp_key}"; then
        warn "Unable to fetch upstream key '${key_url}' while checking '${label}'."
        exit 0
    fi

    if ! is_valid_pubkey "${tmp_key}"; then
        warn "Fetched upstream key '${key_url}' for '${label}' is not valid PEM."
        exit 0
    fi

    if ! cmp -s "${tmp_key}" "${fallback_key}"; then
        warn "Fallback key '${label}' is out of date with '${key_url}'. Please update '${fallback_key}'."
        if [[ "${FAIL_ON_KEY_DRIFT:-0}" == "1" ]]; then
            echo "{{ style('error') }}NOTICE: FAIL_ON_KEY_DRIFT=1 and fallback key '${label}' is stale.{{ NORMAL }}" >&2
            exit 1
        fi
    fi

[group('CI')]
check-fallback-keys:
    #!/usr/bin/env bash
    set ${SET_X:+-x} -eou pipefail

    {{ just }} check-fallback-key \
        "https://raw.githubusercontent.com/ublue-os/main/main/cosign.pub" \
        "{{ justfile_dir() }}/build_files/keys/ublue-os-main-cosign.pub" \
        "ublue-os/main"

# Removes all Tags of an image from container storage.
[group('Utility')]
clean $image_name $fedora_version $variant $registry="":
    #!/usr/bin/bash
    set -eoux pipefail

    : "${registry:=localhost}"
    {{ get-names }}

    declare -a CLEAN="($({{ PODMAN }} image list $registry/$image_name --noheading --format 'table {{{{ .ID }}' | uniq))"
    if [[ -n "${CLEAN[@]:-}" ]]; then
        {{ PODMAN }} rmi -f "${CLEAN[@]}"
    fi

# Get Digest

# Login to GHCR
[group('CI')]
@login-to-ghcr $user $token:
    echo "$token" | {{ PODMAN }} login ghcr.io -u "$user" --password-stdin
    echo "$token" | docker login ghcr.io -u "$user" --password-stdin

# Push Images to Registry
[group('CI')]
push-to-registry $image_name $fedora_version $variant $destination="" $transport="":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail

    {{ get-names }}
    {{ build-missing }}

    : "${destination:={{ IMAGE_REGISTRY }}}"
    : "${transport:="docker://"}"

    declare -a TAGS="($({{ PODMAN }} image list localhost/$image_name:$fedora_version --noheading --format 'table {{{{ .Tag }}'))"
    for tag in "${TAGS[@]}"; do
        if {{ PODMAN }} manifest exists "localhost/$image_name:$tag-manifest"; then
            {{ PODMAN }} manifest rm "localhost/$image_name:$tag-manifest"
        fi
        {{ PODMAN }} manifest create "localhost/$image_name:$tag-manifest"
        {{ PODMAN }} manifest add "localhost/$image_name:$tag-manifest" "containers-storage:localhost/$image_name:$fedora_version"
        for i in {1..5}; do
            {{ PODMAN }} manifest push --compression-format=gzip --add-compression=zstd --add-compression=zstd:chunked "localhost/$image_name:$tag-manifest" "$transport$destination/$image_name:$tag" 2>&1 && break || sleep $((5 * i));
        done
    done

# Sign Images with Cosign
[group('CI')]
cosign-sign $image_name $fedora_version $variant $destination="":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail

    {{ get-names }}
    {{ build-missing }}

    : "${destination:={{ IMAGE_REGISTRY }}}"
    digest="$(skopeo inspect docker://$destination/$image_name:$fedora_version --format '{{{{ .Digest }}')"
    cosign sign -y --key env://COSIGN_PRIVATE_KEY "$destination/$image_name@$digest"

# Generate SBOM
[group('CI')]
gen-sbom $image_name $fedora_version $variant:
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail

    {{ get-names }}
    {{ build-missing }}
    {{ pull-retry }}

    # Get SYFT if needed
    SYFT_ID=""
    if ! command -v syft >/dev/null; then
        pull-retry "docker.io/anchore/syft:latest"
        SYFT_ID="$({{ PODMAN }} create docker.io/anchore/syft:latest)"
        {{ PODMAN }} cp "$SYFT_ID":/syft /tmp/syft.install
        {{ SUDOIF }} cp /tmp/syft.install /usr/local/bin/syft
        {{ SUDOIF }} rm -f /tmp/syft.install
        {{ PODMAN }} rm -f "$SYFT_ID" > /dev/null
        {{ PODMAN }} rmi "docker.io/anchore/syft:latest"
    fi

    # Enable Podman Socket if needed
    if [[ "$EUID" -eq "0" ]] && ! systemctl is-active -q podman.socket; then
        systemctl start podman.socket
        started_podman="true"
    elif ! systemctl is-active -q --user podman.socket; then
        systemctl start --user podman.socket
        started_podman="true"
    fi

    # Make SBOM
    OUTPUT_PATH="$(mktemp -d)/sbom.json"
    SYFT_PARALLELISM="$(( $(nproc) * 2 ))"
    syft "localhost/$image_name:$fedora_version" -o spdx-json="$OUTPUT_PATH" >&2

    # Cleanup
    if [[ "$EUID" -eq "0" && "${started_podman:-}" == "true" ]]; then
        systemctl stop podman.socket
    elif [[ "${started_podman:-}" == "true" ]]; then
        systemctl stop --user podman.socket
    fi

    # Output Path
    echo "$OUTPUT_PATH"

# Add SBOM attestation
[group('CI')]
sbom-attest $fedora_version $image_name $variant $destination="" $sbom="" $digest="":
    #!/usr/bin/bash
    set ${SET_X:+-x} -eou pipefail

    {{ get-names }}
    {{ build-missing }}

    : "${destination:={{ IMAGE_REGISTRY }}}"
    : "${sbom:=$({{ just }} gen-sbom $fedora_version $image_name)}"
    : "${digest:=$({{ PODMAN }} inspect localhost/$image_name:$fedora_version --format '{{ ' {{ .Digest }} ' }}')}"

    # Attest with SBOM
    cd "$(dirname $sbom)" && \
    cosign attest -y \
       --predicate ./sbom.json \
       --type spdxjson \
       --key env://COSIGN_PRIVATE_KEY \
       "$destination/$image_name@$digest"
