#requires -Version 7.0
param([string]$HelperPath='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($HelperPath)){$HelperPath=Join-Path $root 'decisao_metatags.ps1'}
$t=$null;$e=$null
$null=[Management.Automation.Language.Parser]::ParseFile($HelperPath,[ref]$t,[ref]$e)
if($e.Count){throw 'Sintaxe do helper invalida'}
. $HelperPath
# Expectativas: tabela independente do supervisor para RCF7.2, nao obtidas da implementacao.
$cases=@(
 @{Name='absent_null';Current='Original';Requested=$null;Source='';Action='keep';Reason='absent';Conflict=$false;ValueFrom='current'}
 @{Name='absent_whitespace';Current=' Original ';Requested=(' '+[char]9+' ');Source='';Action='keep';Reason='absent';Conflict=$false;ValueFrom='current'}
 @{Name='missing_source';Current='Original';Requested='Novo';Source='';Action='unsupported';Reason='missing_source';Conflict=$false;ValueFrom='current'}
 @{Name='null_source_binding';Current='Original';Requested='Novo';Source=$null;ExpectedSource='';Action='unsupported';Reason='missing_source';Conflict=$false;ValueFrom='current'}
 @{Name='source_whitespace';Current='Original';Requested='Novo';Source=(' '+[char]9);Action='unsupported';Reason='missing_source';Conflict=$false;ValueFrom='current'}
 @{Name='apply_null';Current=$null;Requested='Faixa';Source='csv:Musica';Action='apply';Reason='empty_field';Conflict=$false;ValueFrom='requested'}
 @{Name='apply_empty';Current='';Requested=' Faixa ';Source=' csv:Musica ';Action='apply';Reason='empty_field';Conflict=$false;ValueFrom='requested'}
 @{Name='apply_whitespace';Current=(' '+[char]9);Requested='iTunes';Source='csv:Titulo';Action='apply';Reason='empty_field';Conflict=$false;ValueFrom='requested'}
 @{Name='equal_ordinal';Current='iTunes é DJ';Requested='iTunes é DJ';Source='csv:Titulo';Action='keep';Reason='already_present';Conflict=$false;ValueFrom='current'}
 @{Name='case_conflict';Current='AC/DC';Requested='Ac/Dc';Source='csv:Autor';Action='conflict';Reason='existing_value_differs';Conflict=$true;ValueFrom='current'}
 @{Name='spaces_conflict';Current=' Faixa ';Requested='Faixa';Source='csv:Titulo';Action='conflict';Reason='existing_value_differs';Conflict=$true;ValueFrom='current'}
 @{Name='unicode_not_normalized';Current='é';Requested=('e'+[char]0x301);Source='csv:Titulo';Action='conflict';Reason='existing_value_differs';Conflict=$true;ValueFrom='current'}
 @{Name='current_integer';Current=3;Requested='Novo';Source='csv:Track';Action='unsupported';Reason='non_scalar_value';Conflict=$false;ValueFrom='current'}
 @{Name='requested_integer';Current='Original';Requested=3;Source='csv:Track';Action='unsupported';Reason='non_scalar_value';Conflict=$false;ValueFrom='current'}
 @{Name='current_empty_array';Current=@();Requested='Novo';Source='csv:Titulo';Action='unsupported';Reason='non_scalar_value';Conflict=$false;ValueFrom='current'}
 @{Name='requested_string_array';Current='Original';Requested=@('A','B');Source='csv:Titulo';Action='unsupported';Reason='non_scalar_value';Conflict=$false;ValueFrom='current'}
 @{Name='requested_empty_array';Current=$null;Requested=@();Source='csv:Titulo';Action='unsupported';Reason='non_scalar_value';Conflict=$false;ValueFrom='current'}
 @{Name='mixed_array_with_null';Current=@($null,'A',3);Requested='Novo';Source='csv:Titulo';Action='unsupported';Reason='non_scalar_value';Conflict=$false;ValueFrom='current'}
 @{Name='dictionary';Current=@{a='Original'};Requested='Novo';Source='csv:Titulo';Action='unsupported';Reason='non_scalar_value';Conflict=$false;ValueFrom='current'}
 @{Name='type_priority_absent';Current=@('A','B');Requested=$null;Source='';Action='unsupported';Reason='non_scalar_value';Conflict=$false;ValueFrom='current'}
 @{Name='type_priority_source';Current='Original';Requested=@('A');Source='';Action='unsupported';Reason='non_scalar_value';Conflict=$false;ValueFrom='current'}
 @{Name='source_before_empty';Current='';Requested='Novo';Source='';Action='unsupported';Reason='missing_source';Conflict=$false;ValueFrom='current'}
)
function Assert-TagValuePreserved($Actual,$Expected){
 if($null -eq $Expected){if($null -ne $Actual){throw 'Null alterado'};return}
 if($null -eq $Actual -or $Actual.GetType() -ne $Expected.GetType()){throw 'Tipo do valor alterado'}
 if($Expected -is [string]){if(-not [string]::Equals($Actual,$Expected,[StringComparison]::Ordinal)){throw 'Texto alterado'};return}
 if($Expected -is [array]){
  if($Actual.Length -ne $Expected.Length){throw 'Array alterado'}
  for($i=0;$i -lt $Expected.Length;$i++){Assert-TagValuePreserved $Actual[$i] $Expected[$i]}
  return
 }
 if($Expected -is [Collections.IDictionary]){
  if($Actual.Count -ne $Expected.Count){throw 'Mapa alterado'}
  foreach($k in $Expected.Keys){if(-not $Actual.Contains($k)){throw 'Chave perdida'};Assert-TagValuePreserved $Actual[$k] $Expected[$k]}
  return
 }
 if(-not [object]::Equals($Actual,$Expected)){throw 'Valor alterado'}
}
$failed=0
foreach($c in $cases){
 try{
  $r=Get-EditorialTagValueDecision -CurrentValue $c.Current -RequestedValue $c.Requested -RequestedSource $c.Source
  if($r -isnot [pscustomobject] -or $r.Action -isnot [string] -or $r.Reason -isnot [string] -or $r.Conflict -isnot [bool]){throw 'Tipos do resultado invalidos'}
  if((@($r.PSObject.Properties.Name|Sort-Object) -join '|') -cne 'Action|Conflict|Reason|RequestedSource|RequestedValue|Value'){throw 'Esquema do resultado divergente'}
  if(-not [string]::Equals($r.Action,$c.Action,[StringComparison]::Ordinal) -or -not [string]::Equals($r.Reason,$c.Reason,[StringComparison]::Ordinal) -or $r.Conflict -ne $c.Conflict){throw ('Decisao divergente: '+$r.Action+'/'+$r.Reason)}
  $expected=if($c.ValueFrom -eq 'current'){$c.Current}else{$c.Requested}
  # Evitar enumerar arrays vazios ao selecionar o valor esperado.
  if($c.ValueFrom -eq 'current'){Assert-TagValuePreserved $r.Value $c.Current}else{Assert-TagValuePreserved $r.Value $c.Requested}
  Assert-TagValuePreserved $r.RequestedValue $c.Requested
  $expectedSource=if($c.ContainsKey('ExpectedSource')){$c.ExpectedSource}else{$c.Source}
  Assert-TagValuePreserved $r.RequestedSource $expectedSource
  'PASS '+$c.Name
 }catch{$failed++;'FAIL '+$c.Name+': '+$_.Exception.Message}
}
if($failed){throw ('TAG_VALUE_DECISION_FAILURES='+$failed)}
'TAG_VALUE_DECISION_PASS cases=22'
