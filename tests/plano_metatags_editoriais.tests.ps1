#requires -Version 7
param([string]$HelperPath='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($HelperPath)){$HelperPath=Join-Path $root 'plano_metatags_editoriais.ps1'}
. (Join-Path $root 'decisao_metatags.ps1')
. (Join-Path $root 'comparacao_tags_ordinal.ps1')
. $HelperPath
$script:Cases=0;$script:Failures=0
function Check-Plan([string]$Name,[object]$Current,[object]$Requested,[object]$Sources,[bool]$Ready,[hashtable]$ExpectedUpdates,[hashtable]$ExpectedDecisions,[switch]$Invalid){
 $script:Cases++;$stamp1=[Management.Automation.PSSerializer]::Serialize(@($Current,$Requested,$Sources),15);$caught=$null;$output=@()
 try{$output=@(Get-EditorialTagPlan -CurrentValues $Current -RequestedValues $Requested -RequestedSources $Sources)}catch{$caught=$_.Exception;while($null -ne $caught.InnerException){$caught=$caught.InnerException}}
 try{
  if($Invalid){if($caught -isnot [ArgumentException]){throw ('ArgumentException esperado: '+$caught)}}
  else{
   if($null -ne $caught){throw $caught}
   if($output.Count -ne 1 -or $output[0] -isnot [pscustomobject]){throw 'Retorno nao unico'}
   $p=$output[0]
   if($p.Ready -isnot [bool] -or $p.Ready -ne $Ready -or $p.Updates -isnot [hashtable]){throw 'Ready/Updates invalidos'}
   $null=Assert-OrdinalStringMap -Expected $ExpectedUpdates -Actual $p.Updates
   $tags=@('artist','title','album','track','composer')
   if($p.Decisions -isnot [object[]] -or $p.Decisions.Count -ne 5){throw 'Esperadas5decisoes ordenadas'}
   foreach($i in 0..4){
    $d=$p.Decisions[$i];$expected=@('keep','absent')
    if($ExpectedDecisions.ContainsKey($tags[$i])){$expected=$ExpectedDecisions[$tags[$i]]}
    if(-not [string]::Equals($d.Tag,$tags[$i],[StringComparison]::Ordinal) -or -not [string]::Equals($d.Decision.Action,$expected[0],[StringComparison]::Ordinal) -or -not [string]::Equals($d.Decision.Reason,$expected[1],[StringComparison]::Ordinal)){throw ('Decisao divergente: '+$tags[$i])}
    if($d.Decision.Conflict -isnot [bool] -or $d.Decision.Conflict -ne ($expected[0] -ceq 'conflict')){throw 'Flag conflito'}
   }
  }
  if(-not [string]::Equals($stamp1,[Management.Automation.PSSerializer]::Serialize(@($Current,$Requested,$Sources),15),[StringComparison]::Ordinal)){throw 'Entrada alterada'}
  'PASS '+$Name
 }catch{$script:Failures++;'FAIL '+$Name+': '+$_.Exception.Message}
}
Check-Plan 'empty_noop' $null @{} $null $true @{} @{}
Check-Plan 'apply_title' $null @{title=' Título iTunes '} @{title='csv:Musica'} $true @{title=' Título iTunes '} @{title=@('apply','empty_field')}
$five=@{artist='Artista';title='Título';album='Álbum';track='003';composer='Autor'}
$sources5=@{artist='csv:Artista';title='csv:Musica';album='csv:Album';track='csv:Track';composer='csv:Autor'}
$applies5=@{artist=@('apply','empty_field');title=@('apply','empty_field');album=@('apply','empty_field');track=@('apply','empty_field');composer=@('apply','empty_field')}
Check-Plan 'apply_five' $null $five $sources5 $true $five $applies5
Check-Plan 'already_present' @{title='A'} @{title='A'} @{title='csv:Musica'} $true @{} @{title=@('keep','already_present')}
Check-Plan 'conflict_blocks_all' @{title='Origem'} @{title='Pedido';artist='Novo'} @{title='csv:Musica';artist='csv:Artista'} $false @{} @{title=@('conflict','existing_value_differs');artist=@('apply','empty_field')}
Check-Plan 'missing_source_blocks_all' $null @{title='Pedido';artist='Novo'} @{artist='csv:Artista'} $false @{} @{title=@('unsupported','missing_source');artist=@('apply','empty_field')}
Check-Plan 'requested_array_unsupported' $null @{title=@('A','B')} @{title='csv:Musica'} $false @{} @{title=@('unsupported','non_scalar_value')}
Check-Plan 'current_array_priority' @{title=@('A','B')} @{} $null $false @{} @{title=@('unsupported','non_scalar_value')}
Check-Plan 'absent_whitespace' @{title='Origem'} @{title=' '} $null $true @{} @{}
Check-Plan 'empty_current_preserves_requested' @{title=' '} @{title=' Título '} @{title='csv:Musica'} $true @{title=' Título '} @{title=@('apply','empty_field')}
Check-Plan 'case_value_conflict' @{title='iTunes'} @{title='itunes'} @{title='csv:Musica'} $false @{} @{title=@('conflict','existing_value_differs')}
Check-Plan 'unicode_ordinal_conflict' @{title='iTunes'} @{title=('i'+[char]0xAD+'Tunes')} @{title='csv:Musica'} $false @{} @{title=@('conflict','existing_value_differs')}
Check-Plan 'custom_current_not_inferred' @{custom=1} @{} $null $true @{} @{}
Check-Plan 'current_key_case_exact' @{Title='Origem'} @{title='Novo'} @{title='csv:Musica'} $true @{title='Novo'} @{title=@('apply','empty_field')}
$caseMap=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);$caseMap.Add('title','A');$caseMap.Add('Title','B')
Check-Plan 'current_case_distinct_not_collapsed' $caseMap @{title='A'} @{title='csv:Musica'} $true @{} @{title=@('keep','already_present')}
Check-Plan 'null_requested_invalid' $null $null $null $false @{} @{} -Invalid
Check-Plan 'requested_type_invalid' $null 'x' $null $false @{} @{} -Invalid
Check-Plan 'current_type_invalid' 'x' @{} $null $false @{} @{} -Invalid
Check-Plan 'source_type_invalid' $null @{} @('x') $false @{} @{} -Invalid
Check-Plan 'requested_key_invalid' $null @{Title='X'} $null $false @{} @{} -Invalid
Check-Plan 'source_key_invalid' $null @{} @{Title='csv:Musica'} $false @{} @{} -Invalid
Check-Plan 'current_key_type_invalid' @{1='X'} @{} $null $false @{} @{} -Invalid
Check-Plan 'requested_nul_invalid' $null @{title=('A'+[char]0+'B')} @{title='csv:Musica'} $false @{} @{} -Invalid
Check-Plan 'source_value_type_invalid' $null @{title='X'} @{title=1} $false @{} @{} -Invalid
Check-Plan 'requested_bool_unsupported' $null @{title=$true} @{title='csv:Musica'} $false @{} @{title=@('unsupported','non_scalar_value')}
if($script:Failures){throw ('EDITORIAL_PLAN_FAILURES='+$script:Failures)}
'EDITORIAL_PLAN_PASS cases='+$script:Cases
