# Bump main-stream bitrate/fps for the live channels on the Lorex (RPC2 read-modify-write).
# Targets channels 1,3,4,5,6 -> 15 fps / 6144 kbps. Leaves other channels alone.
# You enter the admin password at the prompt; it is never stored or echoed.

$ErrorActionPreference = 'Stop'
$device = '192.168.1.108'
$user   = 'admin'
$targetFps     = 15
$targetBitrate = 6144
$liveIdx = @(0,2,3,4,5)   # 0-indexed = channels 1,3,4,5,6

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
  Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' -TimeoutSec 20 -Body ($p | ConvertTo-Json -Depth 40)
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

Write-Host "BEFORE:" -ForegroundColor Cyan
foreach ($i in $liveIdx) {
  $v = $table[$i].MainFormat[0].Video
  if ($v) { "  Ch$($i+1): $($v.Width)x$($v.Height) $($v.Compression) $($v.FPS)fps $($v.BitRate)kbps (ctrl=$($v.BitRateControl))" }
}

foreach ($i in $liveIdx) {
  $v = $table[$i].MainFormat[0].Video
  if ($v) { $v.FPS = $targetFps; $v.BitRate = $targetBitrate }
}

Write-Host "`nWriting new settings..." -ForegroundColor Cyan
$set = Rpc $rpcUrl @{ method='configManager.setConfig'; params=@{ name='Encode'; table=$table } }
if (-not $set.result) {
  Write-Host "setConfig FAILED:" -ForegroundColor Red
  $set | ConvertTo-Json -Depth 8
  try { Rpc $rpcUrl @{ method='global.logout'; params=$null } | Out-Null } catch {}
  return
}
Write-Host "setConfig OK." -ForegroundColor Green

Start-Sleep -Seconds 2
$enc2 = Rpc $rpcUrl @{ method='configManager.getConfig'; params=@{ name='Encode' } }
$t2 = $enc2.params.table
Write-Host "`nAFTER:" -ForegroundColor Green
foreach ($i in $liveIdx) {
  $v = $t2[$i].MainFormat[0].Video
  if ($v) { "  Ch$($i+1): $($v.Width)x$($v.Height) $($v.Compression) $($v.FPS)fps $($v.BitRate)kbps" }
}
Write-Host "`nIf AFTER shows the new values, Protect should sharpen up within a minute (it may re-pull the stream)." -ForegroundColor Cyan

try { Rpc $rpcUrl @{ method='global.logout'; params=$null } | Out-Null } catch {}
