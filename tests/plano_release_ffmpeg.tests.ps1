#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'plano_release_ffmpeg.ps1')
# Oracle dos nomes/URLs: release datada do mantenedor, nao gerado pelo modulo.
# https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/tag/autobuild-2026-11-10-12-39
# Hashes abaixo sao apenas fixtures sinteticas de vinculacao, nao hashes dos ZIPs reais.
$x64='ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'
$arm='ffmpeg-n9.0.2-48-gd4070a14ce-winarm64-lgpl-9.0.zip'
$manifest=('A'*64)+'  '+$x64+"`n"+('B'*64)+'  '+$arm
$base=@{Tag='autobuild-2026-11-10-12-39';ReleaseVersion='9.0';BuildVersion='n9.0.2-48-gd4070a14ce';Manifest=$manifest;Architecture='X64'}
$script:Checks=0
function Assert($condition,$message){if(!$condition){throw $message};$script:Checks++}
function MustFail([hashtable]$changes){
    $call=$base.Clone();foreach($key in $changes.Keys){$call[$key]=$changes[$key]}
    $failed=$false;try{$null=New-FfmpegReleasePlan @call}catch{$failed=$true}
    Assert $failed ('Entrada invalida aceita: '+($changes.Keys -join ','))
}
$oracles=@(
    @{Architecture='X64';Asset=$x64;Sha=('a'*64);Url='https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-11-10-12-39/ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'},
    @{Architecture='Arm64';Asset=$arm;Sha=('b'*64);Url='https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-11-10-12-39/ffmpeg-n9.0.2-48-gd4070a14ce-winarm64-lgpl-9.0.zip'}
)
foreach($expected in $oracles){
    $call=$base.Clone();$call.Architecture=$expected.Architecture
    $plan=New-FfmpegReleasePlan @call
    Assert ($plan -is [hashtable] -and $plan.Count -eq 11) 'Contrato deve ter onze campos'
    Assert ($plan.tool -ceq 'ffmpeg-suite' -and $plan.platform -ceq 'Windows') 'Suite/plataforma incorreta'
    Assert ($plan.architecture -ceq $expected.Architecture) 'Arquitetura incorreta'
    Assert ($plan.release_tag -ceq 'autobuild-2026-11-10-12-39' -and $plan.release_version -ceq '9.0' -and $plan.build_version -ceq 'n9.0.2-48-gd4070a14ce') 'Identidade da release incorreta'
    Assert ($plan.asset_name -ceq $expected.Asset -and $plan.url -ceq $expected.Url) 'Asset/URL divergiram da fonte'
    Assert ($plan.manifest_url -ceq 'https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-11-10-12-39/checksums.sha256') 'Manifesto incorreto'
    Assert ($plan.sha256 -ceq $expected.Sha) 'Hash nao corresponde ao asset da arquitetura'
    Assert (@($plan.targets).Count -eq 2 -and ($plan.targets -join '|') -ceq 'ffmpeg.exe|ffprobe.exe') 'Targets incorretos'
}
foreach($invalid in @(
    @{Tag='latest'},@{Tag='autobuild-2026-02-30-12-39'},@{Tag='../autobuild-2026-11-10-12-39'},
    @{Tag="autobuild-2026-11-10-12-39`n"},@{ReleaseVersion='9/0'},@{ReleaseVersion='09.0'},
    @{ReleaseVersion="9.0`n"},@{ReleaseVersion=(('1'*31)+'.0')},
    @{BuildVersion='n8.1.3-34-ga35157abb9'},@{BuildVersion='../n9.0.2'},@{BuildVersion="n9.0.2-48-gd4070a14ce`n"},
    @{BuildVersion=('n9.0.'+('1'*100))},@{Architecture='X86'},@{Architecture='x64'},@{Architecture='arm64'},
    @{Manifest=(('C'*64)+'  outro.zip')},@{Manifest=($manifest+"`n"+$manifest)}
)){MustFail $invalid}
Write-Output "FFMPEG_RELEASE_PLAN_PASS checks$script:Checks; offline/fixtures sinteticas/sem Pester"
