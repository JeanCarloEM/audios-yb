#requires -Version 7.0
# Expectativas independentes: RCF.md 7.1 e contrato explicito do helper; nao derivadas da implementacao.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo=Split-Path $PSScriptRoot -Parent
$tokens=$null;$errors=$null
$path=Join-Path $repo 'nomeacao_editorial.ps1'
$null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Helper com sintaxe invalida'}
. $path
$cases=ConvertFrom-Json -AsHashtable -InputObject @'
[{"name":"padrao","params":{"Autor":"Autor","Track":"2","Titulo":"Faixa"},"parts":["Autor","2","Faixa"],"legacy":false},{"name":"somente_titulo","params":{"Titulo":"iTunes é DJ"},"parts":["iTunes é DJ"],"legacy":false},{"name":"sem_titulo","params":{"Autor":"AC/DC","Track":"3"},"parts":[],"legacy":true},{"name":"titulo_espacos","params":{"Titulo":" \t "},"parts":[],"legacy":true},{"name":"autor_espacos","params":{"Autor":" \t ","Titulo":"Faixa"},"parts":["Faixa"],"legacy":false},{"name":"track_espacos","params":{"Track":" \t ","Titulo":"Faixa"},"parts":["Faixa"],"legacy":false},{"name":"zeros_sem_largura","params":{"Track":"001","Titulo":"Faixa"},"parts":["1","Faixa"],"legacy":false},{"name":"padding_explicito","params":{"Track":"001","Titulo":"Faixa","LarguraTrack":3},"parts":["001","Faixa"],"legacy":false},{"name":"largura_null","params":{"Track":"001","Titulo":"Faixa","LarguraTrack":null},"parts":["1","Faixa"],"legacy":false},{"name":"numero_nao_truncado","params":{"Track":"1234","Titulo":"Faixa","LarguraTrack":2},"parts":["1234","Faixa"],"legacy":false},{"name":"zero","params":{"Track":"000","Titulo":"Faixa"},"parts":["0","Faixa"],"legacy":false},{"name":"maior_int64","params":{"Track":"18446744073709551616","Titulo":"Faixa"},"parts":["18446744073709551616","Faixa"],"legacy":false},{"name":"limite_padding","params":{"Track":"1","Titulo":"Faixa","LarguraTrack":145},"parts":["0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001","Faixa"],"legacy":false},{"name":"numero_extenso","params":{"Track":"99999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999999","Titulo":"Faixa"},"parts":[],"legacy":true},{"name":"track_invalido_1.5","params":{"Track":"1.5","Titulo":"Faixa"},"parts":[],"legacy":true},{"name":"track_invalido_-1","params":{"Track":"-1","Titulo":"Faixa"},"parts":[],"legacy":true},{"name":"track_invalido_١","params":{"Track":"١","Titulo":"Faixa"},"parts":[],"legacy":true},{"name":"track_invalido_1e2","params":{"Track":"1e2","Titulo":"Faixa"},"parts":[],"legacy":true},{"name":"grafias_preservadas","params":{"Autor":" AC/DC \t DJ ","Track":" 03 ","Titulo":" iTunes   é \t DJ "},"parts":["AC/DC DJ","3","iTunes é DJ"],"legacy":false},{"name":"largura_invalida_0","params":{"Titulo":"Faixa","LarguraTrack":0},"throws":true},{"name":"largura_invalida_-1","params":{"Titulo":"Faixa","LarguraTrack":-1},"throws":true},{"name":"largura_invalida_146","params":{"Titulo":"Faixa","LarguraTrack":146},"throws":true}]
'@
$failed=0
foreach($case in $cases){
 try{
  $params=$case.params
  if($case.ContainsKey('throws')){
   $caught=$false
   try{$null=Get-MusicalNameComponents @params}catch{
    $e=$_.Exception;while($null -ne $e.InnerException){$e=$e.InnerException}
    if($e -isnot [ArgumentOutOfRangeException]){throw}
    $caught=$true
   }
   if(-not $caught){throw 'Largura invalida aceita'}
  }else{
   $result=Get-MusicalNameComponents @params
   if($result -isnot [hashtable] -or $result.usar_legado -isnot [bool] -or $result.componentes -isnot [string[]] -or $result.motivo -isnot [string]){throw 'Tipos de retorno invalidos'}
   if($result.usar_legado -ne $case.legacy -or $result.componentes.Count -ne $case.parts.Count){throw 'Fallback/componentes divergentes'}
   for($i=0;$i -lt $case.parts.Count;$i++){if(-not [string]::Equals($result.componentes[$i],$case.parts[$i],[StringComparison]::Ordinal)){throw 'Componente divergente'}}
   if($case.legacy -and [string]::IsNullOrWhiteSpace($result.motivo)){throw 'Fallback sem motivo'}
  }
  Write-Output ('PASS '+$case.name)
 }catch{$failed++;Write-Output ('FAIL '+$case.name+': '+$_.Exception.Message)}
}
if($failed){throw ('EDITORIAL_COMPONENTS_FAILURES='+$failed)}
Write-Output ('EDITORIAL_COMPONENTS_BEHAVIOR_PASS cases='+$cases.Count)
