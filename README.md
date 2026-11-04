# Audio com procedencia e minimo de 128 kbps

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\baixar_audios_ytdlp.ps1 -Csv .\coletanea_uber_instrumental_candidatas.csv
```

Uma unica chamada percorre busca, selecao, download, validacao e publicacao. Quando houver ambiguidade, escolha o indice exibido (a partir de zero) e confirme artista/musica, versao e ausencia de vocais com tres respostas SIM. O processo continua imediatamente, sem gerar uma etapa obrigatoria de reexecucao.

Se faltar procedencia, o script primeiro baixa a fonte e exibe seu ID, formato e SHA-256. Informe o caminho do manifesto JSON real nessa mesma execucao; ele e validado antes da publicacao. Ha ate tres tentativas para corrigir o caminho/documento. Enter cancela a confirmacao daquele item e registra a pendencia. Um manifesto previamente disponivel pode ser fornecido por `-EvidenciasJson`; aprovacoes existentes podem usar `-AprovacoesCsv`.

Mantenha `execucao_unica.ps1` e `evidencias_fonte.ps1` ao lado do principal. `-NaoInterativo` desativa as perguntas: forneca previamente as aprovacoes/evidencias necessarias; informacao ausente permanece pendente, sem aprovacao automatica. A execucao unica permite intervencao humana durante o processo e nao cria documentos de origem inexistentes.

Coloque `yt-dlp.exe`, `ffprobe.exe` e `ffmpeg.exe` junto do script. Node.js local e usado quando disponivel. As ferramentas incluidas neste ambiente sao yt-dlp 2026.10.26 e FFmpeg/ffprobe 9.0.2 (build Gyan, fornecedor indicado em https://ffmpeg.org/download.html). Seus hashes estao em `ferramentas.json`; os executaveis permanecem ignorados pelo Git.

Somente M4A (AAC/ALAC) e MP3 genuinos podem ser publicados em `destino/`. Fontes comprimidas declaradas ou medidas abaixo de 128 kbps sao rejeitadas. A medicao soma bytes e duracoes dos pacotes de audio, sem contar o tamanho do conteiner como bitrate de audio. Variacao entre pacotes e registrada, sem pressupor que seja prova de VBR ou fidelidade. Fontes realmente sem perdas sao tratadas separadamente; o resultado final tambem exige media medida >=128 kbps, sem padding artificial; um FLAC/ALAC derivado de audio inferior nao recupera qualidade.

Todos os nativos admissiveis precedem remux e transcodificacao. Entre nativos comprimidos, o alvo e o bitrate mais proximo de 128 kbps, sempre por cima. Um nativo de 192/256 kbps nao e recodificado para diminuir tamanho. Sem nativo admissivel, AAC/ALAC/MP3 em outro conteiner usam copia do fluxo quando possivel; outros codecs usam AAC excepcionalmente. A conversao tenta 128 kbps e so sobe para 136/160 se a media medida ficar abaixo do minimo. A fonte original fica preservada no controle. Duracao, canais, amostragem, codec, conteiner, extensao e decodificacao completa sao conferidos antes de publicar.

## Evidencia da fonte

Bitrate, espectrograma e metadados isolados nao provam ausencia de compressao anterior nem equivalencia perceptual entre codecs. Sem documentacao de procedencia suficiente, o resultado e `pendente_qualidade`, mesmo que a medicao ultrapasse 128 kbps. O programa verifica a vinculacao criptografica dos documentos e da fonte; a veracidade do historico exige auditoria externa. Nao preencha o manifesto a partir apenas do bitrate anunciado pelo YouTube.

Copie `evidencias.exemplo.json` para `evidencias.json` e substitua os campos por dados reais de uma auditoria de origem. Cada entrada vincula `video_id`, `formato_id` e SHA-256 do arquivo fonte ao documento que demonstra sua cadeia de geracao e compressao. O documento local tambem precisa ter SHA-256 conferido. `qualidade` admite `perdas_verificadas` ou `sem_perdas_verificada`. `bitrate_minimo_historico_kbps` e o menor bitrate de qualquer etapa comprimida com perdas do historico, nao o bitrate final; zero so e cabivel em uma cadeia integralmente sem perdas documentada. Uma etapa de 92/96 kbps impede conformidade mesmo apos recodificacao a 320 kbps ou empacotamento sem perdas.

A fonte recebida fica em `destino/.controle/fontes/VIDEO/FORMATO.ext`; seu hash e a analise ficam no estado/relatorio, inclusive quando rejeitada. A evidencia precisa corresponder exatamente a esses bytes. Nao ha garantia automatica de qualidade perceptual fornecida por FFmpeg ou pelo manifesto.

## Auditoria e reutilizacao opcional

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\baixar_audios_ytdlp.ps1 -Csv .\coletanea_uber_instrumental_candidatas.csv -SomenteAuditarExistentes
```

