#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'transporte_release_ytdlp.ps1')
# Transporte injetado somente nos testes; nenhum acesso de rede.
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
public sealed class ReleaseProbeHandler : HttpMessageHandler {
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
public sealed class ReleaseProbeContent : HttpContent {
 private readonly byte[] data;
 public int Reads;
 public bool Disposed;
 public Stream Body;
 public ReleaseProbeContent(byte[] d) {data=d;}
 protected override bool TryComputeLength(out long length) {length=0;return false;}
 protected override Task SerializeToStreamAsync(Stream stream, TransportContext context) {return stream.WriteAsync(data,0,data.Length);}
 protected override Task<Stream> CreateContentReadStreamAsync() {Reads++;return Task.FromResult<Stream>(Body ?? new MemoryStream(data,false));}
 protected override void Dispose(bool disposing) {Disposed=true;base.Dispose(disposing);}
}
public sealed class ReleaseBlockingStream : Stream {
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
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
function Reply([int]$Code,[string]$Body='abc',[string]$Location=''){
 $r=[Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]$Code)
 $r.Content=[ReleaseProbeContent]::new([Text.Encoding]::ASCII.GetBytes($Body))
 if($Location){$r.Headers.Location=[uri]::new($Location,[UriKind]::RelativeOrAbsolute)}
 return $r
}
function MustFail([scriptblock]$Action,[string]$Why){$failed=$false;try{$null=& $Action}catch{$failed=$true};Assert $failed $Why}
$api='https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'
$asset='https://github.com/yt-dlp/yt-dlp/releases/download/2026.01.02/yt-dlp.exe'
$cdn='https://release-assets.githubusercontent.com/github-production-release-asset/fixture?sig=synthetic'
$h=[ReleaseProbeHandler]::new();$r=Reply 200;$content=$r.Content;$h.Replies.Enqueue($r)
$bytes=Get-YtdlpReleaseBytes -Uri $api -MaxBytes 3 -TimeoutSeconds 5 -Handler $h
Assert ($bytes -is [byte[]] -and [Text.Encoding]::ASCII.GetString($bytes) -ceq 'abc') 'Retornar byte[] exato sem enumerar no pipeline'
Assert ($h.Seen.Count -eq 1 -and $h.Seen[0] -ceq $api -and $h.Agent.Length -gt 0 -and $h.TokenWasCancellable) 'Pedido limitado e User-Agent para API'
Assert $content.Disposed 'Response/content devem ser liberados no sucesso'
Assert (-not $h.Disposed) 'Handler injetado pertence ao chamador'
$h=[ReleaseProbeHandler]::new();$h.Replies.Enqueue((Reply 302 '' $cdn));$h.Replies.Enqueue((Reply 200))
$bytes=Get-YtdlpReleaseBytes -Uri $asset -MaxBytes 3 -TimeoutSeconds 5 -Handler $h
Assert ($h.Seen.Count -eq 2 -and $h.Seen[1] -ceq $cdn -and [Text.Encoding]::ASCII.GetString($bytes) -ceq 'abc') 'Redirect oficial para CDN deve funcionar'
foreach($uri in @(
 'http://github.com/yt-dlp/yt-dlp/releases/download/v1/yt-dlp.exe',
 'https://github.com.evil.test/yt-dlp/yt-dlp/releases/download/v1/yt-dlp.exe',
 'https://evil.test/x','https://user:pass@github.com/yt-dlp/yt-dlp/releases/download/v1/yt-dlp.exe',
 'https://github.com:8443/yt-dlp/yt-dlp/releases/download/v1/yt-dlp.exe',
 'https://github.com/other/repo/releases/download/v1/yt-dlp.exe',
 'https://github.com/yt-dlp/yt-dlp/releases/download/latest/yt-dlp.exe',
 'https://github.com/yt-dlp/yt-dlp/releases/download/v1/evil.exe',
 ($asset+'?external=x'),($asset+'#fragment'),($asset+'/extra'),($asset.Replace('yt-dlp.exe','YT-DLP.EXE')),$cdn,($api+'/'),($api+'other'),($api+'?x=y'),'relative/path'
)){
 $h=[ReleaseProbeHandler]::new();MustFail {Get-YtdlpReleaseBytes -Uri $uri -Handler $h} 'URI inicial nao autorizada'
 Assert ($h.Seen.Count -eq 0) 'URI recusada deve falhar antes de enviar'
}
foreach($location in @('https://evil.test/x','http://release-assets.githubusercontent.com/x','https://release-assets.githubusercontent.com.evil.test/x','https://user@release-assets.githubusercontent.com/x','https://release-assets.githubusercontent.com:8443/x',($cdn+'#x'))){
 $h=[ReleaseProbeHandler]::new();$h.Replies.Enqueue((Reply 302 '' $location))
 MustFail {Get-YtdlpReleaseBytes -Uri $asset -Handler $h} 'Redirect inseguro deve falhar'
 Assert ($h.Seen.Count -eq 1) 'Nao enviar pedido ao redirect recusado'
}
$h=[ReleaseProbeHandler]::new();$h.Replies.Enqueue((Reply 302 '' $cdn))
MustFail {Get-YtdlpReleaseBytes -Uri $api -Handler $h} 'API de metadata nao deve redirecionar a CDN'
Assert ($h.Seen.Count -eq 1) 'API recusada fez segundo pedido'
foreach($code in @(206,404,500,302)){
 $h=[ReleaseProbeHandler]::new();$r=Reply $code;$content=$r.Content;$h.Replies.Enqueue($r)
 MustFail {Get-YtdlpReleaseBytes -Uri $asset -Handler $h} 'Rejeitar status nao200 ou redirect sem Location'
 Assert $content.Disposed 'Liberar response tambem na falha'
}
$h=[ReleaseProbeHandler]::new();$r=Reply 200 'excessivo';$r.Content.Headers.ContentLength=9;$content=$r.Content;$h.Replies.Enqueue($r)
MustFail {Get-YtdlpReleaseBytes -Uri $api -MaxBytes 3 -Handler $h} 'Content-Length maior deve falhar'
Assert ($content.Reads -eq 0 -and $content.Disposed) 'Nao ler corpo declarado excessivo'
$h=[ReleaseProbeHandler]::new();$r=Reply 200 'excessivo';$content=$r.Content;$h.Replies.Enqueue($r)
MustFail {Get-YtdlpReleaseBytes -Uri $api -MaxBytes 3 -Handler $h} 'Corpo sem tamanho declarado tambem limitado'
Assert $content.Disposed 'Limite durante leitura deve liberar response'
$h=[ReleaseProbeHandler]::new();for($i=0;$i -lt 6;$i++){$h.Replies.Enqueue((Reply 302 '' $cdn))}
MustFail {Get-YtdlpReleaseBytes -Uri $asset -Handler $h} 'Limitar cadeia de redirects'
Assert ($h.Seen.Count -eq 5) 'Maximo quatro redirects, cinco pedidos'
$h=[ReleaseProbeHandler]::new();$h.WaitForCancellation=$true
$watch=[Diagnostics.Stopwatch]::StartNew()
MustFail {Get-YtdlpReleaseBytes -Uri $api -TimeoutSeconds 1 -Handler $h} 'Timeout deve cancelar pedido pendente'
Assert ($h.TokenWasCancellable -and $watch.Elapsed.TotalSeconds -lt 10) 'Cancelamento finito deve atingir handler'
$h=[ReleaseProbeHandler]::new();$r=Reply 200;$blocked=[ReleaseBlockingStream]::new();$r.Content.Body=$blocked;$content=$r.Content;$h.Replies.Enqueue($r)
MustFail {Get-YtdlpReleaseBytes -Uri $api -TimeoutSeconds 1 -Handler $h} 'Timeout tambem deve cancelar corpo bloqueado'
Assert ($blocked.TokenWasCancellable -and $blocked.WasCancelled -and $content.Disposed) 'ReadAsync deve receber token e liberar response apos cancelar'
foreach($code in @(301,303,307,308)){
 $h=[ReleaseProbeHandler]::new();$h.Replies.Enqueue((Reply $code '' $cdn));$h.Replies.Enqueue((Reply 200))
 $bytes=Get-YtdlpReleaseBytes -Uri $asset -Handler $h
 Assert ($h.Seen.Count -eq 2 -and [Text.Encoding]::ASCII.GetString($bytes) -ceq 'abc') 'Todos redirects autorizados devem funcionar'
}
$h=[ReleaseProbeHandler]::new();$h.Replies.Enqueue((Reply 302 '' $cdn));$h.Replies.Enqueue((Reply 303 '' '/next?sig=fixture'));$h.Replies.Enqueue((Reply 200))
$bytes=Get-YtdlpReleaseBytes -Uri $asset -Handler $h
Assert ($h.Seen.Count -eq 3 -and $h.Seen[2] -ceq 'https://release-assets.githubusercontent.com/next?sig=fixture') 'Validar e resolver redirect relativo na CDN'
'YTDLP_HTTPS_TRANSPORT_PASS checks'+$script:Checks+'; rede simulada, nao comprova download real ou autenticidade de release'
