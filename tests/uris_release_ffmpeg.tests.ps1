#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'uris_release_ffmpeg.ps1')
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
$api='https://api.github.com/repos/FFmpeg-Builds/FFmpeg-Builds/releases'
$base='https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-11-10-12-39/'
$zip='ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'
foreach($uri in @(($api+'?per_page=3'),($api+'/tags/autobuild-2026-11-10-12-39'),($base+'checksums.sha256'),($base+$zip),($base+'ffmpeg-n9.0.2-48-gd4070a14ce-winarm64-lgpl-9.0.zip'))){
    $r=Test-FfmpegRequestUri -Uri $uri
    Assert ($r -is [bool] -and $r) ('URL permitida recusada: '+$uri)
}
$r=Test-FfmpegRequestUri -Uri ([uri]($base+$zip))
Assert ($r -is [bool] -and $r) 'Uri absoluta deveria ser aceita'
foreach($uri in @(
    $null,123,'','relative/file',('https://github.com/'+('x'*16385)),
    ($api+'?per_page=30'),($api+'?per_page=3&extra=1'),($api+'?PER_PAGE=3'),
    ($api+'/tags/latest'),($api+'/tags/autobuild-2026-02-30-12-39'),
    ($base+'checksums.sha256?x=1'),($base+$zip+'#fragment'),
    $base.Replace('https:','http:'),($base.Replace('https:','http:')+$zip),
    ($base.Replace('github.com','github.com.evil.test')+$zip),($base.Replace('github.com','user:pass@github.com')+$zip),
    ($base.Replace('github.com','github.com:444')+$zip),($base.Replace('/FFmpeg-Builds/FFmpeg-Builds/','/other/repo/')+$zip),
    ($base.Replace('autobuild-2026-11-10-12-39','latest')+$zip),
    ($base+'ffmpeg-master-latest-win64-lgpl.zip'),($base+'ffmpeg-n9.0.2-48-gd4070a14ce-win64-gpl-9.0.zip'),
    ($base+'ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-shared-9.0.zip'),
    ($base+'ffmpeg-n9.1.2-win64-lgpl-9.0.zip'),
    'https://release-assets.githubusercontent.com/object?sig=public-fixture'
)){
    $r=Test-FfmpegRequestUri -Uri $uri
    Assert ($r -is [bool] -and !$r) 'URL nao autorizada aceita ou retorno nao booleano'
}
$cdn='https://release-assets.githubusercontent.com/object?sig=public-fixture&x=1'
Assert ((Test-FfmpegRequestUri -Uri $cdn -Redirect) -eq $true) 'Host CDN esperado recusado em redirect'
foreach($uri in @($cdn.Replace('https:','http:'),($cdn+'#x'),$cdn.Replace('release-assets.githubusercontent.com','user@release-assets.githubusercontent.com'),$cdn.Replace('release-assets.githubusercontent.com','evil.test'),($base+$zip),($api+'?per_page=3'))){
    $r=Test-FfmpegRequestUri -Uri $uri -Redirect
    Assert ($r -is [bool] -and !$r) 'Redirect fora do host/HTTPS aceito'
}
Write-Output "FFMPEG_URI_POLICY_PASS checks$script:Checks; predicado apenas, sem HTTP"
