#requires -Version 7
param([string]$HelperPath='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($HelperPath)){$HelperPath=Join-Path $root 'validacao_tags_editoriais.ps1'}
. (Join-Path $root 'mapa_tags_editoriais.ps1')
. (Join-Path $root 'comparacao_tags_ordinal.ps1')
. $HelperPath
$script:Cases=0;$script:Failures=0
function Check-Snapshot([string]$Name,[object]$Before,[object]$After,[object]$Updates,[type]$ExceptionType){
 $script:Cases++;$stamp1=[Management.Automation.PSSerializer]::Serialize(@($Before,$After,$Updates),15);$caught=$null;$result=@()
 try{$result=@(Assert-EditorialTagSnapshot -Before $Before -After $After -Updates $Updates)}catch{$caught=$_.Exception;while($null -ne $caught.InnerException){$caught=$caught.InnerException}}
 try{
  if($null -eq $ExceptionType){if($null -ne $caught){throw $caught};if($result.Count -ne 1 -or $result[0] -isnot [bool] -or -not $result[0]){throw 'Esperado apenas bool true'}}
  elseif($null -eq $caught -or -not $ExceptionType.IsInstanceOfType($caught)){throw ('Excecao esperada: '+$ExceptionType.FullName+'; recebida: '+$caught)}
  $stamp2=[Management.Automation.PSSerializer]::Serialize(@($Before,$After,$Updates),15)
  if(-not [string]::Equals($stamp1,$stamp2,[StringComparison]::Ordinal)){throw 'Entrada alterada'}
  'PASS '+$Name
 }catch{$script:Failures++;'FAIL '+$Name+': '+$_.Exception.Message}
}
$diff=[IO.InvalidDataException];$arg=[ArgumentException];$soft=[string][char]0xAD
Check-Snapshot 'null_empty_maps' $null $null @{} $null
Check-Snapshot 'null_vs_empty_object' $null ([pscustomobject]@{}) @{} $null
Check-Snapshot 'all_five_plus_preserved' ([pscustomobject]@{marcador_coletanea='Grupo';custom='';encoder='Lavf'}) ([pscustomobject]@{artist='Artista é';title=' Faixa iTunes ';album='Coletânea';track='003';composer='AC/DC';marcador_coletanea='Grupo';custom='';encoder='Lavf'}) @{artist='Artista é';title=' Faixa iTunes ';album='Coletânea';track='003';composer='AC/DC'} $null
Check-Snapshot 'explicit_replace_preserves_rest' ([pscustomobject]@{title='Origem';album='Album fonte';custom='Sentinela'}) ([pscustomobject]@{title='Novo';album='Album fonte';custom='Sentinela'}) @{title='Novo'} $null
Check-Snapshot 'empty_updates_still_compares' ([pscustomobject]@{title='A'}) ([pscustomobject]@{title='B'}) @{} $diff
Check-Snapshot 'extra_tag_rejected' $null ([pscustomobject]@{extra='X'}) @{} $diff
Check-Snapshot 'removed_original_rejected' ([pscustomobject]@{marcador_coletanea='Grupo'}) $null @{} $diff
Check-Snapshot 'requested_tag_missing' $null $null @{title='X'} $diff
Check-Snapshot 'requested_value_wrong' $null ([pscustomobject]@{title='Y'}) @{title='X'} $diff
Check-Snapshot 'tag_name_case' ([pscustomobject]@{title='X'}) ([pscustomobject]@{Title='X'}) @{} $diff
Check-Snapshot 'value_unicode_ordinal' ([pscustomobject]@{title='iTunes'}) ([pscustomobject]@{title=('i'+$soft+'Tunes')}) @{} $diff
Check-Snapshot 'null_updates' $null $null $null $arg
Check-Snapshot 'invalid_request_key' $null $null @{Title='X'} $arg
Check-Snapshot 'invalid_after_hashtable' $null @{title='X'} @{} $arg
Check-Snapshot 'invalid_after_value' $null ([pscustomobject]@{title=@('A','B')}) @{} $arg
Check-Snapshot 'invalid_before_value' ([pscustomobject]@{title=1}) $null @{} $arg
Check-Snapshot 'invalid_after_scalar' $null 'X' @{} $arg
if($script:Failures){throw ('EDITORIAL_SNAPSHOT_FAILURES='+$script:Failures)}
'EDITORIAL_SNAPSHOT_PASS cases='+$script:Cases
