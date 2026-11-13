#requires -Version 7.0
. (Join-Path $PSScriptRoot 'aquisicao_documentos_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'download_temporario_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'instalacao_executavel_ffmpeg.ps1')
function Install-MissingFfmpegTools {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)][AllowNull()][object]$RootDirectory,
        [Parameter(Position=1)][AllowNull()][object]$Architecture,
        [Parameter(Position=2)][AllowNull()][object]$Invoker,
        [Parameter(Position=3)]
        [ValidateRange(1,120)]
        [int]$DocumentTimeoutSeconds = 30,
        [Parameter(Position=4)]
        [ValidateRange(1,300)]
        [int]$TimeoutSeconds = 120,
        [Parameter(Position=5)]
        [System.Net.Http.HttpMessageHandler]$Handler = $null,
        [Parameter(Position=6)]
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )
    if ($null -eq $RootDirectory) { throw "RootDirectory não pode ser nulo." }
    if ($RootDirectory -isnot [string]) { throw "RootDirectory deve ser uma string." }
    if ([string]::IsNullOrEmpty($RootDirectory)) { throw "RootDirectory não pode ser vazio." }
    if (-not [IO.Path]::IsPathFullyQualified($RootDirectory)) { throw "RootDirectory deve ser um caminho totalmente qualificado." }
    if ($null -eq $Architecture) { throw "Architecture não pode ser nulo." }
    if ($Architecture -isnot [string]) { throw "Architecture deve ser uma string." }
    if ($Architecture -cnotin @('X64','Arm64')) { throw "Architecture deve ser 'X64' ou 'Arm64' (case-sensitive)." }
    if ($null -eq $Invoker) { throw "Invoker não pode ser nulo." }
    if ($Invoker -isnot [scriptblock]) { throw "Invoker deve ser um scriptblock." }
    $CancellationToken.ThrowIfCancellationRequested()
    $rootItem = Get-Item -LiteralPath $RootDirectory -ErrorAction Stop
    if ($rootItem -isnot [IO.DirectoryInfo]) { throw "RootDirectory deve ser diretório." }
    $rootPath = $rootItem.FullName
    $targets = @()
    $missing = @()
    foreach ($tool in @('ffmpeg','ffprobe')) {
        $path = Join-Path $rootPath ($tool + '.exe')
        if ([IO.Directory]::Exists($path)) {
            throw "O caminho especificado é um diretório, não um arquivo: $path"
        }
        if ([IO.File]::Exists($path)) {
            $targets += @{status='preserved'; tool=$tool; target_path=$path}
        } else {
            $missing += $tool
        }
    }
    $CancellationToken.ThrowIfCancellationRequested()
    if ($missing.Count -eq 0) {
        return @{root_path=$rootPath; targets=$targets}
    }
    $CancellationToken.ThrowIfCancellationRequested()
    $descriptor = Get-FfmpegReleaseDescriptor -Architecture $Architecture -TimeoutSeconds $DocumentTimeoutSeconds -Handler $Handler
    $CancellationToken.ThrowIfCancellationRequested()

    $plan = $descriptor.release_plan
    $expectedRoot = [IO.Path]::GetFileNameWithoutExtension($plan.asset_name)

    $receipt = Invoke-WithFfmpegDownloadedArchive -RootDirectory $rootPath -Uri $plan.url -ExpectedSize $descriptor.archive_size -ExpectedSha256 $plan.sha256 -TimeoutSeconds $TimeoutSeconds -Handler $Handler -CancellationToken $CancellationToken -Action {
        param($stream, $downloadReceipt)

        $localTargets = @()
        foreach ($tool in $missing) {
            $CancellationToken.ThrowIfCancellationRequested()
            $receipt = Install-FfmpegArchiveExecutable -RootDirectory $rootPath -ArchiveStream $stream -ExpectedRootDirectory $expectedRoot -Tool $tool -ExpectedBuildVersion $plan.build_version -Invoker $Invoker -TimeoutSeconds $TimeoutSeconds -CancellationToken $CancellationToken
            $localTargets += $receipt
        }
        return $localTargets
    }

    $installed = $receipt
    $allTargets = @()
    foreach ($t in $targets) {
        if ($t.status -eq 'preserved') {
            $allTargets += $t
        }
    }
    foreach ($t in $installed) {
        $allTargets += $t
    }

    return @{root_path=$rootPath; targets=$allTargets}
}


