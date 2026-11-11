#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'consulta_metadata_ffmpeg.ps1')
Add-Type -TypeDefinition @'
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public sealed class FfmpegMetadataHandler : HttpMessageHandler {
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
$p=Join-Path $PSScriptRoot '.runtime-ffmpeg-plan-live-d335ce5f86f246fa8dd52ba84a6d070f/metadata.json'
Assert ((Get-FileHash -LiteralPath $p).Hash -ceq '0075A2ABB316F3374FE687B66377E92738499CD5F291B51006278A5F89EE4B20') 'Origem canonica independente preservada'
$bytes=[IO.File]::ReadAllBytes($p)
$utf8=[Text.UTF8Encoding]::new($false,$true)
$json=$utf8.GetString($bytes)
$tag='autobuild-2026-11-10-12-39'
$h=[FfmpegMetadataHandler]::new();$h.Body=$bytes
$r=Get-FfmpegReleaseMetadataDocument -Tag $tag -Handler $h -TimeoutSeconds 5
Assert ($h.Count -eq 1 -and $h.Uri -ceq ('https://api.github.com/repos/FFmpeg-Builds/FFmpeg-Builds/releases/tags/'+$tag)) 'Somente GET datado; sem download de manifesto'
Assert ($r -is [hashtable] -and $r.Count -eq 4 -and $r.json -ceq $json) 'Preservar JSON original e contrato mapa4'
Assert ($r.manifest_size -is [long] -and $r.manifest_size -eq 5728) 'Tamanho manifesto publicado na origem'
Assert ($r.manifest_sha256 -ceq '36f52c420fdf430ffc69cda0ae1833794c5867d71c93d8388641cbb7cb713c67') 'Digest manifesto publicado na origem'
Assert ($r.manifest_url -ceq ('https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/'+$tag+'/checksums.sha256')) 'URL derivada da tag validada'
foreach($badTag in @($null,123,'','latest','autobuild-2026-02-30-12-39',($tag+'?x=1'))){
 $h=[FfmpegMetadataHandler]::new();$h.Body=$bytes
 MustFail {Get-FfmpegReleaseMetadataDocument -Tag $badTag -Handler $h} 'Tag invalida'
 Assert ($h.Count -eq 0) 'Tag invalida antes de HTTP'
}
foreach($case in @('tag','missing','zero','large','digest','duplicate','utf8','root')){
 $m=$json|ConvertFrom-Json -AsHashtable
 $manifest=@($m.assets|Where-Object {$_.name -ceq 'checksums.sha256'})[0]
 switch($case){
  'tag' {$m.tag_name='autobuild-2026-11-09-12-39'}
  'missing' {$m.assets=@($m.assets|Where-Object {$_.name -cne 'checksums.sha256'})}
  'zero' {$manifest.size=0}
  'large' {$manifest.size=1048577}
  'digest' {$manifest.digest=$null}
  'duplicate' {$m.assets+=,$manifest.Clone()}
 }
 $body=$utf8.GetBytes(($m|ConvertTo-Json -Depth 16 -Compress))
 if($case -ceq 'utf8'){$body=[byte[]]@(255)}
 if($case -ceq 'root'){$body=$utf8.GetBytes('[]')}
 $h=[FfmpegMetadataHandler]::new();$h.Body=$body
 MustFail {Get-FfmpegReleaseMetadataDocument -Tag $tag -Handler $h} ('Metadata invalida: '+$case)
 Assert ($h.Count -eq 1) 'Metadata recusada sem requests adicionais'
}
"FFMPEG_METADATA_QUERY_PASS checks$script:Checks; HTTP simulado, fatos canonicos preservados, sem manifesto/ZIP"
