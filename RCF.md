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
| `execucao_unica.ps1` | Leitura interativa, escolha de candidato e três confirmações. O helper histórico de caminho de evidência permanece definido, mas não é chamado pelo fluxo principal atual. |
| `evidencias_fonte.ps1` | Descoberta local, leitura e vinculação de manifestos de procedência a documentos locais e hashes; reúne duplicatas idênticas entre manifestos e exclui chaves conflitantes. |
| `autenticacao_ytdlp.ps1` | Argumentos de sessão explicitamente fornecida por cookies Netscape ou navegador suportado. |
| `coletanea_uber_instrumental_candidatas.csv` | Entrada canônica existente: 372 linhas, 370 buscas e dois vídeos diretos; sugestões NÃO são auditoria musical. |
| `evidencias.exemplo.json` | Modelo com valores fictícios; NÃO é evidência utilizável. |
| `ferramentas.json` | Registro de fornecedor, versão FFmpeg e hashes de três executáveis; NÃO é um instalador nem uma verificação automática de confiança. |
| `tests/*.tests.ps1` | Sete roteiros de qualidade, execução única, autenticação, ambiente, ferramentas, integração portátil e descoberta de evidências. |

**[A]** Não há serviço, banco de dados externo, interface web, gerenciador de filas nem instalação automática de dependências. A execução usa PowerShell/.NET e processos externos. Os cinco helpers são parte obrigatória da distribuição; “autossuficiente” NÃO significa que o principal isolado contenha tudo.

**[A] Fluxo real:** carregar helpers → descobrir/testar ferramentas e Node opcional → validar autenticação explícita → localizar CSV/delimitador → criar controle/adquirir lock → carregar estado e evidências → auditar legado → importar/validar linhas e aprovações → identificar/reutilizar/buscar → obter metadados → tentar formatos → validar fonte/procedência → preservar/remuxar/converter excepcionalmente → validar/publicar → persistir cada resultado → exportar relatórios/resumo e liberar lock.

**[R]** Uma única invocação DEVE executar todo o processamento possível, descobrir caminhos/dependências, diagnosticar obstáculos e aplicar alternativas legítimas sem confirmações ordinárias nem etapas manuais obrigatórias entre busca e publicação. Autonomia NÃO dispensa pré-requisitos reais, credenciais autorizadas ou prova de procedência: quando ausentes, DEVE registrar a causa e continuar o lote. É PROIBIDO escolher uma música ambígua ou fabricar evidência para evitar pendência.

**[A/F]** Hoje o padrão permite perguntas; `-NaoInterativo` impede perguntas e conserva as garantias, mas não cria dados ausentes. Tornar o fluxo ordinário autônomo preservando um modo interativo opcional é adequação futura. Não há garantia de obter todos os áudios do CSV nem de resolver restrições de terceiros.

## 3. Ambiente, distribuição e invocação

### 3.1 Dependências e portabilidade

**[R]** PowerShell `.ps1` DEVE continuar sendo a linguagem principal, com PS 7+ e Windows prioritário. Recursos nativos PowerShell/.NET DEVEM ser priorizados. Dependências externas DEVEM ter necessidade técnica documentada; soluções mantidas e reutilizáveis DEVEM preceder novos mecanismos próprios. NÃO DEVE haver dependência de Chrome ou de outro navegador específico.

**[A]** No Windows, `yt-dlp.exe` é obrigatório junto do principal e recebe `--ignore-config --no-plugin-dirs --version` no preflight. FFmpeg e ffprobe são obrigatórios para validação integral e conversão excepcional; procuram-se primeiro `ffmpeg.exe`/`ffprobe.exe` adjacentes, depois aplicações no PATH. Fora do Windows, esses dois usam nomes sem `.exe`. Node.js é opcional, adjacente ou no PATH, testado antes de passar `--js-runtimes node:CAMINHO`; ausência/falha gera aviso, sem promessa de formatos equivalentes.

