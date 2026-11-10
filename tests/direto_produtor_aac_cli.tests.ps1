#requires -Version 7.0
param(
 [ValidateSet('direto_interativo')]
 [ValidateCount(1,1)]
 [string[]]$Modes=@('direto_interativo')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo=Split-Path $PSScriptRoot -Parent
$work=Join-Path $PSScriptRoot ('.runtime-direto-aac-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$fixture=Join-Path $work 'fixture.m4a'
& (Join-Path $repo 'ffmpeg.exe') -nostdin -v error -f lavfi -i 'anoisesrc=sample_rate=44100:duration=4:seed=1' -ac 2 -c:a aac -b:a 256k -n $fixture
if($LASTEXITCODE -ne 0){throw 'Falha ao gerar fixture independente'}
$hash=(Get-FileHash -LiteralPath $fixture).Hash.ToLowerInvariant()
$source=[IO.File]::ReadAllText((Join-Path $repo 'baixar_audios_ytdlp.ps1'))
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Sintaxe de producao invalida'}
$mainTry=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})
if($mainTry.Count -ne 1){throw 'Bloco principal ambiguo'}
$mocks=@'
$script:E2E=To-Hashtable (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'cenario.json') -Raw|ConvertFrom-Json)
$script:Ffmpeg=Join-Path $script:E2E.repo 'ffmpeg.exe'
$script:Ffprobe=Join-Path $script:E2E.repo 'ffprobe.exe'
$script:Exe=Join-Path $script:E2E.repo 'yt-dlp.exe'
function Resolve-ScriptTools([string]$Root) {
 return @{Exe=(Join-Path $script:E2E.repo 'yt-dlp.exe');Ffmpeg=(Join-Path $script:E2E.repo 'ffmpeg.exe');Ffprobe=(Join-Path $script:E2E.repo 'ffprobe.exe');Node=''}
}
function Save-E2E { [IO.File]::WriteAllText($script:E2E.log,($script:E2E|ConvertTo-Json -Depth 8)) }
function Search-Candidates([string]$Query,[string]$Artist,[string]$Song) {
 if($script:E2E.offline){$script:E2E.remotes++;Save-E2E;throw 'Consulta remota proibida na retomada'}
 $ids=if($script:E2E.unique){@('TestVideo01')}else{@('TestVideo01','TestVideo02')}
 $items=@($ids)|ForEach-Object {@{id=$_;titulo='Artista - Faixa';canal='Artista - Topic';pontuacao=100;url=('https://www.youtube.com/watch?v='+$_)}}
 return @{ok=$true;items=@($items);tentativas=1}
}
function Get-Info([string]$Id) {
 if($script:E2E.offline){$script:E2E.remotes++;Save-E2E;throw 'Metadados remotos proibidos na retomada'}
 $info=[pscustomobject]@{id=$Id;title='Artista - Faixa';channel='Artista - Topic';uploader='Artista';artist='Artista';track='Faixa';duration=4}
 if($script:E2E.variant -ne 'legacy_csv'){
  $info.title='Entrevista com voz';$info.channel='Canal de entrevistas';$info.uploader='Apresentador';$info.artist='';$info.track=''
 }
 if($script:E2E.variant -eq 'bad_id'){$info.id='testVideo01'}
 $fmt=@{id='256';ext='m4a';codec='aac';abr=256;tier=0;quality=0;operacao='nativo';filesize=(Get-Item -LiteralPath $script:E2E.fixture).Length;duracao_origem=4}
 $formatItems=@($fmt)
 if($script:E2E.fallback){$upper=$fmt.Clone();$upper.id='A';$lower=$fmt.Clone();$lower.id='a';$formatItems=@($upper,$lower)}
 return @{ok=$true;info=$info;formats=$formatItems;run=@{tentativas=1}}
}
function Invoke-Checked([string[]]$Arguments,[int]$Timeout=100) {
 $i=[array]::IndexOf($Arguments,'--output')
 if($i -lt 0){throw 'Consulta remota inesperada no teste'}
 if($script:E2E.fallback){
  $formatIndex=[array]::IndexOf($Arguments,'--format')
  if($formatIndex -lt 0){throw 'Formato ausente no download'}
  $requestedFormat=[string]$Arguments[$formatIndex+1]
  $script:E2E.formatCalls+= $requestedFormat;Save-E2E
  if($requestedFormat -ceq 'A'){return @{code=1;diagnostico='formato_indisponivel';tentativas=1;out='';err='Fixture A indisponivel';timeout=$false}}
 }
 $target=$Arguments[$i+1].Replace('%(ext)s','m4a')
 if($Arguments -notcontains '--no-overwrites'){throw 'Contrato de idempotencia ausente'}
 if([IO.File]::Exists($target)){
  if((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -ne $script:E2E.hash){throw 'Fixture existente alterada'}
  return @{code=0;tentativas=1;out='already downloaded';err='';timeout=$false}
 }
 [IO.File]::Copy($script:E2E.fixture,$target,$false)
 $script:E2E.downloads++;Save-E2E
 return @{code=0;tentativas=1;out='';err='';timeout=$false}
}
function Read-InRunValue([string]$Prompt,[switch]$NonInteractive,[scriptblock]$ReadInput) {
 if($script:E2E.no_input){throw 'Leitura indevida no caso nao interativo'}
 if($Prompt -match '(?i)caminho|json|path'){throw ('Pergunta de caminho proibida: '+$Prompt)}
 $script:E2E.reads++;Save-E2E
 if($script:E2E.fixed){return 'SIM'}
 if(($script:E2E.reads % 4) -eq 1){return '0'}
 return 'SIM'
}
Save-E2E
'@
$testSource=$source.Insert($mainTry[0].Extent.StartOffset,$mocks+[Environment]::NewLine)
$t=$null;$e=$null
[void][Management.Automation.Language.Parser]::ParseInput($testSource,[ref]$t,[ref]$e)
if($e.Count){throw ($e|Out-String)}
foreach($variant in @('legacy_csv','technical','bad_id','missing_evidence')){
foreach($mode in $Modes){
 $case=Join-Path $work ($variant+'-'+$mode)
 [void][IO.Directory]::CreateDirectory($case)
 foreach($helper in @(Get-ChildItem -LiteralPath $repo -File -Filter '*.ps1'|Where-Object Name -cne 'baixar_audios_ytdlp.ps1')){[IO.File]::Copy($helper.FullName,(Join-Path $case $helper.Name),$false)}
 $scriptPath=Join-Path $case 'baixar_audios_ytdlp.ps1'
 [IO.File]::WriteAllText($scriptPath,$testSource,(New-Object Text.UTF8Encoding -ArgumentList $true))
 $config=@{variant=$variant;repo=$repo;fixture=$fixture;hash=$hash;no_input=$true;unique=($mode -eq 'auto_sem_aprovacao');fixed=($mode -in @('direto_interativo','retomada_musical','formatos_case_sensitive'));fallback=($mode -eq 'formatos_case_sensitive');formatCalls=@();offline=$false;remotes=0;reads=0;downloads=0;log=(Join-Path $case 'contadores.json')}
 [IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
 $csv=Join-Path $case 'faixas.csv'
 $rows=@([pscustomobject]@{Ordem='1';Artista='Artista';Musica='Faixa';Link_YouTube='https://www.youtube.com/results?search_query=Artista+Faixa';Tipo_link='Busca';Verificacao='Fixture';Observacoes='Fixture sintetica'})
 if($mode -eq 'sem_manifesto'){ $second=$rows[0].PSObject.Copy(); $second.Ordem='2'; $rows+= $second }
 if($mode -in @('direto_sem_aprovacao','direto_interativo','retomada_musical','formatos_case_sensitive')){$rows[0].Link_YouTube='https://www.youtube.com/watch?v=TestVideo01';$rows[0].Tipo_link='Direto'}
 $rows|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
 $csvHash=(Get-FileHash -LiteralPath $csv).Hash
 $approvalCsv=Join-Path $case 'aprovacoes.csv'
 if($variant -eq 'legacy_csv'){[pscustomobject]@{Ordem='1';VideoId='TestVideo01';ArtistaMusicaConferidos='SIM';VersaoConferida='SIM';SemVocaisConferido='SIM'}|Export-Csv -LiteralPath $approvalCsv -NoTypeInformation -Encoding UTF8}
 if($variant -ne 'missing_evidence'){
  $doc=Join-Path $case 'origem.txt'
  [IO.File]::WriteAllText($doc,'Fixture sintetica: PCM local codificado uma unica vez em AAC 256k para este teste.')
  $entry=@{video_id='TestVideo01';formato_id='256';sha256=$hash;documento='origem.txt';documento_sha256=(Get-FileHash -LiteralPath $doc).Hash.ToLowerInvariant();origem='Fixture sintetica gerada localmente com FFmpeg';historico='PCM local sintetico codificado uma unica vez em AAC 256k';qualidade='perdas_verificadas';bitrate_minimo_historico_kbps=128}
  if($mode -eq 'formatos_case_sensitive'){$entry.formato_id='a'}
  if($mode -eq 'manifesto_invalido'){$entry.documento_sha256=('0'*64)}
  $manifestDir=$case
  if($mode -eq 'controle'){ $manifestDir=Join-Path $case 'destino/.controle'; [void][IO.Directory]::CreateDirectory($manifestDir) }
  [IO.File]::WriteAllText((Join-Path $manifestDir 'manifesto-real-fixture.json'),(@($entry)|ConvertTo-Json -Depth 8))
 }
 Push-Location $work
 try{
  if($variant -eq 'legacy_csv'){ & $scriptPath -AprovacoesCsv $approvalCsv }else{ & $scriptPath }
  $caseExit=$LASTEXITCODE
 }finally{Pop-Location}
 if((Get-FileHash -LiteralPath $csv).Hash -ne $csvHash){throw 'CSV canonico foi alterado'}
 if($mode -eq 'conflito_modos'){
  if($caseExit -ne 2 -or (Test-Path -LiteralPath (Join-Path $case 'destino'))){throw 'Conflito de modos nao falhou antes de efeitos'}
  $global:LASTEXITCODE=0
  Write-Output 'PASS E2E conflito_modos exit=2 sem destino'
  continue
 }
 if($caseExit -ne 0){throw ('Falha do processo de teste: '+$caseExit)}
 $dest=Join-Path $case 'destino'
 $state=Get-Content -LiteralPath (Join-Path $dest '.controle\estado.json') -Raw|ConvertFrom-Json
 $records=@($state.registros.PSObject.Properties.Value)
 $record=$records[0]
 $counts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
 $finals=@(Get-ChildItem -LiteralPath $dest -File|Where-Object {$_.Extension -in @('.mp3','.m4a')})
 if($records.Count -ne 1 -or $counts.reads -ne 0){throw 'Registro/pergunta divergente'}
 if($variant -in @('legacy_csv','technical')){
  if($record.resultado -cne 'baixado' -or $counts.downloads -ne 1 -or $finals.Count -ne 1 -or $record.codec -cne 'aac' -or -not $record.auditoria.validado){throw ('Nao publicou AAC validado: '+$record.motivo)}
  if((Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant() -cne $hash){throw 'Nativo alterado'}
  $sections=@($record,$state.videos.TestVideo01,$record.auditoria,$state.videos.TestVideo01.auditoria)
  foreach($section in $sections){
   if($variant -eq 'technical'){
    if($section.PSObject.Properties.Name -contains 'aprovacao_musical' -or $section.selecao_tecnica.versao -ne 2 -or $section.selecao_tecnica.video_id -cne 'TestVideo01' -or $section.selecao_tecnica.metadados.title -cne 'Entrevista com voz' -or $section.selecao_tecnica.PSObject.Properties.Name -contains 'sem_vocais_conferido'){throw 'Prova v2 perdida ou flags humanas fabricadas'}
   }elseif(-not $section.aprovacao_musical.sem_vocais_conferido){throw 'Legado explicito nao preservado'}
  }
  $criterion=if($variant -eq 'technical'){'url_direta_id_literal'}else{'aprovacao_manual'}
  if($record.criterio_selecao -cne $criterion){throw 'Criterio de selecao divergente'}
  if(@($state.publicacoes_pendentes.PSObject.Properties).Count -ne 0){throw 'Referencia pendente apos publicar'}
  $journals=@(Get-ChildItem -LiteralPath (Join-Path $dest '.controle/publicacoes_pendentes') -File -Filter '*.json')
  if($journals.Count -ne 1 -or (Get-FileHash -LiteralPath $journals[0].FullName).Hash.ToLowerInvariant() -cne $state.videos.TestVideo01.publicacao_intencao.sha256){throw 'Journal/rastro divergente'}
 }elseif($variant -eq 'bad_id'){
  if($record.resultado -cne 'falha' -or $counts.downloads -ne 0 -or $finals.Count -ne 0){throw 'ID divergente autorizou transporte'}
 }else{
  if($record.resultado -cne 'pendente_qualidade' -or $counts.downloads -ne 1 -or $finals.Count -ne 0 -or $record.auditoria.validado){throw 'Ausencia de origem autorizou publicacao'}
  $kept=Join-Path $dest '.controle/fontes/TestVideo01/256.m4a'
  if((Get-FileHash -LiteralPath $kept).Hash.ToLowerInvariant() -cne $hash -or $record.selecao_tecnica.versao -ne 2){throw 'Fonte/prova nao preservada'}
 }
 if((Get-FileHash -LiteralPath $fixture).Hash.ToLowerInvariant() -cne $hash -or (Get-FileHash -LiteralPath $csv).Hash -cne $csvHash){throw 'Fonte/CSV alterados'}
 $canonicalUrls=@((Import-Csv -LiteralPath $csv).Link_YouTube)
 if($record.url_original -notin $canonicalUrls){throw 'URL divergiu da fonte canonica'}
 if(-not (Test-Path -LiteralPath (Join-Path $dest '.controle/relatorio.csv'))){throw 'Relatorio ausente'}
 @{variant=$variant;result=$record.resultado;downloads=$counts.downloads;reads=$counts.reads;source_sha256=$hash;csv_sha256=$csvHash;scope='CLI real/fixture AAC e evidencia sinteticas; transporte simulado; novos IDs diretos somente'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $case 'prova-tecnica.json') -Encoding utf8
 Write-Output ('PASS DIRETO_AAC '+$variant+' '+$record.resultado)
 if($variant -in @('legacy_csv','technical')){
  $statePath=Join-Path $dest '.controle/estado.json'
  $baseline=[IO.File]::ReadAllText($statePath)
  $published=$finals[0].FullName
  $reuseCases=if($variant -eq 'technical'){@('valid','bad_proof_id','null_proof_with_legacy','missing_document')}else{@('valid')}
  foreach($reuseCase in $reuseCases){
   $inputState=ConvertFrom-Json $baseline
   $v=$inputState.videos.TestVideo01
   $savedRecord=@($inputState.registros.PSObject.Properties.Value)[0]
   $options=@{}
   if($reuseCase -eq 'bad_proof_id'){$v.selecao_tecnica.video_id='testVideo01'}
   if($reuseCase -eq 'null_proof_with_legacy'){
    $v.selecao_tecnica=$null
    $human=[pscustomobject]@{versao=1;video_id='TestVideo01';artista='Artista';musica='Faixa';artista_musica_conferidos=$true;versao_conferida=$true;sem_vocais_conferido=$true;origem='arquivo_aprovacoes'}
    $v|Add-Member -NotePropertyName aprovacao_musical -NotePropertyValue $human -Force
    $savedRecord|Add-Member -NotePropertyName aprovacao_musical -NotePropertyValue $human -Force
    [pscustomobject]@{Ordem='1';VideoId='TestVideo01';ArtistaMusicaConferidos='SIM';VersaoConferida='SIM';SemVocaisConferido='SIM'}|Export-Csv -LiteralPath $approvalCsv -NoTypeInformation -Encoding UTF8
    $options.AprovacoesCsv=$approvalCsv
   }
   [IO.File]::WriteAllText($statePath,($inputState|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
   $config.offline=$true;$config.remotes=0;$config.downloads=0;$config.reads=0
   [IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
   $document=Join-Path $case 'origem.txt';$parked=Join-Path $case 'origem-preservada.txt'
   if($reuseCase -eq 'missing_document'){[IO.File]::Move($document,$parked)}
   $log=Join-Path $case ('reuso-'+$reuseCase+'.log')
   try{& $scriptPath @options *> $log;$reuseExit=$LASTEXITCODE}
   finally{if($reuseCase -eq 'missing_document'){[IO.File]::Move($parked,$document)}}
   if($reuseExit -ne 0){throw ('Falha CLI no reuso: '+$log)}
   $afterState=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
   $afterRecord=@($afterState.registros.PSObject.Properties.Value)[0]
   $offlineCounts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
   $expectedStatus=if($reuseCase -eq 'valid'){'existente'}elseif($reuseCase -eq 'missing_document'){'pendente_qualidade'}else{'pendente_auditoria'}
   if($afterRecord.resultado -cne $expectedStatus -or $offlineCounts.downloads -ne 0 -or $offlineCounts.reads -ne 0 -or $offlineCounts.remotes -ne 0){throw ('Reuso offline divergiu: '+$reuseCase+' '+$afterRecord.resultado+' '+$afterRecord.motivo)}
   if((Get-FileHash -LiteralPath $published).Hash.ToLowerInvariant() -cne $hash -or (Get-FileHash -LiteralPath $csv).Hash -cne $csvHash -or @(Get-ChildItem -LiteralPath $dest -File|Where-Object Extension -eq '.m4a').Count -ne 1){throw 'Reuso alterou ou duplicou arquivo/CSV'}
   if($reuseCase -eq 'valid'){
    foreach($section in @($afterRecord,$afterState.videos.TestVideo01,$afterRecord.auditoria,$afterState.videos.TestVideo01.auditoria)){
     if($variant -eq 'technical'){
     if($section.PSObject.Properties.Name -contains 'aprovacao_musical' -or $section.selecao_tecnica.versao -ne 2 -or $section.selecao_tecnica.video_id -cne 'TestVideo01'){throw 'Reuso perdeu prova tecnica ou fabricou aprovacao'}
     }elseif($section.aprovacao_musical.versao -ne 1 -or -not $section.aprovacao_musical.sem_vocais_conferido){throw 'Reuso legado perdeu prova v1'}
    }
   }
   @{variant=$reuseCase;result=$afterRecord.resultado;downloads=$offlineCounts.downloads;reads=$offlineCounts.reads;remotes=$offlineCounts.remotes;sha256=$hash;scope='reuso offline com AAC real e provas sinteticas'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $case ('prova-reuso-'+$reuseCase+'.json')) -Encoding utf8
   Write-Output ('PASS REUSO_AAC '+$reuseCase+' '+$afterRecord.resultado)
  }
 }
}
}
'DIRETO_AAC_CLI_TECHNICAL_PASS; '+$work
