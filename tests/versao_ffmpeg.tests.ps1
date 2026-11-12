#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'versao_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Cabecalho/argumento invalido aceito'}
$fixturePath=Join-Path $repo 'tests/fixtures/ffmpeg-version-2026-11-11.json'
if((Get-FileHash -LiteralPath $fixturePath).Hash -cne '3054979865A96EF54F7D9DF5544A4BCBA03DAA65496864FDFCE036A53512C903'){throw 'Fixture divergente'}
$fixture=Get-Content -LiteralPath $fixturePath -Raw|ConvertFrom-Json
Assert ($fixture.version -eq 1 -and $fixture.cases.Count -eq 2 -and $fixture.source.archive_sha256 -ceq '9ccd65428fb0e60a0d574b76145df41f402b754edd2d06c2e24fa506fc1c2b02') 'Origem independente/proveniencia'
foreach($case in $fixture.cases){
 $r=Read-FfmpegVersionHeader -Output ($case.header+"`r`nconfiguration: fixture`n") -Tool $case.tool -ExpectedBuildVersion $case.expected_build
 Assert ($r -is [hashtable] -and $r.Count -eq 3 -and $r.tool -ceq $case.tool -and $r.build_version -ceq $case.expected_build -and $r.version_token -ceq $case.expected_token) 'Header real/retorno'
}
$build='n9.0.2-49-gc179411bbb'
foreach($token in @($build,($build+'-20240229'))){$r=Read-FfmpegVersionHeader ('ffmpeg version '+$token) 'ffmpeg' $build;Assert ($r.version_token -ceq $token) 'Token exato/data valida'}
foreach($token in @(($build+'0'),($build+'-junk'),($build+'-20260230'),($build+'-20260229'),($build+'-20261311'),($build+'-2026111'),($build+'-20261111-extra'))){MustFail {Read-FfmpegVersionHeader ('ffmpeg version '+$token) 'ffmpeg' $build}}
foreach($output in @($null,123,'',('x'*65537),(' ffmpeg version '+$build),('FFmpeg version '+$build),('ffprobe version '+$build),("`nffmpeg version "+$build))){MustFail {Read-FfmpegVersionHeader $output 'ffmpeg' $build}}
foreach($tool in @($null,1,'FFMPEG','other')){MustFail {Read-FfmpegVersionHeader ('ffmpeg version '+$build) $tool $build}}
foreach($expected in @($null,123,'../x','n9.0.3',($build+"`n"))){MustFail {Read-FfmpegVersionHeader ('ffmpeg version '+$build) 'ffmpeg' $expected}}

foreach($argsCase in @(@('other version n9.0.2','other','n9.0.2'),@('ffmpeg version N9.0.2','ffmpeg','n9.0.2'),@('ffmpeg version N9.0.2','ffmpeg','N9.0.2'),@('ffmpeg version  n9.0.2','ffmpeg','n9.0.2'))){
 $failed=$false;try{$null=Read-FfmpegVersionHeader @argsCase}catch{$failed=$true}
 if(!$failed){throw 'Contraprova case/whitespace aceitou invalido'}
}
Write-Output 'FFMPEG_VERSION_HEADER_PASS checks=33; fixture real preservada/negativos, sem execucao'
