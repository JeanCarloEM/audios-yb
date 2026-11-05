#requires -Version 7.0
param(
 [ValidateSet('positivo','controle','nao_interativo','sem_manifesto','manifesto_invalido','autonomo','conflito_modos','direto_sem_aprovacao','auto_sem_aprovacao','direto_interativo','retomada_musical','formatos_case_sensitive')]
 [ValidateCount(1,12)]
 [string[]]$Modes=@('positivo','controle','nao_interativo','sem_manifesto','manifesto_invalido','autonomo','conflito_modos','direto_sem_aprovacao','auto_sem_aprovacao','direto_interativo','retomada_musical','formatos_case_sensitive')
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo=Split-Path $PSScriptRoot -Parent
$work=Join-Path $PSScriptRoot ('.runtime-e2e-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$fixture=Join-Path $work 'fixture.mp3'
& (Join-Path $repo 'ffmpeg.exe') -nostdin -v error -f lavfi -i 'anoisesrc=sample_rate=44100:duration=4:seed=1' -ac 2 -c:a libmp3lame -b:a 128k -n $fixture
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
 $fmt=@{id='128';ext='mp3';codec='mp3';abr=128;tier=0;quality=0;operacao='nativo';filesize=(Get-Item -LiteralPath $script:E2E.fixture).Length;duracao_origem=4}
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
 $target=$Arguments[$i+1].Replace('%(ext)s','mp3')
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
foreach($mode in $Modes){
 $case=Join-Path $work $mode
 [void][IO.Directory]::CreateDirectory($case)
 foreach($name in @('execucao_unica.ps1','evidencias_fonte.ps1','autenticacao_ytdlp.ps1','ambiente_portatil.ps1','ferramentas_portateis.ps1')){[IO.File]::Copy((Join-Path $repo $name),(Join-Path $case $name),$false)}
 $scriptPath=Join-Path $case 'baixar_audios_ytdlp.ps1'
 [IO.File]::WriteAllText($scriptPath,$testSource,(New-Object Text.UTF8Encoding -ArgumentList $true))
 $config=@{repo=$repo;fixture=$fixture;hash=$hash;no_input=($mode -in @('nao_interativo','autonomo','conflito_modos','direto_sem_aprovacao','auto_sem_aprovacao'));unique=($mode -eq 'auto_sem_aprovacao');fixed=($mode -in @('direto_interativo','retomada_musical','formatos_case_sensitive'));fallback=($mode -eq 'formatos_case_sensitive');formatCalls=@();offline=$false;remotes=0;reads=0;downloads=0;log=(Join-Path $case 'contadores.json')}
 [IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
 $csv=Join-Path $case 'faixas.csv'
 $rows=@([pscustomobject]@{Ordem='1';Artista='Artista';Musica='Faixa';Link_YouTube='https://www.youtube.com/results?search_query=Artista+Faixa';Tipo_link='Busca';Verificacao='Fixture';Observacoes='Fixture sintetica'})
 if($mode -eq 'sem_manifesto'){ $second=$rows[0].PSObject.Copy(); $second.Ordem='2'; $rows+= $second }
 if($mode -in @('direto_sem_aprovacao','direto_interativo','retomada_musical','formatos_case_sensitive')){$rows[0].Link_YouTube='https://www.youtube.com/watch?v=TestVideo01';$rows[0].Tipo_link='Direto'}
 $rows|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
 $csvHash=(Get-FileHash -LiteralPath $csv).Hash
 if($mode -in @('positivo','controle','manifesto_invalido','direto_interativo','retomada_musical','formatos_case_sensitive')){
  $doc=Join-Path $case 'origem.txt'
  [IO.File]::WriteAllText($doc,'Fixture sintetica: PCM local codificado uma unica vez em MP3 CBR128 para este teste.')
  $entry=@{video_id='TestVideo01';formato_id='128';sha256=$hash;documento='origem.txt';documento_sha256=(Get-FileHash -LiteralPath $doc).Hash.ToLowerInvariant();origem='Fixture sintetica gerada localmente com FFmpeg';historico='PCM local sintetico codificado uma unica vez em MP3 CBR128';qualidade='perdas_verificadas';bitrate_minimo_historico_kbps=128}
  if($mode -eq 'formatos_case_sensitive'){$entry.formato_id='a'}
  if($mode -eq 'manifesto_invalido'){$entry.documento_sha256=('0'*64)}
  $manifestDir=$case
  if($mode -eq 'controle'){ $manifestDir=Join-Path $case 'destino/.controle'; [void][IO.Directory]::CreateDirectory($manifestDir) }
  [IO.File]::WriteAllText((Join-Path $manifestDir 'manifesto-real-fixture.json'),(@($entry)|ConvertTo-Json -Depth 8))
 }
 Push-Location $work
 try{
  if($mode -in @('autonomo','direto_sem_aprovacao','auto_sem_aprovacao')){ & $scriptPath }
  elseif($mode -eq 'conflito_modos'){ & $scriptPath -Interativo -NaoInterativo }
  else{ & $scriptPath -NaoInterativo:($mode -eq 'nao_interativo') -Interativo:($mode -ne 'nao_interativo') }
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
 if($mode -in @('positivo','controle','direto_interativo','retomada_musical','formatos_case_sensitive')){
  $expectedReads=if($mode -in @('direto_interativo','retomada_musical','formatos_case_sensitive')){3}else{4}
  if($record.resultado -ne 'baixado'){throw ('Nao publicou: '+$record.motivo)}
  if($counts.downloads -ne 1 -or $counts.reads -ne $expectedReads -or $finals.Count -ne 1){throw 'Contagens incorretas na execucao unica'}
  if(-not $record.auditoria.validado -or $record.criterio_selecao -ne 'aprovacao_na_execucao'){throw 'Auditoria/selecao nao comprovada'}
  if((Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant() -ne $hash){throw 'Nativo foi alterado'}
  if(-not $record.aprovacao_musical.sem_vocais_conferido -or -not $state.videos.TestVideo01.aprovacao_musical.versao_conferida){throw 'Aprovacao musical nao persistida'}
  if($mode -eq 'formatos_case_sensitive'){
   if(($counts.formatCalls -join '|') -cne 'A|a'){throw 'ID literal repetido ou descartado na fila'}
   if(@($record.rejeicoes|Where-Object {$_.formato_id -ceq 'A' -and $_.diagnostico -eq 'formato_indisponivel'}).Count -ne 1){throw 'Rejeicao de formato nao rastreada'}
  }
 }elseif($mode -in @('nao_interativo','autonomo','direto_sem_aprovacao','auto_sem_aprovacao')){
  if($record.resultado -ne 'pendente_auditoria' -or $counts.downloads -ne 0 -or $counts.reads -ne 0 -or $finals.Count -ne 0){throw 'Caso negativo aprovou sem confirmacao'}
 }else{
  $expectedCount=if($mode -eq 'sem_manifesto'){2}else{1}
  if($records.Count -ne $expectedCount -or $counts.reads -ne (4*$expectedCount) -or $counts.downloads -lt 1 -or $finals.Count -ne 0){throw 'Lote sem evidencia nao continuou corretamente'}
  foreach($r in $records){if($r.resultado -ne 'pendente_qualidade' -or $r.auditoria.validado){throw 'Fonte sem documento valido foi atestada'}}
  $keptSource=Join-Path $dest '.controle/fontes/TestVideo01/128.mp3'
  if(-not [IO.File]::Exists($keptSource) -or (Get-FileHash -LiteralPath $keptSource).Hash.ToLowerInvariant() -ne $hash){throw 'Fonte nao preservada'}
 }
 $canonicalUrls=@((Import-Csv -LiteralPath $csv).Link_YouTube)
 foreach($r in $records){if($r.url_original -notin $canonicalUrls){throw 'URL divergiu do CSV canonico'}}
 if(-not (Test-Path -LiteralPath (Join-Path $dest '.controle\relatorio.csv'))){throw 'Relatorio ausente'}
 if($mode -eq 'retomada_musical'){
  $statePath=Join-Path $dest '.controle/estado.json'
  $baselineJson=[IO.File]::ReadAllText($statePath)
  $preservedFile=$finals[0].FullName
  $variants=@(
   @{name='prova_persistida';status='existente';reads=0},
   @{name='legado_sem_prova';legacy=$true;status='pendente_auditoria';reads=0},
   @{name='legado_aprovado_csv';legacy=$true;csv=$true;status='existente';reads=0},
   @{name='aprovacao_incompleta';csv=$true;partial=$true;status='pendente_auditoria';reads=0},
   @{name='id_caixa_diferente';csv=$true;wrongid=$true;status='falha';reads=0},
   @{name='prova_inconsistente';badproof=$true;status='pendente_auditoria';reads=0},
   @{name='hash_inconsistente';badhash=$true;status='pendente_qualidade';reads=0},
   @{name='legado_interativo';legacy=$true;interactive=$true;status='existente';reads=3}
  )
  foreach($v in $variants){
   $inputState=ConvertFrom-Json $baselineJson
   $video=$inputState.videos.TestVideo01
   $savedRecord=@($inputState.registros.PSObject.Properties.Value)[0]
   if($v.legacy){
    $video.PSObject.Properties.Remove('aprovacao_musical')
    $savedRecord.PSObject.Properties.Remove('aprovacao_musical')
    $video.auditoria.PSObject.Properties.Remove('aprovacao_musical')
    $savedRecord.auditoria.PSObject.Properties.Remove('aprovacao_musical')
   }
   if($v.badproof){$video.aprovacao_musical.video_id='testVideo01'}
   if($v.badhash){$video.sha256=('0'*64)}
   [IO.File]::WriteAllText($statePath,(ConvertTo-Json $inputState -Depth 30))
   $config.no_input=-not [bool]$v.interactive
   $config.offline=$true;$config.remotes=0;$config.reads=0;$config.downloads=0
   [IO.File]::WriteAllText((Join-Path $case 'cenario.json'),(ConvertTo-Json $config -Depth 8))
   $options=@{}
   if($v.interactive){$options.Interativo=$true}
   if($v.csv){
    $ap=[pscustomobject]@{Ordem='1';VideoId='TestVideo01';ArtistaMusicaConferidos='SIM';VersaoConferida='SIM';SemVocaisConferido='SIM'}
    if($v.partial){$ap.SemVocaisConferido='NAO'}
    if($v.wrongid){$ap.VideoId='testVideo01'}
    $ap|Export-Csv -LiteralPath (Join-Path $case 'aprovacoes.csv') -NoTypeInformation -Encoding UTF8
    $options.AprovacoesCsv='aprovacoes.csv'
   }
   $variantLog=Join-Path $case ($v.name+'.log')
   & $scriptPath @options *> $variantLog
   if($LASTEXITCODE -ne 0){throw ('Retomada fatal: '+$v.name+' '+(Get-Content $variantLog -Tail 8|Out-String))}
   $afterState=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
   $afterRecord=@($afterState.registros.PSObject.Properties.Value)[0]
   $variantCounts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
   if($afterRecord.resultado -ne $v.status -or $variantCounts.downloads -ne 0 -or $variantCounts.reads -ne $v.reads -or $variantCounts.remotes -ne 0){throw ('Retomada divergiu: '+$v.name+' '+$afterRecord.resultado+' '+$afterRecord.motivo)}
   if($v.wrongid -and $afterRecord.motivo -notmatch 'ID da URL direta'){throw 'Erro de ID nao causal'}
   if(-not [IO.File]::Exists($preservedFile) -or (Get-FileHash -LiteralPath $preservedFile).Hash.ToLowerInvariant() -ne $hash){throw 'Retomada alterou ou moveu audio valido'}
   if(@(Get-ChildItem -LiteralPath $dest -File|Where-Object {$_.Extension -in @('.mp3','.m4a')}).Count -ne 1){throw 'Retomada duplicou audio'}
   if((Get-FileHash -LiteralPath $csv).Hash -ne $csvHash){throw 'Retomada alterou CSV canonico'}
   if($v.status -eq 'existente' -and -not $afterState.videos.TestVideo01.aprovacao_musical.sem_vocais_conferido){throw 'Reuso sem prova persistida'}
   Write-Output ('PASS RETOMADA '+$v.name+' '+$afterRecord.resultado+' downloads=0 leituras='+$variantCounts.reads+' remotes=0')
  }
 }
 Write-Output ('PASS E2E '+$mode+' downloads='+$counts.downloads+' leituras='+$counts.reads)
}
Write-Output 'EXECUCAO_UNICA_E2E_PASS'
