#requires -Version 7.0
$ErrorActionPreference='Stop'
# Regressao v2/v1 e fixture AAC real existentes; sem rede.
. (Join-Path $PSScriptRoot 'intencao_plano_tecnico.tests.ps1')
foreach($file in @('consulta_busca.ps1','selecao_automatica.ps1','selecao_busca.ps1')){. (Join-Path $repo $file)}
# Literal do contrato v3; metadados/expectativas nao derivados do construtor.
$searchUrl='https://www.youtube.com/results?search_query=AC%2FDC+iTunes+DJ'
$searchProof=@{versao=[int]3;tipo='selecao_tecnica';video_id='TestVideo01';criterio='busca_exata_canal_artista_unica';metadados=@{id='TestVideo01';title='AC/DC iTunes DJ official audio';channel='AC/DC - Topic'};referencia=@{artista='AC/DC';musica='iTunes DJ';url_original=$searchUrl;consulta='AC/DC iTunes DJ'};candidatos=@(@{id='TestVideo01';titulo='AC/DC - iTunes DJ';canal='AC/DC - Topic'})}
function New-SearchPlanFixture([string]$Name,[object]$Selection=$searchProof,[string]$RecordUrl=$searchUrl){
 $f=New-PlanFixture -Name $Name
 $d=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($f.Args.Path))
 $d.registro.Remove('aprovacao_musical')
 $d.registro.url_original=$RecordUrl
 $text=[string]::Join([char]31,@($d.registro.ordem.Trim(),$d.registro.artista.Trim(),$d.registro.musica.Trim(),$RecordUrl.Trim()))
 $d.registro.chave=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
 $d.registro.selecao_tecnica=$Selection
 # Legado VALIDO junto dos negativos: a prova tecnica presente deve bloquear fallback.
 $d.registro.aprovacao_musical=$proof
 $body=[Text.UTF8Encoding]::new($false).GetBytes(($d|ConvertTo-Json -Depth 25))
 [IO.File]::WriteAllBytes($f.Args.Path,$body)
 $f.Args.ExpectedSha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($body)).ToLowerInvariant()
 return $f
}
function Copy-SearchProof {$searchProof|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable}
$fixtures=@()
$f=New-SearchPlanFixture 'search-valid';$fixtures+=,$f
Assert-PlanReject $f.Args 'Selecao' $false
$params=$f.Args;$p=Get-PublicationRecoveryPlan @params -AllowTechnicalSelection
if($p.Status -cne 'plano_validado_sem_efeitos' -or $p.Action -cne 'publish' -or $p.Selection.Kind -cne 'technical_v3' -or $p.Selection.Field -cne 'selecao_tecnica' -or $null -ne $p.MusicalApproval){throw 'Contrato v3/plano incorreto'}
if($p.Selection.Proof.versao -ne 3 -or $p.Selection.Proof.referencia.url_original -cne $searchUrl -or $p.Selection.Proof.metadados.title -cne $searchProof.metadados.title -or $p.Selection.Proof.ContainsKey('sem_vocais_conferido')){throw 'Prova v3 perdida/flags fabricadas'}
$p.Selection.Proof.referencia.artista='mutado'
if($p.Data.registro.selecao_tecnica.referencia.artista -cne 'AC/DC' -or $searchProof.referencia.artista -cne 'AC/DC'){throw 'Alias da prova'}
$n=3
$bad=Copy-SearchProof;$bad.referencia.consulta='forjada'
$b=New-SearchPlanFixture 'search-query' $bad;$fixtures+=,$b;Assert-PlanReject $b.Args 'Selecao';$n++
$bad=Copy-SearchProof;$bad.versao='3'
$b=New-SearchPlanFixture 'search-version' $bad;$fixtures+=,$b;Assert-PlanReject $b.Args 'Selecao';$n++
$bad=Copy-SearchProof;$bad.metadados.id='OtherId0123'
$b=New-SearchPlanFixture 'search-id' $bad;$fixtures+=,$b;Assert-PlanReject $b.Args 'Selecao';$n++
$bad=Copy-SearchProof;$bad.candidatos+=@{id='OtherId0123';titulo='AC/DC - iTunes DJ';canal='AC/DC - Topic'}
$b=New-SearchPlanFixture 'search-ambiguous' $bad;$fixtures+=,$b;Assert-PlanReject $b.Args 'Selecao';$n++
$b=New-SearchPlanFixture -Name 'search-record-url' -RecordUrl 'https://www.youtube.com/results?search_query=AC%2FDC%20iTunes%20DJ';$fixtures+=,$b
Assert-PlanReject $b.Args 'Selecao';$n++
$kept=$script:Evidencias
try{$script:Evidencias=@{};Assert-PlanReject $f.Args 'Procedencia'}finally{$script:Evidencias=$kept};$n++
$wrong=$f.Args.Clone();$wrong.ExpectedSha256=('0'*64);Assert-PlanReject $wrong 'Hash';$n++
foreach($x in $fixtures){
 if((Get-FileHash -LiteralPath $x.Ready).Hash.ToLowerInvariant() -cne $sourceHash -or (Test-Path -LiteralPath $x.Target) -or (Test-Path -LiteralPath (Join-Path $x.Args.Control 'estado.json')) -or (Get-FileHash -LiteralPath $x.Args.Path).Hash.ToLowerInvariant() -cne $x.Args.ExpectedSha256){throw 'Plano teve efeitos'}
}
$n++
$proofPath=Join-Path $work 'prova-busca.json'
@{criteria=$n;helper_sha256=(Get-FileHash (Join-Path $repo 'publicacao_pendente.ps1')).Hash;scope='plano v3 opt-in com AAC real; sem consumidor/retomada/CLI/rede';legacy_regression='intencao_plano_tecnico.tests.ps1'}|ConvertTo-Json|Set-Content -LiteralPath $proofPath -Encoding utf8
'RECOVERY_PLAN_SEARCH_PASS criterios'+$n+'; '+$proofPath
