# RCF — Referência de Contratos e Funcionamento

## 1. Autoridade, escopo e leitura

Este documento consolida a finalidade, os contratos e as regras do projeto de download auditável de áudio de uma coletânea. A inspeção documental original corresponde ao repositório em `870a96d352d16ebe59701198703914c7eebfb875`, em 05/11/2026. A revisão de conciliação, na mesma data, corresponde ao merge `c85f47272baaa8f0dd22afcb2b3ff81585824d49`, que incorpora o upstream `c598438d2241f963d95f66017019f4f3b4d047b1` e a preservação/versionamento de `2e37a4836c1ce47f62f65629313ce805433b46aa`. Caminhos relativos citados aqui partem da pasta do script principal. A criação original teve somente este RCF como entrega; a conciliação atual atualiza os contratos afetados e verifica a integração, sem alterar o código funcional, o CSV ou os downloads.

**DEVE** indica obrigação; **NÃO DEVE** e **É PROIBIDO**, vedação; **PODE**, possibilidade condicionada. As classificações têm significados distintos:

- **[A] Atual comprovado por inspeção:** comportamento identificável no código desta revisão; não significa homologação integral ou execução bem-sucedida nesta fase.
- **[R] Requisito vigente:** obrigação normativa, inclusive quando o código ainda diverge. Uma divergência DEVE permanecer explícita e NÃO constitui exceção autorizada.
- **[F] Futuro:** recurso ou adaptação ainda não implementado/comprovado, necessário para cumprir um requisito ou permitido condicionalmente. NÃO DEVE ser apresentado como opção disponível.

As novas normas prevalecem nos conflitos expressos; as garantias anteriores compatíveis DEVEM ser preservadas. A ordem de decisão é: **fidelidade efetiva da fonte → M4A/MP3 final genuíno → mínimo de 128 kbps → preservação do áudio original → ausência de transcodificação → proximidade de 128 kbps → eficiência de armazenamento**. Identidade correta, integridade, segurança e rastreabilidade são condições obrigatórias, não critérios negociáveis de desempate.

**[R] Reconciliação:** a proibição histórica de qualquer FFmpeg/conversão e a aceitação de outros formatos finais foram substituídas pela conversão excepcional controlada e pela exclusividade final M4A/MP3. A antiga preferência por 192 kbps foi substituída pelo alvo de 128 kbps, sempre respeitando o piso e a fidelidade. O fluxo interativo existente DEVE continuar disponível como opção explícita; sua presença atual NÃO satisfaz a nova obrigação de autonomia ordinária. PowerShell 5.1 NÃO é requisito do principal atual: a base vigente é PowerShell 7+.

## 2. Finalidade, arquitetura e limites reais

**[R]** O processamento DEVE percorrer o CSV na ordem recebida, identificar vídeos com segurança e produzir **no máximo um resultado final válido por ID de vídeo**, compartilhado entre referências compatíveis. Um vídeo admissível concluído DEVE ter exatamente um resultado final; buscas, fontes de trabalho, tentativas e arquivos preservados NÃO são resultados finais. Falta de identificação ou procedência DEVE gerar pendência, sem fabricação de sucesso.

| Componente existente | Responsabilidade comprovada [A] |
| --- | --- |
| `baixar_audios_ytdlp.ps1` | Orquestração sequencial; validação de URLs/identidade; busca e cache; formatos; download; análise técnica; publicação; estado e relatórios. Exige PS 7.0+. |
| `ambiente_portatil.ps1` | Raiz física do script, resolução de caminhos e descoberta/importação canônica do CSV. |
| `ferramentas_portateis.ps1` | Descoberta dos executáveis e execução de comandos de versão antes dos efeitos do lote. |
| `execucao_unica.ps1` | Escolha e três confirmações no modo explícito; validação de aprovação musical atual/persistida com identidade exata. O helper histórico de caminho JSON não é chamado. |
| `evidencias_fonte.ps1` | Descoberta local, leitura e vinculação de manifestos de procedência a documentos locais e hashes; reúne duplicatas idênticas entre manifestos e exclui chaves conflitantes. |
| `autenticacao_ytdlp.ps1` | Argumentos de sessão explicitamente fornecida por cookies Netscape ou navegador suportado. |
| `publicacao_pendente.ps1` | JSON preservando strings/tipos; intenção imutável, referência durável, validação e reconciliação integradas ao produtor e à inicialização. Evidência de journal isolada não autoriza efeitos. |
| `referencia_publicacao.ps1` | Referência canônica com ID sensível a maiúsculas/minúsculas e nome SHA-256; usada no checkpoint antes do movimento e na recuperação automática. |
| `editorial_audio.ps1` | Normalização/decisão do marcador, leitura e preservação de tags/payload, candidato MP3 e verificação técnica antes da publicação; carregado para marcador não vazio ou metatags habilitadas. |
| `nomeacao_editorial.ps1` | Componentes musicais, espaços, faixa ASCII e padding explícito; preserva grafias. Carregado somente no modo Musical. |
| `mapeamento_nomeacao.ps1` | Mapeamento explícito de colunas do CSV, busca literal Ordinal e retorno ao legado quando insuficiente. Carregado somente no modo Musical. |
| `coletanea_uber_instrumental_candidatas.csv` | Entrada canônica existente: 372 linhas, 370 buscas e dois vídeos diretos; sugestões NÃO são auditoria musical. |
| `evidencias.exemplo.json` | Modelo com valores fictícios; NÃO é evidência utilizável. |
| `ferramentas.json` | Registro de fornecedor, versão FFmpeg e hashes de três executáveis; NÃO é um instalador nem uma verificação automática de confiança. |
| `tests/*.tests.ps1` | Roteiros de verificação, incluindo integração Linux, descoberta nativa, ordenação, evidências, aprovação musical e preflight. Cobertura parametrizada é distinguida de execução por sistema. |

**[A]** Não há serviço, banco de dados externo, interface web, gerenciador de filas nem instalação automática de dependências. A execução usa PowerShell/.NET e processos externos. Os sete helpers são parte obrigatória da distribuição; “autossuficiente” NÃO significa que o principal isolado contenha tudo.

**[A] Fluxo real:** carregar helpers → descobrir/testar ferramentas e Node opcional → validar autenticação explícita → localizar/importar CSV e validar cabeçalhos → importar aprovações e evidências → criar controle/adquirir lock → carregar/criar estado → reconciliar referências pendentes → auditar legado com proteção das pendências → validar/processar linhas na ordem → identificar/reutilizar/buscar → obter metadados e exigir aprovação musical → tentar formatos/validar procedência → preservar/remuxar/converter excepcionalmente → validar resultado → persistir intenção e referência antes do movimento → publicar/reconciliar e persistir resultados/relatórios → liberar lock.

**[R]** Uma única invocação DEVE executar todo o processamento possível, descobrir caminhos/dependências, diagnosticar obstáculos e aplicar alternativas legítimas sem confirmações ordinárias nem etapas manuais obrigatórias entre busca e publicação. Autonomia NÃO dispensa pré-requisitos reais, credenciais autorizadas ou prova de procedência: quando ausentes, DEVE registrar a causa e continuar o lote. É PROIBIDO escolher uma música ambígua ou fabricar evidência para evitar pendência.

**[A]** O padrão não solicita entradas do usuário. -Interativo habilita escolhas, confirmações e recuperação interativa de sessão; -NaoInterativo permanece compatível. Informar ambos como verdadeiros é erro global antes dos efeitos do lote. Esse modo de operação não fornece dados ausentes, não comprova requisitos musicais e não garante todos os downloads nem acesso a terceiros.

## 3. Ambiente, distribuição e invocação

### 3.1 Dependências e portabilidade

**[R]** PowerShell `.ps1` DEVE continuar sendo a linguagem principal, com PS 7+ e Windows prioritário. Recursos nativos PowerShell/.NET DEVEM ser priorizados. Dependências externas DEVEM ter necessidade técnica documentada; soluções mantidas e reutilizáveis DEVEM preceder novos mecanismos próprios. NÃO DEVE haver dependência de Chrome ou de outro navegador específico.

**[A]** No Windows, `yt-dlp.exe` é obrigatório junto do principal e recebe `--ignore-config --no-plugin-dirs --version` no preflight. FFmpeg e ffprobe são obrigatórios para validação integral e conversão excepcional; procuram-se primeiro `ffmpeg.exe`/`ffprobe.exe` adjacentes, depois aplicações no PATH. Fora do Windows, esses dois usam nomes sem `.exe`. Node.js é opcional, adjacente ou no PATH, testado antes de passar `--js-runtimes node:CAMINHO`; ausência/falha gera aviso, sem promessa de formatos equivalentes.

