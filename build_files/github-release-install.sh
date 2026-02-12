#!/bin/bash
#
# A script to install an RPM from the latest Github release for a project.
#
# ORG_PROJ is the pair of URL components for organization/projectName in Github URL
# example: https://github.com/wez/wezterm/releases
#   ORG_PROJ would be "wez/wezterm"
#
# ARCH_FILTER is used to select the specific RPM. Typically this can just be the arch
#   such as 'x86_64' but sometimes a specific filter is required when multiple match.
# example: wezterm builds RPMs for different distros so we must be more specific.
#   ARCH_FILTER of "fedora37.x86_64" gets the x86_64 RPM build for fedora37

ORG_PROJ=${1}
ARCH_FILTER=${2}
LATEST=${3}

usage() {
  echo "$0 ORG_PROJ ARCH_FILTER"
  echo "    ORG_PROJ    - organization/projectname"
  echo "    ARCH_FILTER - optional extra filter to further limit rpm selection"
  echo "    LATEST      - optional tag override for latest release (eg, nightly-dev)"
  echo "    GITHUB_TOKEN - optional env var used for authenticated GitHub API requests"

}

if [ -z ${ORG_PROJ} ]; then
  usage
  exit 1
fi

if [ -z ${ARCH_FILTER} ]; then
  usage
  exit 2
fi

if [ -z ${LATEST} ]; then
  RELTAG="latest"
else
  RELTAG="tags/${LATEST}"
fi

set -ouex pipefail

API_JSON=$(mktemp /tmp/api-XXXXXXXX.json)
API="https://api.github.com/repos/${ORG_PROJ}/releases/${RELTAG}"

CURL_ARGS=(
  "--fail"
  "--retry" "5"
  "--retry-delay" "5"
  "--retry-all-errors"
  "-sL"
)

# Use authenticated GitHub API calls when a token is available.
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  CURL_ARGS+=(
    "-H" "Accept: application/vnd.github+json"
    "-H" "Authorization: Bearer ${GITHUB_TOKEN}"
    "-H" "X-GitHub-Api-Version: 2022-11-28"
  )
fi

# retry up to 5 times with 5 second delays for any error included HTTP 404 etc
had_xtrace=0
if [[ "$-" == *x* ]]; then
  had_xtrace=1
  set +x
fi
curl "${CURL_ARGS[@]}" "${API}" -o "${API_JSON}"
if [[ "${had_xtrace}" -eq 1 ]]; then
  set -x
fi
RPM_URLS=($(cat ${API_JSON} |
  jq \
    -r \
    --arg arch_filter "${ARCH_FILTER}" \
    '.assets | sort_by(.created_at) | reverse | .[] | select(.name|test($arch_filter)) | select(.name|test("rpm$")) | .browser_download_url'))
# WARNING: in case of multiple matches, this only installs the first matched release
if [[ -z "${RPM_URLS[0]:-}" ]]; then
  echo "No matching RPM found for ${ORG_PROJ} (${ARCH_FILTER}) via ${API}" >&2
  exit 3
fi
echo "execute: dnf5 -y install \"${RPM_URLS[0]}\""
dnf5 -y install "${RPM_URLS[0]}"
