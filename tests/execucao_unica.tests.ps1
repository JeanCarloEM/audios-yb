#requires -Version 7.0
param(
 [ValidateSet('positivo','controle','nao_interativo','sem_manifesto','manifesto_invalido')]
 [ValidateCount(1,5)]
 [string[]]$Modes=@('positivo','controle','nao_interativo','sem_manifesto','manifesto_invalido')
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
 $items=@('TestVideo01','TestVideo02')|ForEach-Object {@{id=$_;titulo='Artista - Faixa';canal='Artista - Topic';pontuacao=100;url=('https://www.youtube.com/watch?v='+$_)}}
 return @{ok=$true;items=@($items);tentativas=1}
}
function Get-Info([string]$Id) {
 $info=[pscustomobject]@{id=$Id;title='Artista - Faixa';channel='Artista - Topic';uploader='Artista';artist='Artista';track='Faixa';duration=4}
 $fmt=@{id='128';ext='mp3';codec='mp3';abr=128;tier=0;quality=0;operacao='nativo';filesize=(Get-Item -LiteralPath $script:E2E.fixture).Length;duracao_origem=4}
 return @{ok=$true;info=$info;formats=@($fmt);run=@{tentativas=1}}
}
function Invoke-Checked([string[]]$Arguments,[int]$Timeout=100) {
 $i=[array]::IndexOf($Arguments,'--output')
 if($i -lt 0){throw 'Consulta remota inesperada no teste'}
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
 $config=@{repo=$repo;fixture=$fixture;hash=$hash;no_input=($mode -eq 'nao_interativo');reads=0;downloads=0;log=(Join-Path $case 'contadores.json')}
 [IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
 $csv=Join-Path $case 'faixas.csv'
 $rows=@([pscustomobject]@{Ordem='1';Artista='Artista';Musica='Faixa';Link_YouTube='https://www.youtube.com/results?search_query=Artista+Faixa';Tipo_link='Busca';Verificacao='Fixture';Observacoes='Fixture sintetica'})
 if($mode -eq 'sem_manifesto'){ $second=$rows[0].PSObject.Copy(); $second.Ordem='2'; $rows+= $second }
 $rows|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
 $csvHash=(Get-FileHash -LiteralPath $csv).Hash
 if($mode -in @('positivo','controle','manifesto_invalido')){
  $doc=Join-Path $case 'origem.txt'
  [IO.File]::WriteAllText($doc,'Fixture sintetica: PCM local codificado uma unica vez em MP3 CBR128 para este teste.')
  $entry=@{video_id='TestVideo01';formato_id='128';sha256=$hash;documento='origem.txt';documento_sha256=(Get-FileHash -LiteralPath $doc).Hash.ToLowerInvariant();origem='Fixture sintetica gerada localmente com FFmpeg';historico='PCM local sintetico codificado uma unica vez em MP3 CBR128';qualidade='perdas_verificadas';bitrate_minimo_historico_kbps=128}
  if($mode -eq 'manifesto_invalido'){$entry.documento_sha256=('0'*64)}
  $manifestDir=$case
  if($mode -eq 'controle'){ $manifestDir=Join-Path $case 'destino/.controle'; [void][IO.Directory]::CreateDirectory($manifestDir) }
  [IO.File]::WriteAllText((Join-Path $manifestDir 'manifesto-real-fixture.json'),(@($entry)|ConvertTo-Json -Depth 8))
 }
 Push-Location $work
 try{ & $scriptPath -NaoInterativo:($mode -eq 'nao_interativo'); $caseExit=$LASTEXITCODE }finally{Pop-Location}
 if((Get-FileHash -LiteralPath $csv).Hash -ne $csvHash){throw 'CSV canonico foi alterado'}
 if($caseExit -ne 0){throw ('Falha do processo de teste: '+$caseExit)}
 $dest=Join-Path $case 'destino'
 $state=Get-Content -LiteralPath (Join-Path $dest '.controle\estado.json') -Raw|ConvertFrom-Json
 $records=@($state.registros.PSObject.Properties.Value)
 $record=$records[0]
 $counts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
 $finals=@(Get-ChildItem -LiteralPath $dest -File|Where-Object {$_.Extension -in @('.mp3','.m4a')})
 if($mode -in @('positivo','controle')){
  if($record.resultado -ne 'baixado'){throw ('Nao publicou: '+$record.motivo)}
  if($counts.downloads -ne 1 -or $counts.reads -ne 4 -or $finals.Count -ne 1){throw 'Contagens incorretas na execucao unica'}
  if(-not $record.auditoria.validado -or $record.criterio_selecao -ne 'aprovacao_na_execucao'){throw 'Auditoria/selecao nao comprovada'}
  if((Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant() -ne $hash){throw 'Nativo foi alterado'}
 }elseif($mode -eq 'nao_interativo'){
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
 Write-Output ('PASS E2E '+$mode+' downloads='+$counts.downloads+' leituras='+$counts.reads)
}
Write-Output 'EXECUCAO_UNICA_E2E_PASS'