**[A/R] Descoberta nativa:** Windows preserva exclusivamente yt-dlp.exe adjacente. Linux X64 procura yt-dlp_linux e depois yt-dlp adjacentes; Arm64 procura yt-dlp_linux_aarch64 e depois yt-dlp. macOS procura yt-dlp_macos e depois yt-dlp. Outras arquiteturas/sistemas usam yt-dlp adjacente; nos ramos não Windows, só depois procura aplicação yt-dlp no PATH. Não escolhe yt-dlp.exe como alternativa Unix. Os nomes seguem a distribuição oficial: https://github.com/yt-dlp/yt-dlp#release-files. O genérico pode exigir Python; não instala dependências. O primeiro caminho encontrado passa pelo preflight real de versão, que informa falha de arquitetura/permissões/dependências; arquivo incompatível não é silenciosamente substituído. PE permanece rejeitado fora do Windows. Testes parametrizados de descoberta não equivalem a executar binários em Linux/macOS.

**[A]** As três ferramentas obrigatórias são testadas com timeout de 15 s antes de criar destino/estado ou migrar legado; incompatibilidade informa sistema, arquitetura e caminho. O script NÃO baixa nem instala executáveis. `ferramentas.json` registra FFmpeg/ffprobe `9.0.2-essentials_build-www.gyan.dev`, fornecedor `https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip` e referência `https://ffmpeg.org/download.html`. O README registra yt-dlp `2026.10.26`. Essas versões são retrato da distribuição, NÃO promessa de compatibilidade futura, nem exigência de atualização automática.

**[A/R] Versionamento:** o CSV canônico e `yt-dlp.exe` permanecem no Git convencional; `ffmpeg.exe` e `ffprobe.exe` são versionados por Git LFS, com regras específicas em `.gitattributes` e hashes no manifesto. A reprodução exige os objetos LFS completos; ponteiros isolados NÃO são executáveis. O `.gitignore` exclui somente `/destino/` e `/tests/.runtime-*/`, preservando referências e evidências revisadas fora dessas árvores. É PROIBIDO substituir binários testados ou ocultar fontes/CSV/evidências úteis por exclusões genéricas sem justificativa e validação.

**[R] Preparação:** instalar PS7+, distribuir principal/helpers e ferramentas compatíveis, assegurar escrita no destino e entradas/credenciais realmente necessárias. O preflight de ferramentas e a validação global do CSV, aprovações e evidências explícitas antecedem criação do controle, lock e auditoria do legado. Erros individuais continuam isolados por linha. Carregamento/integridade do estado e falhas posteriores do filesystem ainda podem impedir execução após adquirir lock: não se promete ausência absoluta de efeitos para toda falha possível.

### 3.2 Parâmetros implementados [A]

| Parâmetro | Contrato atual |
| --- | --- |
| `-Csv` | String opcional, posição 0. Caminho absoluto ou relativo à raiz do script. Ausente: descobrir um único CSV elegível adjacente. |
| `-AprovacoesCsv` | CSV de confirmações prévias por `Ordem`, relativo à raiz ou absoluto. Não substitui evidência técnica. |
| `-EvidenciasJson` | Manifesto JSON explícito opcional, relativo à raiz ou absoluto; quando informado substitui a descoberta automática. Documentos relativos também partem da raiz do script, não da pasta do manifesto. |
| `-CookiesArquivo` | Arquivo Netscape explícito, relativo à raiz ou absoluto; mutuamente exclusivo com `-CookiesNavegador`. |
| `-CookiesNavegador` | Descritor explícito de sessão; não é pré-requisito padrão. |
| `-Interativo` | Opção explícita para escolhas, três confirmações e recuperação de sessão. Ausente: sem perguntas. Incompatível com -NaoInterativo quando ambos verdadeiros. |
| `-NaoInterativo` | Mantido por compatibilidade; ausência de -Interativo já impede perguntas. Evidência descoberta normalmente; dados insuficientes permanecem pendentes. |
| `-SomenteAuditarExistentes` | Auditoria local sem consultas remotas; ainda exige/testa ferramentas e PODE preservar/mover legado, atualizar estado e relatórios. Não é modo somente leitura. |
| `-ReavaliarPendentes` | Ignora cache de buscas e permite reconsulta pertinente; não aprova candidatos nem relaxa qualidade. |
| `-ResultadosPorBusca` | Inteiro de 3 a 12; padrão 7. Limita candidatos consultados, não garante identificação. |
| `-MaxTentativas` | Inteiro de 1 a 4; padrão 2. Limita chamadas externas por operação no wrapper; não é o total de pedidos HTTP internos do yt-dlp. |
| `-Destino` | Raiz de saída opcional; relativa à raiz do script ou absoluta. Controle acompanha a raiz. Padrão destino/. |
| `-Marcador` | Texto opcional. Vazio equivale a ausente. Novos MP3: campo adicional verificado. Reuso: confirmar igual ou registrar limitação sem alterar arquivo; ver 7.3. |
| `-ModeloNome` | `Legado` (padrão) ou `Musical`; não renomeia arquivos válidos já publicados. |
| `-LarguraTrack` | Opcional, 1..145; largura mínima de zeros somente quando explícita, sem truncar números maiores. Valor inválido falha antes dos efeitos. |
| `-ColunaAutor` | Coluna declarada de autor/compositor no CSV canônico; opcional, sem inferência a partir de `Artista`. |
| `-ColunaTrack` | Coluna declarada de faixa no CSV canônico; opcional, sem inferência a partir de `Ordem`. |
| `-ColunaTitulo` | Coluna declarada de título musical no CSV canônico. Insuficiência no modo Musical mantém o nome legado e registra pendência editorial. |

**[A]** Destino, marcador, modelo de nome e largura de faixa estão implementados nos limites acima. Metatags editoriais gerais possuem parâmetros opcionais e suporte delimitado a novos MP3, conforme 7.2; capitalização configurável e capa continuam sem parâmetros implementados. **[R/F]** Caminhos, nomes e organização DEVEM tornar-se configuráveis por parâmetros, mantendo os padrões atuais quando não sobrescritos. As opções futuras especificadas na seção 7 NÃO DEVEM constar de exemplos executáveis da versão atual.

### 3.3 Exemplos utilizáveis com a interface atual

```powershell
# Na pasta da distribuição: descobre o único CSV válido, sem perguntas.
pwsh -NoProfile -File ./baixar_audios_ytdlp.ps1 -NaoInterativo

# Entrada real do projeto; pendências não equivalem a sucesso.
pwsh -NoProfile -File ./baixar_audios_ytdlp.ps1 -Csv coletanea_uber_instrumental_candidatas.csv -NaoInterativo

# Somente auditoria local: pode preservar legado e gravar controle.
pwsh -NoProfile -File ./baixar_audios_ytdlp.ps1 -Csv coletanea_uber_instrumental_candidatas.csv -SomenteAuditarExistentes -NaoInterativo

# Modelo operacional: exige arquivos reais já preparados; não copiar placeholders como prova.
pwsh -NoProfile -File ./baixar_audios_ytdlp.ps1 -Csv coletanea_uber_instrumental_candidatas.csv -AprovacoesCsv aprovacoes.csv -EvidenciasJson evidencias.json -NaoInterativo

# Sessão opcional por arquivo; nenhuma instalação de navegador é exigida por esta opção.
pwsh -NoProfile -File ./baixar_audios_ytdlp.ps1 -Csv coletanea_uber_instrumental_candidatas.csv -CookiesArquivo 'C:\dados\youtube-cookies.txt' -NaoInterativo
```

**[R]** A política de execução DEVE ser respeitada no ambiente. Quando necessária e permitida, `-ExecutionPolicy Bypass` PODE ser usado somente no processo invocado, sem alterar a política persistente. Exemplos demonstram sintaxe e entradas existentes/modelos declarados; NÃO certificam acesso remoto ou procedência.

## 4. Entrada, identidade e seleção

**[A/R] CSV:** UTF-8 com ou sem BOM, delimitador vírgula, ponto e vírgula ou tabulação e cabeçalhos entre aspas são tratados pelo mesmo leitor na descoberta/importação. São obrigatórios `Ordem`, `Artista`, `Musica`, `Link_YouTube`, `Tipo_link`, `Verificacao`, `Observacoes`; `Estilo_sugerido` existe no CSV e NÃO é comprovação musical nem álbum. Na descoberta, zero ou vários CSVs com cabeçalho válido geram diagnóstico, sem escolha arbitrária. O CSV DEVE permanecer intacto e ser a fonte canônica de URLs/consultas. O diretório corrente NÃO DEVE alterar essa escolha.

