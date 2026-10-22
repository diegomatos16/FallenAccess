$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'Install-Diagnostics.ps1'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$p = Start-Process -FilePath (Get-Command pwsh.exe).Source -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$script+'"'),'-PlayerSid',$sid) -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Instalação falhou: $($p.ExitCode)" }
$session = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime\current-session.json') -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'deployment.json') -Raw | ConvertFrom-Json
if ($manifest.SessionId -ne $session.Id -or $manifest.Files.Count -ne 12) { throw 'Instalação não corresponde à sessão.' }
Write-Output ('Instalação conferida: ' + $session.Id)