**[A] Limitação:** yt-dlp ainda tem nome adjacente fixo `yt-dlp.exe` em todos os sistemas. Fora do Windows, o preflight rejeita cabeçalho Windows PE e exige que o arquivo assim nomeado seja realmente executável nativo. Isso NÃO representa resolução portátil concluída. **[R/F]** Em outros sistemas DEVE haver resolução condicional de executável nativo compatível com arquitetura e permissões, sem pressupor execução de `.exe` Windows; a ordem de descoberta DEVE ser explícita e testada. Windows DEVE preservar o contrato adjacente `yt-dlp.exe`.

**[A]** As três ferramentas obrigatórias são testadas com timeout de 15 s antes de criar destino/estado ou migrar legado; incompatibilidade informa sistema, arquitetura e caminho. O script NÃO baixa nem instala executáveis. `ferramentas.json` registra FFmpeg/ffprobe `9.0.2-essentials_build-www.gyan.dev`, fornecedor `https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip` e referência `https://ffmpeg.org/download.html`. O README registra yt-dlp `2026.10.26`. Essas versões são retrato da distribuição, NÃO promessa de compatibilidade futura, nem exigência de atualização automática.

**[A/R] Versionamento:** o CSV canônico e `yt-dlp.exe` permanecem no Git convencional; `ffmpeg.exe` e `ffprobe.exe` são versionados por Git LFS, com regras específicas em `.gitattributes` e hashes no manifesto. A reprodução exige os objetos LFS completos; ponteiros isolados NÃO são executáveis. O `.gitignore` exclui somente `/destino/` e `/tests/.runtime-*/`, preservando referências e evidências revisadas fora dessas árvores. É PROIBIDO substituir binários testados ou ocultar fontes/CSV/evidências úteis por exclusões genéricas sem justificativa e validação.

**[R] Preparação:** instalar PS 7+, distribuir o principal e os cinco helpers juntos, disponibilizar os executáveis compatíveis e acesso de escrita ao destino; fornecer CSV e, quando necessários, aprovações, evidências/documentos e sessão autorizada. O preflight DEVE anteceder efeitos do lote. Falhas globais de configuração/integridade PODEM impedir a inicialização; falhas de um item NÃO DEVEM interromper os demais. O código atual ainda audita legado antes de validar integralmente linhas/aprovações: NÃO se DEVE prometer preflight global sem efeitos para todo erro de entrada.

### 3.2 Parâmetros implementados [A]

| Parâmetro | Contrato atual |
| --- | --- |
| `-Csv` | String opcional, posição 0. Caminho absoluto ou relativo à raiz do script. Ausente: descobrir um único CSV elegível adjacente. |
| `-AprovacoesCsv` | CSV de confirmações prévias por `Ordem`, relativo à raiz ou absoluto. Não substitui evidência técnica. |
| `-EvidenciasJson` | Manifesto JSON explícito opcional, relativo à raiz ou absoluto; quando informado substitui a descoberta automática. Documentos relativos também partem da raiz do script, não da pasta do manifesto. |
| `-CookiesArquivo` | Arquivo Netscape explícito, relativo à raiz ou absoluto; mutuamente exclusivo com `-CookiesNavegador`. |
| `-CookiesNavegador` | Descritor explícito de sessão; não é pré-requisito padrão. |
| `-NaoInterativo` | Não solicita aprovações nem sessão; descoberta de evidências permanece ativa quando não há manifesto explícito. Nenhum modo solicita caminho JSON; ausência de dados suficientes mantém pendência. |
| `-SomenteAuditarExistentes` | Auditoria local sem consultas remotas; ainda exige/testa ferramentas e PODE preservar/mover legado, atualizar estado e relatórios. Não é modo somente leitura. |
| `-ReavaliarPendentes` | Ignora cache de buscas e permite reconsulta pertinente; não aprova candidatos nem relaxa qualidade. |
| `-ResultadosPorBusca` | Inteiro de 3 a 12; padrão 7. Limita candidatos consultados, não garante identificação. |
| `-MaxTentativas` | Inteiro de 1 a 4; padrão 2. Limita chamadas externas por operação no wrapper; não é o total de pedidos HTTP internos do yt-dlp. |

