#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'verificacao_candidato_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Operacao invalida aceita'}
$fixturePath=Join-Path $repo 'tests/fixtures/ffmpeg-version-2026-11-11.json'
if((Get-FileHash -LiteralPath $fixturePath).Hash -cne '3054979865A96EF54F7D9DF5544A4BCBA03DAA65496864FDFCE036A53512C903'){throw 'Fixture alterada'}
$fixture=Get-Content -LiteralPath $fixturePath -Raw|ConvertFrom-Json
$root=Join-Path $PSScriptRoot ('.runtime-verified-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($root)
$path=Join-Path $root 'candidate.exe';[IO.File]::WriteAllBytes($path,[byte[]](97,98,99))
$sha='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
$script:invoked=0;$script:consumed=0;$script:mode='ok';$script:savedStream=$null
$invoker={
 param($executable,$arguments,$seconds)
 $script:invoked++
 Assert ($executable -ceq $path -and @($arguments).Count -eq 1 -and $arguments[0] -ceq '-version' -and $seconds -eq 15) 'Contrato invoker'
 MustFail {$w=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$w.Dispose()}
 if($script:mode -ceq 'throw'){throw 'mock-execution-error'}
 if($script:mode -ceq 'badshape'){return 'bad'}
 $reply=@{code=0;timeout=$false;out=$fixture.cases[0].header;err=''}
 switch -CaseSensitive ($script:mode){
  'exit' {$reply.code=7} 'timeout' {$reply.timeout=$true}
  'header' {$reply.out='PowerShell 7'} 'tool' {$reply.out=$fixture.cases[1].header}
  'outlimit' {$reply.out='x'*65537} 'errlimit' {$reply.err='x'*65537}
 }
 return $reply
}
$consumer={param($metadata,$absolutePath,$readStream)$script:consumed++;$script:savedStream=$readStream;Assert ($metadata.Count -eq 3 -and $metadata.tool -ceq 'ffmpeg' -and $metadata.version_token -ceq $fixture.cases[0].expected_token) 'Versao validada';Assert ($absolutePath -ceq $path -and $readStream.CanRead -and !$readStream.CanWrite) 'Lock consumidor';'verified-ok'}
try{
 $result=Invoke-WithVerifiedFfmpegCandidate $path ([long]3) $sha 'ffmpeg' $fixture.cases[0].expected_build $invoker $consumer
 Assert ($result -ceq 'verified-ok' -and $script:invoked -eq 1 -and $script:consumed -eq 1 -and !$script:savedStream.CanRead) 'Output/contadores/Dispose'
 foreach($mode in @('exit','timeout','header','tool','outlimit','errlimit','badshape','throw')){
  $script:mode=$mode;MustFail {Invoke-WithVerifiedFfmpegCandidate $path ([long]3) $sha 'ffmpeg' $fixture.cases[0].expected_build $invoker $consumer}
  $w=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::None);$w.Dispose()
  Assert ($script:consumed -eq 1 -and [IO.File]::ReadAllText($path) -ceq 'abc') 'Falha nao consome/libera lock/preserva bytes'
 }
 $script:mode='ok';$before=$script:invoked
 MustFail {Invoke-WithVerifiedFfmpegCandidate $path 3 $sha 'ffmpeg' $fixture.cases[0].expected_build $invoker $consumer}
 MustFail {Invoke-WithVerifiedFfmpegCandidate $path ([long]3) ('0'*64) 'ffmpeg' $fixture.cases[0].expected_build $invoker $consumer}
 MustFail {Invoke-WithVerifiedFfmpegCandidate $path ([long]3) $sha 'FFMPEG' $fixture.cases[0].expected_build $invoker $consumer}
 MustFail {Invoke-WithVerifiedFfmpegCandidate $path ([long]3) $sha 'ffmpeg' '../x' $invoker $consumer}
 MustFail {Invoke-WithVerifiedFfmpegCandidate $path ([long]3) $sha 'ffmpeg' $fixture.cases[0].expected_build $null $consumer}
 MustFail {Invoke-WithVerifiedFfmpegCandidate $path ([long]3) $sha 'ffmpeg' $fixture.cases[0].expected_build $invoker $null}
 Assert ($script:invoked -eq $before -and $script:consumed -eq 1) 'Invalidos antes invoker'
}finally{[IO.File]::Delete($path);[IO.Directory]::Delete($root,$false)}
Write-Output "FFMPEG_VERIFIED_CANDIDATE_PASS checks=$checks; invoker mock/abc/fixture realheader, sem processo"
