#!/usr/bin/sh

# Repair path for GUI/session variables in the user systemd manager.
# The user-environment-generator seeds these early; this hook updates the
# manager and restarts stale portal services when they were already started
# before the correct session env was visible.
if [ -x /usr/local/libexec/toolbox-sync-user-session-env ]; then
    /usr/local/libexec/toolbox-sync-user-session-env >/dev/null 2>&1 || :
fi
