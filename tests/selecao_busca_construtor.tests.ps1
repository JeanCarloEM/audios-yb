#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'consulta_busca.ps1')
. (Join-Path $repo 'selecao_automatica.ps1')
$p=Join-Path $repo 'selecao_busca.ps1'
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)
if($e.Count -or $a.EndBlock.Statements.Count -ne 2 -or $a.EndBlock.Statements[0] -isnot [Management.Automation.Language.FunctionDefinitionAst] -or $a.EndBlock.Statements[1] -isnot [Management.Automation.Language.FunctionDefinitionAst] -or $a.EndBlock.Statements[0].Name -cne 'New-AutoSearchAudioSelectionProof' -or $a.EndBlock.Statements[1].Name -cne 'Resolve-AutoSearchAudioSelectionProof'){throw 'Modulo deve conter somente construtor e resolver puros'}
. $p
$id='AbCdEf012_-';$url='https://www.youtube.com/results?search_query=Artista+Faixa'
$info=@{id=$id;title='Artista Faixa official audio';channel='Artista - Topic';extra='nao copiar'}
$exact=@{id=$id;titulo='Artista - Faixa';canal='Artista - Topic';pontuacao=1}
$other=@{id='OtherId0123';titulo='Artista - Faixa';canal='Outro';pontuacao=99999}
$items=@($exact,$other)
$parameters=@{VideoId=$id;SourceUrl=$url;Artist='Artista';Song='Faixa';Candidates=$items;Info=$info}
# Expectativa literal do contrato v3, independente da implementacao.
$expected=@{versao=[int]3;tipo='selecao_tecnica';video_id=$id;criterio='busca_exata_canal_artista_unica';metadados=@{id=$id;title='Artista Faixa official audio';channel='Artista - Topic'};referencia=@{artista='Artista';musica='Faixa';url_original=$url;consulta='Artista Faixa'};candidatos=@(@{id=$id;titulo='Artista - Faixa';canal='Artista - Topic'},@{id='OtherId0123';titulo='Artista - Faixa';canal='Outro'})}
function Assert-Literal($actual,$literal){
 if($literal -is [Collections.IDictionary]){
  if($actual -isnot [Collections.IDictionary] -or $actual.Count -ne $literal.Count){throw 'Mapa/contagem divergiu'}
  foreach($k in $literal.Keys){
   if(@($actual.Keys|Where-Object {[string]::Equals([string]$_,[string]$k,[StringComparison]::Ordinal)}).Count -ne 1){throw 'Chave literal ausente/case incorreto'}
   Assert-Literal $actual[$k] $literal[$k]
  }
 }elseif($literal -is [Collections.IList]){
  if($actual -isnot [Collections.IList] -or $actual.Count -ne $literal.Count){throw 'Lista divergiu'}
  for($i=0;$i -lt $literal.Count;$i++){Assert-Literal $actual[$i] $literal[$i]}
 }elseif($literal -is [string]){
  if($actual -isnot [string] -or $actual -cne $literal){throw 'String literal divergiu'}
 }elseif($actual -isnot [int] -or $actual -ne $literal){throw 'Tipo/numero literal divergiu'}
}
$all=@(New-AutoSearchAudioSelectionProof @parameters)
if($all.Count -ne 1 -or $all[0] -isnot [hashtable]){throw 'Retorno nao unico'}
$r=$all[0];Assert-Literal $r $expected
$r.metadados.title='Mutado';$r.candidatos[0].titulo='Mutado'
if($info.title -cne 'Artista Faixa official audio' -or $items[0].titulo -cne 'Artista - Faixa'){throw 'Alias ou mutacao de entrada'}
$n=2
$wrongId=$info.Clone();$wrongId.id=$id.ToLowerInvariant()
$wrongChannel=$info.Clone();$wrongChannel.channel='Outro'
$wrongTitle=$info.Clone();$wrongTitle.title='Entrevista'
$numericTitle=$info.Clone();$numericTitle.title=123
$aliasInfo=@{ID=$id;title='Artista Faixa';channel='Artista'}
$badCandidate=@{ID=$id;titulo='Artista - Faixa';canal='Artista'}
$invalidId=@{id='errado';titulo='Artista - Faixa';canal='Artista'}
$second=@{id='OtherId0123';titulo='Faixa audio';canal='Artista'}
$bad=@(
 @{VideoId=$id.ToLowerInvariant()},@{VideoId=123},@{Info=$wrongId},@{Info=$wrongChannel},@{Info=$wrongTitle},@{Info=$numericTitle},@{Info=$aliasInfo},@{Info=$null},@{Info='texto'},
 @{Candidates=@()},@{Candidates=@($other)},@{Candidates=@($exact,$second)},@{Candidates=@($exact,$exact)},@{Candidates=@($badCandidate)},@{Candidates=@($invalidId)},@{Candidates=$exact},@{Candidates='texto'},
 @{SourceUrl='https://www.youtube.com/watch?v=AbCdEf012_-'},@{SourceUrl='https://www.youtube.com/results?search_query=Outro+Titulo'},@{SourceUrl=$null},@{Artist=''},@{Song=' '},@{Artist=123},@{Song=$null}
)
$bothInfo=[hashtable]::new([StringComparer]::Ordinal);foreach($k in $info.Keys){$bothInfo[$k]=$info[$k]};$bothInfo['ID']=$id
$bothCandidate=[hashtable]::new([StringComparer]::Ordinal);foreach($k in $exact.Keys){$bothCandidate[$k]=$exact[$k]};$bothCandidate['ID']=$id
$selectedOther=@{id='OtherId0123';titulo='Artista - Faixa';canal='Artista - Topic'}
$bad+=@(@{Candidates=@($selectedOther)},@{Info=$bothInfo},@{Candidates=@($bothCandidate)},@{SourceUrl='https://www.youtube.com/results?search_query=+++';Artist='&';Song='!';Info=@{id=$id;title='!!!';channel='---'};Candidates=@(@{id=$id;titulo='!!!';canal='---'})})
foreach($changes in $bad){
 $argsCase=$parameters.Clone();foreach($k in $changes.Keys){$argsCase[$k]=$changes[$k]}
 $caught=$false
 try{$null=New-AutoSearchAudioSelectionProof @argsCase}catch [ArgumentException]{$caught=$true}
 if(-not $caught){throw 'Entrada invalida/ambigua aceita'}
 $n++
}
$caught=$false;try{$null=New-AutoSearchAudioSelectionProof}catch [ArgumentException]{$caught=$true}
if(-not $caught){throw 'Omissao gerou sucesso/prompt'}
$n++
$ps=[powershell]::Create()
try{
 $setup='$ErrorActionPreference=''Stop'''+[Environment]::NewLine+[IO.File]::ReadAllText($p)
 $null=$ps.AddScript($setup).AddStatement().AddCommand('New-AutoSearchAudioSelectionProof').AddParameters($parameters)
 try{$null=$ps.Invoke()}catch{if($ps.Streams.Error.Count -eq 0){throw}}
 if(-not $ps.HadErrors -or $ps.Streams.Error.Count -ne 1 -or $ps.Streams.Error[0].FullyQualifiedErrorId -cne 'CommandNotFoundException' -or -not $ps.Streams.Error[0].Exception.Message.Contains('Get-CanonicalAudioSearchQuery',[StringComparison]::Ordinal)){throw 'Dependencia ausente foi mascarada'}
}finally{$ps.Dispose()}
$n++
$root=Join-Path $PSScriptRoot ('.runtime-selecao-busca-construtor-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
@{criteria=$n;module_sha256=(Get-FileHash $p).Hash;schema_version=3;scope='construtor puro com parser e seletor reais; nao bridge/CLI/verdade musical/vocal'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'prova.json') -Encoding utf8
'BUSCA_CONSTRUTOR_PASS criterios'+$n+'; '+$root
