#requires -Version 7
param([string]$HelperPath='')
$ErrorActionPreference='Stop'
if([string]::IsNullOrWhiteSpace($HelperPath)){$HelperPath=Join-Path (Split-Path -Parent $PSScriptRoot) 'leitura_campo_editorial.ps1'}
. $HelperPath
$data=[pscustomobject]@{Musica=' iTunes ';Artista='Nome';Ordem='007';Empty='';Null=$null;White=' ';Integer=1;Boolean=$false;Array=@('A','B');One=@('A');Zero=@();Nul=('A'+[char]0+'B');' spaced '='literal'}
$cases=@(
 @{N='mapping_null';R=$null;C=$null;V=$null;F=$false;S=$true;Why='mapping_absent';Src=''}
 @{N='mapping_empty';R=$null;C='';V=$null;F=$false;S=$true;Why='mapping_absent';Src=''}
 @{N='mapping_white_preserved';R=42;C='  ';V=$null;F=$false;S=$true;Why='mapping_absent';Src=''}
 @{N='mapped_literal';R=$data;C='Musica';V=' iTunes ';F=$true;S=$true;Why='mapped';Src='csv:Musica'}
 @{N='header_spaces_literal';R=$data;C=' spaced ';V='literal';F=$true;S=$true;Why='mapped';Src='csv: spaced '}
 @{N='no_padding_or_semantics';R=$data;C='Ordem';V='007';F=$true;S=$true;Why='mapped';Src='csv:Ordem'}
 @{N='missing_column';R=$data;C='Missing';V=$null;F=$false;S=$false;Why='missing_column';Src=''}
 @{N='case_exact';R=$data;C='musica';V=$null;F=$false;S=$false;Why='missing_column';Src=''}
 @{N='unicode_exact';R=$data;C=('Mu'+[char]0xAD+'sica');V=$null;F=$false;S=$false;Why='missing_column';Src=''}
 @{N='no_trim_header';R=$data;C='Musica ';V=$null;F=$false;S=$false;Why='missing_column';Src=''}
 @{N='absent_empty';R=$data;C='Empty';V='';F=$true;S=$true;Why='absent';Src='csv:Empty'}
 @{N='absent_null';R=$data;C='Null';V=$null;F=$true;S=$true;Why='absent';Src='csv:Null'}
 @{N='absent_white';R=$data;C='White';V=' ';F=$true;S=$true;Why='absent';Src='csv:White'}
 @{N='raw_integer';R=$data;C='Integer';V=1;F=$true;S=$false;Why='non_scalar_value';Src='csv:Integer'}
 @{N='raw_boolean';R=$data;C='Boolean';V=$false;F=$true;S=$false;Why='non_scalar_value';Src='csv:Boolean'}
 @{N='raw_array';R=$data;C='Array';V=@('A','B');F=$true;S=$false;Why='non_scalar_value';Src='csv:Array'}
 @{N='raw_singleton_array';R=$data;C='One';V=@('A');F=$true;S=$false;Why='non_scalar_value';Src='csv:One'}
 @{N='raw_empty_array';R=$data;C='Zero';V=@();F=$true;S=$false;Why='non_scalar_value';Src='csv:Zero'}
 @{N='raw_nul';R=$data;C='Nul';V=('A'+[char]0+'B');F=$true;S=$false;Why='invalid_nul';Src='csv:Nul'}
 @{N='column_integer_invalid';R=$data;C=1;Invalid=$true}
 @{N='column_array_invalid';R=$data;C=@('Musica');Invalid=$true}
 @{N='column_nul_invalid';R=$data;C=('Mu'+[char]0+'sica');Invalid=$true}
 @{N='row_null_invalid';R=$null;C='Musica';Invalid=$true}
 @{N='row_hashtable_invalid';R=@{Musica='X'};C='Musica';Invalid=$true}
 @{N='row_string_invalid';R='X';C='Musica';Invalid=$true}
)
$failures=0
foreach($case in $cases){
 $before=[Management.Automation.PSSerializer]::Serialize($case.R,15);$caught=$null;$output=@()
 try{$output=@(Get-EditorialCsvField -Row $case.R -Column $case.C)}catch{$caught=$_.Exception;while($null -ne $caught.InnerException){$caught=$caught.InnerException}}
 try{
  if($case.Invalid){if($caught -isnot [ArgumentException]){throw ('ArgumentException esperado: '+$caught)}}
  else{
   if($null -ne $caught){throw $caught}
   if($output.Count -ne 1 -or $output[0] -isnot [pscustomobject]){throw 'Esperado objeto unico'}
   $r=$output[0];$names=@($r.PSObject.Properties.Name)
   if($names.Count -ne 6){throw 'Esperadas6propriedades'}
   foreach($name in @('Column','Value','Source','Found','Supported','Reason')){if([Array]::IndexOf($names,$name) -lt 0){throw 'Schema divergente'}}
   if($r.Found -isnot [bool] -or $r.Supported -isnot [bool] -or $r.Found -ne $case.F -or $r.Supported -ne $case.S){throw 'Flags divergentes'}
   foreach($pair in @(@($r.Reason,$case.Why),@($r.Source,$case.Src))){if(-not [string]::Equals($pair[0],$pair[1],[StringComparison]::Ordinal)){throw 'Texto divergente'}}
   if(-not [string]::Equals([Management.Automation.PSSerializer]::Serialize($r.Column,15),[Management.Automation.PSSerializer]::Serialize($case.C,15),[StringComparison]::Ordinal)){throw 'Column alterada'}
   if(-not [string]::Equals([Management.Automation.PSSerializer]::Serialize($r.Value,15),[Management.Automation.PSSerializer]::Serialize($case.V,15),[StringComparison]::Ordinal)){throw 'Value alterado/convertido'}
  }
  if(-not [string]::Equals($before,[Management.Automation.PSSerializer]::Serialize($case.R,15),[StringComparison]::Ordinal)){throw 'Row alterada'}
  'PASS '+$case.N
 }catch{$failures++;'FAIL '+$case.N+': '+$_.Exception.Message}
}
if($failures){throw ('EDITORIAL_CSV_FIELD_FAILURES='+$failures)}
'EDITORIAL_CSV_FIELD_PASS cases='+$cases.Count
