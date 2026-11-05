#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'evidencias_fonte.ps1')
$script:Root=Join-Path $PSScriptRoot ('.runtime-evidence-contract-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:Root)
function Resolve-Input([string]$Path){
 if([IO.Path]::IsPathRooted($Path)){return [IO.Path]::GetFullPath($Path)}
 return [IO.Path]::GetFullPath((Join-Path $script:Root $Path))
}
function To-Hashtable($Value){
 $h=@{}
 foreach($property in $Value.PSObject.Properties){$h[$property.Name]=$property.Value}
 return $h
}
$doc=Join-Path $script:Root 'documento.txt'
$source=Join-Path $script:Root 'fonte.bin'
[IO.File]::WriteAllText($doc,'Documento independente de fixture para contrato de campos, nao certificacao musical.')
[IO.File]::WriteAllText($source,'Bytes sinteticos independentes: este teste verifica somente o esquema do manifesto.')
$base=@{video_id='TestVideo01';formato_id='140';sha256=(Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant();origem='Fixture local de contrato RCF';historico='Historico sintetico conhecido somente para testes de parser';qualidade='perdas_verificadas';bitrate_minimo_historico_kbps=128;documento=$doc;documento_sha256=(Get-FileHash -LiteralPath $doc).Hash.ToLowerInvariant()}
# Expectativas literais derivadas de RCF 5.4 e piso 5.1, independentes do importador.
$cases=@(
 @{name='128';value=128;ok=$true},
 @{name='192';value=192;ok=$true},
 @{name='zero_sem_perdas';value=0;quality='sem_perdas_verificada';ok=$true},
 @{name='128_sem_perdas';value=128;quality='sem_perdas_verificada';ok=$true},
 @{name='ausente';missing=$true;ok=$false},
 @{name='null';value=$null;ok=$false},
 @{name='negativo';value=-1;ok=$false},
 @{name='abaixo';value=127.999;ok=$false},
 @{name='zero_perdas';value=0;ok=$false},
 @{name='texto';value='128';ok=$false},
 @{name='vazio';value='';ok=$false},
 @{name='booleano';value=$true;ok=$false},
 @{name='array';value=@(128);ok=$false},
 @{name='objeto';value=@{n=128};ok=$false},
 @{name='nan';value=[double]::NaN;ok=$false},
 @{name='infinito';overflow=$true;ok=$false},
 @{name='ausente_sem_perdas';missing=$true;quality='sem_perdas_verificada';ok=$false},
 @{name='negativo_sem_perdas';value=-1;quality='sem_perdas_verificada';ok=$false},
 @{name='96_sem_perdas';value=96;quality='sem_perdas_verificada';ok=$false}
)
foreach($case in $cases){
 $entry=$base.Clone()
 if($case.ContainsKey('quality')){$entry.qualidade=$case.quality}
 if($case.ContainsKey('missing')){[void]$entry.Remove('bitrate_minimo_historico_kbps')}
 elseif(-not $case.ContainsKey('overflow')){$entry.bitrate_minimo_historico_kbps=$case.value}
 $json=ConvertTo-Json -InputObject @($entry) -Depth 8
 if($case.ContainsKey('overflow')){
  $pattern='"bitrate_minimo_historico_kbps"\s*:\s*128'
  if([regex]::Matches($json,$pattern).Count -ne 1){throw 'Fixture de overflow divergiu'}
  $json=[regex]::Replace($json,$pattern,'"bitrate_minimo_historico_kbps": 1e400')
 }
 $path=Join-Path $script:Root ($case.name+'.json')
 [IO.File]::WriteAllText($path,$json)
 $accepted=$false;$errorText=''
 try{
  $entries=Import-SourceEvidence $path
  if($entries.Count -ne 1){throw 'Entrada valida nao preservada'}
  $accepted=$true
 }catch{$errorText=$_.Exception.Message}
 if($accepted -ne $case.ok){throw ('Contrato divergiu: '+$case.name+' aceito='+$accepted+' erro='+$errorText)}
}
$script:Root=Join-Path $script:Root 'isolamento'
[void][IO.Directory]::CreateDirectory($script:Root)
$valid=$base.Clone()
$invalid=$base.Clone();$invalid.bitrate_minimo_historico_kbps='128'
[IO.File]::WriteAllText((Join-Path $script:Root 'a-invalido.json'),(ConvertTo-Json -InputObject @($invalid) -Depth 8))
[IO.File]::WriteAllText((Join-Path $script:Root 'b-valido.json'),(ConvertTo-Json -InputObject @($valid) -Depth 8))
$loaded=Get-LocalSourceEvidence -Root $script:Root -Control (Join-Path $script:Root 'ausente') 3>$null
if($loaded.Count -ne 1){throw 'Manifesto invalido interrompeu o valido'}
$key='TestVideo01|140|'+$base.sha256
if(-not $loaded.ContainsKey($key) -or $loaded[$key].bitrate_minimo_historico_kbps -is [string]){throw 'Coercao ou chave incorreta'}
'RCF_HISTORY_CONTRACT_PASS: '+$cases.Count+' casos e isolamento; somente esquema, sem certificacao externa'
