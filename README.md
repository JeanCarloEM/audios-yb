## Execucao atual: PowerShell 7+

~~~powershell
pwsh -NoProfile -File ./baixar_audios_ytdlp.ps1
~~~

Sem -Csv, procura junto do script um unico CSV com as colunas obrigatorias. Zero ou varios candidatos geram diagnostico, sem escolha arbitraria. Com -Csv, basta nome/caminho relativo a pasta do script; absoluto tambem e aceito. A pasta de execucao nao altera CSV, ferramentas, estado ou destino. Opcionalmente, -Destino escolhe outra raiz de saida: relativo parte da pasta do script, absoluto e aceito, e .controle acompanha essa raiz. Sem -Destino, permanece destino/. O CSV e a fonte canonica das URLs e consultas; nao e reescrito.

Mantenha os sete helpers junto do principal: ambiente_portatil.ps1, ferramentas_portateis.ps1, execucao_unica.ps1, evidencias_fonte.ps1, autenticacao_ytdlp.ps1, publicacao_pendente.ps1 e referencia_publicacao.ps1. Virgula, ponto e virgula e tabulacao, UTF-8 com/sem BOM e cabecalhos entre aspas usam o mesmo leitor na descoberta e importacao.

No Windows, yt-dlp.exe continua obrigatorio junto do script. Linux X64 procura yt-dlp_linux e depois yt-dlp adjacentes; Arm64 procura yt-dlp_linux_aarch64 e depois yt-dlp. macOS procura yt-dlp_macos e depois yt-dlp. Demais arquiteturas/sistemas procuram yt-dlp adjacente. Fora do Windows, a ultima opcao e uma aplicacao yt-dlp no PATH; yt-dlp.exe nao e escolhido como alternativa Unix. Nomes oficiais: https://github.com/yt-dlp/yt-dlp#release-files. O generico pode requerer Python; nao instala ferramentas. O primeiro candidato passa pelo teste real de versao: arquitetura/permissoes/dependencias incompatíveis sao erro, sem substituicao silenciosa. Windows PE e rejeitado fora do Windows. FFmpeg/ffprobe usam nome nativo adjacente e depois PATH; Node continua opcional.

O padrao nao consulta perfil, cookie ou executavel de navegador. Conteudo publico e tentado anonimamente. Sessao por navegador e opcional e explicita; arquivo Netscape valido permite autenticacao sem navegador instalado quando indispensavel. Nao ha garantia de acesso a conteudo privado, controles anti-bot ou bloqueios externos, nem autenticacao universal alem dos mecanismos suportados pelo servico.

