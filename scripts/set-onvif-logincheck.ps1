# Toggle Dahua/Lorex UserGlobal.OnvifLoginCheck via RPC2.
#   .\set-onvif-logincheck.ps1 off   -> disables the separate ONVIF login check (default)
#   .\set-onvif-logincheck.ps1 on    -> restores it (revert)
# You enter the admin password at the prompt; it is never stored or echoed.

param([ValidateSet('on','off')][string]$state = 'off')
$ErrorActionPreference = 'Stop'
$device = '192.168.1.108'
$user   = 'admin'
$target = ($state -eq 'on')   # OnvifLoginCheck value to write

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

# login handshake
$c = Rpc $loginUrl @{ method='global.login'; params=@{ userName=$user; password=''; clientType='Web3.0'; loginType='Direct' } }
$script:session = $c.session
$pwdHash  = MD5U("$user`:$($c.params.realm)`:$pass")
$passHash = MD5U("$user`:$($c.params.random)`:$pwdHash")
$pass = $null
$login = Rpc $loginUrl @{ method='global.login'; params=@{ userName=$user; password=$passHash; clientType='Web3.0'; authorityType='Default'; passwordType='Default' } }
if (-not $login.result) { Write-Host "LOGIN FAILED" -ForegroundColor Red; $login | ConvertTo-Json -Depth 6; return }

# read current
$before = Rpc $rpcUrl @{ method='configManager.getConfig'; params=@{ name='UserGlobal' } }
Write-Host "Before: OnvifLoginCheck = $($before.params.table.OnvifLoginCheck)"

# write new value
$set = Rpc $rpcUrl @{ method='configManager.setConfig'; params=@{ name='UserGlobal'; table=@{ OnvifLoginCheck=$target } } }
if (-not $set.result) { Write-Host "setConfig FAILED:" -ForegroundColor Red; $set | ConvertTo-Json -Depth 6; Rpc $rpcUrl @{method='global.logout';params=$null} | Out-Null; return }

# verify
$after = Rpc $rpcUrl @{ method='configManager.getConfig'; params=@{ name='UserGlobal' } }
$now = $after.params.table.OnvifLoginCheck
if ($now -eq $target) {
  Write-Host "After:  OnvifLoginCheck = $now" -ForegroundColor Green
  Write-Host ("`nDone. ONVIF login check is now {0}." -f $(if($target){'ON (restored)'}else{'OFF'})) -ForegroundColor Green
} else {
  Write-Host "After:  OnvifLoginCheck = $now (unexpected)" -ForegroundColor Yellow
}
try { Rpc $rpcUrl @{ method='global.logout'; params=$null } | Out-Null } catch {}
