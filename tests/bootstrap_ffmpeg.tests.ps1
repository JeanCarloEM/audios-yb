#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$work=Join-Path $PSScriptRoot ('.runtime-ffmpeg-bootstrap-['+[guid]::NewGuid().ToString('N')+']')
$moduleRoot=Join-Path $work 'module';$external=Join-Path $work 'external'
[void][IO.Directory]::CreateDirectory($moduleRoot);[void][IO.Directory]::CreateDirectory($external)
[IO.File]::Copy((Join-Path $repo 'ferramentas_portateis.ps1'),(Join-Path $moduleRoot 'ferramentas_portateis.ps1'))
$fake=@'
function Install-MissingFfmpegTools {
 param($RootDirectory,$Architecture,$Invoker,$RequestedTools)
 $global:FfmpegResolverProbe.Calls+=,@{root=$RootDirectory;architecture=$Architecture;requested=@($RequestedTools)}
 if($global:FfmpegResolverProbe.Fail){throw 'fixture-installer-failure'}
 foreach($tool in $RequestedTools){
  $path=Join-Path $RootDirectory ($tool+'.exe');$r=& $Invoker $path ([string[]]@('-version')) 15
  if($r.code -ne 0 -or $r.timeout){throw 'Adapter inválido'}
  if(!$global:FfmpegResolverProbe.SkipWrite){[IO.File]::WriteAllText($path,'fixture-'+$tool)}
 }
 return @{root_path=$RootDirectory;targets=@($RequestedTools|ForEach-Object {@{tool=$_;status='published'}})}
}
'@
[IO.File]::WriteAllText((Join-Path $moduleRoot 'instalacao_ffmpeg.ps1'),$fake)
. (Join-Path $moduleRoot 'ferramentas_portateis.ps1')
$checks=0;$cases=[Collections.Generic.List[string]]::new();$script:resolverPath=@{}
function Assert($ok,$why){if(!$ok){throw $why};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Operação deveria falhar'}
function Get-Command {param($Name,$CommandType,$ErrorAction) if($script:resolverPath.ContainsKey($Name)){return [pscustomobject]@{Path=$script:resolverPath[$Name]}}}
function Invoke-Ytdlp {
 param($Arguments,$TimeoutSeconds,$Executable)
 $global:FfmpegResolverProbe.Invocations+=,@{path=$Executable;arguments=@($Arguments);seconds=$TimeoutSeconds}
 return @{code=0;timeout=$false;out='fixture';err=''}
}
function New-Case($name){
 $path=Join-Path $work $name;[void][IO.Directory]::CreateDirectory($path);$cases.Add($path)
 [IO.File]::WriteAllText((Join-Path $path 'yt-dlp.exe'),'fixture-ytdlp')
 $global:FfmpegResolverProbe=@{Calls=@();Invocations=@();Fail=$false;SkipWrite=$false};$script:resolverPath=@{}
 return $path
}
try{
 $root=New-Case 'default-off';MustFail {Resolve-ScriptTools -Root $root}
 Assert ($global:FfmpegResolverProbe.Calls.Count -eq 0) 'Bootstrap deve exigir switch'
 $root=New-Case 'both-missing';$r=Resolve-ScriptTools -Root $root -BootstrapFfmpeg
 Assert ($global:FfmpegResolverProbe.Calls.Count -eq 1 -and ($global:FfmpegResolverProbe.Calls[0].requested -join ',') -ceq 'ffmpeg,ffprobe' -and $global:FfmpegResolverProbe.Calls[0].root -ceq $root -and $global:FfmpegResolverProbe.Calls[0].architecture -ceq [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) 'Uma chamada, seleção e arquitetura reais'
 Assert ($r.Ffmpeg -ceq (Join-Path $root 'ffmpeg.exe') -and $r.Ffprobe -ceq (Join-Path $root 'ffprobe.exe') -and $r.ContainsKey('FfmpegBootstrap') -and $r.Exe -ceq (Join-Path $root 'yt-dlp.exe')) 'Redescoberta e recibo sem perder campos'
 Assert ($global:FfmpegResolverProbe.Invocations.Count -eq 2 -and $global:FfmpegResolverProbe.Invocations[0].path -ceq $r.Ffmpeg -and $global:FfmpegResolverProbe.Invocations[0].seconds -eq 15 -and ($global:FfmpegResolverProbe.Invocations[0].arguments -join ',') -ceq '-version' -and $global:FfmpegResolverProbe.Invocations[1].path -ceq $r.Ffprobe) 'Adapter usa Invoke-Ytdlp sem execução real'
 $root=New-Case 'existing';foreach($tool in @('ffmpeg','ffprobe')){[IO.File]::WriteAllText((Join-Path $root ($tool+'.exe')),'original')};$r=Resolve-ScriptTools -Root $root -BootstrapFfmpeg
 Assert ($global:FfmpegResolverProbe.Calls.Count -eq 0 -and !$r.ContainsKey('FfmpegBootstrap') -and [IO.File]::ReadAllText($r.Ffmpeg) -ceq 'original' -and [IO.File]::ReadAllText($r.Ffprobe) -ceq 'original') 'Existentes não são atualizados'
 $root=New-Case 'probe-on-path';$externalProbe=Join-Path $external 'ffprobe.exe';[IO.File]::WriteAllText($externalProbe,'original-path');$script:resolverPath.ffprobe=$externalProbe
 $r=Resolve-ScriptTools -Root $root -BootstrapFfmpeg
 Assert (($global:FfmpegResolverProbe.Calls[0].requested -join ',') -ceq 'ffmpeg' -and $r.Ffprobe -ceq $externalProbe -and ![IO.File]::Exists((Join-Path $root 'ffprobe.exe')) -and [IO.File]::ReadAllText($externalProbe) -ceq 'original-path') 'PATH preservado sem instalação adjacente redundante'
 $root=New-Case 'only-probe';[IO.File]::WriteAllText((Join-Path $root 'ffmpeg.exe'),'original');$r=Resolve-ScriptTools -Root $root -BootstrapFfmpeg
 Assert (($global:FfmpegResolverProbe.Calls[0].requested -join ',') -ceq 'ffprobe' -and [IO.File]::ReadAllText($r.Ffmpeg) -ceq 'original') 'Seleção simétrica'
 $root=New-Case 'failure';$global:FfmpegResolverProbe.Fail=$true;MustFail {Resolve-ScriptTools -Root $root -BootstrapFfmpeg}
 Assert ($global:FfmpegResolverProbe.Calls.Count -eq 1) 'Falha propagada sem retry'
 $root=New-Case 'no-file';$global:FfmpegResolverProbe.SkipWrite=$true;MustFail {Resolve-ScriptTools -Root $root -BootstrapFfmpeg}
 Assert ($global:FfmpegResolverProbe.Calls.Count -eq 1) 'Recibo sem arquivo não basta'
}finally{
 foreach($path in $cases){foreach($name in @('yt-dlp.exe','ffmpeg.exe','ffprobe.exe')){$file=Join-Path $path $name;if([IO.File]::Exists($file)){[IO.File]::Delete($file)}};[IO.Directory]::Delete($path,$false)}
 foreach($name in @('ferramentas_portateis.ps1','instalacao_ffmpeg.ps1')){$file=Join-Path $moduleRoot $name;if([IO.File]::Exists($file)){[IO.File]::Delete($file)}}
 $file=Join-Path $external 'ffprobe.exe';if([IO.File]::Exists($file)){[IO.File]::Delete($file)}
 [IO.Directory]::Delete($moduleRoot,$false);[IO.Directory]::Delete($external,$false);[IO.Directory]::Delete($work,$false)
}
Write-Output "FFMPEG_BOOTSTRAP_RESOLVER_PASS checks=$checks; instalador/invoker/PATH simulados, IO real, sem rede/binario real"
