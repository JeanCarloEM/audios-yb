#requires -Version 7
param([string]$PositiveResultPath)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($PositiveResultPath) -or -not [IO.Path]::IsPathFullyQualified($PositiveResultPath)){throw [ArgumentException]::new('PositiveResultPath absoluto obrigatorio')}
$positiveTest=Join-Path $PSScriptRoot 'validacao_candidato_metatags_mp3.tests.ps1'
if((Get-FileHash -LiteralPath $positiveTest).Hash -cne 'FBFC5E7F4BCF0DAF6640A9A6D21F3D1771515AA340EC6859A5B87FF86C1427C3'){throw 'Bootstrap diverge'}
$positiveSource=[IO.File]::ReadAllText($positiveTest)
$cut=$positiveSource.IndexOf('# Fixture positiva192k;',[StringComparison]::Ordinal)
if($cut -lt 0){throw 'Bootstrap nao localizado'}
$bootstrap=$positiveSource.Substring(0,$cut)
$rootDeclaration='$root = Split-Path $PSScriptRoot'
if([regex]::Matches($bootstrap,[regex]::Escape($rootDeclaration)).Count -ne 1){throw 'Root bootstrap'}
$bootstrap=$bootstrap.Replace($rootDeclaration,'')
. ([scriptblock]::Create($bootstrap))
$positive=Get-Content -LiteralPath $PositiveResultPath -Raw | ConvertFrom-Json
foreach($entry in @(@($positive.sourcePath,$positive.sourceSha256),@($positive.candidatePath,$positive.candidateSha256))){
 if((Get-FileHash -LiteralPath $entry[0]).Hash -cne $entry[1]){throw 'Artefato positivo alterado'}
}
$updates=@{artist='Artistaé';title='FaixaiTunes';album='Coletânea';track='003';composer='AC/DC'}
$wrong=$updates.Clone();$wrong.title='Outro'
$tagError=$null
try{$null=Assert-Mp3EditorialTagCandidate -File $positive.sourcePath -Candidate $positive.candidatePath -Updates $wrong}catch{$tagError=$_.Exception;while($null -ne $tagError.InnerException){$tagError=$tagError.InnerException}}
if($tagError -isnot [IO.InvalidDataException] -or -not $tagError.Message.Contains('Valor divergente para chave ''title''')){throw ('Rejeicao de titulo nao comprovada: '+$tagError)}
'PASS native_wrong_title_rejected'
$caseDir=Join-Path $PSScriptRoot ('.runtime-editorial-negative-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($caseDir)
$lowSource=Join-Path $caseDir 'source96.mp3';$lowCandidate=Join-Path $caseDir 'candidate96.mp3'
$gen=Invoke-Ytdlp -Executable $script:Ffmpeg -Arguments @('-nostdin','-v','error','-f','lavfi','-i','anoisesrc=sample_rate=44100:duration=2:seed=5678','-ac','2','-c:a','libmp3lame','-b:a','96k','-threads','1','-id3v2_version','3','-metadata','keep_tag=Sentinela ç','-metadata','marcador_coletanea=Grupo','-n',$lowSource) -TimeoutSeconds 30
if($gen.code -ne 0){throw ('Fixture96: '+$gen.err)}
$lowSourceHash=(Get-FileHash -LiteralPath $lowSource).Hash
$prepared=New-Mp3EditorialTagCandidate -File $lowSource -Output $lowCandidate -Updates $updates -Ffmpeg $script:Ffmpeg
if($prepared.Validated -isnot [bool] -or $prepared.Validated){throw 'Writer validou sem prova'}
$lowCandidateHash=(Get-FileHash -LiteralPath $lowCandidate).Hash
$sourcePayload=Get-CompressedAudioHash -File $lowSource -Ffmpeg $script:Ffmpeg
$candidatePayload=Get-CompressedAudioHash -File $lowCandidate -Ffmpeg $script:Ffmpeg
if($sourcePayload -cne $candidatePayload){throw 'Fixture96 payload mudou'}
$sourceProbe=Probe-Audio -File $lowSource;$candidateProbe=Probe-Audio -File $lowCandidate
foreach($measurement in @($sourceProbe,$candidateProbe)){
 if($measurement.codec -cne 'mp3' -or $measurement.container -cne 'mp3' -or -not [double]::IsFinite($measurement.bitrate_medido_kbps) -or $measurement.bitrate_medido_kbps -le 0 -or $measurement.bitrate_medido_kbps -ge 128){throw 'Fixture96 nao prova bitrate inferior com MP3 decodificavel'}
}
$qualityError=$null
try{$null=Assert-Mp3EditorialTagCandidate -File $lowSource -Candidate $lowCandidate -Updates $updates}catch{$qualityError=$_.Exception;while($null -ne $qualityError.InnerException){$qualityError=$qualityError.InnerException}}
if($qualityError -isnot [IO.InvalidDataException] -or -not [string]::Equals($qualityError.Message,'Audio nao atende ao contrato final',[StringComparison]::Ordinal)){throw ('Rejeicao de piso nao comprovada: '+$qualityError)}
foreach($entry in @(@($positive.sourcePath,$positive.sourceSha256),@($positive.candidatePath,$positive.candidateSha256),@($lowSource,$lowSourceHash),@($lowCandidate,$lowCandidateHash))){
 if((Get-FileHash -LiteralPath $entry[0]).Hash -cne $entry[1]){throw 'Arquivo mudou durante negativos'}
}
'PASS native_below_128_rejected'
$result=@{PositiveResultPath=$PositiveResultPath;WrongTitleRejected=$true;WrongTitleMessage=$tagError.Message;Below128Rejected=$true;Below128Message=$qualityError.Message;Source96=$lowSource;Candidate96=$lowCandidate;Source96Sha256=$lowSourceHash;Candidate96Sha256=$lowCandidateHash;Payload96Sha256=$sourcePayload;Source96Probe=$sourceProbe;Candidate96Probe=$candidateProbe;AllInputsUnchanged=$true}
[IO.File]::WriteAllText((Join-Path $caseDir 'resultado.json'),($result|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
'EDITORIAL_NATIVE_NEGATIVE_PASS cases=2 artifacts='+$caseDir
