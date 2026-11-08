#requires -Version 7
# Validacao tecnica somente; plano/procedencia/publicacao sao responsabilidade do chamador.
function Assert-Mp3EditorialTagCandidate {
 [CmdletBinding()]
 param([string]$File,[string]$Candidate,[AllowNull()][hashtable]$Updates)
 $argv=New-Mp3EditorialTagArguments -SourcePath $File -CandidatePath $Candidate -Updates $Updates
 $File=$argv[6];$Candidate=$argv[-1]
 $updatesSnapshot=@{};foreach($key in $Updates.Keys){$updatesSnapshot[$key]=$Updates[$key]}
 foreach($path in @($File,$Candidate)){
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw [IO.FileNotFoundException]::new('Arquivo ausente',$path)}
 }
 $sourcePath=[IO.Path]::GetFullPath($File);$candidatePath=[IO.Path]::GetFullPath($Candidate)
 $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
 if([string]::Equals($sourcePath,$candidatePath,$comparison)){throw [ArgumentException]::new('Candidato deve diferir da fonte')}
 $sourceHash=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
 $candidateHash=(Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
 $sourcePayload=Get-CompressedAudioHash -File $sourcePath -Ffmpeg $script:Ffmpeg
 $candidatePayload=Get-CompressedAudioHash -File $candidatePath -Ffmpeg $script:Ffmpeg
 if(-not [string]::Equals($sourcePayload,$candidatePayload,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Payload comprimido alterado')}
 $before=Get-AudioMetadataSnapshot -File $sourcePath -Ffprobe $script:Ffprobe
 $after=Get-AudioMetadataSnapshot -File $candidatePath -Ffprobe $script:Ffprobe
 if($before.format.format_name -cne 'mp3' -or $after.format.format_name -cne 'mp3'){throw [IO.InvalidDataException]::new('Formato deve ser MP3')}
 $null=Assert-EditorialTagSnapshot -Before $before.format.tags -After $after.format.tags -Updates $updatesSnapshot
 $null=Assert-MarkerTagsPreserved -Before $before.streams[0].tags -After $after.streams[0].tags
 $beforeProbe=Probe-Audio -File $sourcePath
 $afterProbe=Probe-Audio -File $candidatePath
 if(-not (Test-FinalAudio -File $sourcePath -Probe $beforeProbe) -or -not (Test-FinalAudio -File $candidatePath -Probe $afterProbe)){throw [IO.InvalidDataException]::new('Audio nao atende ao contrato final')}
 foreach($probe in @($beforeProbe,$afterProbe)){
  foreach($key in @('duracao','bitrate_medido_kbps')){
   $value=[double]$probe[$key]
   if(-not [double]::IsFinite($value) -or $value -le 0){throw [IO.InvalidDataException]::new('Parametro medido invalido: '+$key)}
  }
 }
 foreach($key in @('codec','container','canais','amostragem','bitrate_medido_kbps','bitrate_nominal_bps','variacao_pacotes','lossless')){
  if(-not [object]::Equals($beforeProbe[$key],$afterProbe[$key])){throw [IO.InvalidDataException]::new('Parametro alterado: '+$key)}
 }
 if([Math]::Abs($beforeProbe.duracao-$afterProbe.duracao) -gt 0.001){throw [IO.InvalidDataException]::new('Parametro duracao alterado')}
 if((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -cne $sourceHash -or (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash -cne $candidateHash){throw [IO.InvalidDataException]::new('Arquivo mudou durante validacao')}
 return [pscustomobject]@{Verified=$true;SourcePath=$sourcePath;CandidatePath=$candidatePath;SourceSha256=$sourceHash;CandidateSha256=$candidateHash;CandidateSizeBytes=(Get-Item -LiteralPath $candidatePath).Length;PayloadSha256=$sourcePayload;Updates=$updatesSnapshot;BeforeProbe=$beforeProbe;AfterProbe=$afterProbe}
}
