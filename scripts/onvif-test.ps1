# ONVIF authentication test against the Lorex recorder.
# The Lorex media service uses HTTP Digest auth, so this prompts for the
# password (never stored/echoed), builds a PSCredential, and lets
# Invoke-WebRequest answer the Digest challenge. It calls GetProfiles to
# confirm the account authenticates and to list the channels/streams exposed.

$ErrorActionPreference = 'Stop'
$device   = '192.168.1.108'
$user     = Read-Host "ONVIF username to test (e.g. admin or unifi)"
$mediaUrl = "http://$device/onvif/media_service"

$secure = Read-Host -AsSecureString "Password for '$user'"
$cred   = New-Object System.Management.Automation.PSCredential($user, $secure)

$body = @'
<?xml version="1.0" encoding="UTF-8"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
<s:Body><GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/></s:Body></s:Envelope>
'@

Write-Host "`nCalling GetProfiles at $mediaUrl (HTTP Digest) ...`n" -ForegroundColor Cyan
try {
  $r = Invoke-WebRequest -Uri $mediaUrl -Method Post -Body $body `
        -ContentType 'application/soap+xml; charset=utf-8' `
        -Credential $cred -TimeoutSec 12 -UseBasicParsing
  if ($r.Content -match 'Fault|NotAuthorized|FailedAuthentication') {
    Write-Host "AUTH FAILED - SOAP fault returned:" -ForegroundColor Red
    $r.Content.Substring(0,[Math]::Min(600,$r.Content.Length))
  } else {
    # Each <Profiles token="..."> is one channel/stream the DVR exposes
    $profiles = ([regex]'<[^>]*Profiles[^>]*token="([^"]+)"').Matches($r.Content) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
    $names    = ([regex]'<[^>]*Name>([^<]+)</[^>]*Name>').Matches($r.Content) | ForEach-Object { $_.Groups[1].Value }
    Write-Host "AUTH OK - ONVIF accepted the credentials." -ForegroundColor Green
    Write-Host "`nProfiles exposed to an ONVIF client (what Protect would see):"
    $profiles | ForEach-Object { "  - $_" }
    Write-Host "`nProfile/stream count: $($profiles.Count)"
    if ($names) { Write-Host "Names: $($names -join ', ')" }
  }
} catch {
  $resp = $_.Exception.Response
  if ($resp) {
    $sr = New-Object IO.StreamReader($resp.GetResponseStream()); $txt = $sr.ReadToEnd()
    Write-Host "HTTP $([int]$resp.StatusCode)" -ForegroundColor Yellow
    if ([int]$resp.StatusCode -eq 401) { Write-Host "  -> ONVIF AUTHENTICATION REJECTED for '$user' (wrong password or no ONVIF access)" -ForegroundColor Red }
    if ($txt) { $txt.Substring(0,[Math]::Min(600,$txt.Length)) }
  } else {
    "Request error: $($_.Exception.Message)"
  }
}
