$ErrorActionPreference = 'Stop'
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$archive = Join-Path $dist "FallenAccess-v$version.zip"
$files = @(
    'VERSION','README.md','RELEASE-NOTES.md','CHANGELOG.md','THIRD-PARTY.md',
    'New-DiagnosticSession.ps1','Invoke-DiagnosticInstall.ps1','Install-Diagnostics.ps1',
    'Uninstall.ps1','Disable-Diagnostics.ps1','Deploy.ps1',
    'Watch-DiagnosticSession.ps1','Request-DiagnosticCapture.ps1','Coletar-Diagnostico.cmd',
    'Build-Native.ps1','Package-Release.ps1','src\diagnostic.lua','src\native_speech.cpp',
    'build\fallen_speech.dll','lib\prism\prism.dll',
    'tools\ue4ss\UE4SS.dll','tools\ue4ss\dwmapi.dll','tools\ue4ss\UE4SS-settings.ini',
    'tools\ue4ss\LICENSE','tools\ue4ss\README.md',
    'tools\custom-configs\Star Wars Jedi Fallen Order\MemberVariableLayout.ini'
)
foreach ($directory in @('lib\prism\include','lib\prism\third-party','tools\LuaRaw','tests')) {
    $base = Join-Path $PSScriptRoot $directory
    $files += Get-ChildItem -LiteralPath $base -Recurse -File |
        Where-Object { $_.FullName -notmatch '[\\/]__pycache__[\\/]' } |
        ForEach-Object { [IO.Path]::GetRelativePath($PSScriptRoot, $_.FullName) }
}
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)) {
        throw "Arquivo necessário ausente: $file"
    }
}
$stream = [IO.File]::Open($archive, [IO.FileMode]::Create)
$zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in ($files | Sort-Object -Unique)) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, (Join-Path $PSScriptRoot $file), $file.Replace('\','/'),
            [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $zip.Dispose(); $stream.Dispose() }
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash  $([IO.Path]::GetFileName($archive))" |
    Set-Content -LiteralPath ($archive + '.sha256') -Encoding ascii
Write-Output $archive
Write-Output "SHA256: $hash"