**[A]** Não há parâmetros implementados de destino, modelo de nome, largura de faixa, capitalização, metatags, capa ou marcador comum. **[R/F]** Caminhos, nomes e organização DEVEM tornar-se configuráveis por parâmetros, mantendo os padrões atuais quando não sobrescritos. As opções futuras especificadas na seção 7 NÃO DEVEM constar de exemplos executáveis da versão atual.

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

**[A/R]** `Identity-Matches` confronta música com título/track e artista com título/channel/uploader/artist. A comparação por texto NÃO comprova gravação, autoria musical, versão nem ausência de vocais. URL direta usa o ID indicado e exige metadados coerentes; pode prosseguir sem atestado humano de ausência de vocais. **É PROIBIDO** descrever esse caminho automático como auditoria de instrumentalidade. Quando a versão ou ausência de vocais for requisito ainda não comprovado, o resultado DEVE ser pendência de auditoria; o cumprimento integral dessa barreira em todos os caminhos atuais NÃO está demonstrado.

**[A] Aprovações:** cabeçalho `Ordem,VideoId,ArtistaMusicaConferidos,VersaoConferida,SemVocaisConferido`; vírgula/UTF-8 no importador próprio. Ordem repetida no arquivo é erro global. Cada confirmação aceita `SIM`, `S`, `TRUE` ou `1`, sem distinguir caixa e após trim; o fluxo interativo pede três `SIM`. Ambiguidade pode solicitar índice a partir de zero ou ID presente nos candidatos; há até três entradas de escolha. Confirmação ausente/inválida permanece pendente. **[R]** Aprovação humana DEVE corresponder a conferência real, não preenchimento automático; NÃO substitui verificação técnica/procedência. Sugestão de primeiro candidato no relatório NÃO é seleção aprovada.

## 5. Qualidade, formatos e publicação

### 5.1 Barreiras obrigatórias

**[R]** Somente `.m4a` e `.mp3` genuínos PODEM ser finais. M4A DEVE ter contêiner MP4/MOV compatível e AAC ou ALAC; MP3 DEVE ter contêiner e codec MP3. Trocar extensão NÃO converte um formato. Fontes temporárias em outros formatos PODEM existir somente fora dos finais. É PROIBIDO baixar vídeo audiovisual como alternativa ordinária a uma faixa de áudio.

**[R]** Fontes com perdas comprovadamente inferiores a 128 kbps, declaradas ou medidas, e resultados finais medidos inferiores a 128 kbps são inadmissíveis. `kbps` significa 1.000 bits/s. O alvo é 128 kbps, nunca arredondar 127,x para aprovação. Bitrate superior só se justifica por preservação do original/fidelidade, ausência de alternativa adequada ou necessidade técnica do resultado. Um nativo válido de 192/256 kbps NÃO DEVE ser recodificado apenas para reduzir tamanho.

**[R]** Codec sem perdas e bitrate nominal alto NÃO comprovam fidelidade histórica. Fonte de 92/96 kbps recodificada a 128/192/320 kbps ou reempacotada sem perdas DEVE ser rejeitada. É PROIBIDO elevar bitrate, preencher com padding, alterar cabeçalhos ou inventar procedência para simular qualidade. Ausência de prova DEVE gerar `pendente_qualidade`; NÃO prova que o som é ruim nem permite concluir que é adequado. Equivalência perceptual entre codecs e ausência de transcodificações anteriores NÃO são inferíveis apenas de bitrate, espectrograma ou metadados.

### 5.2 Descoberta, ordem e tratamento atuais [A]

