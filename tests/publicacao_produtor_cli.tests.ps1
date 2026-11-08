#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$harness=Join-Path $repo 'tests/execucao_unica.tests.ps1'
if((Get-FileHash -LiteralPath $harness).Hash -cne '63917D9605ECBC278F57327DE88176403E2C51C588C2E1E44827425EA146CB9F'){throw 'Harness mudou: revisar produtor'}
$source=[IO.File]::ReadAllText($harness)
function Replace-ProducerTestLiteral([string]$Text,[string]$Before,[string]$After){
 if(([regex]::Matches($Text,[regex]::Escape($Before))).Count -ne 1){throw 'Ancora do teste de produtor ausente/ambigua'}
 return $Text.Replace($Before,$After)
}
$source=Replace-ProducerTestLiteral $source '$repo=Split-Path $PSScriptRoot -Parent' ('$repo='+"'"+$repo.Replace("'","''")+"'"+[Environment]::NewLine+'$publicationFaultRequested=($env:AUDIOS_YB_PUBLICATION_TEST_MODE -eq ''fault'')')
$extraMocks=@'
$script:OriginalPublicationRecoveryBody=(Get-Command Invoke-PublicationRecovery -CommandType Function).ScriptBlock
function Invoke-PublicationRecovery {
 param([string]$ReferenceName,[string]$Control,[string]$Out)
 if($env:AUDIOS_YB_PUBLICATION_TEST_MODE -eq 'off'){
  & $script:OriginalPublicationRecoveryBody -ReferenceName $ReferenceName -Control $Control -Out $Out
  return
 }
 $reference=Read-PersistedPublicationReference -ReferenceName $ReferenceName -Control $Control -Out $Out
 $journal=Read-PublicationIntentFile -Path (Join-Path (Join-Path $Control 'publicacoes_pendentes') $ReferenceName) -ExpectedSha256 $reference.sha256 -Control $Control
 $readyPath=Join-Path $Control $journal.Data.pronto_relativo
 $targetPath=Join-Path $Out $journal.Data.arquivo
 if(-not [IO.File]::Exists($readyPath) -or [IO.File]::Exists($targetPath)){throw 'Produtor nao confirmou checkpoint ANTES do Move'}
 [IO.File]::WriteAllText((Join-Path $Control 'producer-before-move.checked'),$reference.sha256,[Text.UTF8Encoding]::new($false))
 if($env:AUDIOS_YB_PUBLICATION_TEST_MODE -eq 'fault'){
  $env:AUDIOS_YB_PUBLICATION_TEST_MODE='off'
  $deny=[IO.File]::Open($script:StateFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{& $script:OriginalPublicationRecoveryBody -ReferenceName $ReferenceName -Control $Control -Out $Out}
  finally{$deny.Dispose()}
 }else{
  & $script:OriginalPublicationRecoveryBody -ReferenceName $ReferenceName -Control $Control -Out $Out
 }
}
'@
$insert='$testSource=$source.Insert($mainTry[0].Extent.StartOffset,$mocks+[Environment]::NewLine)'
$inject='$mocks += [Environment]::NewLine + '+"'"+$extraMocks.Replace("'","''")+"'"+[Environment]::NewLine+$insert
$source=Replace-ProducerTestLiteral $source $insert $inject
# A ancora e construida sem escapes de shell; valor literal original do harness.
$statusCheck='  if($record.resultado -ne ''baixado''){throw (''Nao publicou: ''+$record.motivo)}'
$newStatus='  if($publicationFaultRequested){if($record.resultado -ne ''pendente_auditoria''){throw ''Falha IO nao ficou pendente''}}else{'+$statusCheck.Trim()+'}'
$source=Replace-ProducerTestLiteral $source $statusCheck $newStatus
$hook=@'
 if($mode -ne 'direto_interativo'){throw 'Modo inesperado no teste de produtor'}
 . (Join-Path $repo 'publicacao_pendente.ps1')
 $statePath=Join-Path $dest '.controle/estado.json'
 $produced=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($statePath))
 $control=Join-Path $dest '.controle'
 $proofPath=Join-Path $control 'producer-before-move.checked'
 if(-not [IO.File]::Exists($proofPath)){throw 'Nao verificou checkpoint real antes do Move'}
 if($publicationFaultRequested){
  if($produced.publicacoes_pendentes.Count -ne 1){throw 'IO apos Move perdeu referencia'}
  $reference=@($produced.publicacoes_pendentes.Values)[0]
 }else{
  if($produced.publicacoes_pendentes.Count -ne 0 -or $produced.videos.TestVideo01.publicacao_intencao.situacao -cne 'concluida'){throw 'Publicacao normal nao concluiu checkpoint'}
  $reference=$produced.videos.TestVideo01.publicacao_intencao
 }
 $journal=Read-PublicationIntentFile -Path (Join-Path (Join-Path $control 'publicacoes_pendentes') $reference.arquivo) -ExpectedSha256 $reference.sha256 -Control $control
 if([IO.File]::ReadAllText($proofPath) -cne $reference.sha256 -or $journal.Data.registro.url_original -cne (Import-Csv -LiteralPath $csv)[0].Link_YouTube -or $journal.Data.registro.video_id -cne 'TestVideo01'){throw 'Journal/recibo difere do CSV canonico'}
 $config.no_input=$true;$config.offline=$true;$config.remotes=0;$config.reads=0;$config.downloads=0
 [IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
 $env:AUDIOS_YB_PUBLICATION_TEST_MODE='off'
 & $scriptPath -NaoInterativo
 if($LASTEXITCODE -ne 0){throw 'Retomada/reuso apos produtor falhou'}
 $finished=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($statePath))
 $afterCounts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
 if($finished.publicacoes_pendentes.Count -ne 0 -or $finished.videos.TestVideo01.publicacao_intencao.situacao -cne 'concluida' -or $afterCounts.downloads -ne 0 -or $afterCounts.remotes -ne 0 -or $afterCounts.reads -ne 0 -or (Get-FileHash -LiteralPath $csv).Hash -cne $csvHash -or (Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant() -cne $hash){throw 'Produtor repetiu transporte/perguntas, alterou CSV/audio ou perdeu trace'}
 Write-Output ('PUBLICATION_PRODUCER_CASE_PASS: fault='+$publicationFaultRequested)
'@
$finish=" Write-Output ('PASS E2E '+"+'$mode'+"+' downloads='+"+'$counts.downloads'+"+' leituras='+"+'$counts.reads'+")"
$source=Replace-ProducerTestLiteral $source $finish ($hook+[Environment]::NewLine+$finish)
$t=$null;$e=$null
[void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Clone do produtor invalido'}
$work=Join-Path $PSScriptRoot ('.runtime-producer-cli-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$clone=Join-Path $work 'execucao_produtor.ps1'
[IO.File]::WriteAllText($clone,$source,[Text.UTF8Encoding]::new($false))
. (Join-Path $repo 'tests/processo_capturado.ps1')
$previousMode=$env:AUDIOS_YB_PUBLICATION_TEST_MODE
try{
 foreach($testMode in @('normal','fault')){
  $env:AUDIOS_YB_PUBLICATION_TEST_MODE=$testMode
  $r=Invoke-CapturedTestProcess -Program (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoProfile','-File',$clone,'-Modes','direto_interativo') -TimeoutMs 180000
  $log=Join-Path $work ($testMode+'.log')
  [IO.File]::WriteAllText($log,($r.Stdout+[Environment]::NewLine+$r.Stderr),[Text.UTF8Encoding]::new($false))
  if($r.ExitCode -ne 0 -or -not $r.Stdout.Contains('PUBLICATION_PRODUCER_CASE_PASS')){throw ('Caso produtor falhou: '+$log)}
 }
}finally{$env:AUDIOS_YB_PUBLICATION_TEST_MODE=$previousMode}
'PUBLICATION_PRODUCER_CLI_PASS: normal e IO real apos Move; checkpoint antes do Move; sem transporte extra; Windows'
