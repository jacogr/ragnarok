#!/bin/sh
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# Install one Docker layer's packages using temporary mirrors and the pinned base's signing keys.
set -eu
directory=$(mktemp -d /tmp/ragnarok-apt.XXXXXXXX)
trap 'rm -rf -- "$directory"' EXIT
chmod 0755 "$directory" # APT's sandbox user reads the lists.

fallback=http://mirrors.edge.kernel.org/ubuntu
for scope in archive security; do
    # Make this choice in the same RUN as APT, so Docker never caches it independently.
    host="$scope.ubuntu.com"
    {
        if timeout 5s getent ahosts "$host" >/dev/null; then
            printf 'http://%s/ubuntu\tpriority:1\n' "$host"
        else
            # A stuck resolver would otherwise wait again for each archive object.
            printf 'Ubuntu APT primary %s did not resolve. Using %s\n' "$host" "$fallback" >&2
        fi
        printf '%s\n' "$fallback"
    } > "$directory/$scope.mirrors"
done

# Change only mirror locations. Retain the base image's signed suites and components.
sed \
    -e "s|^URIs: http://archive[.]ubuntu[.]com/ubuntu/*$|URIs: mirror+file:$directory/archive.mirrors|" \
    -e "s|^URIs: http://security[.]ubuntu[.]com/ubuntu/*$|URIs: mirror+file:$directory/security.mirrors|" \
    /etc/apt/sources.list.d/ubuntu.sources > "$directory/ubuntu.sources"
test "$(grep -c '^URIs: mirror+file:' "$directory/ubuntu.sources")" -eq 2
chmod 0644 "$directory"/*

# Treat any incomplete update as a failed acquisition before proceeding to install.
retry=/usr/local/bin/download-retry
sh "$retry" apt-get -o "Dir::Etc::sourcelist=$directory/ubuntu.sources" \
    -o Dir::Etc::sourceparts=- update --error-on=any
sh "$retry" apt-get -o "Dir::Etc::sourcelist=$directory/ubuntu.sources" \
    -o Dir::Etc::sourceparts=- install --no-install-recommends -y "$@"