`Get-Formats` aceita apenas formatos anunciados como áudio sem vídeo, codec presente e ID literal `[A-Za-z0-9_-]{1,45}`. Fontes conhecidas: m4a, mp3, webm, opus, ogg, oga, aac, flac, wav, mp4, mka. Codec anunciado sem perdas é tratado separadamente; áudio com perdas com `abr` ou, na ausência, `tbr` positivo inferior a 128 é filtrado antes de baixar. Bitrate desconhecido exige medição, não aprovação.

1. Nativos M4A AAC/ALAC e MP3 precedem todos os outros formatos.
2. Dentro da classe, menor distância anunciada acima de 128 precede valores maiores; bitrate desconhecido vem depois dos conhecidos. Sem perdas recebe distância zero no código atual. Empates exatos NÃO têm um terceiro critério explícito de ordenação de formato.
3. Formatos com codec compatível AAC/ALAC/MP3 em outro contêiner precedem transcodificação e usam `-c:a copy` quando admissíveis.
4. Demais fontes admissíveis usam excepcionalmente AAC em M4A. Tentativas finitas em 128, 136 e 160 kbps saem sempre da mesma fonte original; resultados reprovados são descartados do trabalho, sem recodificação em cascata.

**[R]** Todas as alternativas nativas tecnicamente pertinentes DEVEM ser esgotadas antes de converter. A medição real e a prova de origem DEVEM prevalecer sobre a ordem baseada em metadados. Empates DEVEM receber desempate estável documentado em adequação futura; NÃO se DEVE inventar que ele já existe. O código tenta a fila finita sem o antigo corte de quatro formatos, mas certas falhas de assinatura/tamanho ou acesso encerram o item: não se DEVE declarar recuperação por todos os formatos em toda causa possível.

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

**[A]** Documento ausente/hash divergente e entradas duplicadas são rejeitados; chave de associação é `video_id|formato_id|sha256`. Na decisão, fonte com perdas medida/nominal abaixo do piso é recusada; histórico positivo abaixo de 128 também, inclusive em codec sem perdas. `sem_perdas_verificada` exige codec real sem perdas; `perdas_verificadas` exige mínimo histórico ≥128. O importador NÃO faz validação explícita completa de presença/tipo/faixa do mínimo histórico para todas as combinações: a norma mais estrita acima é requisito vigente, não garantia do parser atual.

**[R]** Evidência DEVE demonstrar a cadeia histórica efetiva e corresponder aos bytes analisados; um documento escrito a partir apenas do bitrate anunciado NÃO é prova. Verificação de hash demonstra vinculação e integridade, NÃO autenticidade intelectual, autoria ou verdade do histórico. O sistema NÃO dispõe de certificação automática universal dessa verdade; inconsistência DEVE resultar em pendência/rejeição, nunca declaração inventada. O modelo JSON contém placeholders deliberadamente inválidos.

## 6. Persistência, resiliência, segurança e saídas

### 6.1 Layout, identidade persistente e recuperação

**[A]** Raiz é a localização física do script, com tentativa de resolver link simbólico. Entradas relativas são canônicas em relação a ela. Destino atual é fixo `destino/`; controle é `destino/.controle/`:

| Caminho | Uso |
| --- | --- |
| `estado.json` | `versao=1`, mapas `registros`, `videos`, `buscas`; pode incluir `arquivos_preservados`. |
| `execucao.lock` | Abertura exclusiva `FileShare.None`; arquivo não é apagado ao liberar para evitar corrida. |
| `fontes/VIDEO/FORMATO.ext` | Downloads fonte e parciais; resultados intermediários ficam no mesmo controle, nunca contam como finais. |
| `cache/` | Cache local do yt-dlp. |
| `legado/` | Bytes de antigos resultados sem política válida, associados a hash/histórico. |
| `nao_rastreados/` | Áudios encontrados sem estado de conformidade; preservação com nome interno único e nome original/hash registrados. |
| `relatorio.csv`, `pendencias.csv` | Situação das linhas do CSV desta execução; não são substitutos do estado histórico. |
| `sugestoes_aprovacao.csv`, `aprovacoes_modelo.csv` | Sugestões regeneradas sem atestações e modelo de aprovação. |

