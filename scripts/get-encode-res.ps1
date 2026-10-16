# Read the Lorex's actual encoder config (per-channel main/sub resolution + codec).
# Read-only. You enter the admin password at the prompt; it is never stored/echoed.

$ErrorActionPreference = 'Stop'
$device = '192.168.1.108'
$user   = 'admin'

$sec  = Read-Host -AsSecureString "admin password"
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
$pass = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)

function MD5U([string]$s) {
  $m = [Security.Cryptography.MD5]::Create()
  ((($m.ComputeHash([Text.Encoding]::UTF8.GetBytes($s))) | ForEach-Object { $_.ToString('x2') }) -join '').ToUpper()
}
$script:id = 0; $script:session = $null
$loginUrl = "http://$device/RPC2_Login"; $rpcUrl = "http://$device/RPC2"
function Rpc([string]$url,[hashtable]$p) {
  $script:id++; $p.id = $script:id
  if ($script:session) { $p.session = $script:session }
  Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' -TimeoutSec 12 -Body ($p | ConvertTo-Json -Depth 12)
}

$c = Rpc $loginUrl @{ method='global.login'; params=@{ userName=$user; password=''; clientType='Web3.0'; loginType='Direct' } }
$script:session = $c.session
$pwdHash  = MD5U("$user`:$($c.params.realm)`:$pass")
$passHash = MD5U("$user`:$($c.params.random)`:$pwdHash")
$pass = $null
$login = Rpc $loginUrl @{ method='global.login'; params=@{ userName=$user; password=$passHash; clientType='Web3.0'; authorityType='Default'; passwordType='Default' } }
if (-not $login.result) { Write-Host "LOGIN FAILED" -ForegroundColor Red; return }
Write-Host "Logged in.`n" -ForegroundColor Green

$enc = Rpc $rpcUrl @{ method='configManager.getConfig'; params=@{ name='Encode' } }
$table = $enc.params.table
if (-not $table) { Write-Host "No Encode table returned:"; $enc | ConvertTo-Json -Depth 8; return }

Write-Host "Per-channel encoder settings (from the recorder):" -ForegroundColor Cyan
for ($i=0; $i -lt $table.Count; $i++) {
  $m = $table[$i].MainFormat[0].Video
  $e = $table[$i].ExtraFormat[0].Video
  $mr = if ($m) { "$($m.Width)x$($m.Height) $($m.Compression) $($m.FPS)fps $($m.BitRate)kbps" } else { "n/a" }
  $er = if ($e) { "$($e.Width)x$($e.Height) $($e.Compression)" } else { "n/a" }
  "  Ch$($i+1):  MAIN = $mr   |   SUB = $er"
}

Write-Host "`nResolution options the recorder supports for the main stream (ch1):" -ForegroundColor Cyan
try {
  $caps = Rpc $rpcUrl @{ method='encode.getConfigCaps'; params=@{ channel=0 } }
  ($caps | ConvertTo-Json -Depth 10 -Compress)
} catch { "encode.getConfigCaps not available: $($_.Exception.Message)" }

try { Rpc $rpcUrl @{ method='global.logout'; params=$null } | Out-Null } catch {}
