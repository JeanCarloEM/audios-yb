#requires -Version 7.0
param([switch]$V3Only)
$ErrorActionPreference='Stop'
# Regressao AAC real v2/v1 incluindo falha de Save-State existente.
if($V3Only){
 # Reutiliza somente setup e New-RecoveryFixture, sem repetir testes aprovados.
 $fixtureScriptsRoot=$PSScriptRoot
 $harness=Join-Path $fixtureScriptsRoot 'intencao_reconciliacao.tests.ps1'
 if((Get-FileHash $harness).Hash -cne '82E512CE7A9ED0379BC28AF8B4E080B4AA20629FBBAFBC5ED233C744B44517F0'){throw 'Harness alterado'}
 $text=[IO.File]::ReadAllText($harness)
 $ht=$null;$he=$null;$ha=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$ht,[ref]$he)
 $block=@($ha.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst] -and $_.Extent.Text.Contains("New-RecoveryFixture -Name 'not-persisted'")})
 if($he.Count -or $block.Count -ne 1){throw 'Checkpoint setup ambiguo'}
 $setup=$text.Substring(0,$block[0].Extent.StartOffset).Replace('$PSScriptRoot','$fixtureScriptsRoot')
 . ([scriptblock]::Create($setup))
}else{
 . (Join-Path $PSScriptRoot 'intencao_recuperacao_tecnica.tests.ps1')
}
# Dependencia contratual do caller para Register-PublicationReference.
. (Join-Path $repo 'referencia_publicacao.ps1')
# Fixture literal independente ja aceita no teste do plano; nao executar essa suite.
if((Get-FileHash (Join-Path $PSScriptRoot 'plano_selecao_busca.tests.ps1')).Hash -cne '63D3F0D4A0C975C75F67F21E777A5D9DBC51A4381756AD306C237C75E164C362'){throw 'Origem da fixture alterada'}
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'plano_selecao_busca.tests.ps1'),[ref]$t,[ref]$e)
foreach($name in @('searchUrl','searchProof')){
 $x=@($a.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq $name})
 if($e.Count -or $x.Count -ne 1){throw 'Fixture literal ambigua'}
 . ([scriptblock]::Create($x[0].Extent.Text))
}
function Copy-SearchProof {$searchProof|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable}
function New-SearchRecoveryFixture([string]$Name,[object]$Selection=$searchProof){
 $f=New-RecoveryFixture -Name $Name
 $d=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($f.Intent))
 $d.registro.Remove('aprovacao_musical')
 $d.registro.selecao_tecnica=$Selection;$d.registro.url_original=$searchUrl;$d.registro.tipo_link='Busca'
 $text=[string]::Join([char]31,@($d.registro.ordem.Trim(),$d.registro.artista.Trim(),$d.registro.musica.Trim(),$searchUrl))
 $d.registro.chave=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
 $f.RecordKey=$d.registro.chave
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($d|ConvertTo-Json -Depth 25))
 [IO.File]::WriteAllBytes($f.Intent,$bytes)
 $f.IntentHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
 $script:State.publicacoes_pendentes[$f.Name].sha256=$f.IntentHash
 $script:State.publicacoes_pendentes[$f.Name].registro_chave=$f.RecordKey
 Save-State
 return $f
}
function Assert-SearchState($f){
 $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 $video=$disk.videos.TestVideo01;$rec=$disk.registros[$f.RecordKey]
 foreach($section in @($video,$rec,$video.auditoria,$rec.auditoria)){
  if($section.ContainsKey('aprovacao_musical') -or $section.selecao_tecnica.versao -ne 3 -or $section.selecao_tecnica.referencia.url_original -cne $searchUrl -or $section.selecao_tecnica.metadados.title -cne $searchProof.metadados.title -or $section.selecao_tecnica.candidatos.Count -ne 1 -or $section.selecao_tecnica.ContainsKey('sem_vocais_conferido')){throw 'Contrato v3 perdido/flag fabricada'}
 }
 if($disk.publicacoes_pendentes.Count -ne 0 -or $disk.registros.canary.nota -cne 'historico preservado' -or $video.sha256 -cne $sourceHash -or (Get-FileHash $f.Target).Hash.ToLowerInvariant() -cne $sourceHash -or (Get-FileHash $f.Intent).Hash.ToLowerInvariant() -cne $f.IntentHash){throw 'Hash/journal/historico/referencia divergente'}
 return $disk
}
function Assert-SearchReject($f,[string]$Message){
 $hash=(Get-FileHash $script:StateFile).Hash;$caught=$false
 try{$null=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out}catch [IO.InvalidDataException]{if($_.Exception.Message -notmatch $Message){throw};$caught=$true}
 if(-not $caught -or (Test-Path $f.Target) -or -not (Test-Path $f.Ready) -or (Get-FileHash $script:StateFile).Hash -cne $hash){throw 'Rejeicao teve efeitos'}
}
$n=0
try{
 $f=New-SearchRecoveryFixture 'search-publish'
 $script:State.publicacoes_pendentes.Remove($f.Name);Save-State
 $registered=Register-PublicationReference -Path $f.Intent -ExpectedSha256 $f.IntentHash -Control $script:Control -Out $script:Out
 if($null -eq $registered -or $script:State.publicacoes_pendentes[$f.Name].registro_chave -cne $f.RecordKey){throw 'Registro v3 falhou'};$n++
 $result=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out
 if($result.Action -cne 'publish' -or (Test-Path $f.Ready)){throw 'Publicacao v3 falhou'}
 $disk=Assert-SearchState $f;$completed=$disk.videos.TestVideo01;$n++
 $hash=(Get-FileHash $script:StateFile).Hash
 $result=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out
 if($result.Status -cne 'sem_pendencia' -or (Get-FileHash $script:StateFile).Hash -cne $hash){throw 'Idempotencia falhou'};$n++
 $f=New-SearchRecoveryFixture 'search-existing'
 [IO.File]::Move($f.Ready,$f.Target);$script:State.videos.TestVideo01=$completed;Save-State
 $result=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out
 if($result.Action -cne 'restore_state'){throw 'Estado v3 existente rejeitado'}
 $null=Assert-SearchState $f;$n++
 $f=New-SearchRecoveryFixture 'search-context-conflict'
 $old=$completed|ConvertTo-Json -Depth 25|ConvertFrom-Json -AsHashtable
 $old.selecao_tecnica.referencia.url_original='https://www.youtube.com/results?search_query=AC%2FDC%20iTunes%20DJ'
 $script:State.videos.TestVideo01=$old;Save-State
 Assert-SearchReject $f 'Conflito';$n++
 $bad=Copy-SearchProof;$bad.referencia.consulta='forjada'
 $f=New-SearchRecoveryFixture 'search-invalid' $bad
 Assert-SearchReject $f 'Selecao';$n++
 $f=New-SearchRecoveryFixture 'search-save-failure'
 if($IsWindows){
  $stateLock=[IO.File]::Open($script:StateFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $caught=$false
  try{try{$null=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out}catch{
   $failure=$_.Exception;while($null -ne $failure.InnerException){$failure=$failure.InnerException}
   if($failure -isnot [IO.IOException]){throw};$caught=$true
  }}finally{$stateLock.Dispose()}
  $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
  if(-not $caught -or (Test-Path $f.Ready) -or -not (Test-Path $f.Target) -or $disk.videos.Count -ne 0 -or -not $disk.publicacoes_pendentes.ContainsKey($f.Name)){throw 'Falha Move->State perdeu recuperabilidade'}
  $script:State=$disk
 }else{[IO.File]::Move($f.Ready,$f.Target);'SAVE_FAILURE_NOT_TESTED_NONWINDOWS'}
 $result=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out
 if($result.Action -cne 'restore_state'){throw 'Retomada apos falha nao restaurou estado'}
 $null=Assert-SearchState $f;$n++
 if((Get-FileHash $source).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Fonte alterada'};$n++
 $proofPath=Join-Path $work 'prova-recuperacao-busca.json'
 @{criteria=$n;helper_sha256=(Get-FileHash (Join-Path $repo 'publicacao_pendente.ps1')).Hash;scope='Register/Invoke v3 com AAC real; nao CLI/busca remota';windows_save_failure=$IsWindows}|ConvertTo-Json|Set-Content -LiteralPath $proofPath -Encoding utf8
 'RECOVERY_SEARCH_PASS criterios'+$n+'; '+$proofPath
}finally{if($null -ne $script:Lock){$script:Lock.Dispose();$script:Lock=$null}}
