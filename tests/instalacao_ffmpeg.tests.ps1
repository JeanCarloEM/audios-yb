#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'instalacao_ffmpeg.ps1')
# Contratos de orquestração; origem dos valores: recibo nativo aa719f86/descriptor.json, 2026-11-11.
$script:suiteFixture=@{
 archive_size=[long]168580960
 release_plan=@{
  asset_name='ffmpeg-n9.0.2-49-gc179411bbb-win64-lgpl-9.0.zip'
  url='https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-11-11-12-39/ffmpeg-n9.0.2-49-gc179411bbb-win64-lgpl-9.0.zip'
  build_version='n9.0.2-49-gc179411bbb'
  sha256='9ccd65428fb0e60a0d574b76145df41f402b754edd2d06c2e24fa506fc1c2b02'
 }
}
$script:suiteDescCalls=0;$script:suiteDownloadCalls=0;$script:suiteInstalled=@();$script:suiteFailure='';$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function Get-FfmpegReleaseDescriptor {
 param($Architecture,$TimeoutSeconds,$Handler)
 $script:suiteDescCalls++
 Assert ($Architecture -ceq 'X64' -and $TimeoutSeconds -eq 7 -and $null -eq $Handler) 'Argumentos do descritor'
 if($script:suiteFailure -ceq 'descriptor'){throw 'Descritor recusado'}
 return $script:suiteFixture
}
function Invoke-WithFfmpegDownloadedArchive {
 param($RootDirectory,$Action,[uri]$Uri,$ExpectedSize,$ExpectedSha256,$TimeoutSeconds,$Handler,$CancellationToken)
 $script:suiteDownloadCalls++
 Assert ($RootDirectory -ceq $script:suiteRoot -and $Uri.AbsoluteUri -ceq $script:suiteFixture.release_plan.url -and $ExpectedSize -is [long] -and $ExpectedSize -eq 168580960 -and $ExpectedSha256 -ceq '9ccd65428fb0e60a0d574b76145df41f402b754edd2d06c2e24fa506fc1c2b02' -and $TimeoutSeconds -eq 11 -and $null -eq $Handler -and $CancellationToken -eq [Threading.CancellationToken]::None) 'Download autenticado encaminhado'
 if($script:suiteFailure -ceq 'download'){throw 'Download recusado'}
 # Simula nomes locais de dependências: contexto do callback deve ser próprio.
 $missing=@('invalid');$rootPath='shadow';$expectedRoot='shadow';$plan=@{};$Invoker={throw 'Invoker sombreado'};$TimeoutSeconds=1
 $mockStream=[IO.MemoryStream]::new()
 try{& $Action $mockStream @{size=[long]168580960;sha256=$ExpectedSha256}}finally{$mockStream.Dispose()}
}
function Install-FfmpegArchiveExecutable {
 param($RootDirectory,$ArchiveStream,$ExpectedRootDirectory,$Tool,$ExpectedBuildVersion,$Invoker,$TimeoutSeconds,$CancellationToken)
 $script:suiteInstalled+=,$Tool
 Assert ($RootDirectory -ceq $script:suiteRoot -and $ArchiveStream -is [IO.MemoryStream] -and $ArchiveStream.CanRead -and $ExpectedRootDirectory -ceq 'ffmpeg-n9.0.2-49-gc179411bbb-win64-lgpl-9.0' -and $Tool -cin @('ffmpeg','ffprobe') -and $ExpectedBuildVersion -ceq 'n9.0.2-49-gc179411bbb' -and [object]::ReferenceEquals($Invoker,$script:suiteInvoker) -and $TimeoutSeconds -eq 11 -and $CancellationToken -eq [Threading.CancellationToken]::None) 'Instalação recebe contexto correto'
 if($Tool -ceq $script:suiteFailure){throw 'Falha deliberada de publicação'}
 $target=Join-Path $RootDirectory ($Tool+'.exe');[IO.File]::WriteAllText($target,'novo-'+$Tool)
 return @{status='published';tool=$Tool;target_path=$target;size=[long]11;sha256=('a'*64);build_version=$ExpectedBuildVersion;version_token=$ExpectedBuildVersion}
}
function Invoke-Suite { Install-MissingFfmpegTools -RootDirectory $script:suiteRoot -Architecture 'X64' -Invoker $script:suiteInvoker -DocumentTimeoutSeconds 7 -TimeoutSeconds 11 }
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Operação deveria falhar'}
$script:suiteRoot=Join-Path $PSScriptRoot ('.runtime-install-suite-['+[guid]::NewGuid().ToString('N')+']')
[void][IO.Directory]::CreateDirectory($script:suiteRoot)
$script:suiteInvoker={throw 'Mock de orquestração não executa binário'}
$ffmpeg=Join-Path $script:suiteRoot 'ffmpeg.exe';$ffprobe=Join-Path $script:suiteRoot 'ffprobe.exe'
$sentinel=Join-Path $script:suiteRoot 'keep.txt';[IO.File]::WriteAllText($sentinel,'preservar')
try{
 [IO.File]::WriteAllText($ffmpeg,'original');[IO.File]::WriteAllText($ffprobe,'original-probe')
 $r=Invoke-Suite
 Assert ($r -is [hashtable] -and $r.Count -eq 2 -and $r.root_path -ceq $script:suiteRoot -and @($r.targets).Count -eq 2 -and @($r.targets|Where-Object {$_.status -ceq 'preserved'}).Count -eq 2 -and $script:suiteDescCalls -eq 0 -and $script:suiteDownloadCalls -eq 0) 'Tudo existente não consulta nem baixa'
 [IO.File]::Delete($ffprobe);$r=Invoke-Suite
 Assert ($script:suiteDescCalls -eq 1 -and $script:suiteDownloadCalls -eq 1 -and ($script:suiteInstalled -join ',') -ceq 'ffprobe' -and $r.targets[0].tool -ceq 'ffmpeg' -and $r.targets[0].status -ceq 'preserved' -and $r.targets[1].status -ceq 'published' -and [IO.File]::ReadAllText($ffmpeg) -ceq 'original') 'Instala somente faltante e preserva existente'
 [IO.File]::Delete($ffmpeg);[IO.File]::Delete($ffprobe);$script:suiteInstalled=@();$r=Invoke-Suite
 Assert ($script:suiteDescCalls -eq 2 -and $script:suiteDownloadCalls -eq 2 -and ($script:suiteInstalled -join ',') -ceq 'ffmpeg,ffprobe' -and @($r.targets|Where-Object {$_.status -ceq 'published'}).Count -eq 2) 'Um download para ambos'
 [IO.File]::Delete($ffmpeg);[IO.File]::Delete($ffprobe)
 [IO.File]::WriteAllText($ffprobe,'original-probe');$script:suiteInstalled=@();$r=Invoke-Suite
 Assert ($script:suiteDescCalls -eq 3 -and $script:suiteDownloadCalls -eq 3 -and ($script:suiteInstalled -join ',') -ceq 'ffmpeg' -and $r.targets[0].tool -ceq 'ffmpeg' -and $r.targets[0].status -ceq 'published' -and $r.targets[1].tool -ceq 'ffprobe' -and $r.targets[1].status -ceq 'preserved' -and [IO.File]::ReadAllText($ffprobe) -ceq 'original-probe') 'Ordem fixa e preservação quando somente ffmpeg falta'
 [IO.File]::Delete($ffmpeg);[IO.File]::Delete($ffprobe)
 foreach($failure in @('descriptor','download','ffprobe')){
  $script:suiteFailure=$failure;MustFail {Invoke-Suite}
  Assert (![IO.File]::Exists($ffprobe) -and ([IO.File]::Exists($ffmpeg) -eq ($failure -ceq 'ffprobe'))) 'Propaga falha e preserva publicação anterior'
  if([IO.File]::Exists($ffmpeg)){[IO.File]::Delete($ffmpeg)}
 }
 $script:suiteFailure='';$before=$script:suiteDescCalls
 MustFail {Install-MissingFfmpegTools -RootDirectory $script:suiteRoot -Architecture 'x64' -Invoker $script:suiteInvoker}
 MustFail {Install-MissingFfmpegTools -RootDirectory $script:suiteRoot -Architecture 'X64' -Invoker $null}
 MustFail {Install-MissingFfmpegTools -RootDirectory '.' -Architecture 'X64' -Invoker $script:suiteInvoker}
 [void][IO.Directory]::CreateDirectory($ffprobe)
 try{MustFail {Invoke-Suite}}finally{[IO.Directory]::Delete($ffprobe,$false)}
 $cts=[Threading.CancellationTokenSource]::new()
 try{$cts.Cancel();$typed=$false;try{$null=Install-MissingFfmpegTools -RootDirectory $script:suiteRoot -Architecture 'X64' -Invoker $script:suiteInvoker -CancellationToken $cts.Token}catch{if($_.Exception.GetBaseException() -is [OperationCanceledException]){$typed=$true}else{throw}};Assert $typed 'Cancelamento tipado'}finally{$cts.Dispose()}
 Assert ($script:suiteDescCalls -eq $before -and [IO.File]::ReadAllText($sentinel) -ceq 'preservar' -and @([IO.Directory]::EnumerateFiles($script:suiteRoot)).Count -eq 1) 'Guardas antes rede e sentinela intacta'
}finally{
 foreach($name in @('ffmpeg.exe','ffprobe.exe','keep.txt')){$path=Join-Path $script:suiteRoot $name;if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
 [IO.Directory]::Delete($script:suiteRoot,$false)
}
Write-Output "FFMPEG_SUITE_ORCHESTRATION_PASS checks=$checks; mocks de orquestracao, sem rede/binario real"
