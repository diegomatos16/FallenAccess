@echo off
echo Observador somente leitura. Voce abre, navega e fecha o jogo manualmente.
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Watch-DiagnosticSession.ps1" -Seconds 300 -WaitForLaunchSeconds 120
echo Coleta encerrada. Logs preservados no projeto.
pause
