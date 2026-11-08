#requires -Version 7.0
param([ValidateSet('legado','titulo','mapeado','sem_mapa','coluna_ausente')][string]$Case='mapeado')
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo=Split-Path -Parent $PSScriptRoot
$producer=Join-Path $repo 'tests/publicacao_produtor_cli.tests.ps1'
if((Get-FileHash -LiteralPath $producer -Algorithm SHA256).Hash -cne '59502B942A39451CF7DBD90785D1F809A86618142CB261D89102DAEF6D903F24'){throw 'Template produtor mudou'}
function Quote-NamingLiteral([string]$Text){return "'"+$Text.Replace("'","''")+"'"}
function Replace-NamingLiteral([string]$Text,[string]$Before,[string]$After){
 if(([regex]::Matches($Text,[regex]::Escape($Before))).Count -ne 1){throw ('Ancora de nomeacao ausente/ambigua: '+$Before)}
 return $Text.Replace($Before,$After)
}
$fixtures=@{
 legado=@{Name='legado';Args=@{};ExpectedName='1 - Artista - Faixa [TestVideo01].mp3';Applied='Legado';Pending=$false}
 titulo=@{Name='titulo';Args=@{ModeloNome='Musical';ColunaTitulo='Musica'};ExpectedName='Faixa [TestVideo01].mp3';Applied='Musical';Pending=$false}
 mapeado=@{Name='mapeado';Args=@{ModeloNome='Musical';ColunaAutor='Artista';ColunaTrack='Ordem';ColunaTitulo='Musica';LarguraTrack=3};ExpectedName='Artista - 001 - Faixa [TestVideo01].mp3';Applied='Musical';Pending=$false}
 sem_mapa=@{Name='sem_mapa';Args=@{ModeloNome='Musical'};ExpectedName='1 - Artista - Faixa [TestVideo01].mp3';Applied='Legado';Pending=$true}
 coluna_ausente=@{Name='coluna_ausente';Args=@{ModeloNome='Musical';ColunaAutor='Compositor';ColunaTitulo='Musica'};ExpectedName='1 - Artista - Faixa [TestVideo01].mp3';Applied='Legado';Pending=$true}
}
$namingCase=$fixtures[$Case]
$cloneText=[IO.File]::ReadAllText($producer)
$cloneText=Replace-NamingLiteral $cloneText '$repo=Split-Path -Parent $PSScriptRoot' ('$repo='+(Quote-NamingLiteral $repo))
$cloneText=Replace-NamingLiteral $cloneText '$work=Join-Path $PSScriptRoot (''.runtime-producer-cli-''+[guid]::NewGuid().ToString(''N''))' '$work=Join-Path (Join-Path $repo ''tests'') (''.runtime-producer-cli-''+[guid]::NewGuid().ToString(''N''))'
$flag='$publicationFaultRequested=($env:AUDIOS_YB_PUBLICATION_TEST_MODE -eq ''fault'')'
$definitions='$namingCase=ConvertFrom-Json -AsHashtable -InputObject '+(Quote-NamingLiteral ($namingCase|ConvertTo-Json -Compress -Depth 6))+[Environment]::NewLine+'$namingArgs=$namingCase.Args'
$oldCopy='''referencia_publicacao.ps1''))'
$newCopy='''referencia_publicacao.ps1'',''nomeacao_editorial.ps1'',''mapeamento_nomeacao.ps1''))'
$oldCall='  else{ & $scriptPath -NaoInterativo:($mode -eq ''nao_interativo'') -Interativo:($mode -ne ''nao_interativo'') }'
$newCall='  else{ & $scriptPath -NaoInterativo:($mode -eq ''nao_interativo'') -Interativo:($mode -ne ''nao_interativo'') @namingArgs }'
$injections=@(
 ('$source=Replace-ProducerTestLiteral $source '+(Quote-NamingLiteral $flag)+' '+(Quote-NamingLiteral ($flag+[Environment]::NewLine+$definitions)))
 ('$source=Replace-ProducerTestLiteral $source '+(Quote-NamingLiteral $oldCopy)+' '+(Quote-NamingLiteral $newCopy))
 ('$source=Replace-ProducerTestLiteral $source '+(Quote-NamingLiteral $oldCall)+' '+(Quote-NamingLiteral $newCall))
)
$marker='$extraMocks=@'''
$cloneText=Replace-NamingLiteral $cloneText ' & $scriptPath -NaoInterativo' ' & $scriptPath -NaoInterativo -ModeloNome Musical -ColunaAutor Artista -ColunaTrack Ordem -ColunaTitulo Musica -LarguraTrack 2'
$cloneText=Replace-NamingLiteral $cloneText $marker (($injections -join [Environment]::NewLine)+[Environment]::NewLine+$marker)
$assertions=@'
 if(-not [string]::Equals([string]$journal.Data.arquivo,[string]$namingCase.ExpectedName,[StringComparison]::Ordinal)){throw 'Nome do journal incorreto'}
 $key=$journal.Data.registro.chave
 $finishedRecord=$finished.registros[$key]
 if($finishedRecord.resultado -cne 'existente' -or -not [string]::Equals([string]$finishedRecord.arquivo,[string]$namingCase.ExpectedName,[StringComparison]::Ordinal) -or -not [string]::Equals([string]$finished.videos.TestVideo01.arquivo,[string]$namingCase.ExpectedName,[StringComparison]::Ordinal)){throw 'Reuso mudou nome ou resultado'}
 foreach($metadata in @($journal.Data.registro.nomeacao,$finishedRecord.nomeacao)){
  if(-not [string]::Equals([string]$metadata.modelo_aplicado,[string]$namingCase.Applied,[StringComparison]::Ordinal) -or $metadata.pendente_editorial -isnot [bool] -or $metadata.pendente_editorial -ne $namingCase.Pending){throw 'Modelo/pendencia editorial divergentes'}
  foreach($role in @('autor','track','titulo')){
   $parameter=@{autor='ColunaAutor';track='ColunaTrack';titulo='ColunaTitulo'}[$role]
   $declared=if($namingCase.Args.ContainsKey($parameter)){[string]$namingCase.Args[$parameter]}else{''}
   if(-not [string]::Equals([string]$metadata.colunas[$role],$declared,[StringComparison]::Ordinal)){throw 'Declaracao de coluna perdida'}
  }
 }
 $finalAfter=@(Get-ChildItem -LiteralPath $dest -File | Where-Object {$_.Extension -in @('.mp3','.m4a')})
 if($finalAfter.Count -ne 1 -or -not [string]::Equals($finalAfter[0].Name,[string]$namingCase.ExpectedName,[StringComparison]::Ordinal)){throw 'Arquivo renomeado ou duplicado'}
 Write-Output ('NAMING_CLI_CASE_PASS: '+$namingCase.Name)
