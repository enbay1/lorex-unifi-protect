# Delete a camera from UniFi Protect through the Protect API, matched by its IP.
# Useful to remove a stale third-party / ONVIF adoption (for example a recorder that
# Protect added directly as a "General" device) that the web interface will not remove.
# You enter your UniFi console login at the prompt; it is never stored or echoed.
# The script finds the camera, shows it, asks you to confirm, then deletes it.
# Use a LOCAL UniFi admin account (not Ubiquiti cloud SSO, which needs 2FA).

$ErrorActionPreference = 'Stop'
$base   = 'https://192.168.1.1'   # your UniFi console IP
$target = '192.168.1.108'         # the IP of the camera to delete

# --- accept the console's self-signed certificate (Windows PowerShell 5.1) ---
try {
  Add-Type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCerts : ICertificatePolicy {
  public bool CheckValidationResult(ServicePoint s, X509Certificate c, WebRequest r, int p) { return true; }
}
"@
  [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCerts
} catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$cred = Get-Credential -Message 'UniFi console login (local admin account)'
$user = $cred.UserName
$pass = $cred.GetNetworkCredential().Password

function Csrf($resp) {
  foreach ($h in 'X-Updated-Csrf-Token','X-Csrf-Token') { if ($resp.Headers[$h]) { return $resp.Headers[$h] } }
  return $null
}

Write-Host "`nLogging in..." -ForegroundColor Cyan
$loginBody = @{ username = $user; password = $pass } | ConvertTo-Json
$login = Invoke-WebRequest -Uri "$base/api/auth/login" -Method Post -Body $loginBody -ContentType 'application/json' -SessionVariable sess -UseBasicParsing
$pass = $null
$csrf = Csrf $login
if (-not $csrf) { Write-Host "No CSRF token returned - login may have failed or needs 2FA." -ForegroundColor Yellow }
Write-Host "Logged in." -ForegroundColor Green

Write-Host "Fetching Protect devices..." -ForegroundColor Cyan
$hdr = @{}; if ($csrf) { $hdr['X-CSRF-Token'] = $csrf }
$boot = Invoke-WebRequest -Uri "$base/proxy/protect/api/bootstrap" -WebSession $sess -Headers $hdr -UseBasicParsing
$c2 = Csrf $boot; if ($c2) { $csrf = $c2; $hdr['X-CSRF-Token'] = $csrf }
$data = $boot.Content | ConvertFrom-Json

$cam = $data.cameras | Where-Object { $_.host -eq $target }
if (-not $cam) { Write-Host "No camera found at $target. Nothing to delete." -ForegroundColor Yellow; return }
if ($cam.Count -gt 1) { Write-Host "Multiple matches - listing, not deleting:" -ForegroundColor Yellow; $cam | ForEach-Object { "  $($_.name)  id=$($_.id)  host=$($_.host)  type=$($_.type)" }; return }

Write-Host "`nFound this camera:" -ForegroundColor Green
"  Name : $($cam.name)"
"  Id   : $($cam.id)"
"  Host : $($cam.host)"
"  Type : $($cam.type)"
"  State: $($cam.state)"

$ans = Read-Host "`nDelete this camera from Protect? (type 'yes' to confirm)"
if ($ans -ne 'yes') { Write-Host "Cancelled - nothing deleted." -ForegroundColor Yellow; return }

Write-Host "Deleting..." -ForegroundColor Cyan
try {
  $del = Invoke-WebRequest -Uri "$base/proxy/protect/api/cameras/$($cam.id)" -Method Delete -WebSession $sess -Headers $hdr -UseBasicParsing
  Write-Host "Delete returned HTTP $($del.StatusCode) - removed." -ForegroundColor Green
} catch {
  $code = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
  Write-Host "Delete via /cameras/{id} returned HTTP $code." -ForegroundColor Yellow
  if ($_.Exception.Response) { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); Write-Host $sr.ReadToEnd() }
  Write-Host "If this wasn't a 2xx, tell me the code and I'll adjust the endpoint." -ForegroundColor Yellow
}
