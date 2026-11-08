#requires -Version 7
# Selecao tecnica sem publicar; CSV/identidade/procedencia devem estar autorizados pelo chamador.
function Get-EditorialPreparedAudio {
 [CmdletBinding()]
 param([string]$File,[AllowNull()][object]$Row,[AllowNull()][object]$Columns)
 if(-not (Test-Path -LiteralPath $File -PathType Leaf)){throw [IO.FileNotFoundException]::new('Arquivo ausente',$File)}
 $source=[IO.Path]::GetFullPath($File)
 $requests=Get-EditorialCsvRequests -Row $Row -Columns $Columns
 $result=[pscustomobject]@{Path=$source;Changed=$false;TagAudit=@{status='ausente';campos=$requests.Fields}}
 $plan=$null
 if(-not $requests.Ready){$result.TagAudit=@{status='limitacao';motivo='csv_mapping_unsupported';campos=$requests.Fields};return $result}
 if($requests.RequestedValues.Count -eq 0){return $result}
 $candidate=$null
 try {
  if([IO.Path]::GetExtension($source).ToLowerInvariant() -ne '.mp3'){
   $result.TagAudit=@{status='limitacao';motivo='Mapeamento editorial validado somente para MP3 via FFmpeg/ffprobe';campos=$requests.Fields}
   return $result
  }
  $sourceHashBefore=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
  $snapshot=Get-AudioMetadataSnapshot -File $source -Ffprobe $script:Ffprobe
  $current=New-EditorialTagMap -Before $snapshot.format.tags -Updates @{}
  $plan=Get-EditorialTagPlan -CurrentValues $current -RequestedValues $requests.RequestedValues -RequestedSources $requests.RequestedSources
  if(-not $plan.Ready){$result.TagAudit=@{status='limitacao';motivo='conflict_or_unsupported';campos=$requests.Fields;decisoes=$plan.Decisions};return $result}
  if($plan.Updates.Count -eq 0){$result.TagAudit=@{status='sem_alteracoes';campos=$requests.Fields;decisoes=$plan.Decisions};return $result}
  $candidate=Join-Path ([IO.Path]::GetDirectoryName($source)) ('metatags-'+[guid]::NewGuid().ToString('N')+'.mp3')
  $created=New-Mp3EditorialTagCandidate -File $source -Output $candidate -Updates $plan.Updates -Ffmpeg $script:Ffmpeg
  $proof=Assert-Mp3EditorialTagCandidate -File $source -Candidate $created.CandidatePath -Updates $plan.Updates
  if($proof.Verified -isnot [bool] -or -not $proof.Verified -or -not [string]::Equals($sourceHashBefore,$proof.SourceSha256,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Candidato sem verificacao ou fonte alterada')}
  $result.Path=$created.CandidatePath
  $result.Changed=$true
  $result.TagAudit=@{status='aplicado';validado=$true;campos=$requests.Fields;decisoes=$plan.Decisions;origem_sha256=$proof.SourceSha256;resultado_sha256=$proof.CandidateSha256;payload_sha256=$proof.PayloadSha256;resultado_bytes=$proof.CandidateSizeBytes}
  return $result
 }
 catch {
  $result.Path=$source;$result.Changed=$false
  $decisions=@();if($null -ne $plan){$decisions=$plan.Decisions}
  $result.TagAudit=@{status='limitacao';motivo=$_.Exception.Message;campos=$requests.Fields;decisoes=$decisions;arquivo_candidato=$candidate}
  return $result
 }
}
