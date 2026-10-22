# FallenAccess

**Versão 0.1 — Leitura de menus.** Instalação e cobertura: [notas da versão](RELEASE-NOTES.md).

Mod experimental para ler menus de Star Wars Jedi: Fallen Order. Jogador confirmou menu principal, leitura de áudio e valores; leitura de Controles chegou a Editar Controles e Vibração, mas houve lentidão e travamento. Logs mais recentes registram ações de Editar Controles com teclas; correção de fechamento e atraso ao trocar de tela aguarda teste manual. Texto e seleção vêm dos widgets reais do jogo.

Versão atual acrescenta contexto dos botões de Extras, rótulo de Modo Foto, prioridade da janela Editar Controles, nomes das ações com suas teclas/botões e mensagens de remapeamento. Rótulos vêm de referências reais de widgets conferidas no dump, sem traduções ou listas fixas. Comandos usam diretamente RemapRow.ActionName e ButtonLabel, com UI_MenuButtonPrompt_Content.KeyLabel como alternativa para a tecla exibida; a árvore visual profunda do botão não é percorrida. Não anuncia todas as guias ao abrir. Guia atual só é identificada quando CurrentRow aponta para uma das linhas TabRows do próprio jogo; seu nome é lido em ActionName. Mensagens visíveis de remapeamento continuam acompanhadas. Novos ajustes aguardam teste manual.

Listas usam GetSelectedOption do ComboBox real e texto dos elementos UI_Dropdown_Element com foco. Seletores UI_PauseMenuBtn_Selector/TagDebugParent usam campo cmbDropdown; ComboBoxRef continua como alternativa para a outra família de botões. Quando o ComboBox recebe foco Slate, uma busca específica descobre até 64 elementos; depois somente caminhos são consultados. Foco do item tem prioridade; hover único é fallback quando nenhum item tem foco. Se foco do botão pai desaparece ao abrir lista, consulta continua enquanto janela permanece visível e ComboBox tem foco. Não presume seleção por teclas ou índice. dropdown.owner/state registram componente, seleção e foco reais. F8 descobre elementos mesmo sem foco propagado ao pai. Comportamento de foco de cada lista precisa de confirmação no jogo.

## Uso

Abra jogo normalmente pelo atalho habitual. Prism carrega dentro do processo do jogo, anuncia FallenAccess carregado e recebe texto da opção selecionada. Nenhum programa, script ou serviço de fala precisa ser iniciado separadamente.

Leitura automática acompanha mudanças de seleção. Em configurações reconhecidas, anuncia nome e valor ao selecionar; mudanças seguintes anunciam apenas valor ou estado. Recursos de pausar e repetir fala e seus atalhos foram removidos. F6/F8/F9 permanecem apenas para diagnóstico manual.

## Implementação

UE4SS 3.0.1 executa Lua; fallen_speech.dll é um módulo nativo compilado com as mesmas fontes LuaRaw 5.4.4 desse carregador. A DLL carrega prism.dll por caminho absoluto e mantém uma thread própria para Prism/COM. Thread do jogo apenas entrega texto UTF-8; nenhuma síntese de fala roda nela. Leitores ativos têm prioridade; SAPI é fallback explícito. Módulo fica fixado no processo enquanto a thread existe, evitando descarregamento durante destruição dos mods. Encerramento do processo libera recursos; nenhuma desmontagem COM ocorre em DllMain.

Menu principal mantém LabelTxt.GetText e IsFocused. Leitor consulta GetFocusedButton(GetFocusGroupToAccept(), false) de cada RsUiWindow ativo, em vez de resolver e consultar todos os botões. Janelas vêm diretamente de RsUiRoot.OpenWindows a cada amostra: janelas fechadas, ainda existentes em memória, não são consultadas. Somente caminhos dos roots persistem; busca global de RsUiRoot ocorre quando nenhum root válido está disponível, com nova tentativa após três segundos. Abrir Opções não espera essa busca periódica. Menus sem foco registrado nesse sistema precisam de adaptação específica; não há varredura genérica automática como fallback.

Somente controle escolhido tem texto lido. Caminhos dos textos são reutilizados por até um segundo; textos e valores são relidos, sem guardar UObject entre frames. Rótulo único vem do contêiner da configuração. Seletores usam valor exibido; alternâncias usam IsToggled/IsChecked reais, anunciados como ativado/desativado. Não converte valores numéricos por escala presumida. Árvore de texto tem limites de profundidade e tamanho; excedê-los gera diagnóstico, sem falar rótulo parcial.

Visibilidade dos ancestrais, página ativa, janela e grupo de foco filtram controles ocultos ou inativos. Duas amostras estáveis confirmam seleção; alterações de valor são lidas a cada 100 ms. Apenas caminhos de objetos persistem entre frames. Getter com erro Lua isola aquele controle e registra falha; erro geral desativa leitor naquela execução. Classes e campos foram conferidos no dump real, mas áudio, vídeo, jogabilidade, controles, pausa e demais submenus ainda precisam de teste manual individual.

Capturas de Opções mostraram foco antigo no UI_ShellContainer mesmo com UI_GameMenu aberto. Quando UI_GameMenu está visível, no viewport e aceita entrada, leitor descarta candidatos do shell de fundo, inclusive durante transição sem seleção. Outras combinações ambíguas continuam silenciosas e registram todos os candidatos; não presume ordem de janelas pela posição de um array.