**[A]** `Ordem` aceita dígitos; repetição textual da ordem é rejeitada por linha. Artista, música e URL são obrigatórios; artista/música têm máximo de 180 caracteres cada. `Tipo_link` DEVE conter indicação coerente de busca ou direto. Ordem inválida/duplicada ou campos inválidos geram `falha` isolada. **[R]** A ordem do CSV DEVE ser preservada; NÃO se DEVE presumir que `Ordem` é número de faixa de álbum. A unicidade numérica equivalente de ordens com zeros distintos NÃO está comprovada no validador atual.

**[A/R] URLs:** HTTPS, sem credenciais nem porta alternativa, nos hosts `www.youtube.com`, `youtube.com`, `m.youtube.com`, `music.youtube.com`, `youtu.be`. Vídeos aceitos: `/watch?v=ID`, encurtado, `/shorts/ID`, `/live/ID`; ID com 11 caracteres alfanuméricos, `_` ou `-`. Pesquisas: `/results?search_query=...`, termo de 3 a 220 caracteres, sem controles. Parâmetros de consulta duplicados são rejeitados. Pesquisa válida NÃO comprova vídeo identificado/disponível. Não se DEVE trocar uma URL direta por outro ID aprovado.

**[A]** Consultas exigem correspondência de artista/música com o termo fornecido. Normalização interna remove acentos, converte para minúsculas e compara palavras; NÃO altera a grafia exibida. Candidatos precisam de título coerente com música e título/canal/uploader coerente com artista. Termos de versões divergentes, covers, tributos, karaokê, remix, live etc. são filtrados quando não pertencem aos próprios nomes. Pontuação ordena candidatos e ID desempata; pontuação NÃO é aprovação. A seleção automática só ocorre com um único candidato de título exato dentre os padrões aceitos e canal igual ao artista ou `Artista - Topic`, seguida de confirmação pelos metadados completos. ID divergente, live ativo e JSON inválido são rejeitados.

**[A/R]** Identity-Matches confronta música/título/track e artista/título/channel/uploader/artist; texto não comprova gravação, versão nem ausência de vocais. URL direta mantém seu ID literal, incluindo caixa. Antes de novos downloads ou reutilização, exige-se aprovação explícita das três confirmações ou registro persistido válido para o mesmo ID, artista e música. Metadados sozinhos não liberam o item. Falta de aprovação gera pendente_auditoria; legado sem registro musical é preservado, sem aprovação fabricada. Conferência humana real e verdade externa permanecem requisitos, não certificações automáticas.

**[A] Aprovações:** cabeçalho `Ordem,VideoId,ArtistaMusicaConferidos,VersaoConferida,SemVocaisConferido`; vírgula/UTF-8 no importador próprio. Ordem repetida no arquivo é erro global. Cada confirmação aceita `SIM`, `S`, `TRUE` ou `1`, sem distinguir caixa e após trim; o fluxo interativo pede três `SIM`. Ambiguidade pode solicitar índice a partir de zero ou ID presente nos candidatos; há até três entradas de escolha. Confirmação ausente/inválida permanece pendente. **[R]** Aprovação humana DEVE corresponder a conferência real, não preenchimento automático; NÃO substitui verificação técnica/procedência. Sugestão de primeiro candidato no relatório NÃO é seleção aprovada.

## 5. Qualidade, formatos e publicação

### 5.1 Barreiras obrigatórias

**[R]** Somente `.m4a` e `.mp3` genuínos PODEM ser finais. M4A DEVE ter contêiner MP4/MOV compatível e AAC ou ALAC; MP3 DEVE ter contêiner e codec MP3. Trocar extensão NÃO converte um formato. Fontes temporárias em outros formatos PODEM existir somente fora dos finais. É PROIBIDO baixar vídeo audiovisual como alternativa ordinária a uma faixa de áudio.

**[R]** Fontes com perdas comprovadamente inferiores a 128 kbps, declaradas ou medidas, e resultados finais medidos inferiores a 128 kbps são inadmissíveis. `kbps` significa 1.000 bits/s. O alvo é 128 kbps, nunca arredondar 127,x para aprovação. Bitrate superior só se justifica por preservação do original/fidelidade, ausência de alternativa adequada ou necessidade técnica do resultado. Um nativo válido de 192/256 kbps NÃO DEVE ser recodificado apenas para reduzir tamanho.

**[R]** Codec sem perdas e bitrate nominal alto NÃO comprovam fidelidade histórica. Fonte de 92/96 kbps recodificada a 128/192/320 kbps ou reempacotada sem perdas DEVE ser rejeitada. É PROIBIDO elevar bitrate, preencher com padding, alterar cabeçalhos ou inventar procedência para simular qualidade. Ausência de prova DEVE gerar `pendente_qualidade`; NÃO prova que o som é ruim nem permite concluir que é adequado. Equivalência perceptual entre codecs e ausência de transcodificações anteriores NÃO são inferíveis apenas de bitrate, espectrograma ou metadados.

### 5.2 Descoberta, ordem e tratamento atuais [A]

`Get-Formats` aceita apenas formatos anunciados como áudio sem vídeo, codec presente e ID literal `[A-Za-z0-9_-]{1,45}`. Fontes conhecidas: m4a, mp3, webm, opus, ogg, oga, aac, flac, wav, mp4, mka. Codec anunciado sem perdas é tratado separadamente; áudio com perdas com `abr` ou, na ausência, `tbr` positivo inferior a 128 é filtrado antes de baixar. Bitrate desconhecido exige medição, não aprovação.

1. Nativos M4A AAC/ALAC e MP3 precedem todos os outros formatos.
2. Dentro da classe, menor distância anunciada acima de 128 precede valores maiores; desconhecidos vêm depois dos conhecidos e sem perdas conserva distância zero. Empates usam o ID literal em ordem ordinal, incluindo caixa, independentemente da cultura. A mesma função ordena a fila inicial e a atualizada; IDs de tentativa também distinguem caixa.
3. Formatos com codec compatível AAC/ALAC/MP3 em outro contêiner precedem transcodificação e usam `-c:a copy` quando admissíveis.
4. Demais fontes admissíveis usam excepcionalmente AAC em M4A. Tentativas finitas em 128, 136 e 160 kbps saem sempre da mesma fonte original; resultados reprovados são descartados do trabalho, sem recodificação em cascata.

**[R]** Todas as alternativas nativas tecnicamente pertinentes DEVEM ser esgotadas antes de converter. A medição real e a prova de origem DEVEM prevalecer sobre a ordem baseada em metadados. Empates DEVEM usar o ID literal em ordem ordinal, incluindo caixa; fila inicial e atualizada DEVEM compartilhar essa política. O código tenta a fila finita sem o antigo corte de quatro formatos, mas certas falhas de assinatura/tamanho ou acesso encerram o item: não se DEVE declarar recuperação por todos os formatos em toda causa possível.

### 5.3 Validação técnica e limites atuais [A/R]

- `Verify-Signature` exige tamanho mínimo de 2.048 bytes e assinatura compatível com a extensão fonte. Quando tamanho da origem é informado, arquivo abaixo de 97% é rejeitado; tamanho suficiente NÃO dispensa as outras verificações.
- `Probe-Audio` usa ffprobe com protocolo local `file`, exige **exatamente um stream de áudio e nenhum outro stream**, soma tamanhos/durações positivos de pacotes e calcula `8 × soma(bytes) / soma(segundos) / 1000`. Bitrate do contêiner NÃO substitui bitrate do áudio.
- Registra codec, contêiner, bitrate nominal do stream, média medida, duração, canais, amostragem, classe sem perdas e variação entre pacotes. Variação de pacotes NÃO DEVE ser declarada prova autossuficiente de VBR; bitrate médio NÃO demonstra fidelidade perceptual.
- FFmpeg executa decodificação completa com erro fatal em falhas. Codec/contêiner/extensão incompatíveis, pacotes sem duração/tamanho mensuráveis, duração inválida e corrupção são rejeitados.
- Duração fonte versus metadados, quando conhecida, tolera no máximo `max(0,5 s; 1%)`; resultado versus fonte tolera `max(0,25 s; 0,5%)`. Resultado DEVE preservar canais e taxa de amostragem. Essas tolerâncias NÃO autorizam corte intencional.
- Final DEVE passar a compatibilidade M4A/MP3 e média medida ≥128, inclusive ALAC sem perdas; silêncio muito comprimível NÃO autoriza padding para satisfazer o piso.
- A fonte é medida e vinculada à evidência **antes** de qualquer conversão. Só após todas as barreiras o arquivo é movido ao destino final. Colisão preserva o arquivo existente e reprova a publicação, sem sobrescrever.

