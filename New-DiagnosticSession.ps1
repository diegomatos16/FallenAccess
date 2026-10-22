param([ValidateSet('Baseline','Loader','Probe','UI')][string]$Profile = 'Loader')
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'runtime') -Force | Out-Null
$id = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ') + '-' + $Profile.ToLowerInvariant()
$folder = Join-Path $PSScriptRoot ('logs\sessions\' + $id)
New-Item -ItemType Directory -Path $folder -Force | Out-Null
Add-Type -TypeDefinition 'using System.Text; using System.Runtime.InteropServices; public static class FallenDiagnosticPath { [DllImport("kernel32.dll",CharSet=CharSet.Unicode)] public static extern uint GetShortPathName(string path,StringBuilder output,uint size); }' -ErrorAction SilentlyContinue
$buffer = [Text.StringBuilder]::new(32768)
if (-not [FallenDiagnosticPath]::GetShortPathName($folder,$buffer,32768)) { throw 'GetShortPathName falhou.' }
$session = [ordered]@{Id=$id; Profile=$Profile; Directory=$folder; LuaDirectory=$buffer.ToString().Replace('\','/'); CreatedUtc=[DateTime]::UtcNow.ToString('o')}
$json = $session | ConvertTo-Json
$json | Set-Content -LiteralPath (Join-Path $folder 'session.json') -Encoding utf8
$json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime\current-session.json') -Encoding utf8
Write-Output $folder
