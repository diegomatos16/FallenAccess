$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'SwGame-Win64-Shipping','starwarsjedifallenorder' -ErrorAction SilentlyContinue) {
    throw 'Feche o jogo antes de remover.'
}
$manifestPath = Join-Path $PSScriptRoot 'deployment.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$expected = 'C:\Program Files\EA Games\Jedi Fallen Order\SwGame\Binaries\Win64'
if ($manifest.GameDirectory -ne $expected) { throw 'Diretório inesperado no manifesto.' }
$allowed = @('dwmapi.dll','UE4SS.dll','UE4SS-settings.ini','Mods\mods.txt','Mods\FallenAccess\Scripts\main.lua','Mods\FallenAccess\Scripts\config.lua',
    'Jedi Fallen Order\UE4SS-settings.ini','Jedi Fallen Order\MemberVariableLayout.ini','Jedi Fallen Order\Mods\mods.txt',
    'Jedi Fallen Order\Mods\FallenAccess\Scripts\main.lua','Jedi Fallen Order\Mods\FallenAccess\Scripts\config.lua',
    'Jedi Fallen Order\Mods\FallenAccess\Scripts\fallen_speech.dll','Jedi Fallen Order\Mods\FallenAccess\Scripts\prism.dll',
    'Jedi Fallen Order\Mods\FallenAccess\Scripts\third-party\prism\mpl-2.0.txt','Jedi Fallen Order\Mods\FallenAccess\Scripts\third-party\prism\NOTICE',
    'Jedi Fallen Order\Mods\FallenAccess\Scripts\third-party\lua\lua.h') |
    ForEach-Object { Join-Path $expected $_ }
foreach ($path in $manifest.AddedFiles) { if ($path -notin $allowed) { throw "Caminho não pertence aos arquivos próprios conhecidos: $path" } }
if ($manifest.Schema -eq 2) {
    foreach ($file in $manifest.Files) {
        if ((Test-Path -LiteralPath $file.Path) -and (Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256) {
            throw "Arquivo modificado após instalação; revisar antes de remover: $($file.Path)"
        }
    }
}
foreach ($file in $manifest.AddedFiles) {
    $absolute = [IO.Path]::GetFullPath($file)
    if (-not $absolute.StartsWith($expected + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Caminho fora da instalação: $absolute"
    }
    if (Test-Path -LiteralPath $absolute -PathType Leaf) { Remove-Item -LiteralPath $absolute }
}
# Remove only empty folders. UE4SS diagnostic files may be retained for inspection.
foreach ($relative in @('Mods\FallenAccess\Scripts','Mods\FallenAccess','Mods','Jedi Fallen Order\Mods\FallenAccess\Scripts','Jedi Fallen Order\Mods\FallenAccess','Jedi Fallen Order\Mods')) {
    $folder = Join-Path $expected $relative
    if ((Test-Path -LiteralPath $folder) -and -not (Get-ChildItem -LiteralPath $folder -Force)) {
        Remove-Item -LiteralPath $folder
    }
}
Move-Item -LiteralPath $manifestPath -Destination ($manifestPath + '.removed-' + (Get-Date -Format yyyyMMddHHmmss))
Write-Output 'Arquivos instalados removidos. Logs preservados.'
