#requires -Version 7.0
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FixtureRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$script:Root=$repo
$script:Exe=Join-Path $repo 'yt-dlp.exe'
$script:Ffmpeg=Join-Path $repo 'ffmpeg.exe'
$script:Ffprobe=Join-Path $repo 'ffprobe.exe'
. (Join-Path $repo 'editorial_audio.ps1')
$files=@((Join-Path $FixtureRoot 'fonte.mp3'),(Join-Path $FixtureRoot 'marcado.mp3'))
$hashes=@('ED90F05F84430C3C85A9E08BF6748BF42776001509F1827C288C9C18F81DC733','5C1CF6458DED20094404B77B73E857DBE2B916F94590D1A982FBBBB6A7EFE52A')
$payload='0A11D18D8D81BF4A31A13C72CD7BBAA81B4C4D11A35B8DBAF0EA8EEA126C940F'
for($i=0;$i -lt 2;$i++){if((Get-FileHash -LiteralPath $files[$i]).Hash -cne $hashes[$i]){throw 'Fixture independente divergente'}}
$marker='Minha colet'+[char]0x00E2+'nea'
$request=' MINHA COLET'+[char]0x00C2+'NEA '
$result=Assert-Mp3MarkerCandidate -File $files[0] -Candidate $files[1] -Marker $request
if(@($result).Count -ne 1 -or $result.Verified -isnot [bool] -or -not $result.Verified){throw 'Resultado inesperado'}
if($result.SourceSha256 -cne $hashes[0] -or $result.CandidateSha256 -cne $hashes[1] -or $result.PayloadSha256 -cne $payload){throw 'Hashes divergem da prova independente'}
if(-not [string]::Equals($result.SourcePath,[IO.Path]::GetFullPath($files[0]),[StringComparison]::Ordinal) -or -not [string]::Equals($result.CandidatePath,[IO.Path]::GetFullPath($files[1]),[StringComparison]::Ordinal)){throw 'Paths divergentes'}
foreach($probe in @($result.BeforeProbe,$result.AfterProbe)){
 if($probe.codec -cne 'mp3' -or $probe.container -cne 'mp3' -or $probe.amostragem -ne 44100 -or $probe.canais -ne 2 -or $probe.bitrate_medido_kbps -lt 128 -or $probe.integridade -cne 'decodificacao_integral_ok'){throw 'Prova tecnica insuficiente'}
}
$badTitle=Join-Path $FixtureRoot ('titulo-'+[guid]::NewGuid().ToString('N')+'.mp3')
$badPayload=Join-Path $FixtureRoot ('payload-'+[guid]::NewGuid().ToString('N')+'.mp3')
$prefix=@('-nostdin','-v','error','-protocol_whitelist','file','-i',$files[0],'-map','0:a:0','-map_metadata','0')
$preparations=@(
 @{Args=($prefix+@('-c:a','copy','-id3v2_version','3','-metadata','title=Indevido','-metadata',('marcador_coletanea='+$marker),'-n',$badTitle))},
 @{Args=($prefix+@('-c:a','libmp3lame','-b:a','192k','-id3v2_version','3','-metadata',('marcador_coletanea='+$marker),'-n',$badPayload))}
)
foreach($prep in $preparations){
 $run=Invoke-Ytdlp -Executable $script:Ffmpeg -Arguments $prep.Args -TimeoutSeconds 30
 if($run.timeout -or $run.code -ne 0){throw ('Preparo negativo falhou: '+$run.err)}
}
$cases=@(
 @{Path=$files[1];Marker='Outra';Type=[IO.InvalidDataException];Message='Marcador'},
 @{Path=$badTitle;Marker=$marker;Type=[IO.InvalidDataException];Message='Tag'},
 @{Path=$badPayload;Marker=$marker;Type=[IO.InvalidDataException];Message='Payload'},
 @{Path=$files[0];Marker=$marker;Type=[ArgumentException];Message='Candidato'}
)
foreach($case in $cases){
 $caught=$false
 try{$null=Assert-Mp3MarkerCandidate -File $files[0] -Candidate $case.Path -Marker $case.Marker}
 catch{
  if(-not $case.Type.IsInstanceOfType($_.Exception) -or $_.Exception.Message.IndexOf($case.Message,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw}
  $caught=$true
 }
 if(-not $caught){throw 'Controle negativo aceito'}
}
for($i=0;$i -lt 2;$i++){if((Get-FileHash -LiteralPath $files[$i]).Hash -cne $hashes[$i]){throw 'Original alterado'}}
Write-Output 'MARCADOR_VALIDACAO_PASS'
