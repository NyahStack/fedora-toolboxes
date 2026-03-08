#!/usr/bin/env bash

set -euo pipefail

# systemd environment generators should fail soft when runtime inputs are absent.
if [[ ! -r /proc/1/environ ]]; then
    exit 0
fi

emit() {
    printf '%s=%s\n' "$1" "$2"
}

_seen_home=
while IFS='=' read -r key val; do
    case "$key" in
        SHELL)              emit DISTROBOX_USER_SHELL          "$val" ;;
        HOSTNAME)           emit DISTROBOX_CONTAINER_HOSTNAME  "$val" ;;
        HOME)
            emit DISTROBOX_USER_HOME "$val"
            _seen_home=$val
            ;;
        CONTAINER_ID)       emit DISTROBOX_CONTAINER_ID        "$val" ;;
        DISTROBOX_HOST_HOME)emit DISTROBOX_HOST_HOME           "$val" ;;
        DISTROBOX_DISABLE_HOST_TZ) emit DISTROBOX_DISABLE_HOST_TZ "$val" ;;
        SHLVL)              emit DISTROBOX_SHLVL               "$val" ;;
        TERMINFO_DIRS)      emit DISTROBOX_TERMINFO_DIRS       "$val" ;;
        PATH)               emit DISTROBOX_PATH                "$val" ;;
        container_uuid)     emit DISTROBOX_CONTAINER_UUID      "$val" ;;
    esac
done < <(tr '\0' '\n' </proc/1/environ)

if [[ -n "$_seen_home" ]] && user=$(stat -c '%U' -- "$_seen_home" 2>/dev/null); then
    if [[ "$user" != "UNKNOWN" ]]; then
        emit DISTROBOX_USER "$user"
    fi
fi
