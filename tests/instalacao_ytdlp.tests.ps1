#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'instalacao_ytdlp.ps1')
$script:Root=$repo
$main=Join-Path $repo 'baixar_audios_ytdlp.ps1'
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile($main,[ref]$t,[ref]$e)
$f=@($a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Invoke-Ytdlp'},$true))
if($e.Count -or $f.Count -ne 1){throw 'Invoker ambiguo'}
$sha=[Security.Cryptography.SHA256]::Create()
try{$invokerHash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($f[0].Extent.Text.Replace("`r`n","`n")))).Replace('-','')}finally{$sha.Dispose()}
if($invokerHash -cne 'D920FC22148930960DA1553742C1216F77F2E7AC381AF3AC847DD6D1DC94EDD4'){throw 'Fonte canonica do invoker mudou'}
. ([scriptblock]::Create($f[0].Extent.Text.Replace('function Invoke-Ytdlp(','function Invoke-RealYtdlp(')))
$fixture=Join-Path $PSScriptRoot 'transporte_release_ytdlp.tests.ps1'
if((Get-FileHash -LiteralPath $fixture).Hash -cne 'EBC2EAD9B426D3E1813F14FEAF29DF2FA5064FB19EDAA1908D2145E100D87C03'){throw 'Fixture HTTP mudou'}
$a=[Management.Automation.Language.Parser]::ParseFile($fixture,[ref]$t,[ref]$e)
$c=@($a.FindAll({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.StartsWith('using System;')},$true))
if($e.Count -or $c.Count -ne 1){throw 'Fixture HTTP ambigua'}
Add-Type -TypeDefinition $c[0].Value
$original=Join-Path $repo 'yt-dlp.exe'
$baseline=Invoke-RealYtdlp -Executable $original -Arguments @('--ignore-config','--no-plugin-dirs','--version') -TimeoutSeconds 15
if($baseline.timeout -or $baseline.code -ne 0){throw 'Binario fixture local indisponivel'}
$tag=([string]$baseline.out).Trim()
$body=[IO.File]::ReadAllBytes($original);$sourceHash=(Get-FileHash -LiteralPath $original).Hash.ToLowerInvariant()
$work=Join-Path $PSScriptRoot ('.runtime-ytdlp-install-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$script:Checks=0;$script:Calls=@();$script:FakeTimeout=$false
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
function MustFail([scriptblock]$Action,[string]$Why){$failed=$false;try{$null=& $Action}catch{$failed=$true};Assert $failed $Why}
function New-Case($Name){$p=Join-Path $work $Name;[void][IO.Directory]::CreateDirectory($p);return $p}
function New-Handler([string]$Tag=$tag,[string]$Hash=$sourceHash,[byte[]]$Blob=$body){
 $h=[ReleaseProbeHandler]::new()
 $meta=@{tag_name=$Tag;draft=$false;prerelease=$false}|ConvertTo-Json -Compress
 foreach($data in @([Text.Encoding]::UTF8.GetBytes($meta),[Text.Encoding]::UTF8.GetBytes($Hash+'  yt-dlp.exe'),$Blob)){
  $r=[Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::OK);$r.Content=[Net.Http.ByteArrayContent]::new($data);$h.Replies.Enqueue($r)
 }
 return $h
}
function Invoke-Ytdlp([string[]]$Arguments,[int]$TimeoutSeconds,[string]$Executable){
 $blocked=$false;$writer=$null
 try{$writer=[IO.File]::Open($Executable,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [System.IO.IOException]{$blocked=$true}finally{if($writer){$writer.Dispose()}}
 $script:Calls+=,@{args=($Arguments -join '|');timeout=$TimeoutSeconds;hash=(Get-FileHash -LiteralPath $Executable).Hash.ToLowerInvariant();blocked=$blocked}
 if($script:FakeTimeout){return @{code=0;out=$tag;err='';timeout=$true}}
 return (Invoke-RealYtdlp -Executable $Executable -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds)
}
function Empty-Case($Root){Assert (@(Get-ChildItem -LiteralPath $Root -Force).Count -eq 0) 'Falha deixou candidato ou destino'}
$root=New-Case 'normal';$foreign=Join-Path $root '.yt-dlp.candidate.foreign.exe';[IO.File]::WriteAllText($foreign,'alheio')
$h=New-Handler
$installArgs=@{Root=$root;Handler=$h}
if([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -cne 'X64'){$installArgs.Architecture='X64'}
$r=Install-YtdlpDependency @installArgs
Assert (($r.Keys|Sort-Object) -join '|' -ceq 'manifest_sha256|metadata_sha256|metadata_url|publication|version') 'Recibo exato da instalacao'
Assert ($r.version -ceq $tag -and $r.publication.status -ceq 'published' -and $r.publication.sha256 -ceq $sourceHash) 'Versao/hash/publicacao divergentes'
Assert ($script:Calls.Count -eq 1 -and $script:Calls[0].blocked -and $script:Calls[0].hash -ceq $sourceHash) 'Executar somente candidato verificado e travado'
Assert ($script:Calls[0].args -ceq '--ignore-config|--no-plugin-dirs|--version' -and $script:Calls[0].timeout -eq 15) 'Args e timeout de validacao'
Assert ($h.Seen.Count -eq 3 -and -not $h.Disposed) 'Fluxo de rede ou ownership incorreto'
Assert ((Get-FileHash -LiteralPath (Join-Path $root 'yt-dlp.exe')).Hash.ToLowerInvariant() -ceq $sourceHash -and [IO.File]::ReadAllText($foreign) -ceq 'alheio') 'Destino ou arquivo alheio alterado'
Assert (@(Get-ChildItem -LiteralPath $root -Force -File).Count -eq 2) 'Candidato proprio nao limpo'
$root=New-Case 'existing';$target=Join-Path $root 'yt-dlp.exe';[IO.File]::WriteAllText($target,'usuario')
$h=[ReleaseProbeHandler]::new();$script:Calls=@()
MustFail {Install-YtdlpDependency -Root $root -Architecture X64 -Handler $h} 'Preservar destino preexistente antes de rede'
Assert ($h.Seen.Count -eq 0 -and $script:Calls.Count -eq 0 -and [IO.File]::ReadAllText($target) -ceq 'usuario') 'Destino existente nao deve ser atualizado implicitamente'
$root=New-Case 'wrong_version';$h=New-Handler -Tag 'fixture-version-mismatch';$script:Calls=@()
MustFail {Install-YtdlpDependency -Root $root -Architecture X64 -Handler $h} 'Versao deve corresponder a tag do pacote'
Assert ($script:Calls.Count -eq 1) 'Versao divergente nao foi realmente consultada';Empty-Case $root
$root=New-Case 'bad_hash';$h=New-Handler -Hash ('0'*64);$script:Calls=@()
MustFail {Install-YtdlpDependency -Root $root -Architecture X64 -Handler $h} 'Digest deve impedir execucao'
Assert ($script:Calls.Count -eq 0) 'Executou bytes antes de conferir checksum';Empty-Case $root
$root=New-Case 'not_executable';$h=New-Handler -Hash 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad' -Blob ([Text.Encoding]::ASCII.GetBytes('abc'));$script:Calls=@()
MustFail {Install-YtdlpDependency -Root $root -Architecture X64 -Handler $h} 'Checksum nao substitui validacao de executavel'
Assert ($script:Calls.Count -eq 1) 'Artefato nao executavel nao foi validado';Empty-Case $root
$root=New-Case 'timeout';$h=New-Handler;$script:FakeTimeout=$true;$script:Calls=@()
try{MustFail {Install-YtdlpDependency -Root $root -Architecture X64 -Handler $h} 'Timeout deve bloquear mesmo code0/outcorreto'}finally{$script:FakeTimeout=$false}
Assert ($script:Calls.Count -eq 1) 'Timeout nao exercitado';Empty-Case $root
# Colisao de entropia: prova permissao/escrita e propriedade ANTES de qualquer pedido.
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'candidato_ytdlp.ps1'),[ref]$t,[ref]$e)
$f=@($a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Invoke-YtdlpCandidateFile'},$false))
$entropy="[guid]::NewGuid().ToString('N')"
if($e.Count -or $f.Count -ne 1 -or ([regex]::Matches($f[0].Extent.Text,[regex]::Escape($entropy))).Count -ne 1){throw 'Probe de entropia ambiguo'}
# Reimplementa somente a fonte literal da factory com entropia fixa no escopo do teste.
# O instalador real deve chama-la antes da aquisicao; nao modifica arquivo do produto.
. ([scriptblock]::Create($f[0].Extent.Text.Replace($entropy,"'00000000000000000000000000000001'")))
$null=Get-Command -Name Invoke-YtdlpCandidateFile -CommandType Function -ErrorAction Stop
$root=New-Case 'collision';$collision=Join-Path $root '.yt-dlp.candidate.00000000000000000000000000000001.exe';[IO.File]::WriteAllText($collision,'outro escritor')
$h=[ReleaseProbeHandler]::new();$script:Calls=@()
MustFail {Install-YtdlpDependency -Root $root -Architecture X64 -Handler $h} 'CreateNew deve recusar colisao antes de aquisicao'
Assert ($h.Seen.Count -eq 0 -and $script:Calls.Count -eq 0 -and [IO.File]::ReadAllText($collision) -ceq 'outro escritor') 'Colisao nao transfere propriedade nem autoriza rede'
Assert ((Get-FileHash -LiteralPath $original).Hash.ToLowerInvariant() -ceq $sourceHash) 'Binario original foi alterado'
'YTDLP_INSTALL_CANDIDATE_PASS checks'+$script:Checks+'; HTTP simulado, binario local/IO/versoes reais; timeout outcome simulado; '+$work
