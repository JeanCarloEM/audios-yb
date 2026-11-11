#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'copia_stream_ffmpeg.ps1')
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
public class ArchiveNonSeekingStream : MemoryStream {
 public ArchiveNonSeekingStream(byte[] b):base(b,false){}
 public override bool CanSeek {get{return false;}}
 public override long Length {get{throw new NotSupportedException();}}
 public override long Position {get{throw new NotSupportedException();}set{throw new NotSupportedException();}}
}
public sealed class ArchiveBlockingStream : ArchiveNonSeekingStream {
 public bool ObservedToken;
 public bool Cancelled;
 public ArchiveBlockingStream():base(new byte[0]){}
 public override async Task<int> ReadAsync(byte[] b,int o,int n,CancellationToken t) {
  ObservedToken=t.CanBeCanceled;
  try{await Task.Delay(Timeout.Infinite,t);}catch(OperationCanceledException){Cancelled=true;throw;}
  return 0;
 }
}
'@
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Copia invalida aceita'}
$abc=[Text.Encoding]::ASCII.GetBytes('abc')
# Vetor SHA256 publicado para ASCII abc; independe do codigo sob teste.
$sha='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
$source=[ArchiveNonSeekingStream]::new($abc);$dest=[IO.MemoryStream]::new()
try{
 $r=Copy-CheckedFfmpegArchiveStream -Source $source -Destination $dest -ExpectedSize ([long]3) -ExpectedSha256 $sha
 Assert ($r -is [hashtable] -and $r.Count -eq 2 -and $r.size -is [long] -and $r.size -eq 3 -and $r.sha256 -ceq $sha) 'Recibo exato de tamanho e hash'
 Assert ([Text.Encoding]::ASCII.GetString($dest.ToArray()) -ceq 'abc') 'Copiar sem exigir Length/Position/Seek da origem'
 Assert ($source.CanRead -and $dest.CanWrite) 'Streams pertencem ao chamador'
}finally{$source.Dispose();$dest.Dispose()}
$many=[Text.Encoding]::ASCII.GetBytes(('abc'*100000))
$reference=[Security.Cryptography.SHA256]::Create()
try{$manySha=([BitConverter]::ToString($reference.ComputeHash($many))).Replace('-','').ToLowerInvariant()}finally{$reference.Dispose()}
$source=[ArchiveNonSeekingStream]::new($many);$dest=[IO.MemoryStream]::new()
try{$r=Copy-CheckedFfmpegArchiveStream -Source $source -Destination $dest -ExpectedSize ([long]$many.Length) -ExpectedSha256 $manySha;Assert ($r.size -eq 300000 -and $r.sha256 -ceq $manySha -and [Text.Encoding]::ASCII.GetString($dest.ToArray()) -ceq ('abc'*100000)) 'Multiplos chunks vinculados a entrada e SHA referencia independente'}finally{$source.Dispose();$dest.Dispose()}
foreach($case in @('oversize','short','hash')){
 $source=[IO.MemoryStream]::new($abc,$false);$dest=[IO.MemoryStream]::new()
 try{
  $size=if($case -ceq 'oversize'){[long]2}elseif($case -ceq 'short'){[long]4}else{[long]3}
  $expected=if($case -ceq 'hash'){'0'*64}else{$sha}
  MustFail {Copy-CheckedFfmpegArchiveStream -Source $source -Destination $dest -ExpectedSize $size -ExpectedSha256 $expected}
  Assert ($source.CanRead -and $dest.CanWrite) 'Falha nao deve fechar streams'
  if($case -ceq 'oversize'){Assert ($dest.Length -eq 0) 'Nao escrever chunk que ultrapassa limite'}
 }finally{$source.Dispose();$dest.Dispose()}
}
foreach($badSize in @($null,3,'3',([long]0),([long]536870913))){
 $source=[IO.MemoryStream]::new($abc,$false);$dest=[IO.MemoryStream]::new()
 try{MustFail {Copy-CheckedFfmpegArchiveStream -Source $source -Destination $dest -ExpectedSize $badSize -ExpectedSha256 $sha};Assert ($source.Position -eq 0 -and $dest.Length -eq 0) 'Tamanho invalido antesIO'}finally{$source.Dispose();$dest.Dispose()}
}
foreach($badSha in @($null,123,$sha.ToUpperInvariant(),$sha.Substring(1))){
 $source=[IO.MemoryStream]::new($abc,$false);$dest=[IO.MemoryStream]::new()
 try{MustFail {Copy-CheckedFfmpegArchiveStream -Source $source -Destination $dest -ExpectedSize ([long]3) -ExpectedSha256 $badSha};Assert ($source.Position -eq 0 -and $dest.Length -eq 0) 'SHA invalido antesIO'}finally{$source.Dispose();$dest.Dispose()}
}
$same=[IO.MemoryStream]::new($abc)
try{MustFail {Copy-CheckedFfmpegArchiveStream -Source $same -Destination $same -ExpectedSize ([long]3) -ExpectedSha256 $sha};Assert ($same.Position -eq 0) 'Streams iguais recusados antesIO'}finally{$same.Dispose()}
$source=[IO.MemoryStream]::new($abc,$false);$dest=[IO.MemoryStream]::new();$cts=[Threading.CancellationTokenSource]::new();$cts.Cancel()
try{MustFail {Copy-CheckedFfmpegArchiveStream -Source $source -Destination $dest -ExpectedSize ([long]3) -ExpectedSha256 $sha -CancellationToken $cts.Token};Assert ($source.Position -eq 0 -and $dest.Length -eq 0) 'Cancelamento externo antesIO'}finally{$cts.Dispose();$source.Dispose();$dest.Dispose()}
$source=[ArchiveBlockingStream]::new();$dest=[IO.MemoryStream]::new();$watch=[Diagnostics.Stopwatch]::StartNew()
try{MustFail {Copy-CheckedFfmpegArchiveStream -Source $source -Destination $dest -ExpectedSize ([long]3) -ExpectedSha256 $sha -TimeoutSeconds 1};Assert ($source.ObservedToken -and $source.Cancelled -and $watch.Elapsed.TotalSeconds -lt 10) 'Timeout finito cancela ReadAsync bloqueado'}finally{$source.Dispose();$dest.Dispose()}
"FFMPEG_ARCHIVE_STREAM_PASS checks$script:Checks; bytes sinteticos, sem HTTP/arquivos/validacaoZIP"
