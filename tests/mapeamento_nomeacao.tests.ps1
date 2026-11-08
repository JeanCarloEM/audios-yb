#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$root=Split-Path -Parent $PSScriptRoot
$helper=Join-Path $root 'nomeacao_editorial.ps1'

$new=Join-Path $root 'mapeamento_nomeacao.ps1'
$t=$null;$e=$null
$null=[Management.Automation.Language.Parser]::ParseFile($new,[ref]$t,[ref]$e)
if($e.Count){throw 'Sintaxe invalida'}
. $helper
. $new
$row=[pscustomobject]@{Ordem='003';Artista='AC/DC';Musica='iTunes é DJ'}
$map=@{ColunaAutor='Artista';ColunaTrack='Ordem';ColunaTitulo='Musica'}
$cases=@(
 @{Name='nenhuma_inferencia_legado';Row=$row;Args=@{};Legacy=$true;Parts=@()}
 @{Name='nenhuma_inferencia_header_musical';Row=[pscustomobject]@{Autor='AC/DC';Track='3';Titulo='Faixa'};Args=@{};Legacy=$true;Parts=@()}
 @{Name='titulo_apenas';Row=$row;Args=@{ColunaTitulo='Musica'};Legacy=$false;Parts=@('iTunes é DJ')}
 @{Name='declaracao_explicita';Row=$row;Args=$map;Legacy=$false;Parts=@('AC/DC','3','iTunes é DJ')}
 @{Name='padding_explicito';Row=$row;Args=@{ColunaAutor='Artista';ColunaTrack='Ordem';ColunaTitulo='Musica';LarguraTrack=4};Legacy=$false;Parts=@('AC/DC','0003','iTunes é DJ')}
 @{Name='titulo_branco';Row=[pscustomobject]@{Musica=(' '+[char]9+' ')};Args=@{ColunaTitulo='Musica'};Legacy=$true;Parts=@()}
 @{Name='opcionais_brancos';Row=[pscustomobject]@{Artista=(' '+[char]9+' ');Ordem=' ';Musica='Faixa'};Args=$map;Legacy=$false;Parts=@('Faixa')}
 @{Name='coluna_mapeada_ausente';Row=$row;Args=@{ColunaAutor='Compositor';ColunaTitulo='Musica'};Legacy=$true;Parts=@()}
 @{Name='header_ordinal';Row=$row;Args=@{ColunaTitulo='musica'};Legacy=$true;Parts=@()}
 @{Name='celula_nao_string';Row=[pscustomobject]@{Ordem=3;Musica='Faixa'};Args=@{ColunaTrack='Ordem';ColunaTitulo='Musica'};Legacy=$true;Parts=@()}
 @{Name='titulo_null';Row=[pscustomobject]@{Musica=$null};Args=@{ColunaTitulo='Musica'};Legacy=$true;Parts=@()}
 @{Name='header_ponto_literal';Row=[pscustomobject]@{'Titulo.Real'='Faixa';Titulo=[pscustomobject]@{Real='ERRADO'}};Args=@{ColunaTitulo='Titulo.Real'};Legacy=$false;Parts=@('Faixa')}
 @{Name='row_null';Row=$null;Args=@{ColunaTitulo='Musica'};Legacy=$true;Parts=@()}
 @{Name='largura_invalida';Row=$row;Args=@{ColunaTitulo='Musica';LarguraTrack=0};Throws=$true}
)
$dir=Join-Path $root 'tests/.runtime-editorial-mapping'
$null=[IO.Directory]::CreateDirectory($dir)
$log=Join-Path $dir 'test.log'
$failed=0
foreach($c in $cases){
 try{
  $call=@{Row=$c.Row};foreach($k in $c.Args.Keys){$call[$k]=$c.Args[$k]}
  if($c.ContainsKey('Throws')){
   $caught=$false
   try{$null=Get-CsvMusicalNameComponents @call}catch{$ex=$_.Exception;while($null -ne $ex.InnerException){$ex=$ex.InnerException};if($ex -isnot [ArgumentOutOfRangeException]){throw};$caught=$true}
   if(-not $caught){throw 'Largura invalida aceita'}
  }else{
   $r=Get-CsvMusicalNameComponents @call
   if($r -isnot [hashtable] -or $r.usar_legado -isnot [bool] -or $r.componentes -isnot [string[]] -or $r.motivo -isnot [string]){throw 'Contrato de tipos invalido'}
   if($r.usar_legado -ne $c.Legacy -or $r.componentes.Count -ne $c.Parts.Count){throw 'Fallback/quantidade divergente'}
   for($i=0;$i -lt $c.Parts.Count;$i++){if(-not [string]::Equals($r.componentes[$i],$c.Parts[$i],[StringComparison]::Ordinal)){throw 'Componente divergente'}}
   if($c.Legacy -and [string]::IsNullOrWhiteSpace($r.motivo)){throw 'Fallback sem motivo'}
  }
  $line='PASS '+$c.Name
 }catch{$failed++;$line='FAIL '+$c.Name+': '+$_.Exception.Message}
 $line|Write-Output
 $line|Add-Content -LiteralPath $log -Encoding utf8
}
if($failed){throw ('MAPPING_FAILURES='+$failed)}
'MAPPING_BEHAVIOR_PASS cases=14'
'MAPPING_BEHAVIOR_PASS cases=14'|Add-Content -LiteralPath $log -Encoding utf8