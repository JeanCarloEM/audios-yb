#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'download_temporario_ffmpeg.ps1')
Add-Type -TypeDefinition @'
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public sealed class FfmpegOwnedDownloadHandler : HttpMessageHandler {
 public int Count;
 public bool Disposed;
 protected override void Dispose(bool disposing){Disposed=true;base.Dispose(disposing);}
 protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage r,CancellationToken t){
  Count++;
  return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=new ByteArrayContent(new byte[]{97,98,99})});
 }
}
'@
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Operacao invalida aceita'}
$root=Join-Path $PSScriptRoot ('.runtime-owned-download-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$keep=Join-Path $root 'keep.txt';[IO.File]::WriteAllText($keep,'sentinela')
$uri='https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-11-10-12-39/ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'
$sha='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
try{
 $script:Calls=0;$script:Candidate=$null;$script:SavedStream=$null
 $consumer={param($stream,$receipt)
  $script:Calls++;$script:Candidate=$stream.Name;$script:SavedStream=$stream
  Assert ($stream -is [IO.FileStream] -and $stream.Position -eq 0 -and $stream.Length -eq 3) 'Consumidor recebe arquivo verificado e rebobinado'
  Assert ($receipt -is [hashtable] -and $receipt.Count -eq 2 -and $receipt.size -is [long] -and $receipt.size -eq 3 -and $receipt.sha256 -ceq $sha) 'Recibo de transferencia verificada'
  Assert ($stream.ReadByte() -eq 97) 'Consumidor pode ler bytes desde inicio'
  return 'consumer-ok'
 }
 $h=[FfmpegOwnedDownloadHandler]::new()
 $r=Invoke-WithFfmpegDownloadedArchive -RootDirectory $root -Uri $uri -ExpectedSize ([long]3) -ExpectedSha256 $sha -Action $consumer -Handler $h -TimeoutSeconds 5
 Assert ($r -is [string] -and $r -ceq 'consumer-ok' -and $script:Calls -eq 1 -and $h.Count -eq 1) 'Retorna somente saida do consumidor apos transferencia'
 Assert (!$h.Disposed -and !$script:SavedStream.CanRead -and ![IO.File]::Exists($script:Candidate)) 'Handler caller-owned e temporario encerrado/excluido'
 $script:FailurePath=$null;$h=[FfmpegOwnedDownloadHandler]::new()
 MustFail {Invoke-WithFfmpegDownloadedArchive -RootDirectory $root -Uri $uri -ExpectedSize ([long]3) -ExpectedSha256 $sha -Action {param($stream,$receipt) $script:FailurePath=$stream.Name;throw 'consumer-fail'} -Handler $h}
 Assert (![IO.File]::Exists($script:FailurePath) -and !$h.Disposed) 'Erro consumidor preservado com cleanup proprio'
 $h=[FfmpegOwnedDownloadHandler]::new()
 MustFail {Invoke-WithFfmpegDownloadedArchive -RootDirectory $root -Uri $uri -ExpectedSize ([long]3) -ExpectedSha256 ('0'*64) -Action $consumer -Handler $h}
 Assert ($h.Count -eq 1 -and $script:Calls -eq 1 -and [IO.Directory]::GetFiles($root).Count -eq 1) 'Hash invalido nao chama consumidor nem deixa temporario'
 $h=[FfmpegOwnedDownloadHandler]::new();$cts=[Threading.CancellationTokenSource]::new();$cts.Cancel()
 try{MustFail {Invoke-WithFfmpegDownloadedArchive -RootDirectory $root -Uri $uri -ExpectedSize ([long]3) -ExpectedSha256 $sha -Action $consumer -Handler $h -CancellationToken $cts.Token}}finally{$cts.Dispose()}
 Assert ($h.Count -eq 0 -and $script:Calls -eq 1 -and [IO.Directory]::GetFiles($root).Count -eq 1) 'Cancelamento sem rede/consumidor/temporario restante'
 $h=[FfmpegOwnedDownloadHandler]::new()
 MustFail {Invoke-WithFfmpegDownloadedArchive -RootDirectory $root -Uri $uri -ExpectedSize ([long]3) -ExpectedSha256 $sha -Action $null -Handler $h}
 MustFail {Invoke-WithFfmpegDownloadedArchive -RootDirectory $keep -Uri $uri -ExpectedSize ([long]3) -ExpectedSha256 $sha -Action $consumer -Handler $h}
 Assert ($h.Count -eq 0 -and $script:Calls -eq 1) 'Action/root invalidos antes HTTP'
 Assert ([IO.File]::ReadAllText($keep) -ceq 'sentinela' -and [IO.Directory]::GetFiles($root).Count -eq 1) 'Arquivo preexistente preservado'
}finally{
 if([IO.File]::Exists($keep)){[IO.File]::Delete($keep)}
 [IO.Directory]::Delete($root,$false)
}
"FFMPEG_OWNED_DOWNLOAD_PASS checks$script:Checks; HTTP/bytes sinteticos e fixture propria, sem ZIP/instalacao"
