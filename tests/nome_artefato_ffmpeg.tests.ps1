#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'nome_artefato_ffmpeg.ps1')
# Nomes/tuplas literais da release, usados como oraculo externo ao parser.
# https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/tag/autobuild-2026-11-10-12-39
$x64='ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'
$arm='ffmpeg-n9.0.2-48-gd4070a14ce-winarm64-lgpl-9.0.zip'
$base=@{Name=$x64;Architecture='X64'};$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function ExpectError([hashtable]$changes,[type]$Expected){
    $call=$base.Clone();foreach($key in $changes.Keys){$call[$key]=$changes[$key]}
    $problem=$null;try{$null=ConvertFrom-FfmpegAssetName @call}catch{$problem=$_}
    Assert ($null -ne $problem) 'Esperava erro'
    $exception=$problem.Exception
    while($null -ne $exception -and !$Expected.IsInstanceOfType($exception)){$exception=$exception.InnerException}
    Assert ($null -ne $exception) ('Esperava '+$Expected.FullName)
}
foreach($oracle in @(@{Name=$x64;Architecture='X64'},@{Name=$arm;Architecture='Arm64'})){
    $r=ConvertFrom-FfmpegAssetName @oracle
    Assert ($r -is [hashtable] -and $r.Count -eq 4) 'Retorno deve ser map unico de4campos'
    Assert ($r.architecture -ceq $oracle.Architecture) 'Arquitetura incorreta'
    Assert ($r.release_version -ceq '9.0') 'Branch incorreta'
    Assert ($r.build_version -ceq 'n9.0.2-48-gd4070a14ce') 'Build incorreto'
    Assert ($r.asset_name -ceq $oracle.Name) 'Asset incorreto'
}
foreach($name in @(
    'ffmpeg-n9.0.2-48-gd4070a14ce-win64-gpl-9.0.zip',
    'ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-shared-9.0.zip',
    'ffmpeg-n9.0.2-48-gd4070a14ce-linux64-lgpl-9.0.tar.xz',
    'ffmpeg-n9.0-latest-win64-lgpl-9.0.zip','ffmpeg-master-latest-win64-lgpl.zip',
    ('../'+$x64),($x64+"`n"),$arm
)){Assert ($null -eq (ConvertFrom-FfmpegAssetName -Name $name -Architecture 'X64')) 'Familia nao alvo deveria retornar null'}
Assert ($null -eq (ConvertFrom-FfmpegAssetName -Name $x64 -Architecture 'Arm64')) 'Outra arquitetura deveria retornar null'
foreach($invalid in @(@{Name=$null},@{Name=123},@{Name=''},@{Name=' '},@{Name=('x'*256)},@{Architecture='X86'},@{Architecture='x64'},@{Architecture=$null},@{Architecture=123})){
    ExpectError $invalid ([ArgumentException])
}
$longBuild='n9.0.'+('1'*92) # 97 caracteres: acima de96 e ainda dentro deName255.
$longBranch=('1'*31)+'.0' # 33 caracteres, build completo curto e formato valido.
$badNames=@('ffmpeg-n9.1.2-48-gd4070a14ce-win64-lgpl-9.0.zip',('ffmpeg-'+$longBuild+'-win64-lgpl-9.0.zip'),('ffmpeg-n'+$longBranch+'.1-win64-lgpl-'+$longBranch+'.zip'))
Assert ($longBuild.Length -eq 97 -and $longBranch.Length -eq 33) 'Fixture de limite incorreta'
foreach($name in $badNames){
    Assert ($name.Length -le 255) 'Fixture dispararia limite Name em vez de formato'
    foreach($architecture in @('X64','Arm64')){ExpectError @{Name=$name;Architecture=$architecture} ([FormatException])}
}
Write-Output "FFMPEG_ASSET_NAME_PASS checks$script:Checks"
