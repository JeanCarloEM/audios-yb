#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'descritor_manifesto_ffmpeg.ps1')
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Descritor invalido aceito'}
$p=Join-Path $PSScriptRoot '.runtime-ffmpeg-plan-live-d335ce5f86f246fa8dd52ba84a6d070f/metadata.json'
Assert ((Get-FileHash -LiteralPath $p).Hash -ceq '0075A2ABB316F3374FE687B66377E92738499CD5F291B51006278A5F89EE4B20') 'Origem canonica preservada'
$json=[IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false,$true))
$tag='autobuild-2026-11-10-12-39'
$r=Read-FfmpegManifestDescriptor -Json $json -ExpectedTag $tag
Assert ($r -is [hashtable] -and $r.Count -eq 4 -and $r.json -ceq $json) 'Mapa4 e JSON original'
Assert ($r.manifest_size -is [long] -and $r.manifest_size -eq 5728) 'Tamanho publicado na origem'
Assert ($r.manifest_sha256 -ceq '36f52c420fdf430ffc69cda0ae1833794c5867d71c93d8388641cbb7cb713c67') 'Digest publicado na origem'
Assert ($r.manifest_url -ceq ('https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/'+$tag+'/checksums.sha256')) 'URL canonica derivada da tag'
foreach($badTag in @($null,123,'','latest',$tag.ToUpperInvariant(),'autobuild-2026-11-09-12-39')){MustFail {Read-FfmpegManifestDescriptor -Json $json -ExpectedTag $badTag}}
foreach($badJson in @($null,123,'[]','{}')){MustFail {Read-FfmpegManifestDescriptor -Json $badJson -ExpectedTag $tag}}
foreach($case in @('missing','zero','large','digest','duplicate')){
 $m=$json|ConvertFrom-Json -AsHashtable
 $manifest=@($m.assets|Where-Object {$_.name -ceq 'checksums.sha256'})[0]
 switch($case){
  'missing' {$m.assets=@($m.assets|Where-Object {$_.name -cne 'checksums.sha256'})}
  'zero' {$manifest.size=0}
  'large' {$manifest.size=1048577}
  'digest' {$manifest.digest=$null}
  'duplicate' {$m.assets+=,$manifest.Clone()}
 }
 $bad=$m|ConvertTo-Json -Depth 16 -Compress
 MustFail {Read-FfmpegManifestDescriptor -Json $bad -ExpectedTag $tag}
}
"FFMPEG_MANIFEST_DESCRIPTOR_PASS checks$script:Checks; fatos canonicos preservados, sem HTTP/ZIP"
