#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo=Split-Path $PSScriptRoot -Parent
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Sintaxe principal invalida'}
foreach($name in @('Sort-AudioFormats','Get-Formats')){
 $f=@($a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true))
 if($f.Count -ne 1){throw ('Funcao ausente: '+$name)}
 . ([scriptblock]::Create($f[0].Extent.Text))
}
function F([string]$Id,[string]$Ext,[string]$Codec,[object]$Abr,[string]$Video='none'){
 [pscustomobject]@{format_id=$Id;ext=$Ext;acodec=$Codec;abr=$Abr;tbr=$null;vcodec=$Video;filesize=4096}
}
$inputFormats=@(
 (F '140' 'm4a' 'mp4a.40.2' 128)
 (F 'A' 'mp3' 'mp3' 128)
 (F 'a' 'm4a' 'mp4a.40.2' 128)
 (F 'L' 'm4a' 'alac' 0)
 (F '999' 'mp3' 'mp3' 192)
 (F 'u' 'm4a' 'mp4a.40.2' $null)
 (F 'r' 'mp4' 'aac' 128)
 (F 't' 'webm' 'opus' 128)
 (F 'low' 'mp3' 'mp3' 96)
 (F 'video' 'm4a' 'aac' 128 'h264')
 (F 'bad+' 'm4a' 'aac' 128)
 (F 'unknown' 'bin' 'aac' 128)
)
# RCF5.2: nativo/distancia; politica adicional explicita: ID ASCII ordinal, caixa preservada.
$expected='140|A|L|a|999|u|r|t'
$old=[Globalization.CultureInfo]::CurrentCulture
$rng=[Random]::new(173)
$passed=0
try{
 foreach($culture in @([Globalization.CultureInfo]::InvariantCulture,[Globalization.CultureInfo]::GetCultureInfo('pt-BR'),[Globalization.CultureInfo]::GetCultureInfo('tr-TR'))){
  [Globalization.CultureInfo]::CurrentCulture=$culture
  for($trial=0;$trial -lt 12;$trial++){
   $copy=$inputFormats.Clone()
   for($i=$copy.Length-1;$i -gt 0;$i--){$j=$rng.Next($i+1);$swap=$copy[$i];$copy[$i]=$copy[$j];$copy[$j]=$swap}
   $before=ConvertTo-Json -InputObject $copy -Depth 8 -Compress
   $got=@(Get-Formats ([pscustomobject]@{formats=$copy;duration=4}))
   if(($got.id -join '|') -cne $expected){throw ('Ordem indevida: '+($got.id -join '|'))}
   if((ConvertTo-Json -InputObject $copy -Depth 8 -Compress) -cne $before){throw 'Entrada alterada'}
   $reverse=@($got[7..0])
   $refreshed=@(Sort-AudioFormats -Items $reverse)
   if(($refreshed.id -join '|') -cne $expected){throw 'Refresh mudou prioridade'}
   $passed++
  }
 }
}finally{[Globalization.CultureInfo]::CurrentCulture=$old}
if(@(Sort-AudioFormats -Items @()).Count -ne 0){throw 'Fila vazia inventou formato'}
$calls=@($a.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Sort-AudioFormats'},$true))
if($calls.Count -ne 2){throw 'Get-Formats e refresh nao usam ordenacao comum'}
'RCF_FORMAT_ORDER_PASS: '+$passed+' permutacoes/culturas, filtros, fila vazia e refresh; metadados sinteticos'
