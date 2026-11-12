#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'instalacao_executavel_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Composicao invalida aceita'}
$fixturePath=Join-Path $repo 'tests/fixtures/ffmpeg-version-2026-11-11.json'
if((Get-FileHash -LiteralPath $fixturePath).Hash -cne '3054979865A96EF54F7D9DF5544A4BCBA03DAA65496864FDFCE036A53512C903'){throw 'Fixture alterada'}
$fixture=Get-Content -LiteralPath $fixturePath -Raw|ConvertFrom-Json
$payloads=@{ffmpeg=[byte[]](97,98,99);ffprobe=[byte[]](100,101,102)}
$archive=[IO.MemoryStream]::new()
$zip=[IO.Compression.ZipArchive]::new($archive,[IO.Compression.ZipArchiveMode]::Create,$true)
try{foreach($tool in @('ffmpeg','ffprobe')){$entry=$zip.CreateEntry('ffmpeg-fixture/bin/'+$tool+'.exe');$entry.ExternalAttributes=32;$s=$entry.Open();try{$s.Write($payloads[$tool],0,3)}finally{$s.Dispose()}}}finally{$zip.Dispose()}
$root=Join-Path $PSScriptRoot ('.runtime-install-archive-['+[guid]::NewGuid().ToString('N')+']')
[void][IO.Directory]::CreateDirectory($root)
$sentinel=Join-Path $root 'keep.txt';[IO.File]::WriteAllText($sentinel,'preservar')
$script:compositionCalls=0;$script:compositionMode='ok';$script:compositionCase=$fixture.cases[0]
$invoker={
 param($executable,$arguments,$seconds)
 $script:compositionCalls++
 Assert ([IO.Path]::GetDirectoryName($executable) -ceq $root -and @($arguments).Count -eq 1 -and $arguments[0] -ceq '-version' -and $seconds -eq 15) 'Invoker recebe candidato/-version/15'
 Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($executable)) -ceq [Convert]::ToBase64String($payloads[$script:compositionCase.tool])) 'Candidato vem do ZIP sintetico'
 MustFail {$w=[IO.File]::Open($executable,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$w.Dispose()}
 Assert ($archive.CanRead -and $archive.Position -eq 4) 'Archive caller aberto/Position restaurada antes invoker'
 $reply=@{code=0;timeout=$false;out=$script:compositionCase.header;err=''}
 if($script:compositionMode -ceq 'badversion'){$reply.out='PowerShell 7'}
 if($script:compositionMode -ceq 'exit'){$reply.code=7}
 return $reply
}
try{
 foreach($case in $fixture.cases){
  $script:compositionCase=$case;$archive.Position=4
  $r=Install-FfmpegArchiveExecutable $root $archive 'ffmpeg-fixture' $case.tool $case.expected_build $invoker
  $target=Join-Path $root ($case.tool+'.exe')
  $h=[Security.Cryptography.SHA256]::Create();try{$expectedHash=[BitConverter]::ToString($h.ComputeHash($payloads[$case.tool])).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
  Assert ($r -is [hashtable] -and $r.Count -eq 7 -and $r.status -ceq 'published' -and $r.target_path -ceq $target -and $r.tool -ceq $case.tool -and $r.size -is [long] -and $r.size -eq 3 -and $r.sha256 -ceq $expectedHash -and $r.build_version -ceq $case.expected_build -and $r.version_token -ceq $case.expected_token) 'Recibo composto conforme fonte independente'
  Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($target)) -ceq [Convert]::ToBase64String($payloads[$case.tool]) -and $archive.CanRead -and $archive.Position -eq 4 -and @([IO.Directory]::EnumerateFiles($root,'.ffmpeg.candidate.*')).Count -eq 0) 'Publicacao bytes/cleanup/caller'
  $r=Install-FfmpegArchiveExecutable $root $archive 'ffmpeg-fixture' $case.tool $case.expected_build $invoker
  Assert ($r.status -ceq 'existing' -and $r.sha256 -ceq $expectedHash) 'Existing identico'
 }
 $script:compositionCase=$fixture.cases[0]
 $ffmpeg=Join-Path $root 'ffmpeg.exe';[IO.File]::WriteAllText($ffmpeg,'divergente')
 MustFail {Install-FfmpegArchiveExecutable $root $archive 'ffmpeg-fixture' 'ffmpeg' $fixture.cases[0].expected_build $invoker}
 Assert ([IO.File]::ReadAllText($ffmpeg) -ceq 'divergente' -and @([IO.Directory]::EnumerateFiles($root,'.ffmpeg.candidate.*')).Count -eq 0) 'Preserva destino divergente/cleanup'
 [IO.File]::Delete($ffmpeg)
 foreach($failure in @('badversion','exit')){
  $script:compositionMode=$failure
  MustFail {Install-FfmpegArchiveExecutable $root $archive 'ffmpeg-fixture' 'ffmpeg' $fixture.cases[0].expected_build $invoker}
  Assert (![IO.File]::Exists($ffmpeg) -and @([IO.Directory]::EnumerateFiles($root,'.ffmpeg.candidate.*')).Count -eq 0 -and @([IO.Directory]::EnumerateFiles($root,'.ffmpeg.publish.*')).Count -eq 0) 'Versao/execucao invalidas nunca publicam'
 }
 $script:compositionMode='ok';$callsBefore=$script:compositionCalls
 MustFail {Install-FfmpegArchiveExecutable $root $archive 'ffmpeg-fixture' 'ffmpeg' $fixture.cases[0].expected_build $null}
 $cancel=[Threading.CancellationTokenSource]::new()
 try{
  $cancel.Cancel();$canceled=$false
  try{$null=Install-FfmpegArchiveExecutable $root $archive 'ffmpeg-fixture' 'ffmpeg' $fixture.cases[0].expected_build $invoker -CancellationToken $cancel.Token}catch{if($_.Exception.GetBaseException() -is [OperationCanceledException]){$canceled=$true}else{throw}}
  Assert $canceled 'Cancelamento externo tipado'
 }finally{$cancel.Dispose()}
 Assert ($script:compositionCalls -eq $callsBefore -and ![IO.File]::Exists($ffmpeg) -and $archive.CanRead -and $archive.Position -eq 4 -and @([IO.Directory]::EnumerateFiles($root)).Count -eq 2 -and [IO.File]::ReadAllText($sentinel) -ceq 'preservar') 'Guardas antes invoker/semresiduos/sentinela/ownership'
}finally{
 $archive.Dispose()
 foreach($name in @('ffmpeg.exe','ffprobe.exe','keep.txt')){$p=Join-Path $root $name;if([IO.File]::Exists($p)){[IO.File]::Delete($p)}}
 [IO.Directory]::Delete($root,$false)
}
Write-Output "FFMPEG_ARCHIVE_EXECUTABLE_PASS checks=$checks; ZIP sintetico/header canonico/invoker mock, sem executar binario real"