**[A/R]** Chave de registro é SHA-256 de `Ordem`, artista, música e URL, separados por U+001F; vídeos são deduplicados por ID e buscas por hash de consulta/artista/música. Mesmo ID para artista/música divergentes gera conflito. Reuso exige política `fidelidade-128-v1`, auditoria válida, nome sem percurso de diretório, tamanho, assinatura, SHA-256 e nova validação técnica final. Estado de sucesso sem arquivo íntegro vira pendência, não novo download cego. Alterações de CSV NÃO DEVEM apagar o histórico; relatórios DEVEM refletir a entrada corrente.

**[A]** Estado é escrito em temporário e substituído com backup temporário não nulo; arrays JSON são preservados pela conversão para hashtable. Cada finalização salva estado. Migração de legado registra intenção antes do movimento; preserva bytes e reclassifica sucessos antigos como `pendente_qualidade`. Áudios conhecidos sem estado são isolados, não certificados. Uso de GUID em nomes internos de preservação/intermediários NÃO é convenção de nome final determinístico.

**[R]** Retomada DEVE conservar downloads válidos e parciais aproveitáveis, impedir duplicação e manter auditoria. Movimentos, hashes e estado DEVEM permitir reconciliar interrupções em qualquer etapa. A sequência atual publicação → gravação de estado não é uma transação única; NÃO se DEVE afirmar recuperação perfeita de toda janela de crash. A adaptação futura DEVE testar essas janelas sem descartar órfãos nem chamá-los de concluídos. É PROIBIDO apagar lock/estado como procedimento ordinário para “corrigir” uma pendência.

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

**[A]** Nome final atual: `Ordem - Artista - Musica [ID].ext`, com trim dos campos; substitui caracteres Windows proibidos/controles por `_`, compacta espaços, remove espaço/ponto finais, trata nomes reservados e trunca preservando `[ID]`. Comprimento-base máximo é `min(145; 237 − comprimento(destino))`; margem menor que 38 impede escrita segura. A capitalização recebida é preservada; não há title case nem zero-padding explícito.

**[R]** Artista/intérprete e autor/compositor NÃO DEVEM ser confundidos. `Artista` só preenche autor quando a equivalência estiver documentada; título completo do vídeo NÃO é necessariamente título musical. Título musical/track da origem, CSV conferido, álbum e número de faixa DEVEM ter proveniência e significado explícitos. Conflitos DEVEM manter o valor original e registrar pendência editorial, sem invenção. Ausência de álbum NÃO autoriza copiar título do vídeo ou `Estilo_sugerido` para esse campo.

**[R/F]** A nomeação musical preferencial DEVE seguir `{Autor}{Track}{Titulo}.{ext}`, com campos ausentes omitidos e separador ` - ` apenas entre campos presentes. Autor confiável, faixa numérica e título musical DEVERÃO vir de mapeamento explícito; sem identificação suficiente, DEVE usar o padrão atual. O ID DEVE permanecer como sufixo estável de desambiguação, compatível com a convenção existente. Não se DEVE renomear arquivos válidos já publicados silenciosamente.

**[R/F] Interface normativa futura, ainda indisponível:** `-Destino` DEVE substituir a raiz de saída, com relativo resolvido pela raiz do script e controle associado ao destino; sem opção, manter `destino/`. `-ModeloNome` DEVE permitir manter o legado ou selecionar a convenção musical acima, preservando o legado quando não sobrescrito. `-LarguraTrack` PODE fixar uma largura mínima positiva de preenchimento numérico; sem largura expressa/documentada NÃO se DEVE presumir dois, três ou outro número de dígitos. Track desconhecido DEVE ser omitido; zero-padding não altera seu valor e NÃO DEVE truncar números maiores. `Ordem` NÃO vira Track sem mapeamento de coletânea declarado. Toda resolução de colisões DEVE ser estável pelo ID/identidade, sem sobrescrita ou sufixo aleatório final.

