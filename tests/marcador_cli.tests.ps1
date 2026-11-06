#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$harness=Join-Path $repo 'tests/execucao_unica.tests.ps1'
if((Get-FileHash -LiteralPath $harness).Hash -cne '577E25989E3D5E9BA24BF0BB92B37D663C70A3A8E25BEBD1172FD6387BFAF472'){throw 'Harness mudou: revisar adaptacao'}
$source=[IO.File]::ReadAllText($harness)
function Replace-UniqueMarkerTest([string]$Text,[string]$Old,[string]$New){
 if($Text.IndexOf($Old,[StringComparison]::Ordinal) -lt 0 -or $Text.IndexOf($Old,[StringComparison]::Ordinal) -ne $Text.LastIndexOf($Old,[StringComparison]::Ordinal)){throw 'Ancora de teste ausente/ambigua'}
 return $Text.Replace($Old,$New)
}
$repoLine='$repo=Split-Path $PSScriptRoot -Parent'
$injectedRoot='$repo='+"'"+$repo.Replace("'","''")+"'"+[char]10+@'
$cliMarker=' MINHA COLET'+[char]0x00C2+'NEA '
$expectedMarker='Minha colet'+[char]0x00E2+'nea'
. (Join-Path $repo 'tests/processo_capturado.ps1')
'@
$source=Replace-UniqueMarkerTest $source $repoLine $injectedRoot
$source=Replace-UniqueMarkerTest $source "'ferramentas_portateis.ps1'))" "'ferramentas_portateis.ps1','editorial_audio.ps1'))"
$oldCall='else{ & $scriptPath -NaoInterativo:($mode -eq '+ "'nao_interativo'"+') -Interativo:($mode -ne '+ "'nao_interativo'"+') }'
$newCall=$oldCall.Replace(') }',') -Marcador $cliMarker }')
$source=Replace-UniqueMarkerTest $source $oldCall $newCall
$oldHash='  if((Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant() -ne $hash){throw '+ "'Nativo foi alterado'"+'}'
$newHash=@'
  $publishedHash=(Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant()
  if($record.auditoria.origem_sha256 -cne $hash -or $record.auditoria.resultado_sha256 -cne $publishedHash -or $publishedHash -ceq $hash){throw 'Hashes de origem/resultado incorretos'}
  if($record.auditoria.marcador.status -cne 'aplicado' -or -not $record.auditoria.marcador.validado -or -not [string]::Equals([string]$record.auditoria.marcador.valor,$expectedMarker,[StringComparison]::Ordinal)){throw 'Marcador nao aplicado pelo CLI'}
  $probeRun=Invoke-CapturedTestProcess -Program (Join-Path $repo 'ffprobe.exe') -Arguments @('-v','error','-show_format','-of','json',$finals[0].FullName)
  if($probeRun.ExitCode -ne 0){throw $probeRun.Stderr}
  $probe=ConvertFrom-Json $probeRun.Stdout
  if(-not [string]::Equals([string]$probe.format.tags.marcador_coletanea,$expectedMarker,[StringComparison]::Ordinal)){throw 'Tag fisica final divergente'}
  if($state.videos.TestVideo01.sha256 -cne $publishedHash -or $state.videos.TestVideo01.tamanho -ne (Get-Item -LiteralPath $finals[0].FullName).Length){throw 'Estado final diverge dos bytes'}
'@
$source=Replace-UniqueMarkerTest $source $oldHash $newHash
$finish="Write-Output 'EXECUCAO_UNICA_E2E_PASS'"
$offline=@'
$publishedFile=$finals[0].FullName
$publishedHash=(Get-FileHash -LiteralPath $publishedFile).Hash
foreach($request in @(@{Value=$cliMarker;Status='ja_presente'},@{Value='Outra';Status='limitacao'})){
 $config.no_input=$true;$config.offline=$true;$config.remotes=0;$config.reads=0;$config.downloads=0
 [IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
 $log=Join-Path $case ('retomada-'+$request.Status+'.log')
 & $scriptPath -Marcador $request.Value *> $log
 if($LASTEXITCODE -ne 0){throw ('Retomada falhou: '+(Get-Content -LiteralPath $log -Tail 6|Out-String))}
 $after=Get-Content -LiteralPath (Join-Path $dest '.controle/estado.json') -Raw|ConvertFrom-Json
 $record=@($after.registros.PSObject.Properties.Value)[0]
 $counts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
 if($record.resultado -cne 'existente' -or $record.marcador_reuso.status -cne $request.Status -or $counts.downloads -ne 0 -or $counts.reads -ne 0 -or $counts.remotes -ne 0){throw 'Retomada nao respeitou marcador/acesso'}
 if($request.Status -ceq 'limitacao' -and $record.motivo -notmatch 'Marcador:'){throw 'Limitacao editorial silenciosa'}
 if((Get-FileHash -LiteralPath $publishedFile).Hash -cne $publishedHash -or @(Get-ChildItem -LiteralPath $dest -File|Where-Object {$_.Extension -in @('.mp3','.m4a')}).Count -ne 1){throw 'Retomada alterou ou duplicou audio'}
 if(-not [string]::Equals([string]$after.videos.TestVideo01.auditoria.marcador.valor,$expectedMarker,[StringComparison]::Ordinal)){throw 'Auditoria aplicada foi sobrescrita por pedido conflitante'}
 if((Get-FileHash -LiteralPath $csv).Hash -cne $csvHash){throw 'CSV canonico alterado'}
}
Write-Output 'MARCADOR_CLI_PASS'
'@
$source=Replace-UniqueMarkerTest $source $finish $offline
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$work=Join-Path $PSScriptRoot ('.runtime-marcador-cli-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work
$path=Join-Path $work 'execucao_unica_marcador.ps1'
[IO.File]::WriteAllText($path,$source,[Text.UTF8Encoding]::new($false))
$output=@(& 'C:/Program Files/PowerShell/7/pwsh.exe' -NoLogo -NoProfile -NonInteractive -File $path -Modes direto_interativo 2>&1)
if($LASTEXITCODE -ne 0){throw ($output|Out-String)}
$text=$output|Out-String
if(-not $text.Contains('MARCADOR_CLI_PASS')){throw 'Teste nao terminou'}
$text
