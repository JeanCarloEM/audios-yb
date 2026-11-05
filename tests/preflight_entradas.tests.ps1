#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo=Split-Path $PSScriptRoot -Parent
$work=Join-Path $PSScriptRoot ('.runtime-preflight-inputs-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$source=[IO.File]::ReadAllText((Join-Path $repo 'baixar_audios_ytdlp.ps1'))
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Producao invalida'}
$main=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})
if($main.Count -ne 1){throw 'Entrada principal ambigua'}
$mocks=@'
$script:FixtureRepo=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'repo.txt'))
function Resolve-ScriptTools([string]$Root){return @{Exe=(Join-Path $script:FixtureRepo 'yt-dlp.exe');Ffmpeg=(Join-Path $script:FixtureRepo 'ffmpeg.exe');Ffprobe=(Join-Path $script:FixtureRepo 'ffprobe.exe');Node=''}}
function Invoke-Checked {throw 'NETWORK_FORBIDDEN_PREFLIGHT'}
'@
$testSource=$source.Insert($main[0].Extent.StartOffset,$mocks+[Environment]::NewLine)
function Snapshot([string]$Directory){
 if(-not [IO.Directory]::Exists($Directory)){return @('ABSENT')}
 return @(Get-ChildItem -LiteralPath $Directory -Recurse -Force|ForEach-Object {
  if($_.PSIsContainer){'D|'+$_.FullName}else{'F|'+$_.FullName+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash}
 }|Sort-Object)
}
foreach($kind in @('csv_vazio','aprovacao_ausente','aprovacao_cabecalho','aprovacao_duplicada','evidencia_invalida')){
 $case=Join-Path $work $kind
 [void][IO.Directory]::CreateDirectory($case)
 foreach($helper in @('ambiente_portatil.ps1','ferramentas_portateis.ps1','execucao_unica.ps1','evidencias_fonte.ps1','autenticacao_ytdlp.ps1')){[IO.File]::Copy((Join-Path $repo $helper),(Join-Path $case $helper))}
 [IO.File]::WriteAllText((Join-Path $case 'repo.txt'),$repo)
 $scriptPath=Join-Path $case 'baixar_audios_ytdlp.ps1'
 [IO.File]::WriteAllText($scriptPath,$testSource,[Text.UTF8Encoding]::new($true))
 $csv=Join-Path $case 'entrada.csv'
 $row=[pscustomobject]@{Ordem='1';Artista='Fixture';Musica='Faixa';Link_YouTube='https://www.youtube.com/watch?v=TestVideo01';Tipo_link='Direto';Verificacao='Teste';Observacoes='Sem rede'}
 if($kind -eq 'csv_vazio'){[IO.File]::WriteAllText($csv,'Ordem,Artista,Musica,Link_YouTube,Tipo_link,Verificacao,Observacoes'+[Environment]::NewLine)}
 else{$row|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8}
 $options=@{}
 $expectedReason=''
 if($kind -like 'aprovacao_*'){
  $options.AprovacoesCsv='aprovacoes.csv'
  $expectedReason='aprovacoes'
  if($kind -eq 'aprovacao_cabecalho'){[pscustomobject]@{Ordem='1';VideoId='TestVideo01'}|Export-Csv -LiteralPath (Join-Path $case 'aprovacoes.csv') -NoTypeInformation -Encoding UTF8}
  if($kind -eq 'aprovacao_duplicada'){
   $ap=[pscustomobject]@{Ordem='1';VideoId='TestVideo01';ArtistaMusicaConferidos='SIM';VersaoConferida='SIM';SemVocaisConferido='SIM'}
   @($ap,$ap)|Export-Csv -LiteralPath (Join-Path $case 'aprovacoes.csv') -NoTypeInformation -Encoding UTF8
   $expectedReason='duplicada'
  }
 }
 if($kind -eq 'csv_vazio'){$expectedReason='CSV vazio'}
 if($kind -eq 'evidencia_invalida'){
  $options.EvidenciasJson='evidencia.json'
  $ev=@{video_id='TestVideo01';formato_id='140';sha256=('0'*64);origem='Origem sintetica de teste';historico='Historico sintetico usado somente no teste de esquema';qualidade='perdas_verificadas';bitrate_minimo_historico_kbps=96;documento='nao-necessario.txt';documento_sha256=('0'*64)}
  [IO.File]::WriteAllText((Join-Path $case 'evidencia.json'),(ConvertTo-Json -InputObject @($ev) -Depth 8))
  $expectedReason='bitrate_minimo_historico_kbps'
 }
 $dest=Join-Path $case 'destino'
 if($kind -like 'aprovacao_*'){
  $control=Join-Path $dest '.controle';[void][IO.Directory]::CreateDirectory($control)
  [IO.File]::WriteAllBytes((Join-Path $dest 'antigo.mp3'),[byte[]]((0..255)*12))
  $state=@{versao=1;registros=@{};buscas=@{};videos=@{TestVideo01=@{arquivo='antigo.mp3';artista='Fixture';musica='Faixa';auditoria=@{politica='legado';validado=$false}}}}
  [IO.File]::WriteAllText((Join-Path $control 'estado.json'),(ConvertTo-Json $state -Depth 12))
 }
 $before=Snapshot $dest
 $csvHash=(Get-FileHash -LiteralPath $csv).Hash
 $log=Join-Path $case 'run.log'
 & $scriptPath @options *> $log
 $runExit=$LASTEXITCODE
 if($runExit -ne 2){throw ('Preflight nao rejeitou '+$kind+' exit='+$runExit)}
 if(@(Compare-Object $before (Snapshot $dest)).Count){throw ('Preflight alterou destino/legado: '+$kind)}
 if((Get-FileHash -LiteralPath $csv).Hash -ne $csvHash){throw 'CSV canonico alterado'}
 if(([IO.File]::ReadAllText($log)) -notmatch [regex]::Escape($expectedReason)){throw ('Rejeicao nao causal '+$kind)}
 Write-Output ('PASS PREFLIGHT '+$kind+' exit=2 destino e estado intactos')
}
$global:LASTEXITCODE=0
'RCF_PREFLIGHT_INPUTS_PASS: 5 causas globais, sem rede e sem efeitos do lote'