**[R/F]** Normalização editorial DEVE corrigir espaços/formato com regra cultural explícita e conservar siglas, nomes próprios e grafias legítimas (ex.: `AC/DC`, `DJ`, `iTunes`). NÃO DEVE aplicar capitalização cega a títulos/nomes. A normalização de comparação sem acentos do algoritmo atual NÃO DEVE substituir texto editorial. Sem evidência para mudar uma grafia, preservá-la é obrigatório. Metadados editoriais insuficientes NÃO DEVEM invalidar áudio tecnicamente admissível; identidade musical incerta continua bloqueante.

### 7.2 Metatags e cover art condicionais

**[R/F]** Quando tecnicamente viável e validado, o projeto DEVE incorporar metatags consistentes de artista/intérprete, título musical, álbum/coletânea explicitamente identificado, número de faixa e autor quando conhecido. O esquema lógico é `artista`, `titulo`, `album`, `track`, `autor`, mais os campos pertinentes documentados; NÃO são nomes físicos já implementados. Valores DEVEM vir do CSV confiável ou origem conferida, com precedência explícita e registro de conflitos. Álbum da origem e nome da coletânea NÃO DEVEM sobrescrever um ao outro sem escolha documentada. Campos desconhecidos ficam ausentes.

**[R/F]** Thumbnail original do vídeo PODE ser incorporada como capa quando disponível, autorizada e tecnicamente compatível com o contêiner/player alvo. DEVE registrar URL/ID, hash, tipo real, dimensões e eventual adaptação da imagem; NÃO inventar resolução mínima universal, ampliar para simular detalhe nem substituir por imagem de outro vídeo. Resolução/qualidade suficiente e compatibilidade DEVEM ser comprovadas no caso usado. Download de thumbnail está desativado no principal atual; suporte a capa NÃO está implementado nem homologado.

**[R/F] Conflito de streams:** o validador atual rejeita qualquer stream adicional, inclusive capa exposta como imagem anexada. Uma futura exceção DEVE permitir exclusivamente cover art identificável e validada, manter exatamente um stream de áudio e rejeitar vídeo audiovisual/streams arbitrários. A incorporação NÃO PODE ser ativada antes dessa adaptação e seus testes; NÃO se DEVE remover a restrição global sem substituição equivalente.

**[R/F]** Tags/capa DEVEM ser aplicadas por cópia do fluxo, sem transcodificar áudio. Nativo sem enriquecimento DEVE manter bytes; enriquecimento explícito PODE alterar contêiner/hash do arquivo, mas DEVE comprovar preservação do fluxo de áudio e revalidar integridade, codec, duração, canais, amostragem e bitrate medido sem contar imagem/tags. Hash da fonte DEVE permanecer na auditoria; hash/tamanho do resultado DEVEM refletir os bytes após enriquecimento. Publicação/estado DEVEM continuar consistentes e idempotentes. Falha editorial DEVE preservar o download válido, registrar limitação e impedir que saída parcialmente modificada substitua o original. Ferramenta adicional só PODE ser introduzida quando indispensável, justificada e validada por plataforma/contêiner.

### 7.3 Marcador comum opcional

**[R/F]** A interface futura DEVE oferecer `-Marcador` opcional, comum aos downloads da invocação e cumulativo aos demais metadados. Ausência NÃO altera tags; valor vazio após trim equivale a ausente. Valor informado DEVE ser normalizado em Unicode NFC, com espaços externos removidos, primeira letra em maiúscula e demais letras em minúscula por regra invariante; espaços internos, acentos, dígitos e pontuação DEVEM conservar significado. Exemplo: `  MINHA COLETÂNEA  ` → `Minha coletânea`. Valor sem letras DEVE ser preservado após trim/NFC, sem “capitalização” fictícia.

