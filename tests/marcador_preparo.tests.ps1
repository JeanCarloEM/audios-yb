#requires -Version 7.0
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FixtureRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$script:Root=$repo
$script:Exe=Join-Path $repo 'yt-dlp.exe'
$script:Ffmpeg=Join-Path $repo 'ffmpeg.exe'
$script:Ffprobe=Join-Path $repo 'ffprobe.exe'
. (Join-Path $repo 'editorial_audio.ps1')
$source=Join-Path $FixtureRoot 'fonte.mp3'
$marked=Join-Path $FixtureRoot 'marcado.mp3'
$hashes=@('ED90F05F84430C3C85A9E08BF6748BF42776001509F1827C288C9C18F81DC733','5C1CF6458DED20094404B77B73E857DBE2B916F94590D1A982FBBBB6A7EFE52A')
$files=@($source,$marked)
for($i=0;$i -lt 2;$i++){if((Get-FileHash -LiteralPath $files[$i]).Hash -cne $hashes[$i]){throw 'Fixture divergente'}}
$marker='Minha colet'+[char]0x00E2+'nea'
$request=' MINHA COLET'+[char]0x00C2+'NEA '
$savedProbe=$script:Ffprobe
try{
 $script:Ffprobe=Join-Path $FixtureRoot ('ausente-'+[guid]::NewGuid().ToString('N'))
 $blank=Get-MarkerPreparedAudio -File $source -Marker '   '
 if($blank.Changed -or $blank.MarkerAudit.status -cne 'ausente' -or -not [string]::Equals($blank.Path,$source,[StringComparison]::Ordinal)){throw 'Ausencia de marcador alterou selecao ou consultou ferramenta'}
}finally{$script:Ffprobe=$savedProbe}
$prepared=Get-MarkerPreparedAudio -File $source -Marker $request
if(@($prepared).Count -ne 1 -or -not $prepared.Changed -or $prepared.MarkerAudit.status -cne 'aplicado' -or -not $prepared.MarkerAudit.validado){throw 'Marcador nao foi preparado e validado'}
if(-not [string]::Equals($prepared.MarkerAudit.valor,$marker,[StringComparison]::Ordinal) -or $prepared.MarkerAudit.origem_sha256 -cne $hashes[0] -or $prepared.MarkerAudit.payload_sha256 -cne '0A11D18D8D81BF4A31A13C72CD7BBAA81B4C4D11A35B8DBAF0EA8EEA126C940F'){throw 'Auditoria diverge da prova independente'}
if([string]::Equals($prepared.Path,$source,[StringComparison]::Ordinal) -or -not (Test-Path -LiteralPath $prepared.Path -PathType Leaf)){throw 'Candidato nao foi separado'}
$candidateHash=(Get-FileHash -LiteralPath $prepared.Path).Hash
if($prepared.MarkerAudit.resultado_sha256 -cne $candidateHash){throw 'Hash final incorreto'}
$countBefore=@(Get-ChildItem -LiteralPath $FixtureRoot -File).Count
$again=Get-MarkerPreparedAudio -File $prepared.Path -Marker $request
if($again.Changed -or $again.MarkerAudit.status -cne 'ja_presente' -or -not [string]::Equals($again.Path,$prepared.Path,[StringComparison]::Ordinal)){throw 'Reaplicacao indevida'}
if((Get-FileHash -LiteralPath $prepared.Path).Hash -cne $candidateHash -or @(Get-ChildItem -LiteralPath $FixtureRoot -File).Count -ne $countBefore){throw 'Reexecucao reescreveu ou duplicou audio'}
$conflict=Get-MarkerPreparedAudio -File $marked -Marker 'Outra'
if($conflict.Changed -or $conflict.MarkerAudit.status -cne 'limitacao' -or $conflict.MarkerAudit.motivo -cne 'multiple_values_not_validated' -or -not [string]::Equals($conflict.Path,$marked,[StringComparison]::Ordinal)){throw 'Conflito nao preservado'}
$savedFfmpeg=$script:Ffmpeg
try{
 $script:Ffmpeg=$script:Ffprobe
 $failed=Get-MarkerPreparedAudio -File $source -Marker $request
 if($failed.Changed -or $failed.MarkerAudit.status -cne 'limitacao' -or [string]::IsNullOrWhiteSpace($failed.MarkerAudit.motivo) -or -not [string]::Equals($failed.Path,$source,[StringComparison]::Ordinal)){throw 'Falha editorial nao preservou selecao original'}
}finally{$script:Ffmpeg=$savedFfmpeg}
for($i=0;$i -lt 2;$i++){if((Get-FileHash -LiteralPath $files[$i]).Hash -cne $hashes[$i]){throw 'Original alterado'}}
Write-Output 'MARCADOR_PREPARO_PASS'
