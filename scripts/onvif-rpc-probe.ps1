# Dahua/Lorex RPC2 reverse-engineering probe (READ-ONLY).
# Logs in via the documented global.login handshake (you enter the admin
# password; it is never stored or echoed), then queries candidate methods to
# discover how ONVIF users are stored. Writes NOTHING to the recorder.

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

$script:id = 0
$script:session = $null
$loginUrl = "http://$device/RPC2_Login"
$rpcUrl   = "http://$device/RPC2"

function Rpc([string]$url,[hashtable]$payload) {
  $script:id++
  $payload.id = $script:id
  if ($script:session) { $payload.session = $script:session }
  Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' -TimeoutSec 12 -Body ($payload | ConvertTo-Json -Depth 12)
}

# --- Step 1: challenge ---
$c = Rpc $loginUrl @{ method='global.login'; params=@{ userName=$user; password=''; clientType='Web3.0'; loginType='Direct' } }
$script:session = $c.session
$realm  = $c.params.realm
$random = $c.params.random
if (-not $realm) { Write-Host "No challenge returned:"; $c | ConvertTo-Json -Depth 8; $pass=$null; return }

# --- Step 2: real login ---
$pwdHash  = MD5U("$user`:$realm`:$pass")
$passHash = MD5U("$user`:$random`:$pwdHash")
$pass = $null
$login = Rpc $loginUrl @{ method='global.login'; params=@{ userName=$user; password=$passHash; clientType='Web3.0'; authorityType='Default'; passwordType='Default' } }
if (-not $login.result) { Write-Host "LOGIN FAILED:" -ForegroundColor Red; $login | ConvertTo-Json -Depth 8; return }
Write-Host "LOGIN OK (session $script:session)`n" -ForegroundColor Green

# --- Read-only probes ---
function Probe([string]$label,[hashtable]$payload) {
  try {
    $r = Rpc $rpcUrl $payload
    $ok = $r.result
    Write-Host ("[{0}] result={1}" -f $label, $ok) -ForegroundColor ($(if($ok){'Green'}else{'DarkGray'}))
    if ($ok) { ($r | ConvertTo-Json -Depth 8 -Compress) }
    elseif ($r.error) { "    error: $($r.error | ConvertTo-Json -Compress)" }
  } catch { Write-Host "[$label] EXC $($_.Exception.Message)" -ForegroundColor DarkGray }
}

Write-Host "=== Round 3: introspect userManager.addUser (read-only) ===`n"
Probe 'listMethod:userManager(str)'  @{ method='system.listMethod'; params='userManager' }
Probe 'listMethod:userManager(obj)'  @{ method='system.listMethod'; params=@{ service='userManager' } }
Probe 'help:addUser(str)'            @{ method='system.methodHelp'; params='userManager.addUser' }
Probe 'help:addUser(obj)'            @{ method='system.methodHelp'; params=@{ name='userManager.addUser' } }
Probe 'sig:addUser(str)'             @{ method='system.methodSignature'; params='userManager.addUser' }
Probe 'sig:addUser(obj)'             @{ method='system.methodSignature'; params=@{ name='userManager.addUser' } }

# clean logout
try { Rpc $rpcUrl @{ method='global.logout'; params=$null } | Out-Null } catch {}
Write-Host "`nDone. (logged out)"