**[A]** Nativo admissível é movido byte a byte; conversão/remux preserva a fonte excepcional no controle. O comando atual desativa metadados, fixups, thumbnails e outros pós-processamentos do yt-dlp; conversão usa `-map_metadata -1`. Nomes e auditoria NÃO significam metatags incorporadas.

### 5.4 Contrato de evidência de origem

**[A]** Na inicialização, sem `-EvidenciasJson`, o programa descobre JSONs somente na raiz do script e em `destino/.controle/`, sem recursão nem dependência do cwd. Ignora `*.exemplo.json` e documentos sem os campos candidatos `video_id`, `formato_id` e `sha256`; JSON ilegível gera aviso. Cada manifesto candidato passa pelo importador completo: rejeição gera aviso e permite continuar com os demais. Duplicatas idênticas entre manifestos são reunidas; divergência para a mesma chave exclui essa chave de toda a união. Descoberta NÃO constitui aprovação nem prova de procedência. Com `-EvidenciasJson`, somente o manifesto explícito é importado; erro nesse arquivo pode impedir a inicialização.

**[A/R]** Não há pergunta de caminho JSON durante a validação da fonte. Evidência ausente/rejeitada mantém a fonte no controle, registra `pendente_qualidade` e continua o lote; não há fabricação de documento nem relaxamento do piso. A descoberta ocorre na inicialização, sem promessa de recarregamento durante o lote. O importador aceita uma coleção JSON; cada entrada DEVE conter:

| Campo | Contrato |
| --- | --- |
| `video_id`, `formato_id` | ID de vídeo válido e ID literal do formato; mesmos limites usados na seleção. |
| `sha256` | 64 dígitos hexadecimais; hash dos bytes efetivos da fonte baixada. |
| `origem`, `historico` | Referência auditável e cadeia de geração/compressão; validador exige comprimentos mínimos 15 e 20 caracteres, respectivamente. Comprimento NÃO atesta veracidade. |
| `qualidade` | `perdas_verificadas` ou `sem_perdas_verificada`. |
| `bitrate_minimo_historico_kbps` | Menor bitrate de qualquer estágio com perdas. **[R]** DEVE ser numérico, não negativo; zero só para cadeia integralmente sem perdas documentada. Campo ausente, negativo, insuficiente ou contraditório NÃO DEVE produzir conformidade. |
| `documento`, `documento_sha256` | Arquivo local real e seu SHA-256; caminho relativo à raiz do script ou absoluto. |

**[A]** Documento ausente/hash divergente e entradas duplicadas são rejeitados; chave de associação é video_id|formato_id|sha256. O importador exige mínimo histórico presente, JSON numérico real, finito e não negativo: rejeita strings, booleanos, objetos, arrays, nulo e coerção implícita. Histórico positivo inferior a 128 é rejeitado inclusive para codec sem perdas; perdas_verificadas exige pelo menos 128; zero é admitido apenas com sem_perdas_verificada. A verificação posterior continua exigindo codec real sem perdas para esse valor de qualidade e vinculando bytes/documento. Esquema válido não certifica a verdade externa do histórico.

**[R]** Evidência DEVE demonstrar a cadeia histórica efetiva e corresponder aos bytes analisados; um documento escrito a partir apenas do bitrate anunciado NÃO é prova. Verificação de hash demonstra vinculação e integridade, NÃO autenticidade intelectual, autoria ou verdade do histórico. O sistema NÃO dispõe de certificação automática universal dessa verdade; inconsistência DEVE resultar em pendência/rejeição, nunca declaração inventada. O modelo JSON contém placeholders deliberadamente inválidos.

## 6. Persistência, resiliência, segurança e saídas

### 6.1 Layout, identidade persistente e recuperação

**[A]** Raiz é a localização física do script, com tentativa de resolver link simbólico. Entradas relativas são canônicas em relação a ela. Destino padrão é `destino/`; `-Destino` permite outra raiz absoluta ou relativa à pasta do script, com `.controle/` associado. Sem a opção, os caminhos permanecem:

| Caminho | Uso |
| --- | --- |
| `estado.json` | `versao=1`, mapas `registros`, `videos`, `buscas`, `publicacoes_pendentes`; pode incluir `arquivos_preservados`. |
| `execucao.lock` | Abertura exclusiva `FileShare.None`; arquivo não é apagado ao liberar para evitar corrida. |
| `fontes/VIDEO/FORMATO.ext` | Downloads fonte e parciais; resultados intermediários ficam no mesmo controle, nunca contam como finais. |
| `cache/` | Cache local do yt-dlp. |
| `legado/` | Bytes de antigos resultados sem política válida, associados a hash/histórico. |
| `nao_rastreados/` | Áudios encontrados sem estado de conformidade; preservação com nome interno único e nome original/hash registrados. |
| `relatorio.csv`, `pendencias.csv` | Situação das linhas do CSV desta execução; não são substitutos do estado histórico. |
| `sugestoes_aprovacao.csv`, `aprovacoes_modelo.csv` | Sugestões regeneradas sem atestações e modelo de aprovação. |

**[A/R]** Chave de registro é SHA-256 de `Ordem`, artista, música e URL, separados por U+001F; vídeos são deduplicados por ID e buscas por hash de consulta/artista/música. Mesmo ID para artista/música divergentes gera conflito. Reuso exige política `fidelidade-128-v1`, auditoria válida, nome sem percurso de diretório, tamanho, assinatura, SHA-256 e nova validação técnica final. Estado de sucesso sem arquivo íntegro vira pendência, não novo download cego. Alterações de CSV NÃO DEVEM apagar o histórico; relatórios DEVEM refletir a entrada corrente.

**[A]** Estado é serializado sem truncamento permitido, escrito em temporário exclusivo com flush e substituído com backup temporário não nulo. A limpeza só remove o temporário criado pela própria chamada; colisão com arquivo preexistente o preserva. O leitor JSON conserva strings (inclusive títulos em formato ISO), tipos e arrays; recusa chaves exatamente duplicadas. Cada finalização salva estado. Migração de legado registra intenção antes do movimento; preserva bytes e reclassifica sucessos antigos como `pendente_qualidade`. Áudios sem estado e sem proteção de publicação são isolados, não certificados. GUID em nomes internos NÃO é convenção de nome final determinístico.

**[R/A]** Retomada DEVE conservar downloads válidos e parciais aproveitáveis, impedir duplicação e manter auditoria. O produtor atual grava intenção imutável e referência/hash no estado em disco antes do movimento sem sobrescrita; valida novamente identidade, aprovação, evidência e áudio, salva resultado mantendo a referência e só então a remove com nova gravação. A inicialização reconcilia referências antes da auditoria de legado; falhas permanecem `pendente_auditoria` e não repetem formatos/download do item na mesma execução. Auditoria protege destinos vinculados e conserva todos os arquivos quando a referência não permite identificar o destino; `-SomenteAuditarExistentes` não publica. O journal permanece em `publicacoes_pendentes/`; não é autorização autônoma. Essa sequência não é uma transação única nem comprova todas as janelas de crash/falha de armazenamento. Movimentos, hashes e estado DEVEM permitir reconciliar interrupções sem descartar órfãos nem chamá-los de concluídos. É PROIBIDO apagar lock/estado como procedimento ordinário de recuperação.

### 6.2 Retentativas, falhas e autenticação

**[A]** Processos usam `ProcessStartInfo.ArgumentList`, sem shell, com stdout/stderr UTF-8 e timeout. Download usa ID literal de formato, áudio sem vídeo, downloader nativo, `--no-overwrites --continue --part`, sem extrair áudio por pós-processamento do yt-dlp. Há retentativas internas limitadas do yt-dlp (até dois retries configurados) e o wrapper de 1–4 tentativas com espera `min(20 s; 2^tentativa × 3 s)` somente em causas transitórias. Timeouts: metadados/busca 105 s, download 1.800 s, ffprobe 180 s, decodificação 300 s, remux/conversão 600 s.

**[A/R]** Diagnósticos distinguem removido/privado/indisponível, restrição geográfica, DPAPI, anti-bot/login, HTTP 429/5xx/403, DNS/rede/timeout, formato ausente, metadados inconsistentes, erro local e falha não classificada. Privado é classificado como indisponível pelo código atual; NÃO se DEVE prometer acesso com sessão. Formato indisponível/403 após metadados permite uma atualização de metadados por vídeo e novas alternativas; IDs já tentados não se repetem. Fila é reordenada para manter nativos antes da conversão. Falhas individuais são capturadas e registradas; falhas globais de inicialização/integridade PODEM encerrar o processo.

