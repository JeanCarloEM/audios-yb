#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'instalacao_ffmpeg.ps1')
$checks=0;$script:selectionDownloads=0;$script:selectionInstalls=@()
function Assert($ok,$why){if(!$ok){throw $why};$script:checks++}
function Get-FfmpegReleaseDescriptor {
 # Fixture de orquestração: nenhum byte de release é baixado ou executado.
 return @{archive_size=[long]3;release_plan=@{asset_name='ffmpeg-fixture.zip';url='https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-11-11-12-39/ffmpeg-fixture.zip';build_version='n9.0.2';sha256='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'}}
}
function Invoke-WithFfmpegDownloadedArchive {
 param($RootDirectory,$Action,[uri]$Uri,$ExpectedSize,$ExpectedSha256,$TimeoutSeconds,$Handler,$CancellationToken)
 $script:selectionDownloads++;$s=[IO.MemoryStream]::new()
 try{& $Action $s @{size=[long]3;sha256=$ExpectedSha256}}finally{$s.Dispose()}
}
function Install-FfmpegArchiveExecutable {
 param($RootDirectory,$ArchiveStream,$ExpectedRootDirectory,$Tool,$ExpectedBuildVersion,$Invoker,$TimeoutSeconds,$CancellationToken)
 $script:selectionInstalls+=,$Tool;$target=Join-Path $RootDirectory ($Tool+'.exe')
 [IO.File]::WriteAllText($target,'novo-'+$Tool)
 return @{status='published';tool=$Tool;target_path=$target;size=[long]11;sha256=('a'*64);build_version=$ExpectedBuildVersion;version_token=$ExpectedBuildVersion}
}
$root=Join-Path $PSScriptRoot ('.runtime-suite-selection-['+[guid]::NewGuid().ToString('N')+']')
[void][IO.Directory]::CreateDirectory($root)
$ffmpeg=Join-Path $root 'ffmpeg.exe';$ffprobe=Join-Path $root 'ffprobe.exe';$sentinel=Join-Path $root 'keep.txt';[IO.File]::WriteAllText($sentinel,'preservar')
$invoker={throw 'Não executar fixture'}
try{
 foreach($tool in @('ffmpeg','ffprobe')){
  $script:selectionInstalls=@();$before=$script:selectionDownloads
  $r=Install-MissingFfmpegTools -RootDirectory $root -Architecture 'X64' -Invoker $invoker -RequestedTools @($tool)
  $other=if($tool -ceq 'ffmpeg'){$ffprobe}else{$ffmpeg};$target=Join-Path $root ($tool+'.exe')
  Assert ($r.targets.Count -eq 1 -and $r.targets[0].tool -ceq $tool -and $r.targets[0].status -ceq 'published' -and ($script:selectionInstalls -join ',') -ceq $tool -and $script:selectionDownloads -eq $before+1 -and ![IO.File]::Exists($other)) 'Instala só selecionado; outro ausente intocado'
  $r=Install-MissingFfmpegTools -RootDirectory $root -Architecture 'X64' -Invoker $invoker -RequestedTools @($tool)
  Assert ($r.targets.Count -eq 1 -and $r.targets[0].status -ceq 'preserved' -and $script:selectionDownloads -eq $before+1) 'Selecionado existente sem download apesar do outro ausente'
  [IO.File]::Delete($target)
 }
 $r=Install-MissingFfmpegTools -RootDirectory $root -Architecture 'X64' -Invoker $invoker -RequestedTools @('ffprobe','ffmpeg')
 Assert ($r.targets.Count -eq 2 -and $r.targets[0].tool -ceq 'ffmpeg' -and $r.targets[1].tool -ceq 'ffprobe') 'Seleção reversa retorna ordem canônica'
 $before=$script:selectionDownloads
 foreach($case in @(@{value=$null},@{value=@()},@{value='ffmpeg'},@{value=@('FFMPEG')},@{value=@('ffplay')},@{value=@('ffmpeg','ffmpeg')},@{value=@(123)})){
  $failed=$false;try{$null=Install-MissingFfmpegTools -RootDirectory $root -Architecture 'X64' -Invoker $invoker -RequestedTools $case.value}catch{$failed=$true}
  Assert ($failed -and $script:selectionDownloads -eq $before) 'Seleção inválida rejeitada antes rede'
 }
 Assert ([IO.File]::ReadAllText($sentinel) -ceq 'preservar' -and @([IO.Directory]::EnumerateFiles($root)).Count -eq 3) 'Sem efeitos em outros arquivos'
}finally{
 foreach($name in @('ffmpeg.exe','ffprobe.exe','keep.txt')){$path=Join-Path $root $name;if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
 [IO.Directory]::Delete($root,$false)
}
Write-Output "FFMPEG_SUITE_SELECTION_PASS checks=$checks; mocks sem rede/binario real"
