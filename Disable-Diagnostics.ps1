$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'SwGame-Win64-Shipping','starwarsjedifallenorder' -ErrorAction SilentlyContinue) { throw 'Feche o jogo antes de desativar.' }
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'deployment.json') -Raw | ConvertFrom-Json
$proxy = 'C:\Program Files\EA Games\Jedi Fallen Order\SwGame\Binaries\Win64\dwmapi.dll'
if ($manifest.Schema -ne 2 -or $proxy -notin $manifest.AddedFiles) { throw 'Proxy não registrado como próprio.' }
$entry = @($manifest.Files | Where-Object Path -eq $proxy)[0]
if ((Get-FileHash -LiteralPath $proxy).Hash -ne $entry.SHA256) { throw 'Proxy mudou; não mover arquivo desconhecido.' }
$session = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime\current-session.json') -Raw | ConvertFrom-Json
$destination = Join-Path $session.Directory 'disabled-dwmapi.dll'
if (Test-Path -LiteralPath $destination) { throw 'Cópia de desativação já existe.' }
# Exact single file, both absolute paths are fixed/validated within authorized roots.
$project = [IO.Path]::GetFullPath($PSScriptRoot) + '\'
$destination = [IO.Path]::GetFullPath($destination)
if (-not $destination.StartsWith($project,[StringComparison]::OrdinalIgnoreCase)) { throw 'Destino fora do projeto.' }
Move-Item -LiteralPath $proxy -Destination $destination
Write-Output 'Carregador desativado; diagnósticos preservados.'