**[A]** Conteúdo público é tentado anonimamente. Sem parâmetros não há leitura de perfil/cookies/navegador. `-CookiesArquivo` valida existência e primeira linha Netscape/HTTP Cookie File; isso NÃO comprova validade da sessão. `-CookiesNavegador` aceita brave, chrome, chromium, edge, firefox, opera, vivaldi, whale e perfil não vazio quando informado. Ambos juntos são erro. Sessão só é utilizada quando explicitamente fornecida/escolhida; credenciais NÃO DEVEM ser expostas em chats, relatórios ou logs.

**[A]** Em modo interativo, falha de login/anti-bot/DPAPI pode solicitar sessão com `arquivo:CAMINHO` ou `navegador:NOME`; até três entradas inválidas e uma recuperação global de autenticação, na mesma chamada. Vazio cancela. `-NaoInterativo` não solicita nem descobre sessão automaticamente. Bloqueio persistente suspende consultas; três ocorrências de 429 sem sucesso intermediário também podem suspender a rede. Linhas seguintes continuam sendo classificadas, sem insistência remota inútil. **[R]** Essa suspensão DEVE preservar verificações/reuso locais pertinentes; NÃO autoriza contornar controles ou garantir acesso universal.

**[R]** Alternativas DEVEM ser causais, finitas e registradas. É PROIBIDO repetir indefinidamente uma tentativa, esconder erros, escolher estratégia já demonstrada inútil ou impor paralelismo agressivo. Entradas são não confiáveis: NÃO DEVEM virar comandos, expressões de formato, caminhos de fuga ou sobrescritas. Relatórios atuais prefixam células com risco de fórmula com apóstrofo; esse escape NÃO altera o CSV fonte.

### 6.3 Resultado observável

| Estado atual | Significado contratual |
| --- | --- |
| `baixado` | Publicado após as barreiras técnicas/procedência implementadas; NÃO prova automaticamente versão/ausência de vocais nem verdade externa do documento. |
| `existente` | Arquivo previamente auditado foi revalidado e reutilizado sem download. |
| `nao_identificado` | Consulta/candidatos/metadados não estabelecem identidade suficiente. |
| `indisponivel` | Causa classificada impede disponibilidade, inclusive remoção/restrição pertinente. |
| `pendente_auditoria` | Falta decisão confiável de identidade/versão/vocais ou aprovação completa. |
| `pendente_acesso` | Acesso/rede/limitação pendente ou rede suspensa. |
| `pendente_qualidade` | Fonte, histórico ou resultado sem conformidade demonstrada. |
| `falha` | Entrada inválida, conflito ou erro não recuperado; motivo específico é obrigatório. |

**[R]** Somente `baixado`/`existente` com todas as condições de aceite satisfeitas PODEM contar como concluídos conformes; nomes de estado atuais NÃO dispensam as lacunas declaradas neste RCF. O lote DEVE terminar com progresso/resumo objetivo e motivos por entrada. Código de saída atual é 2 para erro fatal de inicialização/integridade; pendências/falhas de itens NÃO implicam por si código diferente de zero. **Exit 0 NÃO significa 372 downloads nem conformidade integral.**

**[A]** O relatório contém ordem, artista, música, URL/tipo/verificação/observações originais, ID/URL/título resolvidos, auditoria e rejeições JSON, critério de seleção, formato, codec, bitrate, arquivo, tentativas totais/de download, resultado, motivo, candidatos e UTC. Estado retém origem/hash/codec/contêiner/medições, evidência, conversão, validação e rejeições por formato. Contadores de tentativas são de chamadas do wrapper, não de pacotes HTTP. `pendencias.csv` inclui todos os não concluídos e até três URLs sugeridas. Com zero pendências ele é removido; não há garantia atual de limpeza de todas as sugestões antigas em todo cenário. Sugestões DEVEM ser copiadas antes de editar, pois são regeneradas; confirmações NÃO são preenchidas automaticamente.

## 7. Identificação editorial, nomes, metatags, capa e marcador

### 7.1 Dados confiáveis e nomeação

**[A]** Nome padrão (legado): `Ordem - Artista - Musica [ID].ext`, com trim dos campos; substitui caracteres Windows proibidos/controles por `_`, compacta espaços, remove espaço/ponto finais, trata nomes reservados e trunca preservando `[ID]`. Comprimento-base máximo é `min(145; 237 − comprimento(destino))`; margem menor que 38 impede escrita segura. A capitalização recebida é preservada; não há title case nem zero-padding no modelo legado.

**[R]** Artista/intérprete e autor/compositor NÃO DEVEM ser confundidos. `Artista` só preenche autor quando a equivalência estiver documentada; título completo do vídeo NÃO é necessariamente título musical. Título musical/track da origem, CSV conferido, álbum e número de faixa DEVEM ter proveniência e significado explícitos. Conflitos DEVEM manter o valor original e registrar pendência editorial, sem invenção. Ausência de álbum NÃO autoriza copiar título do vídeo ou `Estilo_sugerido` para esse campo.

**[R]** A nomeação musical preferencial DEVE seguir `{Autor}{Track}{Titulo}.{ext}`, com campos ausentes omitidos e separador ` - ` apenas entre campos presentes. Autor confiável, faixa numérica e título musical DEVERÃO vir de mapeamento explícito; sem identificação suficiente, DEVE usar o padrão atual. O ID DEVE permanecer como sufixo estável de desambiguação, compatível com a convenção existente. Não se DEVE renomear arquivos válidos já publicados silenciosamente.

**[A] Destino implementado:** `-Destino` substitui a raiz de saída; relativo parte da raiz do script e controle acompanha o destino. Sem opção, mantém `destino/`. Verificação Windows/PS7: padrão, relativo e absoluto, dois cwd, estado/relatórios/lock associados, CSV canônico e saída padrão existente preservados.

**[R] Requisitos das interfaces de nomeação:** `-ModeloNome` DEVE permitir manter o legado ou selecionar a convenção musical acima, preservando o legado quando não sobrescrito. `-LarguraTrack` PODE fixar uma largura mínima positiva de preenchimento numérico; sem largura expressa/documentada NÃO se DEVE presumir dois, três ou outro número de dígitos. Track desconhecido DEVE ser omitido; zero-padding não altera seu valor e NÃO DEVE truncar números maiores. `Ordem` NÃO vira Track sem mapeamento de coletânea declarado. Toda resolução de colisões DEVE ser estável pelo ID/identidade, sem sobrescrita ou sufixo aleatório final.

**[A] Interfaces implementadas:** `-ModeloNome Legado` mantém o padrão; `-ModeloNome Musical` usa somente o mapeamento declarado por `-ColunaAutor`, `-ColunaTrack` e `-ColunaTitulo` no CSV canônico. A busca de cabeçalhos é literal e Ordinal. Autor/faixa não mapeados são omitidos; título insuficiente, coluna mapeada inexistente ou faixa inválida levam ao legado com `nomeacao.pendente_editorial=true`. `-LarguraTrack` aceita 1..145 ou ausência, sem padding implícito nem truncamento do valor. O estado/journal registra o modelo solicitado/aplicado, as colunas declaradas, o motivo e a pendência. O reuso válido preserva o arquivo e o registro de nomeação originais.

**[A] Provas desta integração:** Windows/PowerShell 7+: `tests/nomeacao_editorial_componentes.tests.ps1` (22 casos), `tests/mapeamento_nomeacao.tests.ps1` (14), `tests/nomeacao_base.tests.ps1` (11) e `tests/nomeacao_cli.tests.ps1` (cinco cenários de publicação/journal/reuso offline), além dos 12 modos de regressão de execução única. O reuso com pedido diferente conservou nome, CSV e áudio, com zero downloads, consultas remotas e perguntas adicionais. Mídia MP3 sintética real; transporte e confirmações simulados. Não houve novo download remoto ou ensaio dos novos parâmetros em Linux/macOS; as provas anteriores de outras versões continuam com seus limites. Isso não comprova aderência integral ao RCF.

**[R/F]** Normalização editorial DEVE corrigir espaços/formato com regra cultural explícita e conservar siglas, nomes próprios e grafias legítimas (ex.: `AC/DC`, `DJ`, `iTunes`). NÃO DEVE aplicar capitalização cega a títulos/nomes. A normalização de comparação sem acentos do algoritmo atual NÃO DEVE substituir texto editorial. Sem evidência para mudar uma grafia, preservá-la é obrigatório. Metadados editoriais insuficientes NÃO DEVEM invalidar áudio tecnicamente admissível; identidade musical incerta continua bloqueante.

### 7.2 Metatags e cover art condicionais

