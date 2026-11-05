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

function Resolve-ScriptTools([string]$Root) {
    $rootPath=[IO.Path]::GetFullPath($Root)
    $tools=@{Exe=(Find-YtdlpExecutable -Root $rootPath);Ffmpeg='';Ffprobe='';Node=''}
    foreach($entry in @(@('Ffmpeg','ffmpeg'),@('Ffprobe','ffprobe'),@('Node','node'))){
        $native=if($IsWindows){$entry[1]+'.exe'}else{$entry[1]}
        $local=Join-Path $rootPath $native
        if([IO.File]::Exists($local)){$tools[$entry[0]]=$local}
        else {
            $found=@(Get-Command -Name $entry[1] -CommandType Application -ErrorAction SilentlyContinue)
            if($found.Count -gt 0){$tools[$entry[0]]=[IO.Path]::GetFullPath($found[0].Path)}
        }
        if($entry[0] -ne 'Node' -and -not [IO.File]::Exists($tools[$entry[0]])){
            throw "Ferramenta obrigatoria $($entry[1]) ausente: pasta do script e PATH"
        }
    }
    return $tools
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