#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'parametros_elevacao.ps1')
$checks=0
function Assert($ok,$why){if(!$ok){throw $why};$script:checks++}
function Decode($payload){[Management.Automation.PSSerializer]::Deserialize([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)))}
function MustReject($value){$failed=$false;try{$null=ConvertTo-ElevationParameterPayload -BoundParameters $value}catch{$failed=$true};Assert $failed 'Entrada inválida deve falhar'}
# Expectativas independentes do formato da implementação: conteúdo e binding de parâmetros atuais.
$original=@{
 Csv="C:\pasta [1]\a 'b' `"c`" & `$literal; arquivo.csv"
 Destino="C:\áudio 日本語\linha`nseguinte"
 Marcador=([string][char]0)+'texto'
 Interativo=[Management.Automation.SwitchParameter]::new($true)
 NaoInterativo=[Management.Automation.SwitchParameter]::new($false)
 Nullable=$null;Bool=$false;MaxTentativas=[int]2147483647
 ErrorAction=[Management.Automation.ActionPreference]::Stop
}
$payload=ConvertTo-ElevationParameterPayload -BoundParameters $original
Assert ($payload -is [string] -and $payload -cmatch '\A[A-Za-z0-9+/]+={0,2}\z') 'Somente dados Base64, sem shell'
$round=Decode $payload
Assert ($round -is [hashtable] -and $round.Count -eq 2 -and $round.version -eq 1 -and $round.parameters.Count -eq $original.Count) 'Envelopev1 completo'
foreach($key in $original.Keys){
 Assert ($round.parameters.ContainsKey($key)) 'Preserva chave explicitamente vinculada'
 $expected=$original[$key];$actual=$round.parameters[$key]
 if($null -eq $expected){Assert ($null -eq $actual) 'Preserva null'}
 elseif($expected -is [Management.Automation.SwitchParameter]){Assert ($actual -is [Management.Automation.SwitchParameter] -and $actual.IsPresent -eq $expected.IsPresent) 'Preserva switch verdadeiro/falso'}
 elseif($expected -is [Management.Automation.ActionPreference]){
  # PSSerializer usa Int32 para enum; provar binding nativo equivalente sem executar o principal.
  $bound=& {param([Management.Automation.ActionPreference]$a) $a} $actual
  Assert ($bound -eq [Management.Automation.ActionPreference]::Stop) 'Preserva semântica de ErrorAction'
 }else{Assert ($actual.GetType() -eq $expected.GetType() -and $actual -ceq $expected) 'Preserva tipo e valor primitivos'}
}
Assert ($original.NaoInterativo.IsPresent -eq $false -and $original.ContainsKey('Nullable')) 'Não altera entrada'
$empty=Decode (ConvertTo-ElevationParameterPayload -BoundParameters @{})
Assert ($empty.parameters.Count -eq 0) 'Mapa vazio válido'
MustReject $null
MustReject 'não é mapa'
MustReject @{'bad key'=1}
MustReject @{Bad={throw 'Não deve executar'}}
MustReject @{Bad=[pscustomobject]@{value=1}}
MustReject @{Bad=[long]1}
$duplicate=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal);$duplicate.Add('Csv','a');$duplicate.Add('csv','b');MustReject $duplicate
$many=@{};foreach($n in 0..64){$many['P'+$n]='x'};MustReject $many
MustReject @{Csv=('x'*1048576)}
MustReject @{Csv=('á'*524288)}
Write-Output "ELEVATION_PARAMETER_DATA_PASS checks=$checks; somente serializacao/binding de dados, sem UAC/processo/arquivo"