**[R/F]** Quando tecnicamente viável e validado, o projeto DEVE incorporar metatags consistentes de artista/intérprete, título musical, álbum/coletânea explicitamente identificado, número de faixa e autor quando conhecido. O esquema lógico é `artista`, `titulo`, `album`, `track`, `autor`, mais os campos pertinentes documentados; NÃO são nomes físicos já implementados. Valores DEVEM vir do CSV confiável ou origem conferida, com precedência explícita e registro de conflitos. Álbum da origem e nome da coletânea NÃO DEVEM sobrescrever um ao outro sem escolha documentada. Campos desconhecidos ficam ausentes.

<!-- metatags-rcf-v1 -->
**[A] Metatags implementadas em novos MP3:** `-Metatags` habilita o enriquecimento; sem ele, o comportamento anterior permanece. Os nomes físicos são `artist`, `title`, `album`, `track` e `composer`, declarados respectivamente por `-ColunaArtistaTag` (padrão `Artista`), `-ColunaTituloTag` (padrão `Musica`), `-ColunaAlbumTag`, `-ColunaTrackTag` e `-ColunaAutorTag` (os três últimos sem coluna padrão). A busca de colunas é literal e Ordinal; não infere compositor de `Artista`, faixa de `Ordem` ou álbum de outro campo. Campos opcionais não declarados são omitidos. Os helpers editoriais distribuídos devem acompanhar o principal; o README descreve o uso.

**[A] Preservação e limites:** candidato separado por cópia do fluxo, preservação das tags existentes, payload comprimido, parâmetros técnicos e decodificação verificados antes da publicação. Conflito, valor inválido ou falha editorial mantém o áudio tecnicamente admissível e registra limitação, sem sobrescrever valores conflitantes. A auditoria mantém hashes da fonte e dos bytes finais separados. Quando há marcador, a cadeia liga o intermediário do marcador à fonte das metatags e ao hash final; nomeação Musical permanece independente. Reuso de arquivo válido já publicado não reaplica metatags mesmo com novas opções/CSV; isso não equivale a atualizar tags ausentes nesse arquivo.

**[A] Evidência delimitada:** `tests/metatags_cli.tests.ps1` e `tests/metatags_marcador_nomeacao_cli.tests.ps1` passaram em dois casos cada (normal e falha real de I/O após o movimento), verificando cinco tags, payload, hashes fonte/final, journal e reuso offline sem novo transporte; o segundo inclui marcador e nomeação Musical. Windows/PowerShell 7, mídia e FFmpeg/ffprobe reais, transporte e aprovações simulados. Não houve novo download remoto nem prova de 372 downloads, players GUI ou deste enriquecimento em Linux/macOS. Não há aceite integral desta seção ou do RCF. A capa continua opcional e indisponível nos limites abaixo.

**[R/F]** Thumbnail original do vídeo PODE ser incorporada como capa quando disponível, autorizada e tecnicamente compatível com o contêiner/player alvo. DEVE registrar URL/ID, hash, tipo real, dimensões e eventual adaptação da imagem; NÃO inventar resolução mínima universal, ampliar para simular detalhe nem substituir por imagem de outro vídeo. Resolução/qualidade suficiente e compatibilidade DEVEM ser comprovadas no caso usado. Download de thumbnail está desativado no principal atual; suporte a capa NÃO está implementado nem homologado.

**[R/F] Conflito de streams:** o validador atual rejeita qualquer stream adicional, inclusive capa exposta como imagem anexada. Uma futura exceção DEVE permitir exclusivamente cover art identificável e validada, manter exatamente um stream de áudio e rejeitar vídeo audiovisual/streams arbitrários. A incorporação NÃO PODE ser ativada antes dessa adaptação e seus testes; NÃO se DEVE remover a restrição global sem substituição equivalente.

**[R/F]** Tags/capa DEVEM ser aplicadas por cópia do fluxo, sem transcodificar áudio. Nativo sem enriquecimento DEVE manter bytes; enriquecimento explícito PODE alterar contêiner/hash do arquivo, mas DEVE comprovar preservação do fluxo de áudio e revalidar integridade, codec, duração, canais, amostragem e bitrate medido sem contar imagem/tags. Hash da fonte DEVE permanecer na auditoria; hash/tamanho do resultado DEVEM refletir os bytes após enriquecimento. Publicação/estado DEVEM continuar consistentes e idempotentes. Falha editorial DEVE preservar o download válido, registrar limitação e impedir que saída parcialmente modificada substitua o original. Ferramenta adicional só PODE ser introduzida quando indispensável, justificada e validada por plataforma/contêiner.

### 7.3 Marcador comum opcional

**[R]** A interface DEVE oferecer `-Marcador` opcional, comum aos downloads da invocação e cumulativo aos demais metadados. Ausência NÃO altera tags; valor vazio após trim equivale a ausente. Valor informado DEVE ser normalizado em Unicode NFC, com espaços externos removidos, primeira letra em maiúscula e demais letras em minúscula por regra invariante; espaços internos, acentos, dígitos e pontuação DEVEM conservar significado. Exemplo: `  MINHA COLETÂNEA  ` → `Minha coletânea`. Valor sem letras DEVE ser preservado após trim/NFC, sem “capitalização” fictícia.

**[R/F]** O marcador DEVE usar um campo adicional semanticamente próprio, de nome lógico `marcador_coletanea`; mapeamento físico para cada contêiner/ferramenta/player DEVE ser documentado e testado antes de declarar suporte. NÃO DEVE substituir artista, título, álbum, gênero, comentário ou outro campo de significado distinto. Se um campo adicional suportar múltiplos valores, um novo marcador DEVE ser acrescentado sem duplicatas; sem suporte compatível, DEVE registrar limitação/preservar os demais dados e NÃO alegar que o marcador foi incorporado. Reexecução com marcador NÃO DEVE duplicar áudio nem aplicar enriquecimento repetitivo desnecessário. 

**[A] Suporte delimitado implementado:** `-Marcador` foi acrescentado ao fim da lista de parâmetros, sem mudar posições anteriores. `editorial_audio.ps1` é carregado da raiz do script somente para pedido não vazio. Em novos MP3 admissíveis, FFmpeg cria candidato separado por cópia do fluxo e dos metadados, com ID3v2.3 e `-metadata marcador_coletanea=VALOR`; ffprobe lê o campo em `format.tags.marcador_coletanea`. Normalização, preservação dos demais campos e payload comprimido, decodificação integral, parâmetros medidos e hashes antes/depois são verificados antes da publicação. A auditoria conserva o hash da fonte e atualiza o hash final. Ausência/vazio mantém o comportamento anterior.

**[A] Reuso e limites:** marcador igual já gravado é confirmado sem reescrever/duplicar áudio. Campo ausente ou diferente em arquivo publicado permanece intacto; `marcador_reuso.status=limitacao` e o motivo no relatório impedem alegar incorporação. Atualização posterior de arquivo publicado, multivalor, M4A, players GUI e este enriquecimento em Linux/macOS continuam sem suporte/homologação. O mapeamento acima foi observado apenas com MP3/FFmpeg/ffprobe no Windows/PowerShell 7, não com todos os leitores ID3. Não há aceite integral desta seção nem do RCF.

**[A] Evidência específica:** `tests/marcador_cli.tests.ps1` concluiu uma publicação e duas retomadas offline com marcador igual/conflitante, arquivo único/hash inalterado no reuso, hashes/tamanho do estado corretos e CSV canônico preservado. Mídia e ferramentas são reais; transporte e aprovações são simulados. Passaram também os cinco cenários de `tests/marcador_publicacao.tests.ps1`, as 24 verificações de qualidade e as oito variantes legadas de retomada musical. Os testes de helpers com `-FixtureRoot` exigem fixture e executor de produção preparados pelo wrapper, diferentemente do roteiro CLI autônomo.


## 8. Verificação, lacunas e aceite bloqueante

**[A] Adequação incremental:** contrato histórico validado por 19 casos e isolamento (6e84157); modo padrão sem perguntas e interativo explícito (4d89778); contrato de aprovação musical (2fc22fa), novos downloads (ce64344) e oito retomadas preservando bytes sem rede (860757c). Os testes não autenticam a verdade externa das declarações, não homologam Unix integralmente e não demonstram aderência integral às demais lacunas. Preflight das entradas: cinco causas globais rejeitadas com saída 2, CSV intacto e destino/estado/legado sem alterações; regressão positiva do fluxo também passou. Sem consultas remotas; ferramentas de versão reais e transporte positivo simulado. Ordenação verificada em 36 permutações/culturas, fila vazia e atualização; fallback real do fluxo com IDs sintéticos A/a preservou ambas as tentativas e registrou a rejeição da primeira. As 24 verificações de qualidade passaram após a mudança. Transporte do fallback simulado; sem download remoto novo. Descoberta nativa verificada por ramos/arquiteturas parametrizados, prioridades adjacentes/PATH e contrato Windows obrigatório; preflight real Windows preservado. O inventário inicial não encontrou ferramentas no PATH do Ubuntu WSL; a verificação Linux posterior abaixo registra o ambiente preparado e os testes efetivamente concluídos.

