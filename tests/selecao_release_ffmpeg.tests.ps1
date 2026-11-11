#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'selecao_release_ffmpeg.ps1')
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function MustFail([object]$Json){$failed=$false;try{$null=Select-FfmpegDatedRelease -Json $Json}catch{$failed=$true};Assert $failed 'JSON invalido aceito'}
# Oraculo de ordem: tags literais no formato publicado pelo mantenedor.
# https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases
$current='{"tag_name":"autobuild-2026-11-10-12-39","draft":false,"prerelease":false,"assets":[],"id":123}'
$older='{"tag_name":"autobuild-2026-11-09-12-42","draft":false,"prerelease":false}'
$latest='{"tag_name":"latest","draft":false,"prerelease":false}'
$expected='autobuild-2026-11-10-12-39'
foreach($json in @(('['+$older+','+$latest+','+$current+']'),('['+$current+','+$older+','+$latest+']'))){
    $result=Select-FfmpegDatedRelease -Json $json
    Assert ($result -is [string] -and $result -ceq $expected) 'Escolha nao corresponde a ordem cronologica'
}
$draft='{"tag_name":"autobuild-2026-11-12-12-39","draft":true,"prerelease":false}'
$pre='{"tag_name":"autobuild-2026-11-13-12-39","draft":false,"prerelease":true}'
Assert ((Select-FfmpegDatedRelease -Json ('['+$current+','+$draft+','+$pre+']')) -ceq $expected) 'Draft/prerelease foram escolhidos'
$tooMany='['+((@($current)+@(1..20|ForEach-Object {$latest})) -join ',')+']'
$recordPrefix=$current.Substring(0,$current.Length-1)
$tooLarge='['+$recordPrefix+',"padding":"'+('x'*2097152)+'"}]'
$deep='0';foreach($level in 1..17){$deep='{"x":'+$deep+'}'}
$tooDeep='['+$recordPrefix+',"padding":'+$deep+'}]'
foreach($invalid in @($null,123,'',' ','{','{}','[]',('['+$latest+']'),('['+$current+','+$current+']'),$tooMany,$tooLarge,$tooDeep)){MustFail $invalid}
# Um candidato valido acompanha cada registro defeituoso: nao basta ignorar o erro.
foreach($badRecord in @(
    '1',
    '{"tag_name":"autobuild-2026-02-30-12-39","draft":false,"prerelease":false}',
    '{"tag_name":"x","prerelease":false}',
    '{"tag_name":"x","draft":"false","prerelease":false}',
    '{"tag_name":42,"draft":false,"prerelease":false}',
    '{"tag_name":"","draft":false,"prerelease":false}',
    '{"tag_name":"x","draft":false,"draft":false,"prerelease":false}',
    '{"tag_name":"x","tag_name":"x","draft":false,"prerelease":false}',
    '{"tag_name":"x","draft":false,"prerelease":false,"prerelease":false}',
    '{"tag_name":"x","Tag_Name":"x","draft":false,"prerelease":false}',
    '{"tag_name":"x","DRAFT":false,"draft":false,"prerelease":false}',
    '{"tag_name":"x","draft":false,"Prerelease":false}'
)){MustFail ('['+$current+','+$badRecord+']')}
Write-Output "FFMPEG_DATED_RELEASE_SELECTION_PASS checks$script:Checks"
