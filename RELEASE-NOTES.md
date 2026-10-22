# 0.1 — Leitura de menus

Primeira versão experimental de FallenAccess para Star Wars Jedi: Fallen Order.

- Leitura automática de seleção e texto reais dos menus.
- Valores e estados nas configurações reconhecidas; mudanças anunciam novo valor.
- Contexto dos botões de Extras e Modo Foto.
- Ações e teclas de Editar Controles; guia atual acompanhada pela seleção real.
- Adaptadores para listas de opções e qualidade gráfica.
- Fala integrada ao jogo com Prism; SAPI como fallback.
- Consulta de janelas abertas pelo próprio jogo, caches limitados e diagnósticos de falhas.

Menu principal confirmado pelo jogador. Logs reais registram leitura de configurações e comandos. Cobertura de cada submenu e estabilidade da última correção de transições ainda precisam de teste manual. Jogabilidade ainda não está acessibilizada.

## Instalação

Extraia o pacote inteiro em uma pasta permanente. Caminho de jogo configurado: `C:\Program Files\EA Games\Jedi Fallen Order`.

Com jogo fechado, execute no PowerShell:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\New-DiagnosticSession.ps1 -Profile UI
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Invoke-DiagnosticInstall.ps1
```

Aceite solicitação de administrador do instalador. Abra jogo normalmente; fala inicia dentro do jogo. Preserve pasta extraída: ela contém manifesto e diretório de diagnósticos usados pelo mod.

Para remover, execute `Uninstall.ps1` como administrador, com jogo fechado. Ele confere hashes e remove somente arquivos próprios conhecidos. Executáveis originais e saves são preservados.

F6: anúncio de diagnóstico. F8/F9: captura incremental com confirmação falada. Não há atalhos para pausar ou repetir fala.
