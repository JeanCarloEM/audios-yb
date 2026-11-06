#requires -Version 7.0
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FixtureRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'editorial_audio.ps1')
$files=@((Join-Path $FixtureRoot 'fonte.mp3'),(Join-Path $FixtureRoot 'marcado.mp3'))
$expected=@('ED90F05F84430C3C85A9E08BF6748BF42776001509F1827C288C9C18F81DC733','5C1CF6458DED20094404B77B73E857DBE2B916F94590D1A982FBBBB6A7EFE52A')
for($i=0;$i -lt 2;$i++){if((Get-FileHash -LiteralPath $files[$i]).Hash -cne $expected[$i]){throw 'Fixture independente divergente'}}
$before=Get-AudioMetadataSnapshot -File $files[0] -Ffprobe (Join-Path $repo 'ffprobe.exe')
$after=Get-AudioMetadataSnapshot -File $files[1] -Ffprobe (Join-Path $repo 'ffprobe.exe')
if((Assert-MarkerTagsPreserved -Before $before.format.tags -After $after.format.tags -FormatTags) -ne $true){throw 'Falha nas tags reais'}
if((Assert-MarkerTagsPreserved -Before $before.streams[0].tags -After $after.streams[0].tags) -ne $true){throw 'Falha nas tags reais do stream'}
$controls=@(
 @{Before=$null;After=$null;Format=$false;Accept=$true},
 @{Before=$null;After=[pscustomobject]@{};Format=$false;Accept=$true},
 @{Before=[pscustomobject]@{artist='AC/DC';title='iTunes DJ'};After=[pscustomobject]@{title='iTunes DJ';artist='AC/DC'};Format=$false;Accept=$true},
 @{Before=[pscustomobject]@{artist='AC/DC'};After=[pscustomobject]@{artist='Outro'};Format=$true;Accept=$false},
 @{Before=[pscustomobject]@{artist='AC/DC';composer='Autor'};After=[pscustomobject]@{artist='AC/DC'};Format=$true;Accept=$false},
 @{Before=[pscustomobject]@{artist='AC/DC'};After=[pscustomobject]@{artist='AC/DC';comment='Novo'};Format=$true;Accept=$false},
 @{Before=[pscustomobject]@{artist='AC/DC'};After=[pscustomobject]@{Artist='AC/DC'};Format=$true;Accept=$false},
 @{Before=[pscustomobject]@{title='A'};After=[pscustomobject]@{title=('A'+[char]0x00AD)};Format=$false;Accept=$false},
 @{Before=$null;After=[pscustomobject]@{marcador_coletanea='Teste'};Format=$true;Accept=$true},
 @{Before=$null;After=[pscustomobject]@{marcador_coletanea='Teste'};Format=$false;Accept=$false},
 @{Before=[pscustomobject]@{track='12'};After=[pscustomobject]@{track=12};Format=$true;Accept=$false},
 @{Before=[pscustomobject]@{};After=[pscustomobject]@{title=''};Format=$true;Accept=$false}
)
foreach($case in $controls){
 $caught=$false;$result=$null
 try{$result=Assert-MarkerTagsPreserved -Before $case.Before -After $case.After -FormatTags:$case.Format}
 catch [IO.InvalidDataException]{$caught=$true}
 if($case.Accept){if($caught -or $result -ne $true){throw 'Controle positivo rejeitado'}}
 elseif(-not $caught){throw 'Controle negativo aceito'}
}
for($i=0;$i -lt 2;$i++){if((Get-FileHash -LiteralPath $files[$i]).Hash -cne $expected[$i]){throw 'Original alterado'}}
Write-Output 'MARCADOR_TAGS_PASS'
