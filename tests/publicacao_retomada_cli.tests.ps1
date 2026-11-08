#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$harness=Join-Path $repo 'tests/execucao_unica.tests.ps1'
if((Get-FileHash -LiteralPath $harness).Hash -cne '63917D9605ECBC278F57327DE88176403E2C51C588C2E1E44827425EA146CB9F'){throw 'Harness mudou: revisar integracao de retomada'}
$source=[IO.File]::ReadAllText($harness)
function Replace-StartupTestLiteral([string]$Text,[string]$Before,[string]$After){
 if(([regex]::Matches($Text,[regex]::Escape($Before))).Count -ne 1){throw 'Ancora do teste ausente/ambigua'}
 return $Text.Replace($Before,$After)
}
$source=Replace-StartupTestLiteral $source '$repo=Split-Path $PSScriptRoot -Parent' ('$repo='+"'"+$repo.Replace("'","''")+"'")
$hook=@'
 if($mode -ne 'direto_interativo'){throw 'Modo de integracao inesperado'}
 . (Join-Path $repo 'publicacao_pendente.ps1')
 . (Join-Path $repo 'referencia_publicacao.ps1')
 $saveDefinitions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Save-State'},$true))
 if($saveDefinitions.Count -ne 1){throw 'Gravador de estado ambiguo'}
 . ([scriptblock]::Create($saveDefinitions[0].Extent.Text))
 $script:Out=$dest;$script:Control=Join-Path $dest '.controle';$script:StateFile=Join-Path $script:Control 'estado.json';$script:Utf8=[Text.UTF8Encoding]::new($false)
 $published=$finals[0].FullName;$publishedName=[IO.Path]::GetFileName($published)
 $ready=Join-Path $script:Control 'fontes/checkpoint-proxy/ready.mp3'
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ready))
 $script:Lock=$null
 try{
  $script:Lock=[IO.File]::Open((Join-Path $script:Control 'execucao.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $script:State=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
  $checkpointRecord=@($script:State.registros.Values)[0]
  [IO.File]::Move($published,$ready)
  $snapshot=New-PublicationIntentSnapshot -Ready $ready -Target $published -Control $script:Control -Out $script:Out -VideoId 'TestVideo01' -Record $checkpointRecord -Audit $checkpointRecord.auditoria -Probe $checkpointRecord.auditoria.resultado
  $saved=Save-PublicationIntentFile -Snapshot $snapshot -Control $script:Control -Out $script:Out
  $pendingRef=New-PublicationReference -VideoId 'TestVideo01' -RecordKey $checkpointRecord.chave -IntentSha256 $saved.Sha256
  $script:State.publicacoes_pendentes[$pendingRef.arquivo]=$pendingRef
  # Forcar caminho de legado conhecido: o checkpoint nao pode ter metadados rebaixados.
  $script:State.videos.TestVideo01.auditoria.validado=$false
  Save-State
 }finally{if($null -ne $script:Lock){$script:Lock.Dispose();$script:Lock=$null}}
 $untracked=Join-Path $dest 'alheio.mp3'
 Copy-Item -LiteralPath $fixture -Destination $untracked
 $config.no_input=$true;$config.offline=$true;$config.remotes=0;$config.reads=0;$config.downloads=0
 [IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
 & $scriptPath -NaoInterativo -SomenteAuditarExistentes
 if($LASTEXITCODE -ne 0){throw 'CLI auditoria pendente falhou'}
 $afterAudit=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 if(-not [IO.File]::Exists($ready) -or [IO.File]::Exists($published) -or $afterAudit.publicacoes_pendentes.Count -ne 1 -or $afterAudit.videos.TestVideo01.auditoria.validado -ne $false -or [string]::IsNullOrWhiteSpace($afterAudit.videos.TestVideo01.auditoria.origem_url)){throw 'Auditoria publicou Ready ou alterou legado conhecido protegido'}
 if([IO.File]::Exists($untracked) -or -not [IO.Directory]::Exists((Join-Path $script:Control 'nao_rastreados'))){throw 'Protecao de checkpoint impediu auditoria de arquivo alheio'}
 & $scriptPath -NaoInterativo
 if($LASTEXITCODE -ne 0){throw 'CLI retomada Ready falhou'}
 $afterReady=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 if([IO.File]::Exists($ready) -or -not [IO.File]::Exists($published) -or $afterReady.publicacoes_pendentes.Count -ne 0 -or $afterReady.videos.TestVideo01.publicacao_intencao.situacao -cne 'concluida' -or (Get-FileHash -LiteralPath $published).Hash.ToLowerInvariant() -cne $hash){throw 'Startup nao retomou Ready antes da auditoria'}
 # Mesmo journal imutavel, corte simulado apos Move e antes de gravar video: proteger arquivo sem estado.
 try{
  $script:Lock=[IO.File]::Open((Join-Path $script:Control 'execucao.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $script:State=$afterReady;$null=$script:State.videos.Remove('TestVideo01')
  $script:State.publicacoes_pendentes[$pendingRef.arquivo]=$pendingRef.Clone();Save-State
 }finally{if($null -ne $script:Lock){$script:Lock.Dispose();$script:Lock=$null}}
 & $scriptPath -NaoInterativo -SomenteAuditarExistentes
 if($LASTEXITCODE -ne 0){throw 'CLI auditoria Target falhou'}
 if(-not [IO.File]::Exists($published) -or (Get-FileHash -LiteralPath $published).Hash.ToLowerInvariant() -cne $hash){throw 'Auditoria removeu Target pendente sem registro'}
 & $scriptPath -NaoInterativo
 if($LASTEXITCODE -ne 0){throw 'CLI retomada Target falhou'}
 $afterTarget=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 if($afterTarget.publicacoes_pendentes.Count -ne 0 -or $afterTarget.videos.TestVideo01.publicacao_intencao.situacao -cne 'concluida'){throw 'Startup nao restaurou estado do Target'}
 # Journal inacessivel por hash externo incorreto: preservar todo o destino, continuar sem baixar.
 $protectedUnknown=Join-Path $dest 'guardado.mp3'
 Copy-Item -LiteralPath $fixture -Destination $protectedUnknown
 try{
  $script:Lock=[IO.File]::Open((Join-Path $script:Control 'execucao.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $script:State=$afterTarget;$badRef=$pendingRef.Clone();$badRef.sha256='0'*64
  $script:State.publicacoes_pendentes[$pendingRef.arquivo]=$badRef;Save-State
 }finally{if($null -ne $script:Lock){$script:Lock.Dispose();$script:Lock=$null}}
 & $scriptPath -NaoInterativo -SomenteAuditarExistentes
 if($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($protectedUnknown) -or -not [IO.File]::Exists($published)){throw 'Fallback de preservacao total nao protegeu arquivos'}
 try{
  $script:Lock=[IO.File]::Open((Join-Path $script:Control 'execucao.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
  $script:State=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
  $script:State.publicacoes_pendentes[$pendingRef.arquivo]=$pendingRef.Clone();Save-State
 }finally{if($null -ne $script:Lock){$script:Lock.Dispose();$script:Lock=$null}}
 & $scriptPath -NaoInterativo
 if($LASTEXITCODE -ne 0){throw 'CLI recuperacao apos ref corrigida falhou'}
 $lastState=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 $lastCounts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
 if($lastState.publicacoes_pendentes.Count -ne 0 -or $lastCounts.downloads -ne 0 -or $lastCounts.remotes -ne 0 -or $lastCounts.reads -ne 0 -or (Get-FileHash -LiteralPath $csv).Hash -cne $csvHash -or (Get-FileHash -LiteralPath $published).Hash.ToLowerInvariant() -cne $hash){throw 'Retomada repetiu transporte/perguntas, alterou CSV/audio ou deixou pendencia'}
 Write-Output 'PUBLICATION_STARTUP_CLI_PASS: Ready/Target, auditoria protegida e zero transporte/perguntas'
'@
$finish=" Write-Output ('PASS E2E '+"+'$mode'+"+' downloads='+"+'$counts.downloads'+"+' leituras='+"+'$counts.reads'+")"
$source=Replace-StartupTestLiteral $source $finish ($hook+[Environment]::NewLine+$finish)
$t=$null;$e=$null
[void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Clone de integracao invalido'}
$work=Join-Path $PSScriptRoot ('.runtime-startup-cli-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$clone=Join-Path $work 'execucao_startup.ps1'
[IO.File]::WriteAllText($clone,$source,[Text.UTF8Encoding]::new($false))
. (Join-Path $repo 'tests/processo_capturado.ps1')
$r=Invoke-CapturedTestProcess -Program (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoProfile','-File',$clone,'-Modes','direto_interativo') -TimeoutMs 180000
[IO.File]::WriteAllText((Join-Path $work 'resultado.log'),($r.Stdout+[Environment]::NewLine+$r.Stderr),[Text.UTF8Encoding]::new($false))
if($r.ExitCode -ne 0 -or -not $r.Stdout.Contains('PUBLICATION_STARTUP_CLI_PASS')){throw ('Integracao falhou: '+(Join-Path $work 'resultado.log'))}
'PUBLICATION_STARTUP_CLI_PASS: audio/ferramentas reais; transporte e confirmacoes simulados; Windows'
