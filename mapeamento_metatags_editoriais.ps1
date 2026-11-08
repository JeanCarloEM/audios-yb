#requires -Version 7
function Get-EditorialCsvRequests {
 param([AllowNull()][object]$Row,[AllowNull()][object]$Columns)
 if($null -ne $Columns -and $Columns -isnot [Collections.IDictionary]){throw [ArgumentException]::new('Columns deve ser mapa')}
 $tags=@('artist','title','album','track','composer')
 $mapping=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
 if($null -ne $Columns){foreach($key in $Columns.Keys){
  if($key -isnot [string] -or [Array]::IndexOf($tags,$key) -lt 0){throw [ArgumentException]::new('Tag de mapeamento invalida')}
  if($null -ne $Columns[$key] -and $Columns[$key] -isnot [string]){throw [ArgumentException]::new('Coluna deve ser string ou null')}
  if(-not $mapping.TryAdd($key,$Columns[$key])){throw [ArgumentException]::new('Tag duplicada')}
 }}
 $ready=$true;$values=@{};$sources=@{};$fields=@()
 foreach($tag in $tags){
  $column=$null;if($mapping.ContainsKey($tag)){$column=$mapping[$tag]}
  $field=Get-EditorialCsvField -Row $Row -Column $column
  $fields += [pscustomobject]@{Tag=$tag;Field=$field}
  if(-not $field.Supported){$ready=$false}
  elseif($field.Found){$values[$tag]=$field.Value;$sources[$tag]=$field.Source}
 }
 if(-not $ready){$values.Clear();$sources.Clear()}
 return [pscustomobject]@{Ready=$ready;RequestedValues=$values;RequestedSources=$sources;Fields=$fields}
}
