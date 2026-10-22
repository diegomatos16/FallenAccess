$ErrorActionPreference='Stop'
$zig=Join-Path $PSScriptRoot 'tools\zig\zig-windows-x86_64-0.13.0\zig.exe'
$build=Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Path $build -Force|Out-Null
$env:ZIG_GLOBAL_CACHE_DIR=Join-Path $build 'zig-cache'
$lua=Join-Path $PSScriptRoot 'tools\LuaRaw'
$sources=@(Get-ChildItem -LiteralPath (Join-Path $lua 'src') -Filter '*.c' | Where-Object { $_.Name -notin @('lua.c','luac.c') } | ForEach-Object FullName)
& $zig 'c++' '-shared' '-std=c++17' '-O2' '-static-libstdc++' '-I' (Join-Path $lua 'include') '-I' (Join-Path $PSScriptRoot 'lib\prism\include') '-x' 'c++' (Join-Path $PSScriptRoot 'src\native_speech.cpp') @sources '-lole32' '-o' (Join-Path $build 'fallen_speech.dll')
if($LASTEXITCODE -ne 0) { throw 'Native build failed.' }
& $zig 'c++' '-std=c++17' '-O2' '-static-libstdc++' '-I' (Join-Path $lua 'include') '-x' 'c++' (Join-Path $PSScriptRoot 'tests\native_smoke.cpp') @sources '-o' (Join-Path $build 'native_smoke.exe')
if($LASTEXITCODE -ne 0) { throw 'Native smoke harness build failed.' }
& (Join-Path $build 'native_smoke.exe') (Join-Path $build 'fallen_speech.dll')
if($LASTEXITCODE -ne 0) { throw 'Native Lua bridge smoke test failed.' }
Get-FileHash -LiteralPath (Join-Path $build 'fallen_speech.dll')
