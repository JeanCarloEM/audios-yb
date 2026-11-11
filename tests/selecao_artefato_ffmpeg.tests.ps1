#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'selecao_artefato_ffmpeg.ps1')
# Nomes/tuplas publicados; os exemplos9.10/9.2 e ambiguidades sao sinteticos.
# https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/tag/autobuild-2026-11-10-12-39
$new='ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'
$old='ffmpeg-n8.1.3-34-ga35157abb9-win64-lgpl-8.1.zip'
$arm='ffmpeg-n9.0.2-48-gd4070a14ce-winarm64-lgpl-9.0.zip'
$base=@{Names=@($new);Architecture='X64'};$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function ExpectError([hashtable]$changes,[type]$Expected){
    $call=$base.Clone();foreach($key in $changes.Keys){$call[$key]=$changes[$key]}
    $problem=$null;try{$null=Select-FfmpegAssetCandidate @call}catch{$problem=$_}
    Assert ($null -ne $problem) 'Esperava erro'
    $exception=$problem.Exception
    while($null -ne $exception -and !$Expected.IsInstanceOfType($exception)){$exception=$exception.InnerException}
    Assert ($null -ne $exception) ('Esperava '+$Expected.FullName)
}
foreach($names in @(@($old,$new,'checksums.sha256'),@($new,$old))){
    $r=Select-FfmpegAssetCandidate -Names $names -Architecture 'X64'
    Assert ($r -is [hashtable] -and $r.Count -eq 4) 'Retorno nao e mapa unico'
    Assert ($r.asset_name -ceq $new -and $r.release_version -ceq '9.0' -and $r.build_version -ceq 'n9.0.2-48-gd4070a14ce' -and $r.architecture -ceq 'X64') 'Escolha divergiu da fonte literal'
}
$r=Select-FfmpegAssetCandidate -Names @($new,$arm) -Architecture 'Arm64'
Assert ($r.asset_name -ceq $arm -and $r.architecture -ceq 'Arm64') 'Outra arquitetura escolhida'
$r=Select-FfmpegAssetCandidate -Names @('ffmpeg-n9.2.1-win64-lgpl-9.2.zip','ffmpeg-n9.10.1-win64-lgpl-9.10.zip') -Architecture 'X64'
Assert ($r.release_version -ceq '9.10') 'Comparacao de versao lexical em vez de numerica'
$r=Select-FfmpegAssetCandidate -Names @('ffmpeg-n99.0.1-win64-gpl-99.0.zip','ffmpeg-n99.0.1-win64-lgpl-shared-99.0.zip','ffmpeg-master-latest-win64-lgpl.zip',$new) -Architecture 'X64'
Assert ($r.asset_name -ceq $new) 'Familia nao alvo escolhida'
ExpectError @{Names=@('checksums.sha256','ffmpeg-master-latest-win64-lgpl.zip')} ([InvalidOperationException])
foreach($changes in @(
    @{Names=@($new,$new)},@{Names=@($new,'checksums.sha256','checksums.sha256')},
    @{Names=@($new,'ffmpeg-n9.0.1-win64-lgpl-9.0.zip')},
    @{Names=@($new,$old,'ffmpeg-n8.1.2-win64-lgpl-8.1.zip')},
    @{Names=@($new,'ffmpeg-n9.00.2-win64-lgpl-9.00.zip')}
)){ExpectError $changes ([FormatException])}
foreach($changes in @(@{Names=$null},@{Names=$new},@{Names=123},@{Names=@()},@{Architecture='x64'},@{Architecture='X86'},@{Architecture=$null},@{Names=@($new,123)})){
    ExpectError $changes ([ArgumentException])
}
$many=@($new)+@(1..255|ForEach-Object {'ignored-'+$_+'.txt'})
Assert ($many.Count -eq 256) 'Fixture256 incorreta'
Assert ((Select-FfmpegAssetCandidate -Names $many -Architecture 'X64').asset_name -ceq $new) 'Limite256 deveria ser aceito'
$tooMany=$many+@('ignored-256.txt')
Assert ($tooMany.Count -eq 257) 'Fixture257 incorreta'
ExpectError @{Names=$tooMany} ([ArgumentException])
Write-Output "FFMPEG_CANDIDATE_PASS checks$script:Checks"