**[R/F]** O marcador DEVE usar um campo adicional semanticamente próprio, de nome lógico `marcador_coletanea`; mapeamento físico para cada contêiner/ferramenta/player DEVE ser documentado e testado antes de declarar suporte. NÃO DEVE substituir artista, título, álbum, gênero, comentário ou outro campo de significado distinto. Se um campo adicional suportar múltiplos valores, um novo marcador DEVE ser acrescentado sem duplicatas; sem suporte compatível, DEVE registrar limitação/preservar os demais dados e NÃO alegar que o marcador foi incorporado. Reexecução com marcador NÃO DEVE duplicar áudio nem aplicar enriquecimento repetitivo desnecessário. Não há suporte atual demonstrado a essa opção.

## 8. Verificação, lacunas e aceite bloqueante

**[A] Base da inspeção:** a criação original leu principal, cinco helpers, CSV, modelos JSON, manifesto de ferramentas, README e os seis roteiros então versionados, sem executar lote/testes ou revalidar acesso remoto. A conciliação revisou os deltas do merge e executou os sete roteiros atuais em Windows/PowerShell 7, todos com saída zero: ambiente (48 verificações), autenticação, ferramentas, qualidade (24 verificações), descoberta de evidências, integração portátil e execução única (cinco cenários). Os cenários de execução única confirmaram manifesto na raiz/no controle, nenhuma pergunta de caminho, pendência sem manifesto/documento válido e nenhuma aprovação no modo não interativo. Transporte e respostas humanas desses ensaios são simulados; não houve novo download remoto nem homologação de Linux/macOS.

**[A] Conciliação Git verificada:** após `git fetch --prune origin`, `origin/main` é ancestral do merge inspecionado, sem commits remotos pendentes; `git merge --no-edit '@{upstream}'` confirmou `Already up to date`. O merge preserva tanto os scripts/testes de descoberta automática do upstream quanto as regras locais de preservação, o CSV e os executáveis versionados. `git lfs fsck --objects --pointers HEAD` passou. Essa verificação local NÃO declara publicação dos commits/objetos no remoto.

| Evidência disponível | Alcance e limite |
| --- | --- |
| `tests/qualidade.tests.ps1` | Define 24 verificações com FFmpeg/ffprobe e fixtures: 96 kbps, inflação, VBR medido inferior, MP3 128, nativo 192 sem alteração, conversão FLAC/Opus, remux AAC, extensão falsa, corrupção, truncamento, fila e legado/órfãos. Não comprova procedência dos vídeos reais. |
| `tests/execucao_unica.tests.ps1` | Cinco cenários em cópias: manifesto na raiz, no controle, não interativo, sem manifesto e documento inválido. Verifica CSV intacto, preservação da fonte, ausência de perguntas de caminho e publicação condicionada à evidência. Transporte/respostas humanas simulados, áudio sintético e ferramentas de mídia reais; não comprova procedência dos vídeos reais. |
| `tests/autenticacao.tests.ps1` | Argumentos/cabeçalho, recuperação limitada, cancelamento, não interativo, 429 e DPAPI com respostas simuladas. Não certifica sessão real utilizável. |
| `tests/ambiente_portatil.tests.ps1` | Raiz/cwd, espaços/acentos, BOM/delimitadores/cabeçalhos e ambiguidade. O roteiro explicita que links simbólicos não foram exercitados. |
| `tests/ferramentas_portateis.tests.ps1` | Executáveis reais, ausência/incompatibilidade e PATH vazio; declara não comprovar Linux/macOS. |
| `tests/integracao_portatil.tests.ps1` | CSV canônico em dois cwd, três delimitadores, argumentos reais especiais e preflight sem ferramenta; auditoria isolada sem rede/navegador. |
| `tests/evidencias_descoberta.tests.ps1` | Descoberta não recursiva na raiz/controle, cwd independente, exemplos/JSON inválido/sem campos, diretórios ausentes/duplicados e ausência de alteração dos documentos. Não atesta a verdade do histórico das fontes. |
| README: ensaio remoto `NBnH864JUZw` | Registra transporte anônimo de WebM/Opus de 6.054.403 bytes, 339,541 s, 48 kHz, dois canais, em fixture isolada. Não prova publicação M4A/MP3, procedência histórica nem conclusão do CSV. |
| README: plataformas/autenticação | Windows/PS7 exercitado; Linux/macOS não executados (WSL indisponível/Docker ausente no ensaio). Chrome falhou com DPAPI em ensaio real. Relatos PS5.1 são históricos e NÃO homologam o principal PS7 atual. |

