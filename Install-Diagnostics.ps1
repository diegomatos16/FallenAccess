param([switch]$Preview, [string]$PlayerSid = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
$ErrorActionPreference = 'Stop'
$game = 'C:\Program Files\EA Games\Jedi Fallen Order\SwGame\Binaries\Win64'
$working = Join-Path $game 'Jedi Fallen Order'
$manifestPath = Join-Path $PSScriptRoot 'deployment.json'
$session = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime\current-session.json') -Raw | ConvertFrom-Json
if ($session.Profile -eq 'Baseline') { throw 'Baseline não instala arquivos.' }
if (Get-Process -Name 'SwGame-Win64-Shipping','starwarsjedifallenorder' -ErrorAction SilentlyContinue) { throw 'Jogo aberto; instalação recusada.' }
$sources = @{
    'dwmapi.dll' = Join-Path $PSScriptRoot 'tools\ue4ss\dwmapi.dll'
    'UE4SS.dll' = Join-Path $PSScriptRoot 'tools\ue4ss\UE4SS.dll'
    'Jedi Fallen Order\MemberVariableLayout.ini' = Join-Path $PSScriptRoot 'tools\custom-configs\Star Wars Jedi Fallen Order\MemberVariableLayout.ini'
    'Jedi Fallen Order\Mods\FallenAccess\Scripts\main.lua' = Join-Path $PSScriptRoot 'src\diagnostic.lua'
    'Jedi Fallen Order\Mods\FallenAccess\Scripts\fallen_speech.dll' = Join-Path $PSScriptRoot 'build\fallen_speech.dll'
    'Jedi Fallen Order\Mods\FallenAccess\Scripts\prism.dll' = Join-Path $PSScriptRoot 'lib\prism\prism.dll'
    'Jedi Fallen Order\Mods\FallenAccess\Scripts\third-party\prism\mpl-2.0.txt' = Join-Path $PSScriptRoot 'lib\prism\third-party\prism\mpl-2.0.txt'
    'Jedi Fallen Order\Mods\FallenAccess\Scripts\third-party\prism\NOTICE' = Join-Path $PSScriptRoot 'lib\prism\third-party\prism\NOTICE'
    'Jedi Fallen Order\Mods\FallenAccess\Scripts\third-party\lua\lua.h' = Join-Path $PSScriptRoot 'tools\LuaRaw\include\lua.h'
}
$generated = @('Jedi Fallen Order\UE4SS-settings.ini','Jedi Fallen Order\Mods\mods.txt','Jedi Fallen Order\Mods\FallenAccess\Scripts\config.lua')
$paths = @(@($sources.Keys) + $generated | Sort-Object | ForEach-Object { Join-Path $game $_ })
$old = $null
if (Test-Path -LiteralPath $manifestPath) {
    $old = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($old.GameDirectory -ne $game -or $old.Schema -ne 2) { throw 'Manifesto antigo/incompatível; não sobrescrever.' }
    foreach ($file in $old.Files) {
        if ((Test-Path -LiteralPath $file.Path) -and (Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256) {
            throw "Arquivo do mod mudou fora desta instalação: $($file.Path)"
        }
    }
}
foreach ($path in $paths) {
    if ((Test-Path -LiteralPath $path) -and (-not $old -or $path -notin $old.AddedFiles)) {
        throw "Destino existente não pertence à instalação: $path"
    }
}
foreach ($source in $sources.Values) { if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Fonte ausente: $source" } }
$paths | Write-Output
if ($Preview) { return }
$originals = @(Get-ChildItem -LiteralPath $game -File -Filter '*.exe' | ForEach-Object { @{Path=$_.FullName; SHA256=(Get-FileHash -LiteralPath $_.FullName).Hash} })
$manifest = [ordered]@{Schema=2; GameDirectory=$game; DiagnosticDirectory=$working; AddedFiles=$paths; Files=@(); OriginalExecutables=$originals; SessionId=$session.Id; Profile=$session.Profile; LoaderVersion='3.0.1'; CreatedUtc=[DateTime]::UtcNow.ToString('o')}
# Record paths before any game mutation: even a partial installation is removable.
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
New-Item -ItemType Directory -Path (Join-Path $working 'Mods\FallenAccess\Scripts') -Force | Out-Null
$acl = Get-Acl -LiteralPath $working
$sid = [Security.Principal.SecurityIdentifier]::new($PlayerSid)
$rule = [Security.AccessControl.FileSystemAccessRule]::new($sid,'Modify','ContainerInherit,ObjectInherit','None','Allow')
$acl.AddAccessRule($rule)
Set-Acl -LiteralPath $working -AclObject $acl
$settings = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'tools\ue4ss\UE4SS-settings.ini') -Raw
$settings = $settings -replace '(?m)^GuiConsoleEnabled = 1','GuiConsoleEnabled = 0'
$settings = $settings -replace '(?m)^MajorVersion =[^\r\n]*','MajorVersion = 4'
$settings = $settings -replace '(?m)^MinorVersion =[^\r\n]*','MinorVersion = 21'
$settings = $settings -replace '(?m)^UseCache = 1','UseCache = 0'
$settings = $settings -replace '(?m)^bUseUObjectArrayCache = true','bUseUObjectArrayCache = false'
# Loader/Probe isolate startup from gameplay hooks. UI adds game-thread dispatch.
$settings = $settings -replace '(?m)^(Hook\w+\s*=\s*)1[^\S\r\n]*$', '${1}0'
if ($session.Profile -eq 'UI') { $settings = $settings -replace '(?m)^HookProcessInternal = 0','HookProcessInternal = 1' }
# UE4SS 3.0.1 CrashDumper::~CrashDumper unconditionally dereferences its hook.
# Keep the standard initialization enabled to prevent a null dereference on shutdown.
$settings = $settings -replace '(?m)^EnableDumping = 0','EnableDumping = 1'
$settings = $settings -replace '(?m)^FullMemoryDump = 1','FullMemoryDump = 0'
$settings | Set-Content -LiteralPath (Join-Path $working 'UE4SS-settings.ini') -Encoding utf8NoBOM
foreach ($relative in $sources.Keys) {
    $destination=Join-Path $game $relative
    New-Item -ItemType Directory -Path (Split-Path $destination) -Force|Out-Null
    Copy-Item -LiteralPath $sources[$relative] -Destination $destination
}
$enabled = if ($session.Profile -eq 'Loader') { 'FallenAccess : 0' } else { 'FallenAccess : 1' }
$enabled | Set-Content -LiteralPath (Join-Path $working 'Mods\mods.txt') -Encoding utf8NoBOM
$config = 'return { output = [[' + $session.LuaDirectory + ']], session = [[' + $session.Id + ']], profile = [[' + $session.Profile + ']] }'
$config | Set-Content -LiteralPath (Join-Path $working 'Mods\FallenAccess\Scripts\config.lua') -Encoding utf8NoBOM
$manifest.Files = @($paths | ForEach-Object { @{Path=$_; SHA256=(Get-FileHash -LiteralPath $_).Hash} })
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $session.Directory 'deployment.json')
Copy-Item -LiteralPath (Join-Path $working 'UE4SS-settings.ini') -Destination (Join-Path $session.Directory 'effective-settings.ini')
Write-Output ('Installed profile=' + $session.Profile + ' session=' + $session.Id)
