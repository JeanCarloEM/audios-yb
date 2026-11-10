#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$p=Join-Path $repo 'consulta_busca.ps1'
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)
if($e.Count -or $ast.EndBlock.Statements.Count -ne 1 -or $ast.EndBlock.Statements[0] -isnot [Management.Automation.Language.FunctionDefinitionAst] -or $ast.EndBlock.Statements[0].Name -cne 'Get-CanonicalAudioSearchQuery'){throw 'Modulo deve definir somente uma funcao'}
if(@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)).Count){throw 'Modulo puro nao deve executar comandos'}
. $p
$original=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$t,[ref]$e)
$f=@($original.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-UrlInfo'},$true))
if($e.Count -or $f.Count -ne 1){throw 'Oracle canonico nao unico'}
. ([scriptblock]::Create($f[0].Extent.Text))
$cases=@(
 @{url='https://www.youtube.com/results?search_query=Artista+Faixa';query='Artista Faixa'},
 @{url='https://m.youtube.com/results?search_query=Jo%C3%A3o%20Gilberto+%26+voz&sp=x';query='João Gilberto & voz'},
 @{url='https://music.youtube.com/results?search_query=ABC%2B123%3D4';query='ABC+123=4'},
 @{url='https://youtube.com:443/results?search_query=abc#parte';query='abc'},
 @{url='https://youtube.com/results?sp=x&search_query=abc';query='abc'},
 @{url='https://youtube.com/results?SEARCH_QUERY=abc';query='abc'},
 @{url='https://youtube.com/results?search_query=a=b';query='a=b'},
 @{url='https://m.youtube.com/RESULTS?search_query=abc';query='abc'}
)
$n=0
foreach($case in $cases){
 $oracle=Get-UrlInfo $case.url
 if($oracle.tipo -cne 'busca' -or $oracle.query -cne $case.query){throw 'Expectativa literal diverge da origem canonica'}
 $out=@(Get-CanonicalAudioSearchQuery -SourceUrl $case.url)
 if($out.Count -ne 1 -or $out[0] -isnot [string] -or $out[0] -cne $case.query){throw 'Consulta canonica alterada'}
 $n++
}
$bad=@($null,123,'','/results?search_query=abc',
 'http://youtube.com/results?search_query=abc',
 'https://evil.example/results?search_query=abc',
 'https://youtube.com.evil.example/results?search_query=abc',
 'https://user:secret@youtube.com/results?search_query=abc',
 'https://youtube.com:444/results?search_query=abc',
 'https://youtube.com/watch?v=TestVideo01',
 'https://youtu.be/results?search_query=abc',
 'https://youtube.com/results?sp=x',
 'https://youtube.com/results?search_query=',
 'https://youtube.com/results?search_query=ab',
 ('https://youtube.com/results?search_query='+('a'*221)),
 'https://youtube.com/results?search_query=a%00b',
 'https://youtube.com/results?search_query=a%0Ab',
 'https://youtube.com/results?search_query=abc&search_query=def',
 'https://youtube.com/results?search_query=abc&SEARCH_QUERY=def',
 'https://youtube.com/results?search_query=abc&%73earch_query=def')
foreach($url in $bad){
 $caught=$false
 try{$null=Get-CanonicalAudioSearchQuery -SourceUrl $url}catch [ArgumentException]{$caught=$true}
 if(-not $caught){throw 'URL invalida/direta ou consulta ambigua aceita'}
 $n++
}
$caught=$false
try{$null=Get-CanonicalAudioSearchQuery}catch [ArgumentException]{$caught=$true}
if(-not $caught){throw 'Parametro omitido nao deve gerar prompt nem sucesso'}
$n++
$root=Join-Path $PSScriptRoot ('.runtime-consulta-busca-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
@{criteria=$n;module_sha256=(Get-FileHash $p).Hash;oracle_sha256=(Get-FileHash (Join-Path $repo 'baixar_audios_ytdlp.ps1')).Hash;scope='consulta pura; sem selecao/prova/CLI/rede/audio'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'prova.json') -Encoding utf8
'CONSULTA_BUSCA_PASS criterios'+$n+'; '+$root