**[R]** Os roteiros existentes PODEM ser reproduzidos com `pwsh -NoProfile -File ./tests/NOME.tests.ps1` em ambiente preparado. Eles criam fixtures isoladas e NÃO são ação necessária desta entrega documental. Novos recursos DEVEM receber verificações proporcionais ao seu contrato; testes simulados DEVEM ser identificados como tais. Reais downloads, buscas, ambiguidades, alternativas, indisponibilidade, interrupção e reexecução DEVEM ser distinguidos de cobertura sintética antes de homologação integral.

| Lacuna comprovada ou não homologada | Obrigação vigente para futura adequação |
| --- | --- |
| Perguntas por padrão; `-NaoInterativo` depende dos dados prévios | Fluxo ordinário autônomo com alternativas finitas e pendência sem interação; preservar interativo como opção. |
| Nome fixo `yt-dlp.exe` em Unix; sem ensaio Linux/macOS | Resolução condicional nativa e homologação por plataforma, sem presumir execução de PE. |
| Destino/nome sem parâmetros; sem tratamento editorial novo | Parametrização determinística, compatibilidade com padrões e migração sem renomear/perder arquivos válidos. |
| Sem metatags/capa/marcador; validador só admite um stream | Enriquecimento opcional com preservação de fluxo, exceção restrita para imagem e leitura posterior verificável. |
| Seleção automática não audita vocais/versão por si | Garantir pendência quando requisitos musicais não estiverem comprovados; não confundir identidade textual com audição. |
| Manifesto vincula hashes, mas não autentica verdade; mínimo histórico sem validação exaustiva | Exigir evidência suficiente, validar tipos/faixas/contradições e não emitir certificação de fidelidade baseada apenas em declaração. |
| Empates de formato/janelas de crash/relatórios auxiliares não integralmente cobertos | Desempate estável, recuperação rastreável e testes das condições restantes, sem alegações antecipadas. |

**[R] Aceite do RCF:** DEVE ser autossuficiente, referenciado ao código inspecionado, distinguir [A]/[R]/[F], preservar os contratos compatíveis e registrar cada conflito/limite acima. Não depende de infraestrutura imaginada nem de anexos anteriores para compreender as obrigações. Na fase original de criação, somente `RCF.md` era entrega autorizada. A conciliação posterior verifica a integração e atualiza este documento; NÃO declara resolvidas as lacunas funcionais restantes.

**[R] Aceite funcional futuro:** conclusão conforme exige identidade/versão e requisitos musicais comprovados, fonte/histórico adequados vinculados aos bytes, ausência de qualidade artificial, arquivo M4A/MP3 genuíno decodificável com média ≥128, prioridade nativa respeitada, nenhuma conversão indevida, publicação única e recuperável, origem/decisões/rejeições/hash rastreáveis e nenhuma perda dos arquivos válidos. Tags/capa/marcador só PODEM constar como realizados após verificação específica. Fonte inferior, arquivo incompatível/corrompido ou evidência insuficiente NÃO PODEM ser concluídos. Na falta de alternativa legítima, DEVE registrar pendência e continuar os demais itens; nenhuma promessa de autonomia, eficiência ou sucesso DEVE enfraquecer essas barreiras.