**[A] Verificação Linux posterior:** Ubuntu WSL 24.04.1 x86_64, PowerShell 7.6.9, yt-dlp 2026.10.26 e FFmpeg/ffprobe ELF reais. Passaram sete roteiros: ambiente, contrato e descoberta de evidências, aprovação musical, ordenação, descoberta de ferramentas e qualidade (24 verificações); esta última também passou novamente no Windows. `tests/linux_integracao.tests.ps1` conferiu as 372 linhas, URLs e ordem contra referência independente gerada pelo leitor CSV Python, preservando o CSV canônico. Com fonte MP3 sintética conhecida a 192 kbps e declarações próprias da fixture, publicou, conservou o hash e reutilizou com uma única chamada de transporte simulado; rejeitou PE antes de criar destino. Houve cwd externo, espaços/acentos e ausência de perguntas/cookies/navegador. Os sete resultados e a auditoria já executada foram reaproveitados por hashes; o código de saída da primeira auditoria não havia sido medido, portanto não foi inventado. Não houve novo download remoto. Executar ELF em /mnt/d apresentou disk sleep/p9_client_rpc; copiar os mesmos hashes para /tmp nativo permitiu a execução. Preparo e integração ocorreram na mesma chamada WSL e as provas foram arquivadas no workspace antes do término, sem supor persistência temporária. Recibos locais em `tests/.runtime-linux-tools/project-results.json` e `native-case-artifacts.json` registram o alcance; são artefatos de execução ignorados pelo Git. Não há homologação universal de Linux, de montagens Windows ou de macOS, nem aderência integral ao RCF.

**[A] Base da inspeção:** a criação original leu principal, cinco helpers, CSV, modelos JSON, manifesto de ferramentas, README e os seis roteiros então versionados, sem executar lote/testes ou revalidar acesso remoto. Naquela conciliação, foram revisados os deltas do merge e executados os sete roteiros então atuais em Windows/PowerShell 7, todos com saída zero: ambiente (48 verificações), autenticação, ferramentas, qualidade (24 verificações), descoberta de evidências, integração portátil e execução única (cinco cenários). Os cenários de execução única confirmaram manifesto na raiz/no controle, nenhuma pergunta de caminho, pendência sem manifesto/documento válido e nenhuma aprovação no modo não interativo. Transporte e respostas humanas desses ensaios são simulados; não houve novo download remoto nem homologação de Linux/macOS.

**[A] Conciliação Git verificada:** após `git fetch --prune origin`, `origin/main` é ancestral do merge inspecionado, sem commits remotos pendentes; `git merge --no-edit '@{upstream}'` confirmou `Already up to date`. O merge preserva tanto os scripts/testes de descoberta automática do upstream quanto as regras locais de preservação, o CSV e os executáveis versionados. `git lfs fsck --objects --pointers HEAD` passou. Essa verificação local NÃO declara publicação dos commits/objetos no remoto.

| Evidência disponível | Alcance e limite |
| --- | --- |
| `tests/qualidade.tests.ps1` | Define 24 verificações com FFmpeg/ffprobe e fixtures: 96 kbps, inflação, VBR medido inferior, MP3 128, nativo 192 sem alteração, conversão FLAC/Opus, remux AAC, extensão falsa, corrupção, truncamento, fila e legado/órfãos. Não comprova procedência dos vídeos reais. |
| `tests/execucao_unica.tests.ps1` | Doze modos disponíveis, com evidências cumulativas por unidade. Foram exercitados diretos/automáticos sem aprovação, interação explícita e oito variantes de retomada: aprovação persistida/CSV/interação, ausência/inconsistência, ID literal e hash. Retomadas usam zero downloads/consultas remotas e preservam um arquivo/hash/CSV. Transporte e respostas humanas simulados; mídia e ferramentas reais. Inclui fallback de formato indisponível A para a, sem colapsar IDs literais. |
| `tests/autenticacao.tests.ps1` | Argumentos/cabeçalho, recuperação limitada, cancelamento, não interativo, 429 e DPAPI com respostas simuladas. Não certifica sessão real utilizável. |
| `tests/ambiente_portatil.tests.ps1` | Raiz/cwd, espaços/acentos, BOM/delimitadores/cabeçalhos e ambiguidade. O roteiro explicita que links simbólicos não foram exercitados. |
| `tests/ferramentas_portateis.tests.ps1` | Executáveis reais, ausência/incompatibilidade e PATH vazio; declara não comprovar Linux/macOS. |
| `tests/integracao_portatil.tests.ps1` | CSV canônico em dois cwd, três delimitadores, argumentos reais especiais e preflight sem ferramenta; auditoria isolada sem rede/navegador. |
| `tests/evidencias_descoberta.tests.ps1` | Descoberta não recursiva na raiz/controle, cwd independente, exemplos/JSON inválido/sem campos, diretórios ausentes/duplicados e ausência de alteração dos documentos. Não atesta a verdade do histórico das fontes. |
| README: ensaio remoto `NBnH864JUZw` | Registra transporte anônimo de WebM/Opus de 6.054.403 bytes, 339,541 s, 48 kHz, dois canais, em fixture isolada. Não prova publicação M4A/MP3, procedência histórica nem conclusão do CSV. |
| `tests/linux_integracao.tests.ps1` | Linux real: 372 URLs/ordem canônicos, publicação/reuso sintético com um transporte simulado e hash nativo preservado; cwd externo, nomes com espaços/acentos, sem perguntas/cookies/navegador e PE rejeitado antes de efeitos. Aceita recibo de ferramentas preparado; a evidência atual usou filesystem nativo Linux e arquivou resultados antes de encerrar WSL. |
| README: plataformas/autenticação | Windows/PS7 exercitado; Linux real verificado no escopo acima, macOS não executado. Chrome falhou com DPAPI no ensaio histórico; não é requisito. Relatos PS5.1 são históricos e NÃO homologam o principal PS7 atual. |

**[R]** Os roteiros existentes PODEM ser reproduzidos com `pwsh -NoProfile -File ./tests/NOME.tests.ps1` em ambiente preparado. Eles criam fixtures isoladas e NÃO são ação necessária desta entrega documental. Novos recursos DEVEM receber verificações proporcionais ao seu contrato; testes simulados DEVEM ser identificados como tais. Reais downloads, buscas, ambiguidades, alternativas, indisponibilidade, interrupção e reexecução DEVEM ser distinguidos de cobertura sintética antes de homologação integral.

| Lacuna comprovada ou não homologada | Obrigação vigente para futura adequação |
| --- | --- |
| Modo sem perguntas por padrão implementado; identidade musical não é comprovada pelo modo de execução | Preservar interação explícita e tratar separadamente a barreira universal de versão/vocais e alternativas legítimas. |
| Descoberta nativa e escopo Linux real acima verificados; macOS, outras arquiteturas/montagens e acesso remoto Linux não homologados | Validar somente ambientes efetivamente disponíveis e distinguir transporte simulado, sem presumir execução de PE nem compatibilidade universal. |
| Destino e nomeação musical parametrizados; metatags opcionais em novos MP3 verificadas, com limites em 7.2 | Preservar saída padrão e parametrizar nomes/mapeamentos confiáveis sem renomear/perder arquivos válidos. |
| Marcador e metatags em novos MP3 verificados via FFmpeg/ffprobe; reedição de publicados, outros contêineres/leitores e capa não suportados/homologados; validador só admite um stream | Enriquecimento opcional com preservação de fluxo, exceção restrita para imagem e leitura posterior verificável. |
| Aprovação explícita agora exigida inclusive em direto/automático/reuso; verdade da conferência humana não é autenticada pelo software | Exigir conferência real e manter pendência quando faltam dados; nunca inferir instrumentalidade de título/canal. |
| Manifesto valida mínimo histórico e vincula hashes, mas não autentica a verdade da cadeia | Exigir prova suficiente e manter pendência diante de inconsistências; não certificar fidelidade apenas pela declaração. |
| Desempate/IDs literais e checkpoint produtor/retomada integrados; falhas específicas de I/O/auditoria testadas, demais janelas de crash e relatórios auxiliares ainda não integralmente cobertos | Preservar ordenação estável e recuperação rastreável; testar condições restantes sem alegar proteção absoluta. |

**[R] Aceite do RCF:** DEVE ser autossuficiente, referenciado ao código inspecionado, distinguir [A]/[R]/[F], preservar os contratos compatíveis e registrar cada conflito/limite acima. Não depende de infraestrutura imaginada nem de anexos anteriores para compreender as obrigações. Na fase original de criação, somente `RCF.md` era entrega autorizada. A conciliação posterior verifica a integração e atualiza este documento; NÃO declara resolvidas as lacunas funcionais restantes.

