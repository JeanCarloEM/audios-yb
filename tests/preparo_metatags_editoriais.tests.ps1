#requires -Version 7
param([string]$PositiveResultPath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($PositiveResultPath) -or -not [IO.Path]::IsPathFullyQualified($PositiveResultPath)){throw [ArgumentException]::new('PositiveResultPath absoluto obrigatorio')}
$base=Join-Path $PSScriptRoot 'validacao_candidato_metatags_mp3.tests.ps1'
if((Get-FileHash -LiteralPath $base).Hash -cne 'FBFC5E7F4BCF0DAF6640A9A6D21F3D1771515AA340EC6859A5B87FF86C1427C3'){throw 'Bootstrap diverge'}
$text=[IO.File]::ReadAllText($base);$cut=$text.IndexOf('# Fixture positiva192k;',[StringComparison]::Ordinal)
if($cut -lt 0){throw 'Bootstrap ausente'}
$bootstrap=$text.Substring(0,$cut);$declaration='$root = Split-Path $PSScriptRoot'
if([regex]::Matches($bootstrap,[regex]::Escape($declaration)).Count -ne 1){throw 'Root bootstrap'}
$bootstrap=$bootstrap.Replace($declaration,'')
. ([scriptblock]::Create($bootstrap))
foreach($file in @('leitura_campo_editorial.ps1','mapeamento_metatags_editoriais.ps1','decisao_metatags.ps1','plano_metatags_editoriais.ps1','preparo_metatags_editoriais.ps1')){. (Join-Path $root $file)}
$positive=Get-Content -LiteralPath $PositiveResultPath -Raw|ConvertFrom-Json
foreach($entry in @(@($positive.sourcePath,$positive.sourceSha256),@($positive.candidatePath,$positive.candidateSha256))){if((Get-FileHash -LiteralPath $entry[0]).Hash -cne $entry[1]){throw 'Artefato positivo alterado'}}
$script:OriginalWriter=(Get-Item -LiteralPath 'Function:\New-Mp3EditorialTagCandidate').ScriptBlock
$script:WriterCalls=0;$script:WriterMode='native'
function New-Mp3EditorialTagCandidate {
 param([string]$File,[string]$Output,[hashtable]$Updates,[string]$Ffmpeg)
 $script:WriterCalls++
 if($script:WriterMode -ceq 'partial_failure'){[IO.File]::WriteAllBytes($Output,[byte[]](8,9));throw [IO.IOException]::new('fixture_writer_error')}
 & $script:OriginalWriter -File $File -Output $Output -Updates $Updates -Ffmpeg $Ffmpeg
}
function Assert-Selection([object]$Result,[string]$Path,[bool]$Changed,[string]$Status,[int]$Calls){
 if($Result -isnot [pscustomobject] -or $Result.Changed -isnot [bool] -or $Result.Changed -ne $Changed -or -not [string]::Equals($Result.Path,$Path,[StringComparison]::Ordinal) -or -not [string]::Equals($Result.TagAudit.status,$Status,[StringComparison]::Ordinal) -or $script:WriterCalls -ne $Calls){throw ('Selecao/status/writer divergentes: '+($Result|ConvertTo-Json -Depth 8 -Compress))}
}
$row=[pscustomobject]@{Artista='Artistaé';Musica='FaixaiTunes';Album='Coletânea';Numero='003';Autor='AC/DC'}
$columns=@{artist='Artista';title='Musica';album='Album';track='Numero';composer='Autor'}
try{
 $script:WriterCalls=0
 $absent=Get-EditorialPreparedAudio -File $positive.sourcePath -Row $null -Columns $null
 Assert-Selection $absent $positive.sourcePath $false 'ausente' 0
 'PASS preparation_absent'
 $script:WriterCalls=0
 $badMap=Get-EditorialPreparedAudio -File $positive.sourcePath -Row $row -Columns @{title='Musica';album='Missing'}
 Assert-Selection $badMap $positive.sourcePath $false 'limitacao' 0
 if($badMap.TagAudit.motivo -cne 'csv_mapping_unsupported' -or $badMap.TagAudit.campos.Count -ne 5){throw 'Mapeamento sem rastreio'}
 'PASS preparation_missing_column'
 $script:WriterCalls=0
 $same=Get-EditorialPreparedAudio -File $positive.candidatePath -Row $row -Columns $columns
 Assert-Selection $same $positive.candidatePath $false 'sem_alteracoes' 0
 if($same.TagAudit.decisoes.Count -ne 5){throw 'Decisoes ausentes no noop'}
 'PASS preparation_already_present'
 $script:WriterCalls=0
 $conflict=Get-EditorialPreparedAudio -File $positive.candidatePath -Row ([pscustomobject]@{Musica='Outro'}) -Columns @{title='Musica'}
 Assert-Selection $conflict $positive.candidatePath $false 'limitacao' 0
 if($conflict.TagAudit.motivo -cne 'conflict_or_unsupported' -or @($conflict.TagAudit.decisoes|Where-Object {$_.Decision.Conflict}).Count -ne 1){throw 'Conflito nao preservado'}
 'PASS preparation_conflict'
 $script:WriterCalls=0
 $applied=Get-EditorialPreparedAudio -File $positive.sourcePath -Row $row -Columns $columns
 if($applied.Changed -isnot [bool] -or -not $applied.Changed -or [string]::Equals($applied.Path,$positive.sourcePath,[StringComparison]::Ordinal)){throw 'Nao selecionou candidato independente'}
 Assert-Selection $applied $applied.Path $true 'aplicado' 1
 $appliedHash=(Get-FileHash -LiteralPath $applied.Path).Hash
 if($applied.TagAudit.validado -isnot [bool] -or -not $applied.TagAudit.validado -or $applied.TagAudit.origem_sha256 -cne $positive.sourceSha256 -or $applied.TagAudit.resultado_sha256 -cne $appliedHash -or $applied.TagAudit.payload_sha256 -cne $positive.payloadSha256 -or $applied.TagAudit.resultado_bytes -ne (Get-Item -LiteralPath $applied.Path).Length){throw 'Auditoria aplicada divergente'}
 $tags=(Get-AudioMetadataSnapshot -File $applied.Path -Ffprobe $script:Ffprobe).format.tags
 foreach($entry in @{artist='Artistaé';title='FaixaiTunes';album='Coletânea';track='003';composer='AC/DC';keep_tag='Sentinela ç';marcador_coletanea='Grupo'}.GetEnumerator()){
  if(-not [string]::Equals([string]$tags.($entry.Key),$entry.Value,[StringComparison]::Ordinal)){throw ('Tag divergente: '+$entry.Key)}
 }
 'PASS preparation_native_apply'
 $script:WriterMode='partial_failure';$script:WriterCalls=0
 $failed=Get-EditorialPreparedAudio -File $positive.sourcePath -Row $row -Columns $columns
 Assert-Selection $failed $positive.sourcePath $false 'limitacao' 1
 $partial=$failed.TagAudit.arquivo_candidato
 if($failed.TagAudit.motivo -cne 'fixture_writer_error' -or -not [IO.File]::Exists($partial) -or (Get-Item -LiteralPath $partial).Length -ne 2){throw 'Parcial nao preservado/erro mascarado'}
 'PASS preparation_writer_partial_failure'
 foreach($entry in @(@($positive.sourcePath,$positive.sourceSha256),@($positive.candidatePath,$positive.candidateSha256),@($applied.Path,$appliedHash))){if((Get-FileHash -LiteralPath $entry[0]).Hash -cne $entry[1]){throw 'Audio existente alterado'}}
 $dir=Join-Path $PSScriptRoot ('.runtime-editorial-preparation-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($dir)
 $proof=@{PositiveResultPath=$PositiveResultPath;AppliedPath=$applied.Path;AppliedAudit=$applied.TagAudit;NoopStatus=$same.TagAudit.status;ConflictAudit=$conflict.TagAudit;MappingAudit=$badMap.TagAudit;FailureAudit=$failed.TagAudit;PartialPreserved=$true;AllSourceFilesUnchanged=$true}
 [IO.File]::WriteAllText((Join-Path $dir 'resultado.json'),($proof|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))
 'EDITORIAL_PREPARATION_PASS cases=6 artifacts='+$dir
}finally{Set-Item -LiteralPath 'Function:\New-Mp3EditorialTagCandidate' -Value $script:OriginalWriter}
