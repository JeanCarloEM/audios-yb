#requires -Version 7.0
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FixtureRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'editorial_audio.ps1')
$source=Join-Path $FixtureRoot 'fonte.mp3'
$marked=Join-Path $FixtureRoot 'marcado.mp3'
$files=@($source,$marked)
$before=@($files|ForEach-Object{(Get-FileHash -LiteralPath $_).Hash})
$probe=Join-Path $repo 'ffprobe.exe'
$snapshots=@(foreach($file in $files){Get-AudioMetadataSnapshot -File $file -Ffprobe $probe})
$expected=@{artist='AC/DC';title='iTunes DJ';album='Album teste';track='12';composer='Autor teste';genre='Genero teste';comment='Comentario teste'}
foreach($snapshot in $snapshots){
 foreach($name in $expected.Keys){
  if(-not [string]::Equals([string]$snapshot.format.tags.$name,$expected[$name],[StringComparison]::Ordinal)){throw "Tag divergente: $name"}
 }
 if(@($snapshot.streams).Count -ne 1 -or $snapshot.streams[0].codec_type -cne 'audio' -or $snapshot.streams[0].codec_name -cne 'mp3' -or $snapshot.streams[0].sample_rate -ne 44100 -or $snapshot.streams[0].channels -ne 2){throw 'Parametros da fixture divergentes'}
}
if($snapshots[0].format.tags.PSObject.Properties.Name -contains 'marcador_coletanea'){throw 'Fonte ja marcada'}
$marker='Minha colet'+[char]0x00E2+'nea'
if(-not [string]::Equals($snapshots[1].format.tags.marcador_coletanea,$marker,[StringComparison]::Ordinal)){throw 'Marcador divergente'}
$negative=@(
 @{File=(Join-Path $FixtureRoot ('ausente-'+[Guid]::NewGuid().ToString('N')+'.mp3'));Exe=$probe;Type=[IO.FileNotFoundException]}
 @{File=$source;Exe=(Join-Path $repo 'ffmpeg.exe');Type=[InvalidOperationException]}
)
foreach($case in $negative){
 $caught=$false
 try{$null=Get-AudioMetadataSnapshot -File $case.File -Ffprobe $case.Exe}catch{if(-not $case.Type.IsInstanceOfType($_.Exception)){throw};$caught=$true}
 if(-not $caught){throw 'Negativo retornou sucesso'}
}
for($i=0;$i -lt $files.Count;$i++){if((Get-FileHash -LiteralPath $files[$i]).Hash -cne $before[$i]){throw 'Arquivo foi alterado'}}
'METADADOS_AUDIO_PASS'
