#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'publicacao_artefato_ytdlp.ps1')
$work=Join-Path $PSScriptRoot ('.runtime-ytdlp-artifact-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$source=Join-Path $work 'candidate.bin'
[IO.File]::WriteAllBytes($source,[Text.Encoding]::ASCII.GetBytes('abc'))
# Vetor SHA-256 conhecido; bytes sinteticos, nao um executavel/release real.
$hash='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
$manifest=$hash+'  yt-dlp.exe'
$script:Checks=0
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
function MustFail([scriptblock]$Action,[string]$Why){$failed=$false;try{$null=& $Action}catch{$failed=$true};Assert $failed $Why}
function New-Case($Name){$p=Join-Path $work $Name;[void][IO.Directory]::CreateDirectory($p);return $p}
function Publish($Root,$Source=$source,$Tag='2026.01.02',$Text=$manifest){Publish-YtdlpReleaseArtifact -Root $Root -SourcePath $Source -Tag $Tag -Manifest $Text -Architecture X64}
function No-OwnedTemps($Root){Assert (@(Get-ChildItem -LiteralPath $Root -Force -File|Where-Object {$_.Extension -ceq '.tmp' -and $_.Name -cne '.yt-dlp.foreign.tmp'}).Count -eq 0) 'Temporario proprio abandonado'}
$root=New-Case 'normal'
$foreign=Join-Path $root '.yt-dlp.foreign.tmp';[IO.File]::WriteAllText($foreign,'preservar')
$r=Publish $root
$target=Join-Path $root 'yt-dlp.exe'
Assert (($r.Keys|Sort-Object) -join '|' -ceq 'release_plan|sha256|status|target_path') 'Envelope da publicacao'
Assert ($r.status -ceq 'published' -and $r.target_path -ceq $target -and $r.sha256 -ceq $hash) 'Retorno deve corresponder aos bytes publicados'
Assert ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -ceq $hash -and [IO.File]::ReadAllText($target) -ceq 'abc') 'Bytes publicados incorretos'
Assert ($r.release_plan.url -ceq 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.01.02/yt-dlp.exe' -and $r.release_plan.sha256 -ceq $hash) 'Perdeu vinculo com plano validado'
No-OwnedTemps $root
[IO.File]::SetLastWriteTimeUtc($target,[DateTime]::new(2000,1,2,3,4,5,[DateTimeKind]::Utc))
$mtime=[IO.File]::GetLastWriteTimeUtc($target)
$again=Publish $root
Assert ($again.status -ceq 'existing' -and [IO.File]::GetLastWriteTimeUtc($target) -eq $mtime) 'Reuso nao pode reescrever destino'
$exclusive=[IO.File]::Open($target,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$exclusive.Dispose()
Assert $true 'Handle de destino existente deve ser liberado antes do retorno'
Assert ([IO.File]::ReadAllText($foreign) -ceq 'preservar') 'Removeu temporario alheio'
$badSource=Join-Path $work 'bad.bin';[IO.File]::WriteAllText($badSource,'outros bytes')
$root=New-Case 'hash_ruim';MustFail {Publish $root $badSource} 'Rejeitar bytes sem checksum correspondente'
Assert (-not [IO.File]::Exists((Join-Path $root 'yt-dlp.exe'))) 'Publicou fonte invalida';No-OwnedTemps $root
$root=New-Case 'conflito';$occupied=Join-Path $root 'yt-dlp.exe';[IO.File]::WriteAllText($occupied,'usuario')
MustFail {Publish $root} 'Destino divergente deve bloquear'
Assert ([IO.File]::ReadAllText($occupied) -ceq 'usuario') 'Sobrescreveu arquivo preexistente';No-OwnedTemps $root
$root=New-Case 'locked_source';$lock=[IO.File]::Open($source,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{MustFail {Publish $root} 'Fonte sem acesso deve falhar'}finally{$lock.Dispose()}
Assert (-not [IO.File]::Exists((Join-Path $root 'yt-dlp.exe'))) 'Publicou apos falha de IO';No-OwnedTemps $root
$root=New-Case 'directory_target';$occupied=Join-Path $root 'yt-dlp.exe';[void][IO.Directory]::CreateDirectory($occupied)
$sentinel=Join-Path $occupied 'sentinel';[IO.File]::WriteAllText($sentinel,'preservar')
MustFail {Publish $root} 'Destino diretorio deve bloquear'
Assert ([IO.File]::ReadAllText($sentinel) -ceq 'preservar') 'Alterou diretorio preexistente';No-OwnedTemps $root
$root=New-Case 'invalid_plan';MustFail {Publish $root $source 'latest'} 'Canal mutavel deve falhar antes de efeitos'
Assert (@(Get-ChildItem -LiteralPath $root -Force).Count -eq 0) 'Plano invalido deixou efeitos'
MustFail {Publish (Join-Path $work 'ausente')} 'Nao criar Root implicitamente'
Assert (-not [IO.Directory]::Exists((Join-Path $work 'ausente'))) 'Criou Root sem contrato'
# Injeta somente entropia do nome; toda abertura/copia/limpeza continua com IO real.
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $PSScriptRoot) 'publicacao_artefato_ytdlp.ps1'),[ref]$t,[ref]$e)
$fn=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Publish-YtdlpReleaseArtifact'},$false))
if($e.Count -or $fn.Count -ne 1){throw 'Probe de colisao ambiguo'}
$entropy="[guid]::NewGuid().ToString('N')"
if(([regex]::Matches($fn[0].Extent.Text,[regex]::Escape($entropy))).Count -ne 1){throw 'Entropia nao unica'}
$probe=$fn[0].Extent.Text.Replace('function Publish-YtdlpReleaseArtifact {','function Publish-YtdlpCollisionProbe {').Replace($entropy,'(Get-ArtifactProbeNonce -SourcePath $SourcePath)')
. ([scriptblock]::Create($probe))
$script:SourceProbeBlocked=$false
function Get-ArtifactProbeNonce([string]$SourcePath){
 $writer=$null
 try{$writer=[IO.File]::Open($SourcePath,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [System.IO.IOException]{$script:SourceProbeBlocked=$true}finally{if($null -ne $writer){$writer.Dispose()}}
 return '00000000000000000000000000000001'
}
$root=New-Case 'collision'
$collision=Join-Path $root '.yt-dlp.00000000000000000000000000000001.tmp'
[IO.File]::WriteAllText($collision,'arquivo de outro escritor')
MustFail {Publish-YtdlpCollisionProbe -Root $root -SourcePath $source -Tag '2026.01.02' -Manifest $manifest -Architecture X64} 'CreateNew deve recusar colisao'
Assert $script:SourceProbeBlocked 'Fonte deve continuar travada apos hash e antes do temporario'
Assert ([IO.File]::ReadAllText($collision) -ceq 'arquivo de outro escritor') 'Colisao nao transfere propriedade do temporario'
Assert (-not [IO.File]::Exists((Join-Path $root 'yt-dlp.exe'))) 'Colisao publicou artefato'
Assert ((Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -ceq $hash) 'Fonte foi alterada'
'YTDLP_ARTIFACT_PUBLICATION_PASS checks'+$script:Checks+'; IO real Windows com bytes sinteticos; nao executa nem autentica release; '+$work
