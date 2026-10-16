#!/bin/sh
# Deploy one onvif-server container for each live recorder channel.
# Each container is a separate virtual ONVIF camera. UniFi Protect adopts each
# camera one at a time. Protect cannot adopt a multi-channel recorder directly.
# It gets channel 1 only.
#
# Run build-image.sh first.
#
# ----------------------------------------------------------------------------
# CONFIGURATION - set these for your network and recorder.
# ----------------------------------------------------------------------------
RECORDER_IP=192.168.1.108        # the DVR/NVR IP address
RECORDER_RTSP_USER=viewer        # a normal recorder account (used only in logs; see note)
CHANNELS="1 3 4 5 6"             # the live channels to bridge
PARENT=eth0                      # the Pi network interface on your LAN
SUBNET=192.168.1.0/24            # your LAN subnet
GATEWAY=192.168.1.1              # your LAN gateway
MAC_PREFIX=a2:a2:a2:a2:a2        # locally-administered MAC prefix for the cameras
CONFIG_DIR="$HOME/onvif"         # where the generated configs go
# ----------------------------------------------------------------------------
#
# NOTES
# - Each camera gets its own MAC and pulls its own DHCP lease (udhcpc). This
#   prevents IP conflicts. Reserve the MACs in your DHCP server so the IP
#   addresses do not change. Protect adopts cameras by IP address.
# - Put the RTSP account name and password into Protect when you adopt each
#   camera. The config files contain no credentials.
# ----------------------------------------------------------------------------
set -e
mkdir -p "$CONFIG_DIR"

# Make the macvlan network. This step is idempotent.
sudo docker network inspect onvif_net >/dev/null 2>&1 || \
  sudo docker network create -d macvlan --subnet="$SUBNET" --gateway="$GATEWAY" -o parent="$PARENT" onvif_net

tmp=254
for ch in $CHANNELS; do
  suffix=$(printf '%02d' "$ch")
  mac="$MAC_PREFIX:$suffix"
  uuid=$(cat /proc/sys/kernel/random/uuid)
  cfg="$CONFIG_DIR/ch$ch.yaml"

  # Generate the per-channel config from the template.
  sed -e "s/<CHANNEL>/$ch/g" -e "s/<MAC>/$mac/g" -e "s/<UUID>/$uuid/g" \
      -e "s/<RECORDER_IP>/$RECORDER_IP/g" \
      "$(dirname "$0")/ch.yaml.template" > "$cfg"

  # Start the container. It flushes the throwaway IP, gets a DHCP lease, then
  # starts the server.
  sudo docker rm -f "onvif-ch$ch" >/dev/null 2>&1 || true
  sudo docker run -d --name "onvif-ch$ch" --restart unless-stopped \
    --network onvif_net --ip "192.168.1.$tmp" --mac-address "$mac" \
    --cap-add NET_ADMIN --memory 64m \
    -v "$cfg:/onvif.yaml" \
    --entrypoint sh onvif-server:local \
    -c "ip addr flush dev eth0; udhcpc -i eth0 -b -t 20 -A 2; sleep 3; node main.js /onvif.yaml"
  echo "deployed onvif-ch$ch  (mac $mac)"
  tmp=$((tmp - 1))
done

echo
echo "Find each camera IP address:  sudo docker exec onvif-ch<N> ip -4 addr show eth0"
echo "Then adopt each camera by IP in UniFi Protect, and reserve the MACs in DHCP."
