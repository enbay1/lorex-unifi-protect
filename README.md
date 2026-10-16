# Lorex (Dahua) DVR to UniFi Protect bridge

Add the cameras from a Lorex or Dahua recorder to UniFi Protect. Each channel becomes
a separate ONVIF camera. UniFi Protect adopts each camera one at a time.

A small proxy does this. The proxy runs on a Raspberry Pi. It uses
[`daniela-hase/onvif-server`](https://github.com/daniela-hase/onvif-server).


## Summary

UniFi Protect can adopt third-party ONVIF cameras. But a multi-channel recorder is one
ONVIF device. If you add the recorder directly, Protect gets channel 1 only. There is no
way to select the other channels.

This project starts one small proxy for each channel. Each proxy looks like one ONVIF
camera to Protect. The proxy sends the real video from the recorder over RTSP. The proxy
does not change the video. It only relays it.


## Compatibility

This project was built and tested against the hardware below. It applies to many
Lorex and Dahua recorders, because Lorex recorders use Dahua firmware.

**Recorder (tested):**

| Item | Value |
|---|---|
| Brand | Lorex (Dahua OEM) |
| Device type | `D871A8` (Dahua internal code) |
| Class | 8-channel 4K XVR (analog / HD-CVI; `VideoStandards` = PAL, NTSC) |
| Firmware | `4.001.00LR007.0`, build 2022-06-24 (`LR` = Lorex OEM) |
| Security baseline | V2.1 |
| Processor | ST7108 |
| Web version | 3.2.7.83177 |
| Main stream | up to 3840x2160 (4K) H.265 |
| Sub stream | 704x480 H.264 |
| Max encode resolutions | 3840x2160, 2560x1440, 1080P, 960H, D1, CIF |
| MAC OUI | `00:1f:54` (Dahua) |
| APIs | RTSP (554), ONVIF (80), Dahua RPC2 (`/RPC2`, `/RPC2_Login`) |

**Controller (tested):**

| Item | Value |
|---|---|
| Console | UniFi UCG Max (UniFi Cloud Gateway Max) |
| Software | UniFi Protect 7.3.70 |

**Proxy host (tested):**

| Item | Value |
|---|---|
| Hardware | Raspberry Pi 3B (1 GB RAM, 100 Mbps network) |
| OS | Raspberry Pi OS (64-bit / arm64), Docker |

If you search for one of these symptoms, this project is for you:
- UniFi Protect adopts a Lorex or Dahua DVR but shows **channel 1 only**.
- UniFi Protect reports **"invalid credentials"** for a Lorex or Dahua recorder over ONVIF,
  even with the correct admin password.
- The Lorex or Dahua recorder has **no ONVIF user** option in the web interface.
- `unifi-cam-proxy` does not work with current UniFi Protect.


## How it works

```
        ONVIF + RTSP (one per camera)            RTSP (one per channel)
UniFi   ----------------------------->  proxy  ----------------------->  Recorder
Protect   each proxy = one ONVIF cam   (on Pi)      port 554             (DVR/NVR)
          one container per channel
```

- Each channel gets one Docker container.
- Each container has its own MAC address and its own IP address.
- Protect adopts each container as one ONVIF camera.
- The container relays the RTSP stream from the recorder. It does not transcode.
- The containers run on a Docker **macvlan** network. Each container gets its own
  **DHCP** lease. This prevents IP address conflicts.


## Requirements

- A Lorex or Dahua recorder that gives RTSP and ONVIF (see Compatibility).
- UniFi Protect 5.0.33 or later (third-party ONVIF support).
- A Linux host with Docker on the same LAN. A Raspberry Pi is sufficient.
- One free IP address for each channel. Make a DHCP reservation for each.
- A normal recorder account for the RTSP login (not the admin account if you can avoid it).


## Procedure

Do these steps on the proxy host.

1. Copy the `pi/` folder to the host.
2. Edit the settings at the top of `pi/deploy-cameras.sh`. Set the recorder IP address,
   the channel list, the network interface, the subnet, and the gateway.
3. Build the image:
   ```sh
   sh pi/build-image.sh
   ```
   The published image is `linux/amd64` only. It does not run on a Raspberry Pi. This step
   builds a native image from source. The application is a Node app, so no code change is
   necessary.
4. Start one container for each channel:
   ```sh
   sh pi/deploy-cameras.sh
   ```
5. Install the memory cushion (the Pi has little RAM). Enable the zram swap service:
   ```sh
   sudo cp pi/zram-swap.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now zram-swap.service
   ```
6. Find the IP address of each camera:
   ```sh
   sudo docker exec onvif-ch<N> ip -4 addr show eth0
   ```
7. In UniFi Protect, add each camera. Use "Add third-party camera" (ONVIF). Enter the
   camera IP address. Enter a recorder account for the login.
8. Make a DHCP reservation for each camera MAC address. This keeps the IP address stable.
   Protect adopts cameras by IP address.

The containers start again after a reboot (`--restart unless-stopped`). The zram service
starts again after a reboot.


## Recorder configuration (important)

Lorex and Dahua recorders have two problems that stop a direct ONVIF adoption:

1. **ONVIF uses a separate credential store.** The normal device accounts (admin and any
   user you add) are rejected over ONVIF. They return HTTP 401. A config flag,
   `UserGlobal.OnvifLoginCheck`, controls this. Some firmware has no ONVIF user option in
   the web interface. You can toggle the flag with `scripts/set-onvif-logincheck.ps1`.

   This project does **not** need ONVIF to the recorder. The proxy uses **RTSP** with a
   normal account. Therefore, keep `OnvifLoginCheck` ON (the secure, default state). This
   also stops Protect from re-discovering the recorder as a bogus "General" device.

2. **The encoder settings can be low.** The resolution can be 4K, but the bitrate and the
   frame rate can be too low to look like 4K. Read the current values with
   `scripts/get-encode-res.ps1`. Change them with `scripts/set-encode.ps1`. Note: a
   budget 4K recorder can limit 4K to about 7 fps and a low maximum bitrate. These are
   hardware limits.

All scripts use the Dahua RPC2 API. Each script asks for the admin password at a prompt.
No script stores a password.


## Scripts

All scripts are Windows PowerShell. Run them from a computer on the same LAN. Each script
asks for the password at a prompt. No script stores or logs a password.

| Script | Function |
|---|---|
| `scripts/get-encode-res.ps1` | Read the per-channel resolution, codec, bitrate, and frame rate. |
| `scripts/set-encode.ps1` | Change the main-stream bitrate and frame rate. |
| `scripts/set-onvif-logincheck.ps1` | Turn `OnvifLoginCheck` on or off. |
| `scripts/get-device-info.ps1` | Read the recorder model, firmware, and serial number. |
| `scripts/onvif-rpc-probe.ps1` | Read-only RPC2 survey (users, groups, services, config). |
| `scripts/onvif-digest.ps1` | Test ONVIF HTTP-Digest login against the recorder. |
| `scripts/onvif-test.ps1` | Test an ONVIF `GetProfiles` request. |
| `scripts/delete-protect-camera.ps1` | Delete a camera from UniFi Protect through the Protect API. |
| `scripts/deprecated/run-proxy.ps1` | The old `unifi-cam-proxy` launcher. It does not work with current Protect. Kept for reference. |

Edit the IP addresses at the top of each script for your network. The example value is
`192.168.1.108`.


## Limits

- A Raspberry Pi 3 has a 100 Mbps network port. The proxy relays each stream in and out.
  Therefore, keep (bitrate x channels x 2) well below 100 Mbps. About 4 Mbps to 6 Mbps for
  each channel, and about five channels, is a safe target. A faster host (Raspberry Pi 4
  or 5, or a small x86 computer, with gigabit) allows more.
- A budget 4K recorder can limit 4K to about 7 fps. If smooth motion is more important than
  resolution, set a channel to 1440p to get a higher frame rate.
- The `onvif-server` image on the registry is amd64 only. Always build it from source on
  an ARM host.


## Credits

- [`daniela-hase/onvif-server`](https://github.com/daniela-hase/onvif-server) — the virtual
  ONVIF proxy.
