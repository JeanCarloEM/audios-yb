#requires -Version 7.0
$ErrorActionPreference='Stop'
# Harness existente: arquivos sentinela reais, sem audio/transporte/publicacao.
. (Join-Path $PSScriptRoot 'intencao_publicacao.tests.ps1')
. (Join-Path $repo 'selecao_tecnica.ps1')
$technical=@{versao=[int]2;tipo='selecao_tecnica';video_id='TestVideo01';criterio='url_direta_id_literal';metadados=@{id='TestVideo01';title='Entrevista com voz'};referencia=@{artista='AC/DC';musica='iTunes DJ'}}
$technicalRecord=$record.Clone()
$technicalRecord.Remove('aprovacao_musical')
$technicalRecord.selecao_tecnica=$technical
$parameters=$base.Clone();$parameters.Record=$technicalRecord
$before=ConvertTo-Json -InputObject $technicalRecord -Depth 12 -Compress
$result=New-PublicationIntentSnapshot @parameters
if($result.registro.ContainsKey('aprovacao_musical') -or $result.registro.selecao_tecnica.metadados.title -cne 'Entrevista com voz' -or $result.registro.selecao_tecnica.versao -ne 2){throw 'Contrato tecnico misturado com aprovacao'}
if($result.registro.selecao_tecnica.ContainsKey('sem_vocais_conferido') -or (ConvertTo-Json -InputObject $technicalRecord -Depth 12 -Compress) -cne $before){throw 'Confirmacao fabricada ou entrada mutada'}
$result.registro.selecao_tecnica.metadados.title='Alterado'
if($technical.metadados.title -cne 'Entrevista com voz'){throw 'Alias da prova tecnica'}
# Legado sintetico proposital: snapshot nao certifica verdade musical.
$both=$technicalRecord.Clone();$both.aprovacao_musical=$record.aprovacao_musical
$parameters.Record=$both
$null=New-PublicationIntentSnapshot @parameters
$badVersion=$technical.Clone();$badVersion.versao=1
$wrongId=$technical.Clone();$wrongId.video_id='testVideo01'
$badMeta=$technical.Clone();$badMeta.metadados=@{id='TestVideo01';title=123}
$badCases=@(
 @{Record=$both.Clone();Proof=$null},
 @{Record=$both.Clone();Proof=@{}},
 @{Record=$both.Clone();Proof='texto'},
 @{Record=$both.Clone();Proof=$badVersion},
 @{Record=$both.Clone();Proof=$wrongId},
 @{Record=$both.Clone();Proof=$badMeta}
)
$n=2
foreach($case in $badCases){
 $bad=$case.Record;$bad.selecao_tecnica=$case.Proof;$parameters.Record=$bad
 $caught=$false
 try{$null=New-PublicationIntentSnapshot @parameters}catch [ArgumentException]{$caught=$true}
 if(-not $caught){throw 'Tecnico invalido usou aprovacao antiga'}
 $n++
}
$wrongCase=$record.Clone();$wrongCase.Selecao_tecnica=$technical
$wrongLegacy=$technicalRecord.Clone();$wrongLegacy.Aprovacao_musical=$record.aprovacao_musical
foreach($bad in @($wrongCase,$wrongLegacy)){
 $parameters.Record=$bad;$caught=$false
 try{$null=New-PublicationIntentSnapshot @parameters}catch [ArgumentException]{$caught=$true}
 if(-not $caught){throw 'Nome de campo nao canonico aceito'}
 $n++
}
if((Get-FileHash -LiteralPath $ready).Hash.ToLowerInvariant() -cne $expected -or (Get-FileHash -LiteralPath $existing).Hash -cne $existingHash -or (Test-Path -LiteralPath $target)){throw 'Snapshot alterou arquivos'}
'SNAPSHOT_TECHNICAL_PASS criterios'+$n+'; legado original passou; sem audio/publicacao/retomada'
