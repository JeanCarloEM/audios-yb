#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'aquisicao_documentos_ffmpeg.ps1')
Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Http;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
public sealed class FfmpegAcquisitionHandler : HttpMessageHandler {
 public readonly Queue<byte[]> Replies=new Queue<byte[]>();
 public readonly List<string> Seen=new List<string>();
 protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage r,CancellationToken t) {
  Seen.Add(r.RequestUri.AbsoluteUri);
  if(Replies.Count==0) throw new InvalidOperationException("Unexpected request");
  return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK){Content=new ByteArrayContent(Replies.Dequeue())});
 }
}
'@
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function MustFail([scriptblock]$action,$message){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed $message}
$fixture=Join-Path $PSScriptRoot '.runtime-ffmpeg-plan-live-d335ce5f86f246fa8dd52ba84a6d070f'
$metaPath=Join-Path $fixture 'metadata.json'
$manifestPath=Join-Path $fixture 'checksums.sha256'
Assert ((Get-FileHash -LiteralPath $metaPath).Hash -ceq '0075A2ABB316F3374FE687B66377E92738499CD5F291B51006278A5F89EE4B20') 'Origem metadata canonica preservada'
Assert ((Get-FileHash -LiteralPath $manifestPath).Hash -ceq '36F52C420FDF430FFC69CDA0AE1833794C5867D71C93D8388641CBB7CB713C67') 'Origem manifesto canonico preservada'
$meta=[IO.File]::ReadAllBytes($metaPath)
$manifest=[IO.File]::ReadAllBytes($manifestPath)
$utf8=[Text.UTF8Encoding]::new($false,$true)
$tag='autobuild-2026-11-10-12-39'
$api='https://api.github.com/repos/FFmpeg-Builds/FFmpeg-Builds/releases'
$manifestUrl='https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/'+$tag+'/checksums.sha256'
$list='[{"tag_name":"autobuild-2026-11-09-12-39","draft":false,"prerelease":false},{"tag_name":"latest","draft":false,"prerelease":false},{"tag_name":"autobuild-2026-11-10-12-39","draft":false,"prerelease":false}]'
function Handler($listBytes,$metaBytes,$manifestBytes){
 $h=[FfmpegAcquisitionHandler]::new()
 $h.Replies.Enqueue($listBytes);$h.Replies.Enqueue($metaBytes);$h.Replies.Enqueue($manifestBytes)
 return $h
}
foreach($arch in @('X64','Arm64')){
 $h=Handler ($utf8.GetBytes($list)) $meta $manifest
 $r=Get-FfmpegReleaseDescriptor -Architecture $arch -Handler $h -TimeoutSeconds 5
 Assert ($r -is [hashtable] -and $r.Count -eq 4) 'Contrato descritor aceito'
 Assert ($h.Seen.Count -eq 3 -and $h.Seen[0] -ceq ($api+'?per_page=3') -and $h.Seen[1] -ceq ($api+'/tags/'+$tag) -and $h.Seen[2] -ceq $manifestUrl) 'Tres URLs canonicas derivadas da tag datada; nao ZIP'
 Assert ($r.release_plan.release_tag -ceq $tag -and $r.release_plan.architecture -ceq $arch) 'Tag/arquitetura solicitadas'
 Assert ($r.manifest_size -eq 5728 -and $r.manifest_sha256 -ceq '36f52c420fdf430ffc69cda0ae1833794c5867d71c93d8388641cbb7cb713c67') 'Manifesto real verificado'
 $expected=if($arch -ceq 'X64'){@(168579921,'3c3faf2d691c1e3038b04fda8e38dbc790a1358a9b12b6e796072c5c5f97c821')}else{@(117200897,'099e82999492042684d716cc4c5531c5d1db4d48a63db5d7087192d08b45d2e1')}
 Assert ($r.archive_size -eq $expected[0] -and $r.release_plan.sha256 -ceq $expected[1]) 'Tamanho/digest publicados preservados; nao comprova bytesZIP'
}
foreach($arch in @($null,123,'x64','X86')){
 $h=[FfmpegAcquisitionHandler]::new()
 MustFail {Get-FfmpegReleaseDescriptor -Architecture $arch -Handler $h} 'Arquitetura invalida'
 Assert ($h.Seen.Count -eq 0) 'Arquitetura invalida antes de rede'
}
foreach($badList in @('[]','[{"tag_name":"autobuild-2026-02-30-12-39","draft":false,"prerelease":false}]')){
 $h=Handler ($utf8.GetBytes($badList)) $meta $manifest
 MustFail {Get-FfmpegReleaseDescriptor -Architecture X64 -Handler $h} 'Lista sem release elegivel ou calendario invalido'
 Assert ($h.Seen.Count -eq 1) 'Lista invalida interrompe antes de consultar tag'
}
$h=Handler ([byte[]]@(255)) $meta $manifest
MustFail {Get-FfmpegReleaseDescriptor -Architecture X64 -Handler $h} 'UTF8 invalido nao deve ser substituido silenciosamente'
Assert ($h.Seen.Count -eq 1) 'UTF8 invalido interrompe sequencia'
$wrongMeta=$utf8.GetBytes($utf8.GetString($meta).Replace($tag,'autobuild-2026-11-09-12-39'))
$h=Handler ($utf8.GetBytes($list)) $wrongMeta $manifest
MustFail {Get-FfmpegReleaseDescriptor -Architecture X64 -Handler $h} 'Metadata de outra tag'
Assert ($h.Seen.Count -eq 2) 'Tag divergente antes do manifesto'
$bad=$utf8.GetString($meta)|ConvertFrom-Json -AsHashtable
($bad.assets|Where-Object {$_.name -ceq 'checksums.sha256'}).size=0
$h=Handler ($utf8.GetBytes($list)) ($utf8.GetBytes(($bad|ConvertTo-Json -Depth 16 -Compress))) $manifest
MustFail {Get-FfmpegReleaseDescriptor -Architecture X64 -Handler $h} 'Manifesto sem tamanho valido'
Assert ($h.Seen.Count -eq 2) 'Metadata de manifesto invalida antes do download'
$corrupt=[byte[]]$manifest.Clone();$corrupt[0]=$corrupt[0] -bxor 1
$h=Handler ($utf8.GetBytes($list)) $meta $corrupt
MustFail {Get-FfmpegReleaseDescriptor -Architecture X64 -Handler $h} 'Hash manifesto divergente'
Assert ($h.Seen.Count -eq 3) 'Hash divergente apos apenas documentos'
"FFMPEG_DOCUMENT_ACQUISITION_PASS checks$script:Checks; HTTP simulado e documentos canonicos preservados, sem ZIP/assinatura"
