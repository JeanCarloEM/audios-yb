#requires -Version 7.0
# Descoberta e preflight sem alteracao de arquivos do lote.
function Resolve-ScriptTools([string]$Root) {
    $rootPath=[IO.Path]::GetFullPath($Root)
    $tools=@{Exe=(Join-Path $rootPath 'yt-dlp.exe');Ffmpeg='';Ffprobe='';Node=''}
    if(-not [IO.File]::Exists($tools.Exe)){throw "yt-dlp.exe ausente junto ao script: $($tools.Exe)"}
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
                if($windowsPE){throw 'Executavel Windows PE nao e nativo deste sistema. E necessario binario nativo compativel denominado yt-dlp.exe.'}
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