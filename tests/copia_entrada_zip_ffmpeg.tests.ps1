#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'copia_entrada_zip_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Operacao invalida aceita'}
$payloads=@{ffmpeg=[byte[]](97,98,99);ffprobe=[byte[]](100,101,102)}
function New-Fixture([switch]$MissingProbe){
 $memory=[IO.MemoryStream]::new();$zip=[IO.Compression.ZipArchive]::new($memory,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{
  foreach($name in @('ffmpeg','ffprobe')){
   if($MissingProbe -and $name -ceq 'ffprobe'){continue}
   $entry=$zip.CreateEntry('ffmpeg-fixture/bin/'+$name+'.exe');$entry.ExternalAttributes=32
   $s=$entry.Open();try{$s.Write($payloads[$name],0,3)}finally{$s.Dispose()}
  }
 }finally{$zip.Dispose()}
 return ,$memory
}
$archive=New-Fixture;$destination=[IO.MemoryStream]::new()
try{
 foreach($tool in @('ffmpeg','ffprobe')){
  $archive.Position=4;$destination.SetLength(0)
  $result=Copy-FfmpegZipExecutable -ArchiveStream $archive -ExpectedRootDirectory 'ffmpeg-fixture' -Tool $tool -DestinationStream $destination
  $sha=[Security.Cryptography.SHA256]::Create();try{$expected=[BitConverter]::ToString($sha.ComputeHash($payloads[$tool])).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
  Assert ($result -is [hashtable] -and $result.Count -eq 4 -and $result.tool -ceq $tool -and $result.entry_path -ceq ('ffmpeg-fixture/bin/'+$tool+'.exe') -and $result.size -is [long] -and $result.size -eq 3 -and $result.sha256 -ceq $expected) 'Recibo selecionado'
  Assert ([Convert]::ToBase64String($destination.ToArray()) -ceq [Convert]::ToBase64String($payloads[$tool])) 'Bytes do alvo selecionado'
  Assert ($archive.Position -eq 4 -and $archive.CanRead -and $destination.CanWrite) 'Ownership sucesso'
 }
 foreach($tool in @($null,'FFMPEG','other',1)){
  $archive.Position=4;$destination.SetLength(0);MustFail {Copy-FfmpegZipExecutable $archive 'ffmpeg-fixture' $tool $destination}
  Assert ($archive.Position -eq 4 -and $destination.Length -eq 0) 'Guarda Tool antes IO'
 }
 MustFail {Copy-FfmpegZipExecutable $archive 'ffmpeg-fixture' 'ffmpeg' $archive}
 MustFail {Copy-FfmpegZipExecutable $archive 'ffmpeg-fixture' 'ffmpeg' $null}
 $cancel=[Threading.CancellationTokenSource]::new()
 try{$cancel.Cancel();MustFail {Copy-FfmpegZipExecutable $archive 'ffmpeg-fixture' 'ffmpeg' $destination -CancellationToken $cancel.Token};Assert ($destination.Length -eq 0 -and $archive.CanRead -and $destination.CanWrite) 'Cancelamento ownership'}finally{$cancel.Dispose()}
}finally{$archive.Dispose();$destination.Dispose()}
$archive=New-Fixture -MissingProbe;$destination=[IO.MemoryStream]::new()
try{
 $archive.Position=4;MustFail {Copy-FfmpegZipExecutable $archive 'ffmpeg-fixture' 'ffmpeg' $destination}
 Assert ($archive.Position -eq 4 -and $archive.CanRead -and $destination.Length -eq 0 -and $destination.CanWrite) 'Alvos incompletos antes write'
}finally{$archive.Dispose();$destination.Dispose()}
Write-Output "FFMPEG_ZIP_EXECUTABLE_COPY_PASS checks=$checks; ZIP sintetico em memoria, sem arquivos/publicacao"
