#requires -Version 7.0
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FixtureRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'editorial_audio.ps1')
$source=Join-Path $FixtureRoot 'fonte.mp3'
$marked=Join-Path $FixtureRoot 'marcado.mp3'
$files=@($source,$marked)
$expectedFiles=@('ED90F05F84430C3C85A9E08BF6748BF42776001509F1827C288C9C18F81DC733','5C1CF6458DED20094404B77B73E857DBE2B916F94590D1A982FBBBB6A7EFE52A')
$before=@($files|ForEach-Object{(Get-FileHash -LiteralPath $_).Hash})
for($i=0;$i -lt 2;$i++){if($before[$i] -cne $expectedFiles[$i]){throw 'Fixture diverge da prova independente'}}
$ffmpeg=Join-Path $repo 'ffmpeg.exe'
$probe=Join-Path $repo 'ffprobe.exe'
$output=Join-Path $FixtureRoot ('candidato-'+[guid]::NewGuid().ToString('N')+'.mp3')
$inputMarker=' MINHA COLET'+[char]0x00C2+'NEA '
$expectedMarker='Minha colet'+[char]0x00E2+'nea'
$candidate=New-Mp3MarkerCandidate -File $source -Output $output -Marker $inputMarker -Ffmpeg $ffmpeg
if($candidate.Validated -isnot [bool] -or $candidate.Validated){throw 'Candidato deve permanecer nao validado'}
if(-not [string]::Equals($candidate.SourcePath,[IO.Path]::GetFullPath($source),[StringComparison]::Ordinal)){throw 'SourcePath incorreto'}
if(-not [string]::Equals($candidate.CandidatePath,[IO.Path]::GetFullPath($output),[StringComparison]::Ordinal)){throw 'CandidatePath incorreto'}
if(-not [string]::Equals($candidate.Marker,$expectedMarker,[StringComparison]::Ordinal)){throw 'Marcador retornado incorreto'}
$snapshot=Get-AudioMetadataSnapshot -File $output -Ffprobe $probe
$tags=@{artist='AC/DC';title='iTunes DJ';album='Album teste';track='12';composer='Autor teste';genre='Genero teste';comment='Comentario teste';marcador_coletanea=$expectedMarker}
foreach($key in $tags.Keys){if(-not [string]::Equals([string]$snapshot.format.tags.$key,$tags[$key],[StringComparison]::Ordinal)){throw ('Tag divergente: '+$key)}}
$stream=$snapshot.streams[0]
if($stream.codec_name -cne 'mp3' -or [string]$stream.sample_rate -cne '44100' -or $stream.channels -ne 2){throw 'Parametros de audio divergentes'}
$expectedPayload='0A11D18D8D81BF4A31A13C72CD7BBAA81B4C4D11A35B8DBAF0EA8EEA126C940F'
foreach($file in @($source,$output)){if((Get-CompressedAudioHash -File $file -Ffmpeg $ffmpeg) -cne $expectedPayload){throw 'Payload diverge da prova independente'}}
$negativeOutput=Join-Path $FixtureRoot ('vazio-'+[guid]::NewGuid().ToString('N')+'.mp3')
$cases=@(
 @{Output=$source;Marker='Teste';Type=[ArgumentException]},
 @{Output=$marked;Marker='Teste';Type=[IO.IOException]},
 @{Output=$negativeOutput;Marker='   ';Type=[ArgumentException]}
)
foreach($case in $cases){
 $caught=$false
 try{$null=New-Mp3MarkerCandidate -File $source -Output $case.Output -Marker $case.Marker -Ffmpeg $ffmpeg}
 catch{if(-not $case.Type.IsInstanceOfType($_.Exception)){throw};$caught=$true}
 if(-not $caught){throw 'Controle negativo aceitou operacao indevida'}
}
if(Test-Path -LiteralPath $negativeOutput){throw 'Marcador vazio criou arquivo'}
for($i=0;$i -lt 2;$i++){if((Get-FileHash -LiteralPath $files[$i]).Hash -cne $before[$i]){throw 'Arquivo original alterado'}}
Write-Output 'MARCADOR_CANDIDATO_PASS'
