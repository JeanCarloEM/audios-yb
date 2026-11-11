#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'transporte_arquivo_ffmpeg.ps1')
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
public sealed class FfmpegArchiveProbeHandler : HttpMessageHandler {
 public readonly Queue<HttpResponseMessage> Replies = new Queue<HttpResponseMessage>();
 public readonly List<string> Seen = new List<string>();
 public bool WaitForCancellation;
 public bool TokenWasCancellable;
 public string Agent;
 public bool Disposed;
 protected override void Dispose(bool disposing) {Disposed=true;base.Dispose(disposing);}
 protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage r, CancellationToken token) {
  Seen.Add(r.RequestUri.AbsoluteUri); Agent=r.Headers.UserAgent.ToString(); TokenWasCancellable=token.CanBeCanceled;
  if(WaitForCancellation) return Wait(token);
  if(Replies.Count==0) throw new InvalidOperationException("Unexpected request");
  return Task.FromResult(Replies.Dequeue());
 }
 private async Task<HttpResponseMessage> Wait(CancellationToken t) {await Task.Delay(Timeout.Infinite,t);return null;}
}
public sealed class FfmpegArchiveProbeContent : HttpContent {
 private readonly byte[] data;
 public int Reads;
 public bool Disposed;
 public Stream Body;
 public FfmpegArchiveProbeContent(byte[] d) {data=d;}
 protected override bool TryComputeLength(out long length) {length=0;return false;}
 protected override Task SerializeToStreamAsync(Stream stream, TransportContext context) {return stream.WriteAsync(data,0,data.Length);}
 protected override Task<Stream> CreateContentReadStreamAsync() {Reads++;return Task.FromResult<Stream>(Body ?? new MemoryStream(data,false));}
 protected override void Dispose(bool disposing) {Disposed=true;base.Dispose(disposing);}
}
public sealed class FfmpegArchiveBlockingStream : Stream {
 public bool TokenWasCancellable;
 public bool WasCancelled;
 public override bool CanRead {get{return true;}}
 public override bool CanSeek {get{return false;}}
 public override bool CanWrite {get{return false;}}
 public override long Length {get{throw new NotSupportedException();}}
 public override long Position {get{throw new NotSupportedException();}set{throw new NotSupportedException();}}
 public override void Flush() {throw new NotSupportedException();}
 public override long Seek(long x, SeekOrigin o) {throw new NotSupportedException();}
 public override void SetLength(long x) {throw new NotSupportedException();}
 public override void Write(byte[] b,int x,int n) {throw new NotSupportedException();}
 public override int Read(byte[] b,int x,int n) {throw new InvalidOperationException("Synchronous body Read forbidden");}
 public override async Task<int> ReadAsync(byte[] b,int x,int n,CancellationToken token) {
  TokenWasCancellable=token.CanBeCanceled;
  try {await Task.Delay(Timeout.Infinite,token);}catch(OperationCanceledException){WasCancelled=true;throw;}
  return 0;
 }
}
'@
$script:Checks=0
$script:Destination=$null
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Transferencia invalida aceita'}
function Reply([int]$code,[string]$body='abc',[string]$location=''){
 $r=[Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]$code)
 $r.Content=[FfmpegArchiveProbeContent]::new([Text.Encoding]::ASCII.GetBytes($body))
 if($location){$r.Headers.Location=[uri]::new($location,[UriKind]::RelativeOrAbsolute)}
 return $r
}
$archive='https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-11-10-12-39/ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'
$cdn='https://release-assets.githubusercontent.com/object?sig=synthetic'
$sha='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
function Invoke-Probe($handler,[object]$uri=$archive,[object]$size=([long]3),[object]$hash=$sha,[int]$timeout=5,[Threading.CancellationToken]$token=[Threading.CancellationToken]::None){
 if($null -ne $script:Destination){$script:Destination.Dispose()}
 $script:Destination=[IO.MemoryStream]::new()
 return Receive-FfmpegArchiveStream -Uri $uri -Destination $script:Destination -ExpectedSize $size -ExpectedSha256 $hash -TimeoutSeconds $timeout -CancellationToken $token -Handler $handler
}
try{
 $h=[FfmpegArchiveProbeHandler]::new();$response=Reply 200;$content=$response.Content;$h.Replies.Enqueue($response)
 $r=Invoke-Probe $h
 Assert ($r -is [hashtable] -and $r.Count -eq 2 -and $r.size -is [long] -and $r.size -eq 3 -and $r.sha256 -ceq $sha) 'Recibo da primitiva size/SHA'
 Assert ([Text.Encoding]::ASCII.GetString($script:Destination.ToArray()) -ceq 'abc') 'Bytes transmitidos ao destino'
 Assert ($h.Seen.Count -eq 1 -and $h.Seen[0] -ceq $archive -and $h.Agent.Length -gt 0 -and $h.TokenWasCancellable) 'GET canonico e token/UserAgent'
 Assert ($content.Disposed -and !$h.Disposed -and $script:Destination.CanWrite) 'Response proprio descartado; handler/destino pertencem caller'
 foreach($uri in @('https://api.github.com/repos/FFmpeg-Builds/FFmpeg-Builds/releases?per_page=3',$archive.Replace('ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip','checksums.sha256'),$cdn,$archive.Replace('https:','http:'),$archive.Replace('github.com','evil.test'),$archive.Replace('lgpl-9.0.zip','gpl-9.0.zip'),($archive+'?x=1'))){
  $h=[FfmpegArchiveProbeHandler]::new();MustFail {Invoke-Probe $h -uri $uri};Assert ($h.Seen.Count -eq 0) 'URL invalida antes HTTP'
 }
 foreach($size in @($null,3,'3',([long]0),([long]536870913))){$h=[FfmpegArchiveProbeHandler]::new();MustFail {Invoke-Probe $h -size $size};Assert ($h.Seen.Count -eq 0) 'Size invalido antes HTTP'}
 foreach($hash in @($null,123,$sha.ToUpperInvariant())){$h=[FfmpegArchiveProbeHandler]::new();MustFail {Invoke-Probe $h -hash $hash};Assert ($h.Seen.Count -eq 0) 'SHA invalido antes HTTP'}
 foreach($code in @(301,302,303,307,308)){
  $h=[FfmpegArchiveProbeHandler]::new();$h.Replies.Enqueue((Reply $code '' $cdn));$h.Replies.Enqueue((Reply 200))
  $r=Invoke-Probe $h;Assert ($h.Seen.Count -eq 2 -and $r.sha256 -ceq $sha) 'Redirect permitido preserva verificacao'
 }
 foreach($location in @('https://evil.test/x','http://release-assets.githubusercontent.com/x',($cdn+'#x'),'https://user@release-assets.githubusercontent.com/x')){
  $h=[FfmpegArchiveProbeHandler]::new();$h.Replies.Enqueue((Reply 302 '' $location));MustFail {Invoke-Probe $h};Assert ($h.Seen.Count -eq 1) 'Destino redirect recusado sem envio'
 }
 $h=[FfmpegArchiveProbeHandler]::new();for($i=0;$i -lt 6;$i++){$h.Replies.Enqueue((Reply 302 '' $cdn))};MustFail {Invoke-Probe $h};Assert ($h.Seen.Count -eq 5) 'Ate quatro redirects/cinco pedidos'
 $h=[FfmpegArchiveProbeHandler]::new();$h.Replies.Enqueue((Reply 302 '' $cdn));$h.Replies.Enqueue((Reply 303 '' '/next?sig=synthetic'));$h.Replies.Enqueue((Reply 200));$r=Invoke-Probe $h;Assert ($h.Seen.Count -eq 3 -and $h.Seen[2] -ceq 'https://release-assets.githubusercontent.com/next?sig=synthetic' -and $r.size -eq 3) 'Redirect relativo na CDN'
 foreach($code in @(206,404,500,302)){$h=[FfmpegArchiveProbeHandler]::new();$r=Reply $code;$content=$r.Content;$h.Replies.Enqueue($r);MustFail {Invoke-Probe $h};Assert $content.Disposed 'Status/Location invalidos descartam response'}
 $h=[FfmpegArchiveProbeHandler]::new();$r=Reply 200;$r.Content.Headers.ContentLength=4;$content=$r.Content;$h.Replies.Enqueue($r);MustFail {Invoke-Probe $h};Assert ($content.Reads -eq 0 -and $content.Disposed -and $script:Destination.Length -eq 0) 'ContentLength divergente antes leitura'
 $h=[FfmpegArchiveProbeHandler]::new();$h.Replies.Enqueue((Reply 200 'abcd'));MustFail {Invoke-Probe $h};Assert ($script:Destination.Length -eq 0) 'Chunk excessivo nao escrito'
 $h=[FfmpegArchiveProbeHandler]::new();$h.Replies.Enqueue((Reply 200 'ab'));MustFail {Invoke-Probe $h};Assert ($script:Destination.Length -eq 2) 'Tamanho curto falha; parcial pertence caller'
 $h=[FfmpegArchiveProbeHandler]::new();$h.Replies.Enqueue((Reply 200));MustFail {Invoke-Probe $h -hash ('0'*64)};Assert ($script:Destination.Length -eq 3 -and $script:Destination.CanWrite) 'Hash divergente nao publica sucesso nem fecha destino'
 $h=[FfmpegArchiveProbeHandler]::new();$h.WaitForCancellation=$true;$watch=[Diagnostics.Stopwatch]::StartNew();MustFail {Invoke-Probe $h -timeout 1};Assert ($h.TokenWasCancellable -and $watch.Elapsed.TotalSeconds -lt 10) 'Deadline cancela envio bloqueado'
 $h=[FfmpegArchiveProbeHandler]::new();$r=Reply 200;$blocked=[FfmpegArchiveBlockingStream]::new();$r.Content.Body=$blocked;$content=$r.Content;$h.Replies.Enqueue($r);MustFail {Invoke-Probe $h -timeout 1};Assert ($blocked.WasCancelled -and $content.Disposed) 'Deadline cobre corpo e libera response'
 $h=[FfmpegArchiveProbeHandler]::new();$cts=[Threading.CancellationTokenSource]::new();$cts.Cancel();try{MustFail {Invoke-Probe $h -token $cts.Token};Assert ($h.Seen.Count -eq 0) 'Token externo cancelado antes envio'}finally{$cts.Dispose()}
 'FFMPEG_ARCHIVE_TRANSPORT_PASS checks'+$script:Checks+'; HTTP/bytes sinteticos, sem arquivos ou validacaoZIP'
}finally{if($null -ne $script:Destination){$script:Destination.Dispose()}}
