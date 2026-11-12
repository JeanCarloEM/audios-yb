#requires -Version 7.0
. (Join-Path $PSScriptRoot 'verificacao_candidato_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'publicacao_ffmpeg.ps1')

function Publish-VerifiedFfmpegCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [AllowNull()][object]$RootDirectory,
        [Parameter(Mandatory=$true, Position=1)]
        [AllowNull()][object]$Path,
        [Parameter(Mandatory=$true, Position=2)]
        [AllowNull()][object]$Tool,
        [Parameter(Mandatory=$true, Position=3)]
        [AllowNull()][object]$ExpectedSize,
        [Parameter(Mandatory=$true, Position=4)]
        [AllowNull()][object]$ExpectedSha256,
        [Parameter(Mandatory=$true, Position=5)]
        [AllowNull()][object]$ExpectedBuildVersion,
        [Parameter(Mandatory=$true, Position=6)]
        [AllowNull()][object]$Invoker,
        [ValidateRange(1,300)]
        [int]$TimeoutSeconds = 120,
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    if ($null -eq $RootDirectory -or $RootDirectory -isnot [string]) {
        throw [ArgumentException]::new('RootDirectory deve ser string não nula.', 'RootDirectory')
    }
    if (-not [IO.Path]::IsPathFullyQualified($RootDirectory)) {
        throw [ArgumentException]::new('RootDirectory deve ser totalmente qualificado.', 'RootDirectory')
    }
    $rootItem = Get-Item -LiteralPath $RootDirectory -ErrorAction Stop
    if ($rootItem -isnot [IO.DirectoryInfo]) {
        throw [ArgumentException]::new('RootDirectory deve ser diretório válido.', 'RootDirectory')
    }
    $RootDirectory = $rootItem.FullName

    $CancellationToken.ThrowIfCancellationRequested()

    Invoke-WithVerifiedFfmpegCandidate -Path $Path -ExpectedSize $ExpectedSize -ExpectedSha256 $ExpectedSha256 -Tool $Tool -ExpectedBuildVersion $ExpectedBuildVersion -Invoker $Invoker -Action {
        param($metadata, $lockedPath, $readStream)
        $result = Publish-FfmpegExecutable -RootDirectory $RootDirectory -SourceStream $readStream -Tool $Tool -ExpectedSize $ExpectedSize -ExpectedSha256 $ExpectedSha256 -TimeoutSeconds $TimeoutSeconds -CancellationToken $CancellationToken
        return @{
            status = $result.status
            target_path = $result.target_path
            size = $result.size
            sha256 = $result.sha256
            tool = $metadata.tool
            build_version = $metadata.build_version
            version_token = $metadata.version_token
        }
    }
}
