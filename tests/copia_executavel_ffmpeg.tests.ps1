#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'copia_executavel_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Operacao invalida aceita'}
$source=[IO.MemoryStream]::new([byte[]](97,98,99));$dest=[IO.MemoryStream]::new()
try{
 $r=Copy-FfmpegExecutableStream -SourceStream $source -DestinationStream $dest -ExpectedSize ([long]3)
 Assert ($r -is [hashtable] -and $r.Count -eq 2 -and $r.size -is [long] -and $r.size -eq 3 -and $r.sha256 -ceq 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') 'Recibo/hash abc independente'
 Assert ([Convert]::ToBase64String($dest.ToArray()) -ceq 'YWJj') 'Bytes copiados'
 Assert ($source.CanRead -and $dest.CanWrite) 'Ownership sucesso'
 foreach($size in @($null,3,'3',[long]0,[long]536870913)){
  $source.Position=0;$dest.SetLength(0)
  MustFail {Copy-FfmpegExecutableStream $source $dest $size}
  Assert ($source.Position -eq 0 -and $dest.Length -eq 0) 'Guarda antes IO'
 }
 foreach($size in @([long]2,[long]4)){
  $source.Position=0;$dest.SetLength(0);MustFail {Copy-FfmpegExecutableStream $source $dest $size}
  Assert ($source.CanRead -and $dest.CanWrite) 'Ownership erro'
 }
 $source.Position=0;$dest.SetLength(0)
 MustFail {Copy-FfmpegExecutableStream $source $source ([long]3)}
 MustFail {Copy-FfmpegExecutableStream $null $dest ([long]3)}
 MustFail {Copy-FfmpegExecutableStream $source $null ([long]3)}
 $cancel=[Threading.CancellationTokenSource]::new()
 try{
  $cancel.Cancel();MustFail {Copy-FfmpegExecutableStream $source $dest ([long]3) -CancellationToken $cancel.Token}
  Assert ($dest.Length -eq 0 -and $source.CanRead -and $dest.CanWrite) 'Cancelamento/ownership'
 }finally{$cancel.Dispose()}
}finally{$source.Dispose();$dest.Dispose()}
Write-Output "FFMPEG_EXECUTABLE_COPY_PASS checks=$checks; bytes sinteticos, sem ZIP/IO/publicacao"
