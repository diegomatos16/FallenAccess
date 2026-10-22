# FallenAccess — preferências do jogador

- Responder em português, usando skill caveman já solicitada.
- Usuário realiza testes manualmente. Não iniciar/fechar jogo, enviar teclas/mouse, controlar desktop ou ativar automações de testes.
- Usuário sempre fecha jogo após terminar testes. Ao dizer "pronto" ou concluir teste, considerar jogo fechado; não perguntar novamente. Instalador mantém verificação técnica antes de escrever arquivos.
- Preparar código e instalação do mod; analisar arquivos e logs diretamente. Observador deve ser somente leitura e iniciado pelo usuário.
- Objetivo atual: expandir leitura do menu principal para demais menus, incluindo valores e estados reais. Nunca inventar lista de opções nem inferir seleção contando teclas. Cobertura de cada menu exige teste manual.
- Menu principal considerado bom pelo jogador; preservar leitura simples de foco/texto e aplicar mesma abordagem aos demais menus, evitando varreduras extensas na thread do jogo.
- Editar Comandos: não anunciar todas as guias ao abrir. Ler somente guia atual ao navegar e ação/tecla quando seleção passar aos comandos.
- Saída de fala: Prism, fallback explícito SAPI. Diagnóstico sozinho não comprova fala nem menu acessível.
- Fala deve iniciar dentro do jogo, sem serviço externo manual. Usuário pediu remover recursos e atalhos de pausar/repetir fala; não reintroduzir F7/F10.
- Ler NOTEBOOK.md antes de retomar. Configuração e falhas anteriores precisam ser consideradas; preservar executáveis originais e saves.
