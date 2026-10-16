# Hand-rolled HTTP Digest (RFC 2617) ONVIF test for the Lorex.
# Bypasses Invoke-WebRequest's digest quirks (empty opaque, body-on-retry).
# Prompts for the password (never stored/echoed), parses the 401 challenge,
# computes the digest response manually, and re-sends GetProfiles with it.

$ErrorActionPreference = 'Stop'
$device = '192.168.1.108'
$path   = '/onvif/media_service'
$url    = "http://$device$path"
$method = 'POST'

$user = Read-Host "ONVIF username to test (admin / unifi / other)"
$sec  = Read-Host -AsSecureString "Password for '$user'"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
$pass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

function MD5Hex([string]$s) {
  $md5 = [Security.Cryptography.MD5]::Create()
  ($md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)) | ForEach-Object { $_.ToString('x2') }) -join ''
}

$body = '<?xml version="1.0" encoding="UTF-8"?><s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"><s:Body><GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/></s:Body></s:Envelope>'
$bodyBytes = [Text.Encoding]::UTF8.GetBytes($body)

function Send-Req([hashtable]$headers) {
  $req = [Net.HttpWebRequest]::Create($url)
  $req.Method = $method
  $req.ContentType = 'application/soap+xml; charset=utf-8'
  $req.ContentLength = $bodyBytes.Length
  $req.AllowAutoRedirect = $false
  foreach ($k in $headers.Keys) { $req.Headers.Add($k, $headers[$k]) }
  $rs = $req.GetRequestStream(); $rs.Write($bodyBytes,0,$bodyBytes.Length); $rs.Close()
  try {
    $resp = $req.GetResponse()
    $sr = New-Object IO.StreamReader($resp.GetResponseStream())
    return @{ code = [int]$resp.StatusCode; body = $sr.ReadToEnd(); auth = $null }
  } catch [Net.WebException] {
    $r = $_.Exception.Response
    if (-not $r) { throw }
    $sr = New-Object IO.StreamReader($r.GetResponseStream())
    return @{ code = [int]$r.StatusCode; body = $sr.ReadToEnd(); auth = $r.Headers['WWW-Authenticate'] }
  }
}

# Step 1: unauthenticated request to capture the challenge
Write-Host "`nStep 1: fetching digest challenge ..." -ForegroundColor Cyan
$first = Send-Req @{}
if ($first.code -ne 401) { Write-Host "Unexpected (no 401). Code $($first.code)"; $pass=$null; return }

$chal = $first.auth
Write-Host "  challenge: $chal"
function Field([string]$name) { if ($chal -match "$name=""([^""]*)""") { return $matches[1] } elseif ($chal -match "$name=([^,]+)") { return $matches[1].Trim() } }
$realm = Field 'realm'; $nonce = Field 'nonce'; $qop = Field 'qop'; $opaque = Field 'opaque'

# Step 2: compute digest response by hand
$cnonce = (MD5Hex([Guid]::NewGuid().ToString())).Substring(0,16)
$nc = '00000001'
$HA1 = MD5Hex("$user`:$realm`:$pass")
$HA2 = MD5Hex("$method`:$path")
if ($qop) { $response = MD5Hex("$HA1`:$nonce`:$nc`:$cnonce`:$qop`:$HA2") }
else      { $response = MD5Hex("$HA1`:$nonce`:$HA2") }
$pass = $null

$auth = "Digest username=""$user"", realm=""$realm"", nonce=""$nonce"", uri=""$path"", response=""$response"""
if ($qop)    { $auth += ", qop=$qop, nc=$nc, cnonce=""$cnonce""" }
if ($null -ne $opaque) { $auth += ", opaque=""$opaque""" }

Write-Host "`nStep 2: re-sending GetProfiles with hand-built Authorization ..." -ForegroundColor Cyan
$second = Send-Req @{ Authorization = $auth }
Write-Host "  HTTP $($second.code)"

if ($second.code -eq 200 -and $second.body -notmatch 'Fault') {
  $profiles = ([regex]'<[^>]*Profiles[^>]*token="([^"]+)"').Matches($second.body) | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique
  Write-Host "`nAUTH OK -- '$user' authenticates over ONVIF!" -ForegroundColor Green
  Write-Host "Channels/profiles exposed to Protect:"
  $profiles | ForEach-Object { "  - $_" }
  Write-Host "Profile count: $($profiles.Count)"
} elseif ($second.code -eq 401) {
  Write-Host "`nSTILL 401 -- this account genuinely is not in the ONVIF user list." -ForegroundColor Red
} else {
  Write-Host "`nUnexpected response:" -ForegroundColor Yellow
  $second.body.Substring(0,[Math]::Min(500,$second.body.Length))
}
