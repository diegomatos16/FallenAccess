param([ValidateRange(5,600)][int]$Seconds = 120, [ValidateRange(5,300)][int]$WaitForLaunchSeconds = 120)
$ErrorActionPreference = 'Stop'
$session = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime\current-session.json') -Raw | ConvertFrom-Json
$probeFolder = $session.Directory
$folder = Join-Path $probeFolder ('observations\' + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$game = 'C:\Program Files\EA Games\Jedi Fallen Order\SwGame\Binaries\Win64'
$loaderLog = Join-Path $game 'Jedi Fallen Order\UE4SS.log'
$started = Get-Date
$journal = Join-Path $folder 'observer.jsonl'
function Record([string]$Event, $Data) {
    @{Utc=[DateTime]::UtcNow.ToString('o'); Session=$session.Id; Event=$Event; Data=$Data} |
        ConvertTo-Json -Compress -Depth 8 | Add-Content -LiteralPath $journal -Encoding utf8
}
function Snapshot-Modules($Process) {
    try {
        $modules = @($Process.Modules | ForEach-Object { @{Name=$_.ModuleName; Path=$_.FileName; Size=$_.ModuleMemorySize} })
        $modules | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $folder 'modules.json') -Encoding utf8
        Record 'modules' @{Count=$modules.Count; UE4SS=@($modules | Where-Object Name -eq 'UE4SS.dll').Count}
    } catch { Record 'modules.error' $_.Exception.Message }
}
$summary = [ordered]@{Session=$session.Id; Profile=$session.Profile; StartedUtc=$started.ToUniversalTime().ToString('o'); Status='not_started'; ProcessId=$null; ProcessChain=@(); ExitCode=$null; CloseOutcome='not_requested'; ObservationSeconds=$Seconds; LuaStarted=$false; LuaReady=$false; Heartbeats=0; CrashEvents=0; MenuConfirmed=$false}
try {
    Record 'observer.start' @{Profile=$session.Profile; PowerShell=$PSVersionTable.PSVersion.ToString()}
    $existing = @(Get-Process -Name 'SwGame-Win64-Shipping','starwarsjedifallenorder' -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 1) { throw 'Mais de um processo do jogo; observação ambígua.' }
    $manifest = $null
    $manifestPath = Join-Path $PSScriptRoot 'deployment.json'
    if ($session.Profile -eq 'Baseline') {
        if (Test-Path -LiteralPath (Join-Path $game 'dwmapi.dll')) { throw 'Baseline recusado: proxy instalado.' }
    } else {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($manifest.SessionId -ne $session.Id -or $manifest.Profile -ne $session.Profile) { throw 'Sessão e instalação não correspondem.' }
        foreach ($file in $manifest.Files) {
            if ((Get-FileHash -LiteralPath $file.Path).Hash -ne $file.SHA256) { throw "Hash instalado mudou: $($file.Path)" }
        }
    }
    $originals = @(Get-ChildItem -LiteralPath $game -Filter '*.exe' -File | ForEach-Object { @{Path=$_.FullName; SHA256=(Get-FileHash -LiteralPath $_.FullName).Hash; Size=$_.Length} })
    @{Session=$session; Executables=$originals; Manifest=$manifest} | ConvertTo-Json -Depth 9 |
        Set-Content -LiteralPath (Join-Path $folder 'preflight.json') -Encoding utf8
    if (Test-Path -LiteralPath $loaderLog) {
        Copy-Item -LiteralPath $loaderLog -Destination (Join-Path $folder 'loader-before.log')
    }
    Write-Output 'Observador somente leitura. Abra, navegue e feche o jogo manualmente.'
    $deadline = (Get-Date).AddSeconds($WaitForLaunchSeconds)
    $process = $null
    while ((Get-Date) -lt $deadline -and -not $process) {
        $process = Get-Process -Name 'SwGame-Win64-Shipping','starwarsjedifallenorder' -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $process) { Start-Sleep -Milliseconds 100 }
    }
    if (-not $process) { $summary.Status='process_not_seen'; throw 'Processo não apareceu durante o prazo configurado.' }
    # Retain a process handle so an early crash still has a readable exit code.
    $null = $process.Handle
    if ($process.Path -notin @((Join-Path $game 'starwarsjedifallenorder.exe'),(Join-Path $game 'SwGame-Win64-Shipping.exe'))) { throw 'Processo inesperado.' }
    $summary.ProcessId = $process.Id
    $summary.ProcessChain += $process.Id
    Record 'process.seen' @{Id=$process.Id; Path=$process.Path; StartTimeUtc=$process.StartTime.ToUniversalTime().ToString('o')}
    Write-Output ('Processo observado: ' + $process.Id + ' perfil=' + $session.Profile)
    $end = (Get-Date).AddSeconds($Seconds)
    $lastModules = [DateTime]::MinValue
    while ((Get-Date) -lt $end) {
        $process.Refresh()
        if ($process.HasExited) {
            Record 'process.exit' @{Id=$process.Id; Code=$process.ExitCode.ToString('X8')}
            $replacement = $null
            $handoffDeadline = (Get-Date).AddSeconds(8)
            while ((Get-Date) -lt $handoffDeadline -and -not $replacement) {
                $replacement = Get-Process -Name 'SwGame-Win64-Shipping','starwarsjedifallenorder' -ErrorAction SilentlyContinue |
                    Where-Object { $_.Id -notin $summary.ProcessChain -and $_.StartTime -ge $started.AddSeconds(-2) } | Select-Object -First 1
                if (-not $replacement) { Start-Sleep -Milliseconds 200 }
            }
            if (-not $replacement) { break }
            $process = $replacement
            $null = $process.Handle
            $summary.ProcessId=$process.Id
            $summary.ProcessChain += $process.Id
            Record 'process.handoff' @{Id=$process.Id; Path=$process.Path; Reason='Launcher replaced process; not automatically classified as crash'}
            $lastModules=[DateTime]::MinValue
        }
        try {
            Record 'process.sample' @{Responding=$process.Responding; MainWindowTitle=$process.MainWindowTitle; WorkingSet=$process.WorkingSet64; CpuSeconds=$process.TotalProcessorTime.TotalSeconds; Threads=$process.Threads.Count}
        } catch { Record 'process.sample.error' $_.Exception.Message }
        if (((Get-Date)-$lastModules).TotalSeconds -ge 10) { Snapshot-Modules $process; $lastModules=Get-Date }
        if (Test-Path -LiteralPath $loaderLog) { Copy-Item -LiteralPath $loaderLog -Destination (Join-Path $folder 'UE4SS.log') -Force }
        Start-Sleep -Milliseconds 1000
    }
    if ($process.HasExited) {
        $summary.Status='exited_during_observation'
        $summary.ExitCode = $process.ExitCode.ToString('X8')
        Record 'process.exit' @{Code=$summary.ExitCode}
    } else {
        $summary.Status='alive_after_observation'
        Record 'observation.complete' 'Process alive; this does not prove that main menu loaded.'
    }

} catch {
    Record 'observer.error' $_.Exception.Message
    if ($summary.Status -eq 'not_started') { $summary.Status='observer_error' }
    $summary['Error']=$_.Exception.Message
} finally {
    try {
        if (Test-Path -LiteralPath $loaderLog) { Copy-Item -LiteralPath $loaderLog -Destination (Join-Path $folder 'UE4SS.log') -Force }
        $probe = Join-Path $probeFolder 'probe.jsonl'
        $probeAfter = $started.ToUniversalTime().AddSeconds(-1)
        if ($process) { try { $probeAfter=$process.StartTime.ToUniversalTime().AddSeconds(-1) } catch {} }
        if (Test-Path -LiteralPath $probe) {
            $events = @(Get-Content -LiteralPath $probe | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } | Where-Object { $_.session -eq $session.Id -and [DateTime]::Parse($_.utc).ToUniversalTime() -ge $probeAfter })
            $events | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $folder 'probe-events.json') -Encoding utf8
            $summary.LuaStarted = @($events | Where-Object event -eq 'lua.start').Count -gt 0
            $summary.LuaReady = @($events | Where-Object event -eq 'probe.ready').Count -gt 0
            $summary.Heartbeats = @($events | Where-Object event -eq 'heartbeat').Count
        }
        # Allow Windows Error Reporting time to publish an event after a crash.
        if ($summary.Status -eq 'exited_during_observation') { Start-Sleep -Seconds 3 }
        $crashes = @(Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=$started; Id=1000,1001,1002} -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match 'starwarsjedifallenorder.exe|SwGame-Win64-Shipping.exe' } |
            ForEach-Object { @{Utc=$_.TimeCreated.ToUniversalTime().ToString('o'); Id=$_.Id; RecordId=$_.RecordId; Message=$_.Message; Xml=$_.ToXml()} })
        $crashes | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $folder 'windows-events.json') -Encoding utf8
        $summary.CrashEvents=$crashes.Count
        if ($crashes.Count -gt 0) { $summary.Status='crash_event_observed'; $summary.CloseOutcome='no_control_by_observer' }
        elseif ($summary.ExitCode -eq '00000000') { $summary.Status='normal_exit_observed'; $summary.CloseOutcome='no_control_by_observer' }
        elseif ($summary.ExitCode) { $summary.Status='nonzero_exit_observed'; $summary.CloseOutcome='no_control_by_observer' }
        if ($manifest) {
            $changed = @($manifest.OriginalExecutables | Where-Object { (Get-FileHash -LiteralPath $_.Path).Hash -ne $_.SHA256 })
            $summary['OriginalExecutablesUnchanged']=($changed.Count -eq 0)
        }
    } catch { Record 'collection.error' $_.Exception.Message; $summary['CollectionError']=$_.Exception.Message }
    $summary['FinishedUtc']=[DateTime]::UtcNow.ToString('o')
    $summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $folder 'summary.json') -Encoding utf8
    Record 'observer.end' $summary
    $summary | ConvertTo-Json -Depth 5 | Write-Output
}