'@
$oldPass=' Write-Output (''PUBLICATION_PRODUCER_CASE_PASS: fault=''+$publicationFaultRequested)'
$cloneText=Replace-NamingLiteral $cloneText $oldPass ($assertions+[Environment]::NewLine+$oldPass)
$cloneText=Replace-NamingLiteral $cloneText 'foreach($testMode in @(''normal'',''fault'')){' 'foreach($testMode in @(''normal'')){'
$oldCheck='-not $r.Stdout.Contains(''PUBLICATION_PRODUCER_CASE_PASS'')'
$newCheck='(-not $r.Stdout.Contains(''PUBLICATION_PRODUCER_CASE_PASS'') -or -not $r.Stdout.Contains(''NAMING_CLI_CASE_PASS:''))'
$cloneText=Replace-NamingLiteral $cloneText $oldCheck $newCheck
$cloneText=Replace-NamingLiteral $cloneText '''PUBLICATION_PRODUCER_CLI_PASS: normal e IO real apos Move; checkpoint antes do Move; sem transporte extra; Windows''' '''NAMING_PRODUCER_NORMAL_PASS'''
$t=$null;$e=$null
$null=[Management.Automation.Language.Parser]::ParseInput($cloneText,[ref]$t,[ref]$e)
if($e.Count){$e|ForEach-Object {$_.Message};throw 'Clone de nomeacao invalido'}
$work=Join-Path $PSScriptRoot ('.runtime-nomeacao-cli-'+$Case+'-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$clone=Join-Path $work 'produtor_nomeacao.ps1'
[IO.File]::WriteAllText($clone,$cloneText,[Text.UTF8Encoding]::new($false))
. (Join-Path $repo 'tests/processo_capturado.ps1')
$r=Invoke-CapturedTestProcess -Program ([Environment]::ProcessPath) -Arguments @('-NoLogo','-NoProfile','-NonInteractive','-File',$clone) -TimeoutMs 210000
$log=Join-Path $work 'case.log'
[IO.File]::WriteAllText($log,($r.Stdout+[Environment]::NewLine+$r.Stderr),[Text.UTF8Encoding]::new($false))
if($r.ExitCode -ne 0 -or -not $r.Stdout.Contains('NAMING_PRODUCER_NORMAL_PASS')){throw ('Nomeacao CLI falhou: '+$log)}
Write-Output ('NAMING_CLI_E2E_PASS: '+$Case+'; publicacao+journal; reuso offline; CSV e audio preservados; transporte simulado; log='+$log)
