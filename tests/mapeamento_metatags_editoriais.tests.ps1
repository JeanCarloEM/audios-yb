#requires -Version 7
param([string]$HelperPath='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($HelperPath)){$HelperPath=Join-Path $root 'mapeamento_metatags_editoriais.ps1'}
. (Join-Path $root 'leitura_campo_editorial.ps1')
. (Join-Path $root 'comparacao_tags_ordinal.ps1')
. (Join-Path $root 'decisao_metatags.ps1')
. (Join-Path $root 'plano_metatags_editoriais.ps1')
. $HelperPath
$script:Cases=0;$script:Failures=0
function Check-Requests([string]$Name,[object]$Row,[object]$Columns,[bool]$Ready,[hashtable]$Values,[hashtable]$Sources,[hashtable]$Reasons,[switch]$Invalid){
 $script:Cases++;$before=[Management.Automation.PSSerializer]::Serialize(@($Row,$Columns),15);$caught=$null;$output=@()
 try{$output=@(Get-EditorialCsvRequests -Row $Row -Columns $Columns)}catch{$caught=$_.Exception;while($null -ne $caught.InnerException){$caught=$caught.InnerException}}
 try{
  if($Invalid){if($caught -isnot [ArgumentException]){throw ('ArgumentException esperado: '+$caught)}}
  else{
   if($null -ne $caught){throw $caught}
   if($output.Count -ne 1 -or $output[0] -isnot [pscustomobject]){throw 'Retorno nao unico'}
   $r=$output[0]
   if($r.Ready -isnot [bool] -or $r.Ready -ne $Ready -or $r.RequestedValues -isnot [hashtable] -or $r.RequestedSources -isnot [hashtable]){throw 'Schema flags/mapas'}
   $null=Assert-OrdinalStringMap -Expected $Sources -Actual $r.RequestedSources
   if($r.RequestedValues.Count -ne $Values.Count){throw 'Count de pedidos'}
   foreach($key in $Values.Keys){
    if([Array]::IndexOf(@($r.RequestedValues.Keys),$key) -lt 0 -or -not [string]::Equals([Management.Automation.PSSerializer]::Serialize($r.RequestedValues[$key],15),[Management.Automation.PSSerializer]::Serialize($Values[$key],15),[StringComparison]::Ordinal)){throw 'Pedido alterado'}
   }
   $tags=@('artist','title','album','track','composer')
   if($r.Fields -isnot [object[]] -or $r.Fields.Count -ne 5){throw 'Esperados5campos'}
   foreach($i in 0..4){$reason='mapping_absent';if($Reasons.ContainsKey($tags[$i])){$reason=$Reasons[$tags[$i]]};if(-not [string]::Equals($r.Fields[$i].Tag,$tags[$i],[StringComparison]::Ordinal) -or -not [string]::Equals($r.Fields[$i].Field.Reason,$reason,[StringComparison]::Ordinal)){throw 'Rastreio divergente'}}
  }
  if(-not [string]::Equals($before,[Management.Automation.PSSerializer]::Serialize(@($Row,$Columns),15),[StringComparison]::Ordinal)){throw 'Entrada alterada'}
  'PASS '+$Name
 }catch{$script:Failures++;'FAIL '+$Name+': '+$_.Exception.Message}
}
$row=[pscustomobject]@{Artista='Intérprete';Musica=' Canção ';Ordem='42';Album='Álbum';Numero='003';Autor='Compositor'}
$two=@{artist='Artista';title='Musica'}
$five=@{artist='Artista';title='Musica';album='Album';track='Numero';composer='Autor'}
Check-Requests 'no_mapping_null' $null $null $true @{} @{} @{}
Check-Requests 'no_mapping_empty' $null @{} $true @{} @{} @{}
Check-Requests 'canonical_declared_two' $row $two $true @{artist='Intérprete';title=' Canção '} @{artist='csv:Artista';title='csv:Musica'} @{artist='mapped';title='mapped'}
Check-Requests 'five_declared' $row $five $true @{artist='Intérprete';title=' Canção ';album='Álbum';track='003';composer='Compositor'} @{artist='csv:Artista';title='csv:Musica';album='csv:Album';track='csv:Numero';composer='csv:Autor'} @{artist='mapped';title='mapped';album='mapped';track='mapped';composer='mapped'}
Check-Requests 'no_inferred_aliases' $row @{title='Musica'} $true @{title=' Canção '} @{title='csv:Musica'} @{title='mapped'}
Check-Requests 'missing_blocks_all' $row @{title='Musica';album='Inexistente'} $false @{} @{} @{title='mapped';album='missing_column'}
Check-Requests 'array_blocks_all' ([pscustomobject]@{Artista='Intérprete';Musica=@('A','B')}) $two $false @{} @{} @{artist='mapped';title='non_scalar_value'}
Check-Requests 'blank_mapping_optional' $null @{title=' '} $true @{} @{} @{}
Check-Requests 'blank_value_literal' ([pscustomobject]@{Musica=' '}) @{title='Musica'} $true @{title=' '} @{title='csv:Musica'} @{title='absent'}
Check-Requests 'null_value_literal' ([pscustomobject]@{Musica=$null}) @{title='Musica'} $true @{title=$null} @{title='csv:Musica'} @{title='absent'}
Check-Requests 'header_case_missing' $row @{title='musica'} $false @{} @{} @{title='missing_column'}
Check-Requests 'mapping_key_case_invalid' $row @{Title='Musica'} $false @{} @{} @{} -Invalid
Check-Requests 'mapping_value_invalid' $row @{title=1} $false @{} @{} @{} -Invalid
Check-Requests 'columns_array_invalid' $row @('Musica') $false @{} @{} @{} -Invalid
Check-Requests 'row_null_declared_invalid' $null $two $false @{} @{} @{} -Invalid
Check-Requests 'nul_blocks_all' ([pscustomobject]@{Musica=('A'+[char]0+'B')}) @{title='Musica'} $false @{} @{} @{title='invalid_nul'}
$requests=Get-EditorialCsvRequests -Row $row -Columns $two
$plan=Get-EditorialTagPlan -CurrentValues $null -RequestedValues $requests.RequestedValues -RequestedSources $requests.RequestedSources
if(-not $requests.Ready -or -not $plan.Ready){throw 'Composicao de aplicacao bloqueada'}
$null=Assert-OrdinalStringMap -Expected @{artist='Intérprete';title=' Canção '} -Actual $plan.Updates
'PASS composed_plan_apply'
$blocked=Get-EditorialTagPlan -CurrentValues @{title='Origem'} -RequestedValues $requests.RequestedValues -RequestedSources $requests.RequestedSources
if($blocked.Ready -or $blocked.Updates.Count -ne 0){throw 'Conflito da origem nao bloqueou operacao'}
'PASS composed_plan_conflict'
if($script:Failures){throw ('EDITORIAL_CSV_REQUESTS_FAILURES='+$script:Failures)}
'EDITORIAL_CSV_REQUESTS_PASS cases='+($script:Cases+2)
