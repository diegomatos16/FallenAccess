param([switch]$Preview)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'Install-Diagnostics.ps1') -Preview:$Preview
