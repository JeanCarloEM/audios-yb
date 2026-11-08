#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$root=Split-Path -Parent $PSScriptRoot
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'baixar_audios_ytdlp.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Sintaxe do principal invalida'}
$f=@($ast.FindAll({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'File-Base'},$true))
if($f.Count -ne 1){throw 'File-Base nao unica'}
. ([ScriptBlock]::Create($f[0].Extent.Text))
function Assert-Equal($Name,$Actual,[string]$Expected){
 if($Actual -isnot [string] -or -not [string]::Equals($Actual,$Expected,[StringComparison]::Ordinal)){throw ($Name+': nome divergente: '+$Actual)}
 'PASS '+$Name
}
function Assert-True($Name,[bool]$Value){if(-not $Value){throw $Name};'PASS '+$Name}
$id='NBnH864JUZw'
$script:Out='x'
$legacy='01 - AC_DC - iTunes é DJ [NBnH864JUZw]'
Assert-Equal 'legado_padrao' (File-Base '01' 'AC/DC' 'iTunes é DJ' $id) $legacy
Assert-Equal 'musical_explicito' (File-Base '01' 'Ignorado' 'Ignorada' $id -MusicalStem 'AC/DC - 3 - iTunes é DJ') 'AC_DC - 3 - iTunes é DJ [NBnH864JUZw]'
Assert-Equal 'stem_vazio' (File-Base '01' 'AC/DC' 'iTunes é DJ' $id -MusicalStem '') $legacy
Assert-Equal 'stem_branco' (File-Base '01' 'AC/DC' 'iTunes é DJ' $id -MusicalStem (' '+[char]9+' ')) $legacy
Assert-Equal 'stem_null' (File-Base '01' 'AC/DC' 'iTunes é DJ' $id -MusicalStem $null) $legacy
Assert-Equal 'controle_e_espacos' (File-Base '01' 'X' 'Y' $id -MusicalStem ('A'+[char]1+'B   C')) 'A_B C [NBnH864JUZw]'
Assert-Equal 'reservado_windows' (File-Base '01' 'X' 'Y' $id -MusicalStem 'CON.x') '_CON.x [NBnH864JUZw]'
Assert-Equal 'legado_zeros_preservados' (File-Base '003' 'Autor' 'Faixa' $id) '003 - Autor - Faixa [NBnH864JUZw]'
$v=File-Base '01' 'X' 'Y' $id -MusicalStem ('A'*200)
Assert-True 'limite145_id_preservado' ($v.Length -eq 145 -and $v.EndsWith(' [NBnH864JUZw]',[StringComparison]::Ordinal))
$script:Out='x'*199
$v=File-Base '01' 'X' 'Y' $id -MusicalStem ('A'*200)
Assert-True 'limite38_id_preservado' ($v.Length -eq 38 -and $v.EndsWith(' [NBnH864JUZw]',[StringComparison]::Ordinal))
$script:Out='x'*200
$caught=$false
try{$null=File-Base '01' 'X' 'Y' $id -MusicalStem 'Faixa'}catch{if($_.Exception.Message -notlike '*destino muito longo*'){throw};$caught=$true}
Assert-True 'destino_longo_rejeitado' $caught
'FILE_BASE_BEHAVIOR_PASS cases=11'
