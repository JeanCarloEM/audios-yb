#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'consulta_busca.ps1')
. (Join-Path $repo 'selecao_automatica.ps1')
$p=Join-Path $repo 'selecao_busca.ps1'
. $p
# Importa somente a assercao conhecida; nao executa a suite do construtor.
$t=$null;$e=$null
$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'selecao_busca_construtor.tests.ps1'),[ref]$t,[ref]$e)
$helper=@($a.FindAll({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq 'Assert-Literal'},$false))
if($e.Count -or $helper.Count -ne 1){throw 'Assercao literal ausente'}
. ([scriptblock]::Create($helper[0].Extent.Text))
$id='AbCdEf012_-';$url='https://www.youtube.com/results?search_query=Artista+Faixa'
# Contrato v3 literal aprovado; nao derivado do construtor nem do resolver.
$literal=@{versao=[int]3;tipo='selecao_tecnica';video_id=$id;criterio='busca_exata_canal_artista_unica';metadados=@{id=$id;title='Artista Faixa official audio';channel='Artista - Topic'};referencia=@{artista='Artista';musica='Faixa';url_original=$url;consulta='Artista Faixa'};candidatos=@(@{id=$id;titulo='Artista - Faixa';canal='Artista - Topic'},@{id='OtherId0123';titulo='Artista - Faixa';canal='Outro'})}
function Copy-Proof { $literal|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable }
function Context($proof){@{VideoId=$id;SourceUrl=$url;Artist='Artista';Song='Faixa';StoredProof=$proof}}
$n=0
$argsValid=Context $literal
$output=@(Resolve-AutoSearchAudioSelectionProof @argsValid)
if($output.Count -ne 1 -or $output[0] -isnot [hashtable]){throw 'Saida valida deve ser Hashtable unica'}
$r=$output[0];Assert-Literal $r $literal;$n++
foreach($pair in @(@($r,$literal),@($r.metadados,$literal.metadados),@($r.referencia,$literal.referencia),@($r.candidatos,$literal.candidatos),@($r.candidatos[0],$literal.candidatos[0]))){if([object]::ReferenceEquals($pair[0],$pair[1])){throw 'Alias indevido'}}
$r.metadados.title='alterado';$r.candidatos[0].titulo='alterado'
if($literal.metadados.title -cne 'Artista Faixa official audio' -or $literal.candidatos[0].titulo -cne 'Artista - Faixa'){throw 'Mutacao da entrada'}
$n++
$long=Copy-Proof;$long.versao=[long]3;$params=Context $long
$r=Resolve-AutoSearchAudioSelectionProof @params;Assert-Literal $r $literal;$n++
$ordered=[ordered]@{};foreach($k in $literal.Keys){$ordered[$k]=$literal[$k]}
$params=Context $ordered;Assert-Literal (Resolve-AutoSearchAudioSelectionProof @params) $literal;$n++
if($null -ne (Resolve-AutoSearchAudioSelectionProof)){throw 'Defaults aceitos/prompt'};$n++
$cases=@(
 {param($s)$s.versao='3'}, {param($s)$s.versao=[double]3}, {param($s)$s.versao=$true},
 {param($s)$s.versao=1}, {param($s)$s.versao=2}, {param($s)$s.tipo='Selecao_tecnica'},
 {param($s)$s.criterio='url_direta_id_literal'}, {param($s)$s.video_id='aBCdEf012_-'},
 {param($s)$s.metadados.id='OtherId0123'}, {param($s)$s.metadados.title='Outro titulo'},
 {param($s)$s.metadados.channel='Outro canal'}, {param($s)$s.referencia.consulta='Artista Faixa adulterada'},
 {param($s)$s.referencia.artista='Outro'}, {param($s)$s.referencia.musica='Outra'},
 {param($s)$s.referencia.url_original='https://www.youtube.com/results?search_query=Artista%20Faixa'},
 {param($s)$s.candidatos=@()}, {param($s)$s.candidatos=@('invalido')},
 {param($s)$s.candidatos+=@{id='ThirdId0123';titulo='Artista - Faixa';canal='Artista - Topic'}},
 {param($s)$s.candidatos[0].id='OtherId0123'}, {param($s)$s.candidatos[0].titulo='Outra'},
 {param($s)$s.candidatos[0].canal=$null}, {param($s)$s.metadados.title=42}
)
foreach($mut in $cases){$s=Copy-Proof;&$mut $s;$params=Context $s;if($null -ne (Resolve-AutoSearchAudioSelectionProof @params)){throw ('Caso invalido aceito: '+$mut)};$n++}
# Chaves extras, ausentes e case incorreto em cada nivel fechado.
foreach($level in @('top','metadados','referencia','candidate')){
 foreach($variant in @('extra','missing','case')){
  $s=Copy-Proof;$map=switch($level){top{$s}metadados{$s.metadados}referencia{$s.referencia}candidate{$s.candidatos[0]}}
  $key=switch($level){top{'versao'}metadados{'id'}referencia{'artista'}candidate{'id'}}
  if($variant -eq 'extra'){$map['aprovacao_humana']=$true}
  elseif($variant -eq 'missing'){$map.Remove($key)}
  else{
   $exact=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
   foreach($k in $map.Keys){$exact.Add($(if($k -ceq $key){$k.ToUpperInvariant()}else{$k}),$map[$k])}
   switch($level){top{$s=$exact}metadados{$s.metadados=$exact}referencia{$s.referencia=$exact}candidate{$s.candidatos[0]=$exact}}
  }
  $params=Context $s;if($null -ne (Resolve-AutoSearchAudioSelectionProof @params)){throw ('Forma aceita: '+$level+'/'+$variant)};$n++
 }
}
foreach($k in @('VideoId','Artist','Song','SourceUrl')){
 $params=Context (Copy-Proof)
 $params[$k]=switch($k){VideoId{'OtherId0123'}Artist{'Outro'}Song{'Outra'}SourceUrl{'https://www.youtube.com/results?search_query=Artista%20Faixa'}}
 if($null -ne (Resolve-AutoSearchAudioSelectionProof @params)){throw ('Contexto divergente aceito: '+$k)};$n++
}
$params=Context (Copy-Proof);$params.VideoId=42
if($null -ne (Resolve-AutoSearchAudioSelectionProof @params)){throw 'Contexto nao string aceito'};$n++
# Dependencia ausente deve propagar, nunca virar null ou ArgumentException.
$ps=[powershell]::Create()
try{
 $setup='$ErrorActionPreference=''Stop'''+[Environment]::NewLine+[IO.File]::ReadAllText($p)
 $null=$ps.AddScript($setup).AddStatement().AddCommand('Resolve-AutoSearchAudioSelectionProof').AddParameters($argsValid)
 try{$null=$ps.Invoke()}catch{if($ps.Streams.Error.Count -eq 0){throw}}
 if(-not $ps.HadErrors -or $ps.Streams.Error.Count -ne 1 -or $ps.Streams.Error[0].FullyQualifiedErrorId -cne 'CommandNotFoundException' -or -not $ps.Streams.Error[0].Exception.Message.Contains('Get-CanonicalAudioSearchQuery',[StringComparison]::Ordinal)){throw 'Dependencia mascarada'}
}finally{$ps.Dispose()}
$n++
$root=Join-Path $PSScriptRoot ('.runtime-selecao-busca-releitura-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
@{criteria=$n;module_sha256=(Get-FileHash $p).Hash;schema_version=3;scope='releitura estrita; nao CLI/bridge/verdade musical/vocal'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'prova.json') -Encoding utf8
'BUSCA_RELEITURA_PASS criterios'+$n+'; '+$root
