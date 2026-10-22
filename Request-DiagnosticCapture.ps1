param([ValidatePattern('^[a-z0-9-]{1,40}$')][string]$Label = 'manual')
$ErrorActionPreference = 'Stop'
$session = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime\current-session.json') -Raw | ConvertFrom-Json
if ($session.Profile -ne 'UI') { throw 'Captura exige perfil UI.' }
$ready = Join-Path $session.Directory 'probe.jsonl'
if (-not (Test-Path -LiteralPath $ready)) { throw 'Sonda ainda não escreveu prova de início.' }
$events = @(Get-Content -LiteralPath $ready | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object session -eq $session.Id)
if (-not @($events | Where-Object event -eq 'ui.keys.ready').Count) { throw 'Captura ainda não inicializada.' }
$request = Join-Path $session.Directory 'capture.request'
if (Test-Path -LiteralPath $request) { throw 'Solicitação anterior ainda pendente.' }
$token = $Label + '-' + [Guid]::NewGuid().ToString('N')
$temporary = Join-Path $session.Directory ('capture-' + $token + '.tmp')
$token | Set-Content -LiteralPath $temporary -Encoding utf8NoBOM
Move-Item -LiteralPath $temporary -Destination $request
Write-Output ('Capture requested session=' + $session.Id + ' token=' + $token)