Validacao atual Windows/PS7: descoberta em dois diretorios, nomes com espacos/acentos, BOM, tres delimitadores e ambiguidade; argumentos especiais reais; ferramentas reais, PATH vazio, executavel ausente/incompativel; falta de yt-dlp nao cria destino; autenticacao simulada, 24 verificacoes de qualidade e fluxo positivo/negativo de execucao unica. Testes em tests/*.tests.ps1. O transporte dos testes automatizados do principal e simulado.

Teste real: NBnH864JUZw, URL da ordem 1 do CSV, baixado sem cookies/leitura de navegador/PATH, com Node.js pelo caminho descoberto. Recebeu 6.054.403 bytes WebM/Opus, 48 kHz, dois canais, 339,541 segundos; hash fisico e CSV intacto conferidos. Arquivo isolado em tests/.runtime-real-anonymous-b1d41a9962b2493faebdcb6c236f69d3/NBnH864JUZw.webm. Comprova transporte nesta maquina; nao certifica procedencia historica, publicacao M4A/MP3, qualidade auditada nem conclusao dos 372 itens.

Validacao Linux realizada em Ubuntu WSL 24.04.1 x86_64, PowerShell 7.6.9 e ferramentas ELF reais: sete roteiros passaram (ambiente, contrato/descoberta de evidencias, aprovacao musical, ordenacao, descoberta de ferramentas e qualidade com 24 verificacoes). A integracao adicional conferiu 372 registros e URLs/ordem contra o CSV canonico, publicou MP3 sintetico 192 kbps com hash preservado, reutilizou sem novo download e rejeitou PE antes de criar destino. Usou cwd externo e nomes com espacos/acentos, sem perguntas/cookies/navegador; metadados e transporte foram simulados. Nao houve novo download remoto. Binarios em /mnt/d ficaram em disk sleep/p9_client_rpc; as mesmas ferramentas funcionaram em /tmp nativo. Preparo e teste usaram a mesma chamada WSL, com provas arquivadas no workspace antes de encerrar; nao se presume persistencia de /tmp. Isso comprova esse escopo Linux, sem homologar toda montagem, arquitetura ou macOS. Validacoes PS5.1 antigas sao historicas; o principal exige PS7+.
## Audio com procedencia e minimo de 128 kbps

```powershell
pwsh -NoProfile -File .\baixar_audios_ytdlp.ps1 -Csv .\coletanea_uber_instrumental_candidatas.csv
```

Uma unica chamada percorre o processamento possivel sem perguntas por padrao. Ambiguidade ou dados insuficientes geram pendencia, sem escolhas ou atestados fabricados. Para escolher candidatos e confirmar artista/musica, versao e ausencia de vocais durante a mesma chamada, use -Interativo. -NaoInterativo permanece compativel; ambos verdadeiros sao rejeitados antes de criar destino. Nenhum modo pede caminho JSON. Diretos, candidatos exatos e reuso exigem as tres confirmacoes explicitas ou aprovacao musical persistida valida; titulo/canal nao substituem conferência real. Arquivos antigos sem essa aprovacao sao preservados e ficam pendentes. Uma aprovacao valida permite reuso apos verificar integridade, sem novo download.

O script nao solicita caminho JSON. Sem -EvidenciasJson, descobre manifestos JSON adjacentes ao script e em destino/.controle, sem recursao e ignorando *.exemplo.json e JSON sem campos de evidencia. Valida esquema, documento local e hashes antes de aceitar cada manifesto. Duplicatas identicas sao reunidas; evidencias conflitantes para a mesma fonte sao excluidas. Ausencia ou rejeicao de evidencia preserva a fonte baixada, registra pendente_qualidade e continua o lote, sem inventar procedencia. -EvidenciasJson continua opcional para indicar um manifesto explicitamente; aprovacoes existentes podem usar -AprovacoesCsv.

Mantenha execucao_unica.ps1 e evidencias_fonte.ps1 junto do principal. O padrao e sem perguntas; -Interativo preserva as confirmacoes humanas como opcao explicita. A descoberta de evidencias funciona em ambos os modos. Informacao ausente permanece pendente; nenhum documento de origem e criado automaticamente.

Mantenha yt-dlp.exe compativel junto do script; FFmpeg/ffprobe usam a descoberta nativa descrita acima. Node.js local e usado quando disponivel. As ferramentas Windows versionadas sao yt-dlp 2026.10.26 e FFmpeg/ffprobe 9.0.2 (build Gyan, fornecedor indicado em https://ffmpeg.org/download.html). Seus hashes estao em `ferramentas.json`; `yt-dlp.exe` esta no Git convencional e `ffmpeg.exe`/`ffprobe.exe` no Git LFS, conforme `.gitattributes`.

### Preservacao e reproducao do repositorio

Instale Git LFS antes de clonar. Em uma copia existente, execute na raiz do repositorio:

```powershell
git lfs install --local
git lfs pull
$manifesto = Get-Content -LiteralPath ./ferramentas.json -Raw | ConvertFrom-Json
foreach ($arquivo in $manifesto.hashes_sha256.PSObject.Properties) {
    $hash = (Get-FileHash -LiteralPath $arquivo.Name -Algorithm SHA256).Hash
    if ($hash -ine $arquivo.Value) { throw "SHA-256 divergente: $($arquivo.Name)" }
}
```

`git lfs pull` requer acesso ao remoto que armazena os objetos LFS; ponteiros sem os objetos nao sao executaveis utilizaveis. Ao publicar commits com esses binarios, preserve tambem seus objetos LFS. Nao substitua os executaveis sem verificar versao, testes e hashes do manifesto.

O `.gitignore` exclui somente `/destino/` (downloads, estado, cache, relatorios e lock de cada lote) e `/tests/.runtime-*/` (fixtures geradas e copias temporarias criadas pelos testes). Esses arquivos continuam no disco. Nao ha exclusao geral por extensao nem do restante de `tests/`: fontes, configuracoes, CSVs, executaveis, arquivos de referencia e evidencias revisadas podem ser versionados. `coletanea_uber_instrumental_candidatas.csv` permanece obrigatoriamente rastreado, com seu conteudo preservado.

`tests/amostra-real.csv` preserva a entrada de um item; `tests/execucao-real.log` e `auditoria_128.log` preservam evidencias historicas revisadas, antes ocultas pelas regras gerais. Registram bloqueio anti-bot e pendencias, nao uma nova execucao nem downloads concluidos. Os caminhos de workspace nesses logs sao referencias historicas, nao dependencias. Novas evidencias uteis devem ser revisadas e guardadas fora das arvores de execucao; nunca inclua cookies, sessoes, tokens ou credenciais no commit.

Somente M4A (AAC/ALAC) e MP3 genuinos podem ser publicados em `destino/`. Fontes comprimidas declaradas ou medidas abaixo de 128 kbps sao rejeitadas. A medicao soma bytes e duracoes dos pacotes de audio, sem contar o tamanho do conteiner como bitrate de audio. Variacao entre pacotes e registrada, sem pressupor que seja prova de VBR ou fidelidade. Fontes realmente sem perdas sao tratadas separadamente; o resultado final tambem exige media medida >=128 kbps, sem padding artificial; um FLAC/ALAC derivado de audio inferior nao recupera qualidade.

Todos os nativos admissiveis precedem remux e transcodificacao. Entre nativos comprimidos, o alvo e o bitrate mais proximo de 128 kbps, sempre por cima. Um nativo de 192/256 kbps nao e recodificado para diminuir tamanho. Sem nativo admissivel, AAC/ALAC/MP3 em outro conteiner usam copia do fluxo quando possivel; outros codecs usam AAC excepcionalmente. A conversao tenta 128 kbps e so sobe para 136/160 se a media medida ficar abaixo do minimo. A fonte original fica preservada no controle. Duracao, canais, amostragem, codec, conteiner, extensao e decodificacao completa sao conferidos antes de publicar.

## Evidencia da fonte

Bitrate, espectrograma e metadados isolados nao provam ausencia de compressao anterior nem equivalencia perceptual entre codecs. Sem documentacao de procedencia suficiente, o resultado e `pendente_qualidade`, mesmo que a medicao ultrapasse 128 kbps. O programa verifica a vinculacao criptografica dos documentos e da fonte; a veracidade do historico exige auditoria externa. Nao preencha o manifesto a partir apenas do bitrate anunciado pelo YouTube.

Copie `evidencias.exemplo.json` para `evidencias.json` e substitua os campos por dados reais de uma auditoria de origem. Cada entrada vincula `video_id`, `formato_id` e SHA-256 do arquivo fonte ao documento que demonstra sua cadeia de geracao e compressao. O documento local tambem precisa ter SHA-256 conferido. `qualidade` admite `perdas_verificadas` ou `sem_perdas_verificada`. `bitrate_minimo_historico_kbps` e o menor bitrate de qualquer etapa comprimida com perdas do historico, nao o bitrate final; zero so e cabivel em uma cadeia integralmente sem perdas documentada. Uma etapa de 92/96 kbps impede conformidade mesmo apos recodificacao a 320 kbps ou empacotamento sem perdas.

A fonte recebida fica em `destino/.controle/fontes/VIDEO/FORMATO.ext`; seu hash e a analise ficam no estado/relatorio, inclusive quando rejeitada. A evidencia precisa corresponder exatamente a esses bytes. Nao ha garantia automatica de qualidade perceptual fornecida por FFmpeg ou pelo manifesto.

## Auditoria e reutilizacao opcional

```powershell
pwsh -NoProfile -File .\baixar_audios_ytdlp.ps1 -Csv .\coletanea_uber_instrumental_candidatas.csv -SomenteAuditarExistentes
```

Esse comando audita o estado local sem consultas remotas. Downloads legados sem conformidade comprovada sao preservados em `destino/.controle/legado/`, com hash e historico, e deixam de contar como concluidos. A migracao e idempotente. Com evidencia real, uma execucao normal pode reavaliar as fontes. Mantenha `estado.json` para preservar rastreabilidade e impedir duplicacoes.

Buscas conservam o criterio de identidade por artista/titulo e pendencia diante de ambiguidades. Aprovacoes de artista/versao/vocais usam `-AprovacoesCsv` e nao substituem evidencia tecnica da fonte. `-ReavaliarPendentes` atualiza buscas. Falhas transitorias recebem as tentativas configuradas na mesma execucao. Bloqueios de acesso/anti-bot sao registrados como pendencias; o script nao garante resolver restricoes externas. A politica de execucao Bypass vale apenas para o processo chamado.

`destino/.controle/relatorio.csv` e `pendencias.csv` refletem o CSV atual; `estado.json` guarda origem, analises, evidencia, conversao, hashes e rejeicoes por formato. Arquivos de trabalho e resultados nao admissiveis ficam fora dos resultados finais.

## Marcador de coletanea em MP3

~~~powershell
pwsh -NoProfile -File ./baixar_audios_ytdlp.ps1 -Marcador '  MINHA COLETÂNEA  '
~~~

`-Marcador` e opcional e nao exige caminhos adicionais. Mantenha `editorial_audio.ps1` junto do principal para usar a opcao; o helper e carregado somente quando o valor nao e vazio. Sem marcador ou com apenas espacos, o fluxo anterior permanece. O CSV de entrada continua sendo a fonte canonica das URLs.

Em novos MP3 admissiveis, o valor e normalizado em Unicode NFC, trim e capitalizacao invariante (`Minha coletânea`). FFmpeg copia o audio e os metadados para um candidato ID3v2.3 separado; ffprobe relê o campo adicional `format.tags.marcador_coletanea`. Antes de publicar, o script exige tags restantes preservadas, mesmo payload comprimido SHA-256, codec/duracao/canais/amostragem/bitrate medido compativeis e decodificacao integral. A auditoria guarda o hash da fonte e o hash dos bytes finais separadamente. Falha editorial preserva o audio admissivel e registra limitacao.

No reuso, o mesmo marcador ja existente e apenas confirmado, sem reescrever ou duplicar o audio. Se o campo estiver ausente ou tiver valor diferente, o arquivo publicado permanece intacto: esta versao registra `limitacao` em `marcador_reuso` do registro e acrescenta o motivo ao relatorio. A aplicacao posterior a arquivo ja publicado e o acrescimo de multiplos valores ainda nao estao disponiveis.

Escopo comprovado: Windows/PowerShell 7, MP3 e leitura por FFmpeg/ffprobe. Marcador em M4A, exibicao em players GUI e execucao deste enriquecimento em Linux/macOS nao foram homologados. A opcao nao substitui aprovacao musical, evidencia de origem ou disponibilidade do servico. Nomeacao musical e metatags editoriais gerais sao opcionais; a publicacao possui journal e retomada nos limites documentados abaixo. Capa e aderencia integral ao RCF continuam pendentes.

Verificacao: `tests/marcador_cli.tests.ps1` e executavel com `pwsh -NoProfile -File ./tests/marcador_cli.tests.ps1`. Ele reutiliza o harness de execucao unica com midia/ferramentas/provas sinteticas reais e transporte/aprovacoes simulados, verifica publicacao e duas retomadas offline (igual/conflitante), hash/tamanho do estado, campo lido e CSV preservado. Tambem passaram cinco cenarios de publicacao e as 24 verificacoes de qualidade existentes. Os testes de helpers com `-FixtureRoot` dependem da fixture e do executor de producao preparados pelo wrapper; nao sao comandos avulsos sem essa preparacao.

## Verificacao executada

O principal atual requer PowerShell 7+. Nesta revisao, testes locais em Windows/PowerShell 7 verificaram: fontes de 96 kbps, bitrate inflado, VBR nominal superior com media inferior a 128, MP3 CBR 128, nativo 192 preservado byte a byte, FLAC documentado convertido, Opus documentado convertido, remux AAC, extensao falsa, corrupcao, ordenacao dos formatos, truncamento perante a duracao esperada e migracao/reexecucao de legado. O roteiro `tests/qualidade.tests.ps1` esta versionado. A suite atual passou nas 24 verificacoes em PowerShell 7 apos a integracao do marcador. O fluxo principal tambem foi exercitado com transporte simulado e documento/hash reais da fixture, incluindo publicacao e reexecucao sem duplicacao.

As fixtures sinteticas tem historico conhecido porque sao geradas localmente para o teste. Isso nao comprova a procedencia dos videos reais do CSV. A aprovacao manual de identidade e a autenticidade de documentos externos nao foram homologadas por esses testes.

O teste tests/execucao_unica.tests.ps1 verifica o fluxo principal em copias isoladas no PowerShell 7: CSV descoberto automaticamente a partir de outro diretorio, quatro respostas de selecao/aprovacao e nenhuma pergunta de caminho. Manifesto local valido junto do script ou no controle permite auditoria e publicacao na mesma chamada; ausencia de manifesto em lote de dois registros e documento com hash invalido preservam a fonte e registram pendencias sem publicar. O caso NaoInterativo confirma zero downloads/perguntas sem aprovacao. A fixture MP3 e sintetica e o hash esperado vem de sua geracao independente; FFmpeg/ffprobe reais. Dados remotos e transporte sao simulados: nao homologa disponibilidade nem procedencia dos videos reais. Selecao e as tres confirmacoes usam -Interativo; cenarios adicionais verificam o padrao sem flags e conflito de modos antes de efeitos.

## Autenticacao do YouTube

Mantenha autenticacao_ytdlp.ps1 junto dos outros helpers e do script principal. Para usar uma sessao escolhida explicitamente desde o inicio:

~~~powershell
.\baixar_audios_ytdlp.ps1 -Csv .\coletanea_uber_instrumental_candidatas.csv -CookiesNavegador chrome
~~~

O parametro -CookiesArquivo 'C:\caminho\youtube-cookies.txt' aceita cookies Netscape exportados da sessao autorizada, como alternativa a -CookiesNavegador. Os dois parametros sao mutuamente exclusivos. Nao compartilhe o conteudo dos cookies em relatorios ou chats.

Se ocorrer login/anti-bot ou Failed to decrypt with DPAPI, o modo interativo pede uma sessao opcional: arquivo:CAMINHO ou navegador:NOME. O mesmo pedido e repetido dentro da execucao atual, com uma unica recuperacao global e no maximo tres entradas invalidas. Vazio cancela. -NaoInterativo nao pergunta nem escolhe sessao automaticamente; parametros explicitos continuam disponiveis. Persistindo o bloqueio, as demais consultas sao suspensas.

No teste real desta maquina, a extracao direta do Chrome falhou com DPAPI antes do download. Esse caminho ainda depende de uma sessao utilizavel; nao e comprovado pelos testes com transporte simulado. A correcao nao modifica a protecao do navegador. A alternativa por arquivo exige cookies validos e pode continuar sujeita a restricoes do YouTube. Consulte a [FAQ oficial](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp) e o [registro do erro DPAPI](https://github.com/yt-dlp/yt-dlp/issues/10927).

O teste tests/autenticacao.tests.ps1 cobre argv, cabecalho Netscape, recuperacao limitada na mesma chamada, reutilizacao da sessao, cancelamento, modo nao interativo, HTTP 429 e DPAPI, com respostas remotas simuladas. Qualidade, auditoria e publicacao continuam exigindo as evidencias descritas acima.


## Publicacao com checkpoint e retomada

Depois das validacoes de identidade, aprovacao musical, procedencia e audio, o fluxo principal grava uma intencao imutavel em destino/.controle/publicacoes_pendentes/ e confirma sua referencia, com hash externo, no estado em disco antes de mover o resultado. A publicacao valida novamente os dados e o audio, move sem sobrescrever, salva o resultado e somente entao remove a referencia pendente. O journal permanece como evidencia; sua presenca isolada nao autoriza recuperar um arquivo.

Na inicializacao seguinte, as referencias persistidas sao reconciliadas antes da auditoria de legado. Falhas preservam os arquivos e ficam como pendente_auditoria, sem repetir formatos/downloads do mesmo item naquela execucao. A auditoria protege os arquivos vinculados; referencia cujo destino nao possa ser identificado exige preservacao conservadora. -SomenteAuditarExistentes preserva as pendencias, sem concluir publicacao. Nao apague estado/lock como procedimento de recuperacao. Isso nao garante recuperacao de toda falha de armazenamento ou janela de crash.

Evidencias Windows: tests/publicacao_produtor_cli.tests.ps1 verificou referencia duravel antes do movimento, publicacao normal, falha real de I/O apos o movimento e retomada offline sem novo transporte/perguntas. tests/publicacao_retomada_cli.tests.ps1 verificou recuperacao na inicializacao e protecao durante auditoria. tests/estado_duravel.tests.ps1 verificou serializacao recusada antes de efeitos, escrita/substituicao e preservacao de temporario alheio em colisao real de CreateNew; o controle negativo detectou o escritor anterior a correcao f303115. Midia, ferramentas e filesystem reais; transporte e confirmacoes musicais simulados.

A versao 7ad976f foi tambem executada no Ubuntu WSL 24.04.1, PS7.6.9, com ferramentas ELF em /tmp: referencia/journal/hash, publicacao MP3 sintetica, reuso sem novo download, CSV canonico de 372 linhas e rejeicao de PE foram confirmados. As provas locais ficam em tests/.runtime-publication-linux-current/ (ignorado pelo Git). A correcao posterior f303115 de propriedade do temporario foi testada no Windows; nao foi reexecutada nesse ensaio Linux. Nao houve novo download remoto nem homologacao de macOS ou aderencia integral ao RCF.

## Nomeação musical opcional

O padrão continua sendo `-ModeloNome Legado`: `Ordem - Artista - Musica [ID].ext`, a partir do CSV canônico. Para selecionar a convenção musical, declare as colunas cujo significado foi conferido. Quando `Musica` contém o título musical:

```powershell
pwsh -NoProfile -File ./baixar_audios_ytdlp.ps1 -ModeloNome Musical -ColunaTitulo Musica
```

`-ColunaAutor`, `-ColunaTrack` e `-ColunaTitulo` recebem nomes literais de colunas do mesmo CSV; a comparação distingue maiúsculas/minúsculas. Autor e faixa não mapeados são omitidos. Não se presume que `Artista` seja compositor nem que `Ordem` seja faixa: qualquer equivalência exige declaração e conferência. Os componentes presentes seguem `Autor - Track - Titulo [ID].ext`, com sanitização e limites de caminho existentes.

`-LarguraTrack` é opcional: aceita 1..145, preenche zeros somente quando informada e nunca trunca números maiores. Sem largura, não há padding automático. Em modo Musical, título insuficiente ou mapeamento inválido mantém o nome legado e registra `nomeacao.pendente_editorial=true`. O estado e o journal guardam o modelo, as colunas declaradas e o motivo. Arquivos válidos já publicados conservam nome e áudio mesmo com opções diferentes no reuso.

Mantenha `nomeacao_editorial.ps1` e `mapeamento_nomeacao.ps1` junto do principal para usar Musical; seu carregamento é condicional. Isso não muda a descoberta do CSV, sua função canônica para URLs, as aprovações ou a qualidade exigida, nem grava tags ou capas.

Verificação Windows/PowerShell 7+: cinco cenários de publicação, journal e reuso offline preservaram nome e hashes de CSV/áudio, sem novo transporte ou perguntas no reuso. Foi usada mídia MP3 sintética real com transporte e confirmações simulados. Esses novos parâmetros não foram ensaiados em Linux/macOS; não houve novo download remoto nem comprovação de 372 downloads.
