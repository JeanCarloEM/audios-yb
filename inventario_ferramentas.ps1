#requires -Version 7.0
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
