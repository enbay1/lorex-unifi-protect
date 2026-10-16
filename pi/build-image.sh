#!/bin/sh
# Build the onvif-server image from source.
# The published image (ghcr.io/daniela-hase/onvif-server) is linux/amd64 ONLY,
# so it will not run on an arm64 Raspberry Pi. It's a plain Node app, so building
# from source on the Pi produces a native arm64 image with no code changes.
set -e

SRC="${1:-$HOME/onvif/src}"

if [ -d "$SRC/.git" ]; then
  (cd "$SRC" && git pull --ff-only)
else
  git clone --depth 1 https://github.com/daniela-hase/onvif-server.git "$SRC"
fi

sudo docker build -t onvif-server:local "$SRC"
echo "Built image: onvif-server:local"
