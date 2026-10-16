# unifi-cam-proxy local test launcher
# Prompts for the Lorex account password (never stored, never echoed),
# then runs ONE proxy container in the foreground so you can watch the logs.
# Ctrl+C stops it. Nothing is written to disk and nothing persists.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- fixed settings (filled in for you) ---
$protectHost = '192.168.1.1'                                  # UniFi Protect console
$token       = '<ADOPTION_TOKEN>'                             # get from https://<console>/proxy/protect/api/cameras/manage-payload (valid 60 min)
$lorexHost   = '192.168.1.108'                                # Lorex recorder
$lorexUser   = 'unifi'                                        # account we created
$channel     = 1                                              # camera channel to test
$subtype     = 1                                              # 1 = substream (confirmed in VLC); 0 = main
$fakeMac     = 'AA:BB:CC:00:11:22'                            # made-up MAC for this test camera
$certPath    = Join-Path $here 'client.pem'

# --- prompt for the password securely ---
$secure = Read-Host -AsSecureString "Lorex 'unifi' account password"
$bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
$plain  = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

# URL-encode the password so special characters can't break the RTSP URL
$encPw = [uri]::EscapeDataString($plain)
$rtsp  = "rtsp://${lorexUser}:${encPw}@${lorexHost}:554/cam/realmonitor?channel=${channel}&subtype=${subtype}"

Write-Host ""
Write-Host "Starting proxy: channel $channel (subtype $subtype) -> Protect at $protectHost" -ForegroundColor Cyan
Write-Host "Watch below for 'Adopted' / a new camera in Protect. Ctrl+C to stop." -ForegroundColor Cyan
Write-Host ""

# Env-var mode: the image's /entrypoint.sh assembles the correct command when
# HOST, TOKEN and RTSP_URL are all set (it uses the generic 'rtsp' backend).
# This avoids the arg-passthrough bug where our flags replaced the default CMD.
docker run --rm -it `
  -e HOST=$protectHost `
  -e TOKEN=$token `
  -e MAC=$fakeMac `
  -e "RTSP_URL=$rtsp" `
  -v "${certPath}:/client.pem" `
  keshavdv/unifi-cam-proxy

# scrub the plaintext from memory
$plain = $null
