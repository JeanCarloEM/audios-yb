#requires -Version 7.0
. (Join-Path $PSScriptRoot 'candidato_extraido_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'publicacao_candidato_ffmpeg.ps1')
function Install-FfmpegArchiveExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][AllowNull()][object]$RootDirectory,
        [Parameter(Position=1)][AllowNull()][object]$ArchiveStream,
        [Parameter(Position=2)][AllowNull()][object]$ExpectedRootDirectory,
        [Parameter(Position=3)][AllowNull()][object]$Tool,
        [Parameter(Position=4)][AllowNull()][object]$ExpectedBuildVersion,
        [Parameter(Position=5)][AllowNull()][object]$Invoker,
        [ValidateRange(1,300)]
        [int]$TimeoutSeconds = 120,
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )
    if ($Tool -isnot [string] -or $Tool -cnotin @('ffmpeg','ffprobe')) {
        throw 'Tool deve ser "ffmpeg" ou "ffprobe".'
    }
    if ($Invoker -isnot [scriptblock]) {
        throw 'Invoker deve ser scriptblock.'
    }
    if ($ExpectedBuildVersion -isnot [string] -or $ExpectedBuildVersion.Length -gt 160 -or $ExpectedBuildVersion -cnotmatch '\An[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9]+-g[0-9a-f]{7,40})?\z') {
        throw 'ExpectedBuildVersion deve ser string <=160 chars com formato válido.'
    }
    $CancellationToken.ThrowIfCancellationRequested()
    $installArchiveRoot = $RootDirectory
    $installArchiveArchive = $ArchiveStream
    $installArchiveExpectedRoot = $ExpectedRootDirectory
    $installArchiveTool = $Tool
    $installArchiveBuild = $ExpectedBuildVersion
    $installArchiveInvoker = $Invoker
    $installArchiveSeconds = $TimeoutSeconds
    $installArchiveToken = $CancellationToken
    $receipt = Invoke-WithExtractedFfmpegCandidate -RootDirectory $installArchiveRoot -ArchiveStream $installArchiveArchive -ExpectedRootDirectory $installArchiveExpectedRoot -Tool $installArchiveTool -TimeoutSeconds $installArchiveSeconds -CancellationToken $installArchiveToken -Action {
        param($candidatePath, $copyReceipt)
        Publish-VerifiedFfmpegCandidate -RootDirectory $installArchiveRoot -Path $candidatePath -Tool $installArchiveTool -ExpectedSize $copyReceipt.size -ExpectedSha256 $copyReceipt.sha256 -ExpectedBuildVersion $installArchiveBuild -Invoker $installArchiveInvoker -TimeoutSeconds $installArchiveSeconds -CancellationToken $installArchiveToken
    }
    return $receipt
}
