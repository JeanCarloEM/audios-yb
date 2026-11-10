#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$p=Join-Path $repo 'selecao_automatica.ps1'
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)
$names=@('Normal','Is-ExactArtistAudio','Select-AutoCandidate')
if($e.Count -or $a.EndBlock.Statements.Count -ne 3 -or @($a.EndBlock.Statements|Where-Object {$_ -isnot [Management.Automation.Language.FunctionDefinitionAst] -or $_.Name -cnotin $names}).Count){throw 'Modulo deve conter somente as tres funcoes canonicas'}
. $p
if((Normal 'AÇÃO & Voz 123') -cne 'acao voz 123' -or (Normal $null) -cne ''){throw 'Normalizacao literal divergente'}
$n=2
foreach($channel in @('Artista','Artista - Topic')){
 foreach($title in @('Faixa','Faixa audio','Artista - Faixa','Artista Faixa audio','Artista Faixa official audio')){
  if(-not (Is-ExactArtistAudio -Title $title -Channel $channel -Artist 'Artista' -Song 'Faixa')){throw 'Padrao canonico recusado'}
  $n++
 }
}
foreach($bad in @(@{title='Faixa';channel='Outro'},@{title='Faixa official audio';channel='Artista'},@{title='Artista Faixa live';channel='Artista'},@{title='Prefixo Artista Faixa';channel='Artista - Topic'})){
 if(Is-ExactArtistAudio -Title $bad.title -Channel $bad.channel -Artist 'Artista' -Song 'Faixa'){throw 'Correspondencia apenas parcial aceita'}
 $n++
}
if(-not (Is-ExactArtistAudio -Title 'Ártista — Faíxa' -Channel 'ÁRTISTA - Topic' -Artist 'Artista' -Song 'Faixa')){throw 'NFD/case/pontuacao divergiu'}
$n++
$exact=@{id='TestVideo01';titulo='Artista - Faixa';canal='Artista - Topic';pontuacao=1}
$other=@{id='TestVideo02';titulo='Artista - Faixa';canal='Outro';pontuacao=99999}
$r=Select-AutoCandidate -Items @($other,$exact) -Artist 'Artista' -Song 'Faixa'
if($null -eq $r -or $r.id -cne 'TestVideo01'){throw 'Score substituiu criterio exato'}
$n++
$second=@{id='TestVideo02';titulo='Faixa audio';canal='Artista'}
foreach($case in @(@{items=@()},@{items=@($other)},@{items=@($exact,$second)},@{items=@($exact,$exact)})){
 if($null -ne (Select-AutoCandidate -Items $case.items -Artist 'Artista' -Song 'Faixa')){throw 'Ausencia/ambiguidade foi escolhida arbitrariamente'}
 $n++
}
$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$t,[ref]$e)
if($e.Count -or @($a.FindAll({param($node)$node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -cin @('Normal','Is-ExactArtistAudio','Select-AutoCandidate')},$true)).Count){throw 'Definicoes duplicadas no principal'}
$root=Join-Path $PSScriptRoot ('.runtime-selecao-automatica-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
@{criteria=$n;helper_sha256=(Get-FileHash $p).Hash;main_sha256=(Get-FileHash (Join-Path $repo 'baixar_audios_ytdlp.ps1')).Hash;scope='mesmo algoritmo textual, nao aprovacao musical/vocal'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'prova.json') -Encoding utf8
'SELECAO_AUTOMATICA_PASS criterios'+$n+'; '+$root
