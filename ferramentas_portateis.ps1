#requires -Version 7.0
# Descoberta e preflight sem alteracao de arquivos do lote.
function Find-YtdlpExecutable {
    [CmdletBinding()]
    param(
        [string]$Root,
        [ValidateSet('Windows','Linux','macOS','Other')][string]$Platform = $(if($IsWindows){'Windows'}elseif($IsMacOS){'macOS'}elseif($IsLinux){'Linux'}else{'Other'}),
        [Runtime.InteropServices.Architecture]$Architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    )
    $rootPath=[IO.Path]::GetFullPath($Root)
    if($Platform -eq 'Windows'){
        $exe=Join-Path $rootPath 'yt-dlp.exe'
        if(-not [IO.File]::Exists($exe)){throw "yt-dlp.exe ausente junto ao script: $exe"}
        return $exe
    }
    $names=@('yt-dlp')
    if($Platform -eq 'macOS'){$names=@('yt-dlp_macos','yt-dlp')}
    elseif($Platform -eq 'Linux'){
        if($Architecture -eq [Runtime.InteropServices.Architecture]::X64){$names=@('yt-dlp_linux','yt-dlp')}
        elseif($Architecture -eq [Runtime.InteropServices.Architecture]::Arm64){$names=@('yt-dlp_linux_aarch64','yt-dlp')}
    }
    foreach($name in $names){
        $candidate=Join-Path $rootPath $name
        if([IO.File]::Exists($candidate)){return $candidate}
    }
    $found=@(Get-Command -Name 'yt-dlp' -CommandType Application -ErrorAction SilentlyContinue)
    if($found.Count -gt 0 -and [IO.File]::Exists($found[0].Path)){return [IO.Path]::GetFullPath($found[0].Path)}
    throw ('yt-dlp nativo ausente; sistema='+$Platform+'; arquitetura='+$Architecture+'; procurar '+($names -join ', ')+' junto ao script ou yt-dlp no PATH')
}

