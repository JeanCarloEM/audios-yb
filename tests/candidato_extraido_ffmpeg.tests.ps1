#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'candidato_extraido_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Operacao invalida aceita'}
$payloads=@{ffmpeg=[byte[]](97,98,99);ffprobe=[byte[]](100,101,102)}
function New-Fixture([switch]$MissingProbe){
 $memory=[IO.MemoryStream]::new();$zip=[IO.Compression.ZipArchive]::new($memory,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{foreach($name in @('ffmpeg','ffprobe')){if($MissingProbe -and $name -ceq 'ffprobe'){continue};$entry=$zip.CreateEntry('ffmpeg-fixture/bin/'+$name+'.exe');$entry.ExternalAttributes=32;$s=$entry.Open();try{$s.Write($payloads[$name],0,3)}finally{$s.Dispose()}}}finally{$zip.Dispose()}
 return ,$memory
}
$fixtureRoot=Join-Path (Split-Path -Parent $PSScriptRoot) ('.runtime-extracted-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$sentinel=Join-Path $fixtureRoot 'ffmpeg.exe';[IO.File]::WriteAllText($sentinel,'preservar')
$archive=New-Fixture;$script:observedPath=$null;$script:called=0
try{
 foreach($tool in @('ffmpeg','ffprobe')){
  $archive.Position=4
  $result=Invoke-WithExtractedFfmpegCandidate -RootDirectory $fixtureRoot -ArchiveStream $archive -ExpectedRootDirectory 'ffmpeg-fixture' -Tool $tool -Action {
   param($path,$receipt)
   $script:observedPath=$path;$script:called++
   $sha=[Security.Cryptography.SHA256]::Create();try{$expected=[BitConverter]::ToString($sha.ComputeHash($payloads[$tool])).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
   Assert ($receipt.Count -eq 4 -and $receipt.tool -ceq $tool -and $receipt.entry_path -ceq ('ffmpeg-fixture/bin/'+$tool+'.exe') -and $receipt.size -is [long] -and $receipt.size -eq 3 -and $receipt.sha256 -ceq $expected) 'Recibo da fixture independente'
   Assert ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -ceq [Convert]::ToBase64String($payloads[$tool])) 'Bytes arquivo/handle escrita fechado'
   Assert ($archive.Position -eq 4 -and $archive.CanRead -and [IO.Path]::GetDirectoryName($path) -ceq $fixtureRoot) 'Ownership/raiz'
   'extracted-ok'
  }
  Assert ($result -ceq 'extracted-ok' -and ![IO.File]::Exists($script:observedPath)) 'Saida/cleanup sucesso'
 }
 MustFail {Invoke-WithExtractedFfmpegCandidate $fixtureRoot $archive 'ffmpeg-fixture' 'ffmpeg' {param($p,$r)$script:observedPath=$p;throw 'consumer-error'}}
 Assert (![IO.File]::Exists($script:observedPath) -and $archive.CanRead -and $archive.Position -eq 4) 'Cleanup erro'
 MustFail {Invoke-WithExtractedFfmpegCandidate $fixtureRoot $archive 'ffmpeg-fixture' 'ffmpeg' $null}
 $cancel=[Threading.CancellationTokenSource]::new()
 try{$cancel.Cancel();MustFail {Invoke-WithExtractedFfmpegCandidate $fixtureRoot $archive 'ffmpeg-fixture' 'ffmpeg' {$script:called++} -CancellationToken $cancel.Token}}finally{$cancel.Dispose()}
 $archive.Dispose();$archive=New-Fixture -MissingProbe;$archive.Position=4
 MustFail {Invoke-WithExtractedFfmpegCandidate $fixtureRoot $archive 'ffmpeg-fixture' 'ffmpeg' {$script:called++}}
 Assert ($script:called -eq 2 -and $archive.CanRead -and $archive.Position -eq 4 -and @([IO.Directory]::EnumerateFiles($fixtureRoot)).Count -eq 1 -and [IO.File]::ReadAllText($sentinel) -ceq 'preservar') 'Falhas semresiduos/callback/sentinela'
}finally{$archive.Dispose();[IO.File]::Delete($sentinel);[IO.Directory]::Delete($fixtureRoot,$false)}
Write-Output "FFMPEG_EXTRACTED_CANDIDATE_PASS checks=$checks; ZIP sintetico/fixture own, sem executar/publicar"
