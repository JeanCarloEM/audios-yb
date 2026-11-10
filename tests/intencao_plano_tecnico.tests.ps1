$ErrorActionPreference='Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSScriptRoot)
. ./tests/intencao_plano.tests.ps1
. ./selecao_tecnica.ps1
$technical=@{versao=[int]2;tipo='selecao_tecnica';video_id='TestVideo01';criterio='url_direta_id_literal';metadados=@{id='TestVideo01';title='Entrevista com voz'};referencia=@{artista='AC/DC';musica='iTunes DJ'}}
function New-TechnicalPlanFixture([string]$Name,[object]$Technical=$technical,[switch]$KeepLegacy,[switch]$WrongCase){
 $f=New-PlanFixture -Name $Name
 $d=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($f.Args.Path))
 if(-not $KeepLegacy){$d.registro.Remove('aprovacao_musical')}
 if($WrongCase){$d.registro.Selecao_tecnica=$Technical}else{$d.registro.selecao_tecnica=$Technical}
 $body=[Text.UTF8Encoding]::new($false).GetBytes(($d|ConvertTo-Json -Depth 25))
 $h=[Security.Cryptography.SHA256]::Create()
 try{$hash=[BitConverter]::ToString($h.ComputeHash($body)).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
 [IO.File]::WriteAllBytes($f.Args.Path,$body)
 $f.Args.ExpectedSha256=$hash
 return $f
}
function Assert-PlanReject([hashtable]$Arguments,[string]$Message,[bool]$Allow=$true){
 $caught=$false
 try{$null=Get-PublicationRecoveryPlan @Arguments -AllowTechnicalSelection:$Allow}
 catch [IO.InvalidDataException]{if($_.Exception.Message.IndexOf($Message,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw};$caught=$true}
 if(-not $caught){throw ('Negativo aceito: '+$Message)}
}
$f=New-TechnicalPlanFixture -Name 'technical'
Assert-PlanReject $f.Args 'Selecao' $false
$arguments=$f.Args
$p=Get-PublicationRecoveryPlan @arguments -AllowTechnicalSelection
if($p.Status -cne 'plano_validado_sem_efeitos' -or $p.Action -cne 'publish' -or $p.Selection.Kind -cne 'technical_v2' -or $p.Selection.Field -cne 'selecao_tecnica' -or $null -ne $p.MusicalApproval -or $p.Selection.Proof.metadados.title -cne 'Entrevista com voz' -or $p.Selection.Proof.ContainsKey('sem_vocais_conferido')){throw 'Plano tecnico misturou contratos'}
$p.Selection.Proof.metadados.title='Mutado'
if($p.Data.registro.selecao_tecnica.metadados.title -cne 'Entrevista com voz' -or $technical.metadados.title -cne 'Entrevista com voz'){throw 'Alias tecnico'}
$legacyArgs=$main.Args
$legacy=Get-PublicationRecoveryPlan @legacyArgs
if($legacy.Selection.Kind -cne 'legacy_human_v1' -or $legacy.Selection.Field -cne 'aprovacao_musical' -or -not $legacy.MusicalApproval.sem_vocais_conferido){throw 'Legado alterado'}
$wrongVersion=$technical.Clone();$wrongVersion.versao=1
$wrongId=$technical.Clone();$wrongId.video_id='testVideo01'
$b1=New-TechnicalPlanFixture -Name 'invalid-version' -Technical $wrongVersion -KeepLegacy
$b2=New-TechnicalPlanFixture -Name 'invalid-id' -Technical $wrongId -KeepLegacy
$b3=New-TechnicalPlanFixture -Name 'invalid-case' -KeepLegacy -WrongCase
foreach($bad in @($b1,$b2,$b3)){Assert-PlanReject $bad.Args 'Selecao'}
$kept=$script:Evidencias
try{$script:Evidencias=@{};Assert-PlanReject $f.Args 'Procedencia'}finally{$script:Evidencias=$kept}
$wrongHash=$f.Args.Clone();$wrongHash.ExpectedSha256=('0'*64)
Assert-PlanReject $wrongHash 'Hash'
foreach($fixture in @($f,$b1,$b2,$b3)){
 if((Get-FileHash -LiteralPath $fixture.Ready).Hash.ToLowerInvariant() -cne $sourceHash -or (Test-Path -LiteralPath $fixture.Target) -or (Test-Path -LiteralPath (Join-Path $fixture.Args.Control 'estado.json'))){throw 'Plano teve efeitos'}
}
$proofPath=Join-Path $work 'prova-tecnica.json'
@{helper_sha256=(Get-FileHash publicacao_pendente.ps1).Hash;checks=@('legacy_harness','default_gate','technical_contract','copy_no_flags','legacy_contract','invalid_version_no_fallback','literal_id_no_fallback','field_case_no_fallback','source_evidence','external_hash','no_effects');scope='plano opt-in; sem consumidor/CLI/rede/publicacao'}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $proofPath -Encoding utf8
'RECOVERY_PLAN_TECHNICAL_PASS criterios11; '+$proofPath
