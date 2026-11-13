#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'instalacao_ffmpeg.ps1')
$script:preflightNetworkCalls=0;$checks=0
function Get-FfmpegReleaseDescriptor {$script:preflightNetworkCalls++;throw 'Rede indevida'}
function Invoke-WithFfmpegDownloadedArchive {$script:preflightNetworkCalls++;throw 'Download indevido'}
function Reject([hashtable]$parameters){
 $failed=$false
 try{$null=Install-MissingFfmpegTools @parameters}catch{$failed=$true}
 if(!$failed -or $script:preflightNetworkCalls -ne 0){throw ('Entrada não rejeitada antes rede: '+($parameters|Out-String))}
 $script:checks++
}
$root=Join-Path $PSScriptRoot ('.runtime-suite-preflight-['+[guid]::NewGuid().ToString('N')+']')
[void][IO.Directory]::CreateDirectory($root)
$sentinel=Join-Path $root 'keep.txt';[IO.File]::WriteAllText($sentinel,'preservar')
$validInvoker={throw 'Invocação indevida'}
$ffmpeg=Join-Path $root 'ffmpeg.exe';$ffprobe=Join-Path $root 'ffprobe.exe'
try{
 Reject @{RootDirectory='.';Architecture='X64';Invoker=$validInvoker}
 Reject @{RootDirectory=$null;Architecture='X64';Invoker=$validInvoker}
 Reject @{RootDirectory=123;Architecture='X64';Invoker=$validInvoker}
 Reject @{RootDirectory=$sentinel;Architecture='X64';Invoker=$validInvoker}
 Reject @{RootDirectory=$root;Architecture='x64';Invoker=$validInvoker}
 Reject @{RootDirectory=$root;Architecture=$null;Invoker=$validInvoker}
 Reject @{RootDirectory=$root;Architecture='X64';Invoker=$null}
 Reject @{RootDirectory=$root;Architecture='X64';Invoker='script inválido'}
 Reject @{RootDirectory=$root;Architecture='X64';Invoker=$validInvoker;DocumentTimeoutSeconds=0}
 Reject @{RootDirectory=$root;Architecture='X64';Invoker=$validInvoker;TimeoutSeconds=301}
 [void][IO.Directory]::CreateDirectory($ffprobe)
 try{Reject @{RootDirectory=$root;Architecture='X64';Invoker=$validInvoker}}finally{[IO.Directory]::Delete($ffprobe,$false)}
 [IO.File]::WriteAllText($ffmpeg,'original');[IO.File]::WriteAllText($ffprobe,'original-probe')
 $cts=[Threading.CancellationTokenSource]::new()
 try{
  $cts.Cancel();$canceled=$false
  try{$null=Install-MissingFfmpegTools -RootDirectory $root -Architecture 'X64' -Invoker $validInvoker -CancellationToken $cts.Token}catch{if($_.Exception.GetBaseException() -is [OperationCanceledException]){$canceled=$true}else{throw}}
  if(!$canceled -or $script:preflightNetworkCalls -ne 0){throw 'Cancelamento prévio deve preceder retorno preserved/rede'};$checks++
 }finally{$cts.Dispose()}
 $r=Install-MissingFfmpegTools -RootDirectory $root -Architecture 'X64' -Invoker $validInvoker
 if($r.root_path -cne $root -or @($r.targets).Count -ne 2 -or $r.targets[0].status -cne 'preserved' -or $r.targets[1].status -cne 'preserved' -or $script:preflightNetworkCalls -ne 0 -or [IO.File]::ReadAllText($ffmpeg) -cne 'original' -or [IO.File]::ReadAllText($ffprobe) -cne 'original-probe' -or [IO.File]::ReadAllText($sentinel) -cne 'preservar'){throw 'Preservação falhou'};$checks++
 $normalized=Install-MissingFfmpegTools -RootDirectory ($root+'/.') -Architecture 'X64' -Invoker $validInvoker
 if($normalized.root_path -cne $root -or $normalized.targets[0].target_path -cne $ffmpeg -or $normalized.targets[1].target_path -cne $ffprobe -or $script:preflightNetworkCalls -ne 0){throw 'Root deve usar FullName literal normalizado'};$checks++
}finally{
 foreach($name in @('ffmpeg.exe','ffprobe.exe','keep.txt')){$path=Join-Path $root $name;if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}
 [IO.Directory]::Delete($root,$false)
}
Write-Output "FFMPEG_SUITE_PREFLIGHT_PASS checks=$checks; network_calls=$script:preflightNetworkCalls"
