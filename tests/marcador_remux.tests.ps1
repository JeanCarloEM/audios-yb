#requires -Version 7.0
# Sequencia MP3/FFmpeg/ffprobe comprovada no Windows; CLI principal nao integrada.
[CmdletBinding()]
param([string]$FixtureReceipt='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($FixtureReceipt)){
 $created=& (Join-Path $PSScriptRoot 'criar_fixture_marcador_mp3.ps1')
 $FixtureReceipt=($created|ConvertFrom-Json).receipt_path
}
if(-not [IO.Path]::IsPathRooted($FixtureReceipt)){$FixtureReceipt=Join-Path $PSScriptRoot $FixtureReceipt}
$receiptPath=[IO.Path]::GetFullPath($FixtureReceipt)
$sourceReceipt=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
if($sourceReceipt.'$schema' -ne 'audios-yb-mp3-fixture/v1'){throw 'Schema divergente'}
$source=[IO.Path]::GetFullPath($sourceReceipt.fixture.sourcepath)
$dir=Split-Path -Parent $source
$relative=[IO.Path]::GetRelativePath($PSScriptRoot,$dir)
if($relative -notmatch '^\.runtime-marcador-mp3-fixture-[0-9a-f]{32}$'){throw 'Fixture fora do diretorio de teste'}
if([IO.Path]::GetFileName($source) -cne 'fonte.mp3'){throw 'Nome da fonte divergente'}
if($sourceReceipt.fixture.hash -notmatch '^[0-9a-fA-F]{64}$' -or (Get-FileHash -LiteralPath $source).Hash -ne $sourceReceipt.fixture.hash){throw 'Fonte alterada'}
$out=Join-Path $dir ('marcado-'+[Guid]::NewGuid().ToString('N')+'.mp3')
. (Join-Path $PSScriptRoot 'processo_capturado.ps1')
. (Join-Path $root 'editorial_audio.ps1')
if(Test-Path -LiteralPath $out){throw 'Saida ja existe; nao repetir remux'}
$marker=ConvertTo-CollectionMarker (' MINHA COLET'+[char]0x00C2+'NEA ')
$expected='Minha colet'+[char]0x00E2+'nea'
if($marker -cne $expected){throw 'Normalizacao incorreta'}
$argv=@('-v','error','-i',$source,'-map','0:a:0','-map_metadata','0','-c:a','copy','-id3v2_version','3','-metadata',('marcador_coletanea='+$marker),'-n',$out)
Invoke-CapturedTestProcess -Program (Join-Path $root 'ffmpeg.exe') -Arguments $argv | Out-Null
if((Get-FileHash -LiteralPath $source).Hash -ne $sourceReceipt.fixture.hash){throw 'Fonte alterada'}
$probeText=(Invoke-CapturedTestProcess -Program (Join-Path $root 'ffprobe.exe') -Arguments @('-v','error','-of','json','-show_format','-show_streams',$out)).Stdout
$after=$probeText|ConvertFrom-Json
$before=$sourceReceipt.probe
foreach($tag in $sourceReceipt.expected_tags.PSObject.Properties){
 if($before.format.tags.($tag.Name) -cne $tag.Value -or $after.format.tags.($tag.Name) -cne $tag.Value){throw "Tag divergente: $($tag.Name)"}
}
$expected='Minha colet'+[char]0x00E2+'nea'
if($after.format.tags.marcador_coletanea -cne $expected){throw 'Marcador incorreto'}
foreach($probe in @($before,$after)){
 if(@($probe.streams).Count -ne 1 -or $probe.streams[0].codec_type -cne 'audio'){throw 'Streams incorretos'}
}
foreach($name in @('codec_name','sample_rate','channels','duration','bit_rate')){
 $a=[string]$before.streams[0].$name; $b=[string]$after.streams[0].$name
 if([string]::IsNullOrEmpty($a) -or $a -cne $b){throw "Parametro divergente: $name"}
}
$payload=@()
foreach($file in @($source,$out)){
 $text=(Invoke-CapturedTestProcess -Program (Join-Path $root 'ffmpeg.exe') -Arguments @('-v','error','-i',$file,'-map','0:a:0','-c:a','copy','-f','hash','-hash','sha256','-')).Stdout
 $match=[regex]::Match($text,'(?im)^SHA256=([0-9a-f]{64})\s*$')
 if(-not $match.Success){throw 'Hash de payload ausente/invalido'}
 $payload+=$match.Groups[1].Value.ToUpperInvariant()
}
if($payload[0] -cne $payload[1]){throw 'Payload comprimido alterado'}
$sourceHash=(Get-FileHash -LiteralPath $source).Hash
if($sourceHash -ne $sourceReceipt.fixture.hash){throw 'Fonte alterada'}
if((Get-Item -LiteralPath $out).Length -le 0){throw 'Saida vazia'}
$ffmpegVersion=(Invoke-CapturedTestProcess -Program (Join-Path $root 'ffmpeg.exe') -Arguments @('-version')).Stdout.Split([char]10)[0].Trim()
$ffprobeVersion=(Invoke-CapturedTestProcess -Program (Join-Path $root 'ffprobe.exe') -Arguments @('-version')).Stdout.Split([char]10)[0].Trim()
$proof=[ordered]@{schema='audios-yb-mp3-marker-proof/v1';source_receipt=$receiptPath;source_file_hash=$sourceHash;output_file_hash=(Get-FileHash -LiteralPath $out).Hash;output=$out;payload_before=$payload[0];payload_after=$payload[1];before=$before;after=$after;marker_expected=$expected;ffmpeg=$ffmpegVersion;ffprobe=$ffprobeVersion;checks=@('7_tags_before_after','1_audio_only','codec_rate_channels_duration_bitrate','compressed_payload_equal','source_file_unchanged');limitations='Windows/FFmpeg/ffprobe; player GUI, M4A, multivalor, idempotencia e integracao nao homologados'}
$proofPath=[IO.Path]::ChangeExtension($out,'.proof.json')
$proof|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $proofPath -Encoding utf8
[pscustomobject]@{result='PASS';receipt_path=$proofPath;payload_sha256=$payload[0];source_preserved=$true}|ConvertTo-Json -Compress
