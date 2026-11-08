#requires -Version 7
function Get-EditorialCsvField {
 param([AllowNull()][object]$Row,[AllowNull()][object]$Column)
 if($null -ne $Column -and $Column -isnot [string]){throw [ArgumentException]::new('Column deve ser string ou null')}
 if($Column -is [string] -and $Column.Contains([char]0)){throw [ArgumentException]::new('Column com NUL')}
 $result=[pscustomobject]@{Column=$Column;Value=$null;Source='';Found=$false;Supported=$true;Reason='mapping_absent'}
 if($null -eq $Column -or [string]::IsNullOrWhiteSpace($Column)){return $result}
 if($null -eq $Row -or $Row -isnot [pscustomobject]){throw [ArgumentException]::new('Row deve ser PSCustomObject')}
 $property=$null
 foreach($prop in $Row.PSObject.Properties){
  if([string]::Equals($prop.Name, $Column, [StringComparison]::Ordinal)){if($null -ne $property){throw [ArgumentException]::new('Coluna duplicada')};$property=$prop}
 }
 if($null -eq $property){$result.Supported=$false;$result.Reason='missing_column';return $result}
 $result.Value=$property.Value;$result.Source='csv:'+$Column;$result.Found=$true
 if($null -ne $result.Value -and $result.Value -isnot [string]){$result.Supported=$false;$result.Reason='non_scalar_value'}
 elseif($result.Value -is [string] -and $result.Value.Contains([char]0)){$result.Supported=$false;$result.Reason='invalid_nul'}
 elseif($null -eq $result.Value -or [string]::IsNullOrWhiteSpace($result.Value)){$result.Reason='absent'}
 else{$result.Reason='mapped'}
 return $result
}
