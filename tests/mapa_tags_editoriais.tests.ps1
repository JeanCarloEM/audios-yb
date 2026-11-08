#requires -Version 7
param([string]$HelperPath='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($HelperPath)){$HelperPath=Join-Path $root 'mapa_tags_editoriais.ps1'}
. $HelperPath
. (Join-Path $root 'comparacao_tags_ordinal.ps1')
$script:Cases=0;$script:Failures=0
function Check-EditorialMap([string]$Name,[object]$Before,[object]$Updates,[object]$Expected,[bool]$ExpectError=$false,[switch]$OmitUpdates){
 $script:Cases++;$stamp1=[Management.Automation.PSSerializer]::Serialize(@($Before,$Updates),15)
 $caught=$null;$result=@()
 try{if($OmitUpdates){$result=@(New-EditorialTagMap -Before $Before)}else{$result=@(New-EditorialTagMap -Before $Before -Updates $Updates)}}catch{$caught=$_.Exception;while($null -ne $caught.InnerException){$caught=$caught.InnerException}}
 try{
  if($ExpectError){if($caught -isnot [ArgumentException]){throw ('ArgumentException esperado: '+$caught)}}
  else{
   if($null -ne $caught){throw $caught}
   if($result.Count -ne 1 -or $result[0] -isnot [Collections.Generic.Dictionary[string,string]]){throw 'Retorno deve ser um Dictionary[string,string] unico'}
   $null=Assert-OrdinalStringMap -Expected $Expected -Actual $result[0]
   $result[0]['__test_only__']='changed'
  }
  $stamp2=[Management.Automation.PSSerializer]::Serialize(@($Before,$Updates),15)
  if(-not [string]::Equals($stamp1,$stamp2,[StringComparison]::Ordinal)){throw 'Argumentos alterados ou retorno compartilha armazenamento'}
  'PASS '+$Name
 }catch{$script:Failures++;'FAIL '+$Name+': '+$_.Exception.Message}
}
$soft=[string][char]0xAD
Check-EditorialMap 'empty_from_null' $null @{} @{}
Check-EditorialMap 'empty_from_object' ([pscustomobject]@{}) @{} @{}
Check-EditorialMap 'preserve_existing_literal' ([pscustomobject]@{artist='Artista é';custom='';marcador_coletanea='Grupo';encoder='Lavf';nul=('A'+[char]0+'B')}) @{} @{artist='Artista é';custom='';marcador_coletanea='Grupo';encoder='Lavf';nul=('A'+[char]0+'B')}
Check-EditorialMap 'all_five' $null @{artist='Artista é';title='Faixa iTunes';album='Coletânea';track='003';composer='AC/DC'} @{artist='Artista é';title='Faixa iTunes';album='Coletânea';track='003';composer='AC/DC'}
Check-EditorialMap 'replace_only_requested' ([pscustomobject]@{title='Origem';album='Album fonte';custom='Sentinela';marcador_coletanea='Grupo'}) @{title='Novo'} @{title='Novo';album='Album fonte';custom='Sentinela';marcador_coletanea='Grupo'}
Check-EditorialMap 'spaces_and_unicode_not_normalized' $null @{title=(' i'+$soft+'Tunes ')} @{title=(' i'+$soft+'Tunes ')}
Check-EditorialMap 'equal_value' ([pscustomobject]@{title='A'}) @{title='A'} @{title='A'}
$caseExpected=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
$caseExpected.Add('Title','Old');$caseExpected.Add('title','New')
Check-EditorialMap 'different_case_names_preserved' ([pscustomobject]@{Title='Old'}) @{title='New'} $caseExpected
Check-EditorialMap 'null_updates' $null $null $null $true
Check-EditorialMap 'omitted_updates' $null $null $null $true -OmitUpdates
$badBefore=@(@{Name='string';Value='x'},@{Name='integer';Value=1},@{Name='array';Value=@('A','B')},@{Name='hashtable';Value=@{title='A'}})
foreach($fixture in $badBefore){Check-EditorialMap ('before_'+$fixture.Name) $fixture.Value @{} $null $true}
$badProps=@(@{Name='null';Value=$null},@{Name='integer';Value=1},@{Name='array';Value=@('A','B')})
foreach($fixture in $badProps){Check-EditorialMap ('property_'+$fixture.Name) ([pscustomobject]@{title=$fixture.Value}) @{} $null $true}
$badKeys=@(@{Name='uppercase';Value='Title'},@{Name='soft';Value=('ti'+$soft+'tle')},@{Name='unknown';Value='custom'},@{Name='integer';Value=1},@{Name='empty';Value=''},@{Name='space';Value='title '})
foreach($fixture in $badKeys){$updatesForCase=@{};$updatesForCase[$fixture.Value]='X';Check-EditorialMap ('key_'+$fixture.Name) $null $updatesForCase $null $true}
$badValues=@(@{Name='null';Value=$null},@{Name='integer';Value=1},@{Name='boolean';Value=$true},@{Name='array';Value=@('A','B')},@{Name='empty_array';Value=@()},@{Name='empty';Value=''},@{Name='space';Value=' '},@{Name='nul';Value=('A'+[char]0+'B')})
foreach($fixture in $badValues){Check-EditorialMap ('value_'+$fixture.Name) $null @{title=$fixture.Value} $null $true}
if($script:Failures){throw ('EDITORIAL_MAP_FAILURES='+$script:Failures)}
'EDITORIAL_MAP_PASS cases='+$script:Cases
