#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'consulta_tag_ffmpeg.ps1')
Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public sealed class FfmpegTagHandler : HttpMessageHandler {
 public byte[] Body;
 public int Count;
 public string Uri;
 protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage r,CancellationToken t) {
  Count++;Uri=r.RequestUri.AbsoluteUri;
  return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=new ByteArrayContent(Body)});
 }
}
'@
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function MustFail([scriptblock]$action,$message){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed $message}
$utf8=[Text.UTF8Encoding]::new($false,$true)
$list='[{"tag_name":"autobuild-2026-11-09-12-39","draft":false,"prerelease":false},{"tag_name":"latest","draft":false,"prerelease":false},{"tag_name":"autobuild-2026-11-10-12-39","draft":false,"prerelease":false}]'
$h=[FfmpegTagHandler]::new();$h.Body=$utf8.GetBytes($list)
$tag=Get-FfmpegDatedReleaseTag -Handler $h -TimeoutSeconds 5
Assert ($tag -is [string] -and $tag -ceq 'autobuild-2026-11-10-12-39') 'Selecionar tag datada mais recente sem latest'
Assert ($h.Count -eq 1 -and $h.Uri -ceq 'https://api.github.com/repos/FFmpeg-Builds/FFmpeg-Builds/releases?per_page=3') 'Unico GET na API limitada; sem consultar assets'
foreach($json in @('[]','{}','[{"tag_name":"autobuild-2026-02-30-12-39","draft":false,"prerelease":false}]','[{"tag_name":"autobuild-2026-11-10-12-39","draft":true,"prerelease":false}]','[{"tag_name":"autobuild-2026-11-10-12-39","draft":false,"prerelease":true}]')){
 $h=[FfmpegTagHandler]::new();$h.Body=$utf8.GetBytes($json)
 MustFail {Get-FfmpegDatedReleaseTag -Handler $h} 'Lista invalida ou sem release elegivel'
 Assert ($h.Count -eq 1) 'Nao iniciar consulta adicional apos lista recusada'
}
$h=[FfmpegTagHandler]::new();$h.Body=[byte[]]@(255)
MustFail {Get-FfmpegDatedReleaseTag -Handler $h} 'Recusar UTF8 invalido sem substituicao'
Assert ($h.Count -eq 1) 'Somente consulta inicial com UTF8 invalido'
foreach($timeout in @(0,121)){
 $h=[FfmpegTagHandler]::new();$h.Body=$utf8.GetBytes($list)
 MustFail {Get-FfmpegDatedReleaseTag -Handler $h -TimeoutSeconds $timeout} 'Timeout fora de1..120'
 Assert ($h.Count -eq 0) 'Timeout invalido antes de HTTP'
}
$h=[FfmpegTagHandler]::new();$h.Body=[byte[]]::new(2097153)
MustFail {Get-FfmpegDatedReleaseTag -Handler $h} 'Lista maior que2MiB'
Assert ($h.Count -eq 1) 'Consulta limitada sem downloads adicionais'
"FFMPEG_TAG_QUERY_PASS checks$script:Checks; HTTP simulado, sem manifesto ou ZIP"
