#requires -Version 7
param([string]$HelperPath='')
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($HelperPath)){$HelperPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'comparacao_tags_ordinal.ps1'}
. $HelperPath
$script:Cases=0;$script:Failures=0
function Check-Map([string]$Name,[object]$Expected,[object]$Actual,[type]$ExceptionType){
 $script:Cases++
 $stamp1=[Management.Automation.PSSerializer]::Serialize(@($Expected,$Actual),15)
 $caught=$null;$result=@()
 try{$result=@(Assert-OrdinalStringMap -Expected $Expected -Actual $Actual)}catch{$caught=$_.Exception;while($null -ne $caught.InnerException){$caught=$caught.InnerException}}
 $stamp2=[Management.Automation.PSSerializer]::Serialize(@($Expected,$Actual),15)
 try{
  if(-not [string]::Equals($stamp1,$stamp2,[StringComparison]::Ordinal)){throw 'Argumentos alterados'}
  if($null -eq $ExceptionType){
   if($null -ne $caught){throw $caught}
   if($result.Count -ne 1 -or $result[0] -isnot [bool] -or -not $result[0]){throw 'Sucesso deve retornar somente bool true'}
  }elseif($null -eq $caught -or -not $ExceptionType.IsInstanceOfType($caught)){throw ('Excecao esperada: '+$ExceptionType.FullName+'; recebida: '+$caught)}
  'PASS '+$Name
 }catch{$script:Failures++;'FAIL '+$Name+': '+$_.Exception.Message}
}
$bad=[ArgumentException];$diff=[IO.InvalidDataException];$soft=[string][char]0xAD
Check-Map 'empty' @{} @{} $null
Check-Map 'all_tags_literal' @{artist='Artista é';title=' Faixa iTunes ';album='Coletânea';track='003';composer='AC/DC';marcador_coletanea='Grupo';custom='';encoder='Lavf'} @{encoder='Lavf';custom='';marcador_coletanea='Grupo';composer='AC/DC';track='003';album='Coletânea';title=' Faixa iTunes ';artist='Artista é'} $null
Check-Map 'empty_key_and_value' @{''=''} @{''=''} $null
Check-Map 'literal_nul_allowed_in_existing_value' @{custom=('A'+[char]0+'B')} @{custom=('A'+[char]0+'B')} $null
Check-Map 'different_value' @{title='A'} @{title='B'} $diff
Check-Map 'missing' @{title='A'} @{} $diff
Check-Map 'extra' @{} @{title='A'} $diff
Check-Map 'key_case' @{title='A'} @{Title='A'} $diff
Check-Map 'value_case' @{title='A'} @{title='a'} $diff
Check-Map 'key_soft_hyphen' @{title='A'} @{('ti'+$soft+'tle')='A'} $diff
Check-Map 'value_soft_hyphen' @{title='iTunes'} @{title=('i'+$soft+'Tunes')} $diff
$two=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
$two.Add('title','lower');$two.Add('Title','UPPER')
$reordered=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
$reordered.Add('Title','UPPER');$reordered.Add('title','lower')
Check-Map 'distinct_case_keys_preserved' $two $reordered $null
Check-Map 'distinct_case_keys_not_collapsed' $two @{title='lower'} $diff
$swapped=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
$swapped.Add('Title','lower');$swapped.Add('title','UPPER')
Check-Map 'distinct_case_values_not_swapped' $two $swapped $diff
Check-Map 'expected_null' $null @{} $bad
Check-Map 'actual_null' @{} $null $bad
Check-Map 'both_null' $null $null $bad
Check-Map 'expected_string' 'x' @{} $bad
Check-Map 'actual_string' @{} 'x' $bad
Check-Map 'expected_array' @('x') @{} $bad
Check-Map 'actual_psobject' @{} ([pscustomobject]@{title='A'}) $bad
Check-Map 'expected_integer_key' @{1='A'} @{} $bad
Check-Map 'actual_integer_key' @{} @{1='A'} $bad
Check-Map 'expected_null_value' @{title=$null} @{} $bad
Check-Map 'actual_null_value' @{} @{title=$null} $bad
Check-Map 'expected_integer_value' @{title=1} @{} $bad
Check-Map 'actual_integer_value' @{} @{title=1} $bad
Check-Map 'expected_array_value' @{title=@('A','B')} @{} $bad
Check-Map 'actual_array_value' @{} @{title=@('A','B')} $bad
if($script:Failures){throw ('ORDINAL_MAP_FAILURES='+$script:Failures)}
'ORDINAL_MAP_PASS cases='+$script:Cases