function Resolve-ScriptTools([string]$Root, [switch]$BootstrapYtdlp, [switch]$BootstrapFfmpeg) {
    # tool-inventory-resolver-integrated-v1: coleta todas as ausencias antes do diagnostico.
    $inventory=Get-ScriptToolInventory -Root $Root
    # resolver-ytdlp-bootstrap-v1: instalador local explicito, somente na ausencia do yt-dlp.
    $bootstrap=$null
    if($BootstrapYtdlp -and $IsWindows -and $inventory.tools.Exe -ceq ''){
        $moduleRoot=Split-Path -Parent $MyInvocation.MyCommand.ScriptBlock.File
        . (Join-Path $moduleRoot 'instalacao_ytdlp.ps1')
        $bootstrap=Install-YtdlpDependency -Root $Root
        $inventory=Get-ScriptToolInventory -Root $Root
    }
    # resolver-ffmpeg-bootstrap-v1: instalador local explicito, somente na ausencia de ffmpeg/ffprobe.
    $ffmpegBootstrap=$null
    if($BootstrapFfmpeg -and $IsWindows -and ($inventory.tools.Ffmpeg -ceq '' -or $inventory.tools.Ffprobe -ceq '')){
        $moduleRoot=Split-Path -Parent $MyInvocation.MyCommand.ScriptBlock.File
        . (Join-Path $moduleRoot 'instalacao_ffmpeg.ps1')
        $requested=@()
        if($inventory.tools.Ffmpeg -ceq ''){$requested+='ffmpeg'}
        if($inventory.tools.Ffprobe -ceq ''){$requested+='ffprobe'}
        $ffmpegBootstrap=Install-MissingFfmpegTools -RootDirectory ([IO.Path]::GetFullPath($Root)) -Architecture ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) -RequestedTools $requested -Invoker {param($candidatePath,$versionArguments,$versionSeconds) Invoke-Ytdlp -Executable $candidatePath -Arguments $versionArguments -TimeoutSeconds $versionSeconds}
        $inventory=Get-ScriptToolInventory -Root $Root
    }
    if($inventory.required_missing.Count -gt 0){
        $names=@{Exe='yt-dlp';Ffmpeg='ffmpeg';Ffprobe='ffprobe'}
        $absent=@($inventory.required_missing|ForEach-Object {$names[$_]})
        throw ('Ferramentas obrigatorias ausentes: '+($absent -join ', ')+'.')
    }
    if($null -ne $bootstrap){$inventory.tools.YtdlpBootstrap=$bootstrap}
    if($null -ne $ffmpegBootstrap){$inventory.tools.FfmpegBootstrap=$ffmpegBootstrap}
    return $inventory.tools
}
function Test-ScriptTools([hashtable]$Tools) {
    $versions=@{}
    foreach($key in @('Exe','Ffmpeg','Ffprobe')){
        $path=[string]$Tools[$key]
        try {
            if(-not [IO.File]::Exists($path)){throw 'arquivo executavel ausente'}
            if($key -eq 'Exe' -and -not $IsWindows){
                $stream=[IO.File]::OpenRead($path)
                try{$windowsPE=($stream.ReadByte() -eq 77 -and $stream.ReadByte() -eq 90)}finally{$stream.Dispose()}
                if($windowsPE){throw 'Executavel Windows PE nao e nativo deste sistema. Use yt-dlp nativo compativel com o sistema, arquitetura e permissoes de execucao.'}
            }
            $arguments=if($key -eq 'Exe'){@('--ignore-config','--no-plugin-dirs','--version')}else{@('-version')}
            $run=Invoke-Ytdlp -Arguments $arguments -TimeoutSeconds 15 -Executable $path
            if($run.timeout -or $run.code -ne 0){throw ("exit="+$run.code+"; timeout="+$run.timeout+"; "+$run.err)}
            $line=@($run.out -split '\r?\n'|Where-Object {-not [string]::IsNullOrWhiteSpace($_)}|Select-Object -First 1)
            if($line.Count -eq 0){throw 'saida de versao vazia'}
            $versions[$key]=$line[0]
        } catch {
            throw ("Ferramenta "+$key+" incompativel ou indisponivel; OS="+[Runtime.InteropServices.RuntimeInformation]::OSDescription+"; Arch="+[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture+"; Path="+$path+"; "+$_.Exception.Message)
        }
    }
    return $versions
}
function Get-ScriptToolInventory {
    [CmdletBinding()]
    param(
        [parameter(Mandatory)][string]$Root,
        [ValidateSet('Windows','Linux','macOS','Other')][string]$Platform = $(if($IsWindows){'Windows'}elseif($IsMacOS){'macOS'}elseif($IsLinux){'Linux'}else{'Other'}),
        [Runtime.InteropServices.Architecture]$Architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    )
    if([string]::IsNullOrWhiteSpace($Root)){throw 'Root não pode ser vazio ou whitespace'}
    $rootPath=[IO.Path]::GetFullPath($Root)
    $tools=@{Exe='';Ffmpeg='';Ffprobe='';Node=''}
    $missing=New-Object System.Collections.Generic.List[string]
    $required_missing=New-Object System.Collections.Generic.List[string]
    # inventory-discovery-repaired-v1: regras de nomes da descoberta canonica, sem executar binarios.
    $names=@('yt-dlp')
    if($Platform -eq 'Windows'){$names=@('yt-dlp.exe')}
    elseif($Platform -eq 'macOS'){$names=@('yt-dlp_macos','yt-dlp')}
    elseif($Platform -eq 'Linux'){
        if($Architecture -eq [Runtime.InteropServices.Architecture]::X64){$names=@('yt-dlp_linux','yt-dlp')}
        elseif($Architecture -eq [Runtime.InteropServices.Architecture]::Arm64){$names=@('yt-dlp_linux_aarch64','yt-dlp')}
    }
    foreach($name in $names){
        $candidate=Join-Path $rootPath $name
        if([IO.File]::Exists($candidate)){$tools.Exe=$candidate;break}
    }
    if($tools.Exe -ceq '' -and $Platform -ne 'Windows'){
        $found=@(Get-Command -Name 'yt-dlp' -CommandType Application -ErrorAction SilentlyContinue)
        if($found.Count -gt 0 -and [IO.File]::Exists($found[0].Path)){$tools.Exe=[IO.Path]::GetFullPath($found[0].Path)}
    }
    if($tools.Exe -ceq ''){$missing.Add('Exe');$required_missing.Add('Exe')}
    foreach($entry in @(@('Ffmpeg','ffmpeg'),@('Ffprobe','ffprobe'),@('Node','node'))){
        $native=if($Platform -eq 'Windows'){$entry[1]+'.exe'}else{$entry[1]}
        $local=Join-Path $rootPath $native
        if([IO.File]::Exists($local)){$tools[$entry[0]]=$local}
        else{
            $found=@(Get-Command -Name $entry[1] -CommandType Application -ErrorAction SilentlyContinue)
            if($found.Count -gt 0 -and [IO.File]::Exists($found[0].Path)){$tools[$entry[0]]=[IO.Path]::GetFullPath($found[0].Path)}
            else{$missing.Add($entry[0]);if($entry[0] -ne 'Node'){$required_missing.Add($entry[0])}}}
    }
    return @{
        tools=$tools
        missing=$missing
        required_missing=$required_missing
        execution_checked=$false
        integrity_checked=$false
    }
}