**[R] Aceite funcional futuro:** conclusão conforme exige identidade/versão e requisitos musicais comprovados, fonte/histórico adequados vinculados aos bytes, ausência de qualidade artificial, arquivo M4A/MP3 genuíno decodificável com média ≥128, prioridade nativa respeitada, nenhuma conversão indevida, publicação única e recuperável, origem/decisões/rejeições/hash rastreáveis e nenhuma perda dos arquivos válidos. Tags/capa/marcador só PODEM constar como realizados após verificação específica. Fonte inferior, arquivo incompatível/corrompido ou evidência insuficiente NÃO PODEM ser concluídos. Na falta de alternativa legítima, DEVE registrar pendência e continuar os demais itens; nenhuma promessa de autonomia, eficiência ou sucesso DEVE enfraquecer essas barreiras.


### Evidências posteriores de publicação e estado [A]

No Windows/PowerShell 7, tests/publicacao_produtor_cli.tests.ps1 passou para publicação normal e falha real de I/O no estado após o movimento: a referência foi lida do disco antes de mover, a pendência preservou os bytes e a retomada offline concluiu sem novo transporte/perguntas. tests/publicacao_retomada_cli.tests.ps1 passou para retomada antes da auditoria, proteção de arquivo conhecido/não rastreado e referência inválida. A integração 7ad976f também passou nos doze modos E2E, marcador CLI, títulos ISO com oito variantes de retomada e qualidade (24 verificações). Áudio, ferramentas e I/O reais; transporte e confirmações humanas simulados.

A versão 7ad976f passou em uma fixture nova no Ubuntu WSL 24.04.1, PS7.6.9 e ferramentas ELF reais em /tmp: auditoria independente das 372 linhas/URLs/ordem do CSV, publicação MP3 sintética, journal ligado ao hash externo e rastreio concluído, reuso sem novo download, ausência de perguntas/cookies e rejeição de PE antes de criar destino. Não houve download remoto. Fontes, logs e arquivos arquivados foram conferidos por hash em tests/.runtime-publication-linux-current/result.json. Os artefatos são locais e ignorados pelo Git; não constituem homologação de macOS ou de outros sistemas/montagens.

A correção f303115 limita a limpeza de Save-State ao temporário criado pela chamada. tests/estado_duravel.tests.ps1 injeta somente a entropia de nomes na função real, mantendo CreateNew e I/O reais; o controle negativo detectou o escritor anterior e o teste corrigido preservou temporário alheio/estado. Passaram também as verificações de serialização/tipos e a regressão do produtor com falha real após o movimento. Esse ajuste posterior foi testado no Windows e não foi reexecutado no ensaio Linux acima. O aviso provocado pela prova negativa de profundidade JSON corresponde à serialização recusada antes de efeitos, não a estado truncado aceito.

Esses resultados encerram apenas os microescopos descritos. As lacunas editoriais, outras plataformas e demais condições não verificadas continuam vigentes; não há aceite integral do RCF.

### Evidencia posterior de relatorios auxiliares [A]

<!-- reports-io-evidence-v1 -->
No Windows/PowerShell 7, tests/relatorios_falha_io.tests.ps1 extrai por AST Safe-Cell, Export-Reports e o try/catch da chamada no finally do principal. Uma fixture isolada bloqueia relatorio.csv por FileStream com FileShare.None; a IOException antes da abertura preserva os hashes dos tres CSVs sentinela, a ausencia de aprovacoes_modelo.csv e os snapshots de estado/RowsForReport em memoria e JSON. Apos liberar o bloqueio, a chamada real gera relatorio.csv, pendencias.csv, sugestoes_aprovacao.csv e aprovacoes_modelo.csv com uma linha esperada cada, confirmacoes humanas vazias e sem aviso; os snapshots continuam intactos.

Este ensaio nao executa o lote/downloads nem o processo principal completo; os JSONs persistidos pertencem a fixture. Nao comprova interrupcao durante escrita, atomicidade conjunta dos relatorios, todas as janelas de crash ou homologacao de outros sistemas. As demais lacunas e requisitos desta secao continuam vigentes, sem aceite integral do RCF.

## 9. Norma posterior: autossuficiencia e codecs exclusivos

<!-- autonomy-codecs-user-v1 -->
Esta norma prevalece sobre exigencias anteriores conflitantes deste documento, inclusive aprovacoes humanas obrigatorias e aceitacao de outros codecs. O registro da norma nao significa que sua implementacao esteja concluida.

Um script AUTOSSUFICIENTE DEVE cumprir sua missao de ponta a ponta sem depender de supervisao, aprovacao, resposta, interpretacao, decisao, descoberta, preparacao, intervencao ou iteracao humana, direta ou indireta, imediata ou posterior. A ausencia de perguntas durante a execucao, por si so, NAO demonstra autossuficiencia.

Se a conclusao exigir que o usuario aprove, confirme, escolha, interprete pendencias, descubra a proxima providencia, prepare condicoes, corrija estados, forneca informacoes ou reinvoque o script depois de uma providencia humana, o criterio NAO foi atendido.

O script DEVE decidir e resolver autonomamente o que estiver em seu escopo, resolver dependencias, antecipar e tratar condicoes previsiveis, utilizar alternativas seguras quando cabiveis e concluir ou declarar tecnicamente uma impossibilidade real, fundamentada em evidencias. NAO DEVE simular sucesso, transferir silenciosamente responsabilidades nem trocar uma dependencia humana por uma pendencia meramente renomeada. A falta de um sinal de aprovacao humana nao constitui, isoladamente, impossibilidade tecnica. Relatorios e notificacoes sao permitidos quando nenhuma acao humana for necessaria para considerar a missao concluida.

Lista FECHADA de codecs de audio aceitos: AAC e AC3. Na identificacao canonica do ffprobe, os valores permitidos sao somente aac e ac3; eac3 e todos os demais sao excluidos. Nao validar, publicar ou aceitar implicitamente no reuso um audio de outro codec. Extensao, conteiner ou nome do formato nao substituem a identificacao do codec real. Arquivos preexistentes devem ser preservados, mesmo quando nao forem admissiveis segundo esta regra.

As verificacoes de integridade, qualidade, ausencia de inflacao artificial, identidade e rastreabilidade compativeis continuam obrigatorias. A substituicao de etapas humanas DEVE empregar decisoes e evidencias tecnicas explicitas, sem fabricar confirmacoes, procedencia ou certeza musical.

## 10. Escopo de audios, deteccao de vocais e dependencias

<!-- audio-scope-dependencies-user-v1 -->
Esta norma posterior prevalece sobre qualquer disposicao conflitante anterior, inclusive a proibicao absoluta de interacao da secao 9: a unica excecao admitida e a solicitacao antecipada de elevacao de privilegios efetivamente indispensavel. A lista exclusiva AAC/AC3 permanece vigente.

O produto e um BAIXADOR DE AUDIOS: musicas sao o foco principal, nao exclusivo. Listas podem conter musicas com ou sem vocais, audios de outras naturezas ou conteudos mistos. NAO restringir o processamento a musicas nem a musicas instrumentais; classificacao musical ou ausencia de vocais NAO pode ser condicao para baixar.

Quando tecnicamente viavel, a identificacao de vocais DEVE utilizar bibliotecas open source existentes, preferencialmente mantidas, seguras e confiaveis. NAO implementar detector proprio. A analise e informativa e NAO deve excluir musicas vocalizadas, fala, outros audios ou limitar o escopo de download. Falta de resultado confiavel NAO deve ser convertida em ausencia comprovada de vocais.

O script DEVE identificar, instalar, configurar e validar autonomamente TODAS as dependencias externas necessarias, sem exigir preparacao ou intervencao do usuario. Dependencias e artefatos obtidos devem ter origem e integridade verificadas. As instalacoes devem usar os privilegios realmente necessarios, sem elevar indiscriminadamente.

A necessidade real de privilegios elevados DEVE ser verificada nos primeiros segundos da execucao, antes de operacoes demoradas ou de qualquer etapa dependente desses privilegios. Quando indispensavel, solicitar elevacao imediatamente. Depois de concedida, prosseguir autonomamente, preservando os argumentos e sem reinvocacao manual ou outra aprovacao, confirmacao ou preparacao humana. Nenhuma solicitacao tardia de elevacao pode substituir essa verificacao inicial.

Registrar esta norma nao comprova sua implementacao: dependencias automaticas, elevacao antecipada, escopo geral e deteccao vocal precisam ser integrados e verificados antes do aceite.