## Diagnóstico

Leitor ignora objetos marcados RF_BeginDestroyed/RF_FinishDestroyed. Ao mudar conjunto de janelas visíveis ou grupo de foco, invalida contextos e cancela captura antiga. Não há espera adicional para reconhecer a janela; somente a seleção exige duas amostras estáveis. Leituras enfileiradas resolvem os objetos atuais na game thread. Dois fechamentos recentes registraram acesso inválido em UE4SS+0x4c2b3f, UObject::ProcessEvent+0x17f, durante consulta de estado de UI_GameMenu. A mudança para OpenWindows remove consultas às janelas fechadas que a busca global antiga mantinha. Estabilidade ainda precisa de confirmação manual. Campo de tecla opcional com erro é isolado sem silenciar nome real da ação. A conversão FKey por função Unreal foi retirada; textos vêm diretamente dos widgets.

Módulo nativo observa até 16 exceções de acesso, instrução inválida e término fatal por execução. native-exceptions.log registra horário, etapa da leitura na thread, endereço e pilha; continua tratamento normal da exceção, sem tentar recuperar jogo. Uma exceção de primeira chance pode ser tratada pelo jogo e não comprova crash. Atualizações de etapa não gravam em disco; arquivo só é criado se houver exceção observada. Esse diagnóstico só é ativado junto ao mod no jogo e não controla execução ou entradas.

logs/sessions/<sessão>/probe.jsonl registra carregamento, seleção e entrega ao módulo nativo. native-speech.log registra backend, resultados Prism e textos recebidos. speech-requests.jsonl é trilha de auditoria; não é consumida por processo externo. Sucesso de uma API não substitui confirmação auditiva do jogador.

F8/F9 produzem ui-<execução>-N.jsonl com janelas e seus botões registrados. Captura avança em blocos de até dois controles, com orçamento cooperativo de 3 ms entre controles, sem gravar um log por getter. Orçamento não interrompe chamada nativa em andamento. Leitura automática continua durante captura; confirmação “Diagnóstico salvo.” ocorre ao concluir. Limite de captura: 512 controles.

performance.poll registra média/máximo das consultas em milissegundos, quantidade acima de 12 ms, número de janelas e maior etapa de captura. Relógio usa QueryPerformanceCounter; não são estimativas a partir de quantidade de chamadas. Capturas aceitam tanto tabelas retornadas por funções quanto TArray e incluem elementos de listas descobertos. Coletar-Diagnostico.cmd é observador opcional iniciado pelo jogador; não abre/fecha jogo nem envia entradas.

Crash UE4SS+0x2df805 foi localizado com PDB oficial compatível em UE4SSProgram::~UE4SSProgram: CrashDumper::~CrashDumper tenta desmontar ponteiro nulo quando EnableDumping=0. Instalador restaura padrão EnableDumping=1 e mantém FullMemoryDump=0. Não há patch no executável ou no carregador. Esta correção de configuração ainda precisa de validação de saída; não comprova a causa de qualquer fechamento anterior ao desligamento do carregador. Evidências em runtime/crash-analysis.json e runtime/CrashDumper-v3.0.1.cpp.

## Manutenção

Build-Native.ps1 compila com Zig portátil e valida ABI usando um executável isolado que não inicia thread de fala. tests/test_menu_pipeline.py reproduz capturas reais em Lua isolado para verificar mudanças, exclusão de focos ocultos, acentos e ausência dos atalhos removidos. Essas verificações não executam jogo ou leitor.

New-DiagnosticSession.ps1 prepara sessão; Invoke-DiagnosticInstall.ps1 instala com jogo fechado. deployment.json lista arquivos próprios e hashes dos executáveis originais. Uninstall.ps1, executado como administrador com jogo fechado, remove somente arquivos próprios verificados e preserva logs/saves.

Fontes e licenças: [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1), [Prism](https://github.com/ethindp/prism/releases/tag/v0.18.2), LuaRaw do mesmo release UE4SS. Licenças Prism e Lua acompanham DLLs instaladas. Detalhes e evidências em NOTEBOOK.md.

## Preparação a partir do código

Pacote da release inclui dependências binárias usadas pelo instalador. Git mantém código, testes, headers/licenças Prism, fontes LuaRaw compatíveis e configuração UE4SS; não contém logs, credenciais, ferramentas portáteis ou executáveis do jogo.

Para compilar: Zig 0.13.0 em `tools/zig/zig-windows-x86_64-0.13.0`, Prism 0.18.2 em `lib/prism/prism.dll`, UE4SS 3.0.1 e proxy oficial em `tools/ue4ss/UE4SS.dll` e `dwmapi.dll`. Execute `Build-Native.ps1`. Não substitua LuaRaw por Lua stock: ABI do carregador é modificada. Testes Python requerem Python 3 e Lupa com Lua 5.4 (`pip install lupa`). Execute `python tests/test_menu_pipeline.py`. Nenhum desses testes inicia jogo ou leitor.

`Package-Release.ps1` gera pacote em `dist/` a partir das dependências e build locais. Projeto experimental; não foi escolhida licença para o código próprio. Componentes de terceiros mantêm suas licenças.