Esse comando audita o estado local sem consultas remotas. Downloads legados sem conformidade comprovada sao preservados em `destino/.controle/legado/`, com hash e historico, e deixam de contar como concluidos. A migracao e idempotente. Com evidencia real, uma execucao normal pode reavaliar as fontes. Mantenha `estado.json` para preservar rastreabilidade e impedir duplicacoes.

Buscas conservam o criterio de identidade por artista/titulo e pendencia diante de ambiguidades. Aprovacoes de artista/versao/vocais usam `-AprovacoesCsv` e nao substituem evidencia tecnica da fonte. `-ReavaliarPendentes` atualiza buscas. Falhas transitorias recebem as tentativas configuradas na mesma execucao. Bloqueios de acesso/anti-bot sao registrados como pendencias; o script nao garante resolver restricoes externas. A politica de execucao Bypass vale apenas para o processo chamado.

`destino/.controle/relatorio.csv` e `pendencias.csv` refletem o CSV atual; `estado.json` guarda origem, analises, evidencia, conversao, hashes e rejeicoes por formato. Arquivos de trabalho e resultados nao admissiveis ficam fora dos resultados finais.

## Verificacao executada

Testes locais em PowerShell 5.1 e 7: fontes de 96 kbps, bitrate inflado, VBR nominal superior com media inferior a 128, MP3 CBR 128, nativo 192 preservado byte a byte, FLAC documentado convertido, Opus documentado convertido, remux AAC, extensao falsa, corrupcao, ordenacao dos formatos, truncamento perante a duracao esperada e migracao/reexecucao de legado. O roteiro `tests/qualidade.tests.ps1` esta versionado. Passaram 24 verificacoes em cada versao de PowerShell. O fluxo principal tambem foi exercitado com transporte simulado e documento/hash reais da fixture, incluindo publicacao e reexecucao sem duplicacao.

As fixtures sinteticas tem historico conhecido porque sao geradas localmente para o teste. Isso nao comprova a procedencia dos videos reais do CSV. A aprovacao manual de identidade e a autenticidade de documentos externos nao foram homologadas por esses testes.

O teste `tests/execucao_unica.tests.ps1` confirmou o fluxo principal em copias isoladas, em PowerShell 5.1 e 7: busca ambigua, tres confirmacoes, um download simulado, manifesto fornecido depois do download, auditoria e publicacao na mesma chamada. O MP3 e sintetico e a validacao usa FFmpeg/ffprobe reais; o hash final corresponde a fixture independente. O caso negativo com `-NaoInterativo` confirmou zero downloads e nenhuma publicacao sem aprovacao. Dados remotos e transporte sao simulados; isso nao homologa disponibilidade nem procedencia dos videos reais.

## Autenticacao do YouTube

Mantenha autenticacao_ytdlp.ps1 junto dos outros helpers e do script principal. Para usar uma sessao escolhida explicitamente desde o inicio:

~~~powershell
.\baixar_audios_ytdlp.ps1 -Csv .\coletanea_uber_instrumental_candidatas.csv -CookiesNavegador chrome
~~~

O parametro -CookiesArquivo 'C:\caminho\youtube-cookies.txt' aceita cookies Netscape exportados da sessao autorizada, como alternativa a -CookiesNavegador. Os dois parametros sao mutuamente exclusivos. Nao compartilhe o conteudo dos cookies em relatorios ou chats.

Se ocorrer login/anti-bot ou Failed to decrypt with DPAPI, o modo interativo pede uma sessao: navegador:chrome ou arquivo:C:\caminho\youtube-cookies.txt. O mesmo pedido e repetido dentro da execucao atual, com uma unica recuperacao global e no maximo tres entradas invalidas. Vazio cancela. -NaoInterativo nao pergunta nem escolhe sessao automaticamente; parametros explicitos continuam disponiveis. Persistindo o bloqueio, as demais consultas sao suspensas.

No teste real desta maquina, a extracao direta do Chrome falhou com DPAPI antes do download. Esse caminho ainda depende de uma sessao utilizavel; nao e comprovado pelos testes com transporte simulado. A correcao nao modifica a protecao do navegador. A alternativa por arquivo exige cookies validos e pode continuar sujeita a restricoes do YouTube. Consulte a [FAQ oficial](https://github.com/yt-dlp/yt-dlp/wiki/FAQ#how-do-i-pass-cookies-to-yt-dlp) e o [registro do erro DPAPI](https://github.com/yt-dlp/yt-dlp/issues/10927).

O teste tests/autenticacao.tests.ps1 cobre argv, cabecalho Netscape, recuperacao limitada na mesma chamada, reutilizacao da sessao, cancelamento, modo nao interativo, HTTP 429 e DPAPI, com respostas remotas simuladas. Qualidade, auditoria e publicacao continuam exigindo as evidencias descritas acima.