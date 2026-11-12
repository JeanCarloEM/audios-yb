#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'publicacao_candidato_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Candidato invalido aceito'}
$fixturePath=Join-Path $repo 'tests/fixtures/ffmpeg-version-2026-11-11.json'
if((Get-FileHash -LiteralPath $fixturePath).Hash -cne '3054979865A96EF54F7D9DF5544A4BCBA03DAA65496864FDFCE036A53512C903'){throw 'Fixture alterada'}
$fixture=Get-Content -LiteralPath $fixturePath -Raw|ConvertFrom-Json
$root=Join-Path $PSScriptRoot ('.runtime-publish-verified-['+[guid]::NewGuid().ToString('N')+']');[void][IO.Directory]::CreateDirectory($root)
$payloads=@{ffmpeg=[byte[]](97,98,99);ffprobe=[byte[]](100,101,102)}
foreach($tool in @('ffmpeg','ffprobe')){[IO.File]::WriteAllBytes((Join-Path $root ('source-'+$tool+'.exe')),$payloads[$tool])}
$sentinel=Join-Path $root 'keep.txt';[IO.File]::WriteAllText($sentinel,'preservar')
$script:boundMode='ok';$script:boundCalls=0;$script:boundCase=$fixture.cases[0];$script:boundPath=$null
$invoker={
 param($executable,$arguments,$seconds)
 $script:boundCalls++
 Assert ($executable -ceq $script:boundPath -and @($arguments).Count -eq 1 -and $arguments[0] -ceq '-version' -and $seconds -eq 15) 'Candidato/argv/timeout do invoker'
 Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($executable)) -ceq [Convert]::ToBase64String($payloads[$script:boundCase.tool])) 'Bytes do candidato'
 MustFail {$w=[IO.File]::Open($executable,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$w.Dispose()}
 $reply=@{code=0;timeout=$false;out=$script:boundCase.header;err=''}
 if($script:boundMode -ceq 'header'){$reply.out='PowerShell 7'}
 if($script:boundMode -ceq 'exit'){$reply.code=9}
 if($script:boundMode -ceq 'cancel'){$script:boundCancel.Cancel()}
 return $reply
}
try{
 foreach($case in $fixture.cases){
  $script:boundCase=$case;$script:boundPath=Join-Path $root ('source-'+$case.tool+'.exe')
  $h=[Security.Cryptography.SHA256]::Create();try{$sha=[BitConverter]::ToString($h.ComputeHash($payloads[$case.tool])).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
  $r=Publish-VerifiedFfmpegCandidate $root $script:boundPath $case.tool ([long]3) $sha $case.expected_build $invoker
  $target=Join-Path $root ($case.tool+'.exe')
  Assert ($r -is [hashtable] -and $r.Count -eq 7 -and $r.status -ceq 'published' -and $r.target_path -ceq $target -and $r.size -is [long] -and $r.size -eq 3 -and $r.sha256 -ceq $sha -and $r.tool -ceq $case.tool -and $r.build_version -ceq $case.expected_build -and $r.version_token -ceq $case.expected_token) 'Recibo7/fonte canonica'
  Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -ceq [Convert]::ToBase64String($payloads[$case.tool]) -and [IO.File]::Exists($script:boundPath)) 'Publica bytes e preserva candidato caller'
  $r=Publish-VerifiedFfmpegCandidate $root $script:boundPath $case.tool ([long]3) $sha $case.expected_build $invoker
  Assert ($r.status -ceq 'existing' -and $r.sha256 -ceq $sha) 'Identico existing'
 }
 $script:boundCase=$fixture.cases[0];$script:boundPath=Join-Path $root 'source-ffmpeg.exe';$sha='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
 $ffmpeg=Join-Path $root 'ffmpeg.exe';[IO.File]::WriteAllText($ffmpeg,'xyz')
 MustFail {Publish-VerifiedFfmpegCandidate $root $script:boundPath 'ffmpeg' ([long]3) $sha $script:boundCase.expected_build $invoker}
 Assert ([IO.File]::ReadAllText($ffmpeg) -ceq 'xyz') 'Preserva divergente mesmo tamanho'
 [IO.File]::Delete($ffmpeg)
 foreach($failure in @('header','exit')){$script:boundMode=$failure;MustFail {Publish-VerifiedFfmpegCandidate $root $script:boundPath 'ffmpeg' ([long]3) $sha $script:boundCase.expected_build $invoker};Assert (![IO.File]::Exists($ffmpeg)) 'Falha validacao nao publica'}
 $script:boundMode='cancel';$script:boundCancel=[Threading.CancellationTokenSource]::new()
 try{
  $canceled=$false;try{$null=Publish-VerifiedFfmpegCandidate $root $script:boundPath 'ffmpeg' ([long]3) $sha $script:boundCase.expected_build $invoker -CancellationToken $script:boundCancel.Token}catch{if($_.Exception.GetBaseException() -is [OperationCanceledException]){$canceled=$true}else{throw}}
  Assert $canceled 'Cancelamento durante invoker tipado'
  Assert (![IO.File]::Exists($ffmpeg) -and @([IO.Directory]::EnumerateFiles($root,'.ffmpeg.publish.*')).Count -eq 0) 'Cancelamento apos validacao nao publica'
 }finally{$script:boundCancel.Dispose()}
 $script:boundMode='ok';$callsBefore=$script:boundCalls
 MustFail {Publish-VerifiedFfmpegCandidate $root $script:boundPath 'ffmpeg' ([long]3) ('0'*64) $script:boundCase.expected_build $invoker}
 Assert ($script:boundCalls -eq $callsBefore) 'Hash verificado antes invoker'
 MustFail {Publish-VerifiedFfmpegCandidate $root $script:boundPath 'ffmpeg' ([long]3) $sha $script:boundCase.expected_build $null}
 $cancel=[Threading.CancellationTokenSource]::new();try{$cancel.Cancel();$canceled=$false;try{$null=Publish-VerifiedFfmpegCandidate $root $script:boundPath 'ffmpeg' ([long]3) $sha $script:boundCase.expected_build $invoker -CancellationToken $cancel.Token}catch{if($_.Exception.GetBaseException() -is [OperationCanceledException]){$canceled=$true}else{throw}};Assert $canceled 'Cancelamento previo tipado'}finally{$cancel.Dispose()}
 Assert ($script:boundCalls -eq $callsBefore -and ![IO.File]::Exists($ffmpeg) -and [IO.File]::ReadAllText($sentinel) -ceq 'preservar' -and @([IO.Directory]::EnumerateFiles($root)).Count -eq 4) 'Guardas/ownership/sentinela/sem residuos'
}finally{
 foreach($name in @('ffmpeg.exe','ffprobe.exe','source-ffmpeg.exe','source-ffprobe.exe','keep.txt')){$p=Join-Path $root $name;if([IO.File]::Exists($p)){[IO.File]::Delete($p)}}
 [IO.Directory]::Delete($root,$false)
}
Write-Output "FFMPEG_VERIFIED_PUBLICATION_PASS checks=$checks; payloads abc/def/header canonico/invoker mock, sem binario real"
