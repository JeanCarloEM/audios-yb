#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'intencao_reconciliacao.tests.ps1')
$technical=@{versao=[int]2;tipo='selecao_tecnica';video_id='TestVideo01';criterio='url_direta_id_literal';metadados=@{id='TestVideo01';title='Entrevista com voz'};referencia=@{artista='AC/DC';musica='iTunes DJ'}}
function New-TechnicalRecoveryFixture([string]$Name,[object]$Technical=$technical,[switch]$KeepLegacy){
 $f=New-RecoveryFixture -Name $Name
 $d=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($f.Intent))
 if(-not $KeepLegacy){$d.registro.Remove('aprovacao_musical')}
 $d.registro.selecao_tecnica=$Technical
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($d|ConvertTo-Json -Depth 25))
 $h=[Security.Cryptography.SHA256]::Create()
 try{$hash=[BitConverter]::ToString($h.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
 [IO.File]::WriteAllBytes($f.Intent,$bytes)
 $f.IntentHash=$hash;$script:State.publicacoes_pendentes[$f.Name].sha256=$hash
 Save-State
 return $f
}
function Assert-TechnicalState($f){
 $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 $video=$disk.videos.TestVideo01;$record=$disk.registros[$key]
 foreach($section in @($video,$record,$video.auditoria,$record.auditoria)){
  if($section.ContainsKey('aprovacao_musical') -or $section.selecao_tecnica.versao -ne 2 -or $section.selecao_tecnica.metadados.title -cne 'Entrevista com voz' -or $section.selecao_tecnica.ContainsKey('sem_vocais_conferido')){throw 'Prova tecnica perdida ou rotulada como aprovacao humana'}
 }
 if($disk.publicacoes_pendentes.Count -ne 0 -or $disk.registros.canary.nota -cne 'historico preservado' -or $video.sha256 -cne $sourceHash -or (Get-FileHash -LiteralPath $f.Target).Hash.ToLowerInvariant() -cne $sourceHash -or (Get-FileHash -LiteralPath $f.Intent).Hash.ToLowerInvariant() -cne $f.IntentHash){throw 'Hash/journal/historico/referencia divergentes'}
}
try{
 $f=New-TechnicalRecoveryFixture -Name 'technical-publish'
 $r=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out
 if($r.Action -cne 'publish' -or (Test-Path -LiteralPath $f.Ready)){throw 'Publicacao tecnica falhou'}
 Assert-TechnicalState $f
 $hash=(Get-FileHash -LiteralPath $script:StateFile).Hash
 $r=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out
 if($r.Status -cne 'sem_pendencia' -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $hash){throw 'Reexecucao alterou estado'}
 $f=New-TechnicalRecoveryFixture -Name 'technical-conflict'
 $script:State.videos.TestVideo01=@{artista='AC/DC';musica='iTunes DJ';arquivo='final.m4a';sha256=$sourceHash;aprovacao_musical=$proof}
 Save-State;$hash=(Get-FileHash -LiteralPath $script:StateFile).Hash;$caught=$false
 try{$null=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out}catch [IO.InvalidDataException]{if($_.Exception.Message -notmatch 'Conflito'){throw};$caught=$true}
 if(-not $caught -or (Test-Path -LiteralPath $f.Target) -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $hash){throw 'Conflito v1/v2 teve efeitos'}
 $bad=$technical.Clone();$bad.versao=1
 $f=New-TechnicalRecoveryFixture -Name 'technical-invalid' -Technical $bad -KeepLegacy
 $hash=(Get-FileHash -LiteralPath $script:StateFile).Hash;$caught=$false
 try{$null=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out}catch [IO.InvalidDataException]{if($_.Exception.Message -notmatch 'Selecao'){throw};$caught=$true}
 if(-not $caught -or (Test-Path -LiteralPath $f.Target) -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $hash){throw 'Tecnico invalido usou aprovacao antiga'}
 $f=New-TechnicalRecoveryFixture -Name 'technical-save-failure'
 if($IsWindows){
  $stateLock=[IO.File]::Open($script:StateFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $caught=$false
  try{try{$null=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out}catch{
   $failure=$_.Exception;while($null -ne $failure.InnerException){$failure=$failure.InnerException}
   if($failure -isnot [IO.IOException]){throw};$caught=$true
  }}finally{$stateLock.Dispose()}
  $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
  if(-not $caught -or (Test-Path -LiteralPath $f.Ready) -or -not (Test-Path -LiteralPath $f.Target) -or $disk.videos.Count -ne 0 -or -not $disk.publicacoes_pendentes.ContainsKey($f.Name)){throw 'Falha Move->State perdeu recuperabilidade'}
  $script:State=$disk
 }else{[IO.File]::Move($f.Ready,$f.Target);'FALHA_SAVE_POS_MOVE_NAO_TESTADA_NESTE_SO'}
 $r=Invoke-PublicationRecovery -ReferenceName $f.Name -Control $script:Control -Out $script:Out
 if($r.Action -cne 'restore_state'){throw 'Retomada tecnica nao restaurou estado'}
 Assert-TechnicalState $f
 if((Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Fonte alterada'}
 'INTENCAO_RECUPERACAO_TECNICA_PASS; AAC real; legado/persistencia4secoes/idempotencia/conflito/semfallback/falhaIO/retomada'
}finally{if($null -ne $script:Lock){$script:Lock.Dispose();$script:Lock=$null}}
