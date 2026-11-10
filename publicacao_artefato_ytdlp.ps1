#requires -Version 7.0
. (Join-Path $PSScriptRoot 'plano_release_ytdlp.ps1')

function Publish-YtdlpReleaseArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][string]$Tag,
        [Parameter(Mandatory=$true)][string]$Manifest,
        [Parameter(Mandatory=$true)][string]$Architecture
    )

    if (-not [IO.Directory]::Exists($Root)) {
        throw [System.IO.DirectoryNotFoundException]::new("Root deve existir: $Root")
    }

    $plan = New-YtdlpReleasePlan -Tag $Tag -Manifest $Manifest -Architecture $Architecture

    if (-not [IO.File]::Exists($SourcePath)) {
        throw [System.IO.FileNotFoundException]::new("Fonte não encontrada: $SourcePath")
    }

    $sourceHash = $null
    $sourceStream = $null
    # artifact-resources-repaired-v1: trava unica da fonte, propriedade e disposal explicitos.
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $sourceStream = [IO.File]::Open($SourcePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $sourceHash = $hasher.ComputeHash($sourceStream)
        $sourceHashStr = [BitConverter]::ToString($sourceHash).Replace('-', '').ToLowerInvariant()

    if ($sourceHashStr -cne $plan.sha256) {
        throw [ArgumentException]::new("Hash da fonte não corresponde ao plano.")
    }

    $targetPath = Join-Path $Root 'yt-dlp.exe'

    if ([IO.File]::Exists($targetPath)) {
        $existingStream = [IO.File]::OpenRead($targetPath)
        try { $existingHash = $hasher.ComputeHash($existingStream) }
        finally { $existingStream.Dispose() }
        $existingHashStr = [BitConverter]::ToString($existingHash).Replace('-', '').ToLowerInvariant()
        if ($existingHashStr -ceq $sourceHashStr) {
            return @{
                status = 'existing'
                target_path = [IO.Path]::GetFullPath($targetPath)
                sha256 = $sourceHashStr
                release_plan = $plan
            }
        } else {
            throw [System.IO.IOException]::new("Destino divergente: $targetPath")
        }
    } elseif ([IO.Directory]::Exists($targetPath)) {
        throw [System.IO.IOException]::new("Destino é diretório: $targetPath")
    }

    $tempPath = $null
    $tempStream = $null
    $tempOwned = $false
    try {
        $tempPath = Join-Path $Root ('.yt-dlp.' + [guid]::NewGuid().ToString('N') + '.tmp')

        $sourceStream.Position = 0
        $tempStream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $tempOwned = $true

        $sourceStream.CopyTo($tempStream)
        $tempStream.Flush($true)
        $tempStream.Position = 0

        $tempHash = $hasher.ComputeHash($tempStream)
        $tempHashStr = [BitConverter]::ToString($tempHash).Replace('-', '').ToLowerInvariant()

        if ($tempHashStr -cne $sourceHashStr) {
            throw [System.IO.IOException]::new("Hash do temporário diverge da fonte.")
        }
    } catch {
        if ($null -ne $tempStream) { $tempStream.Dispose() }
        if ($tempOwned -and $null -ne $tempPath -and [IO.File]::Exists($tempPath)) {
            try { [IO.File]::Delete($tempPath) } catch { }
        }
        throw
    }

    if ($null -ne $tempStream) { $tempStream.Dispose() }

    try {
        [IO.File]::Move($tempPath, $targetPath)
    } catch {
        if ($tempOwned -and $null -ne $tempPath -and [IO.File]::Exists($tempPath)) {
            try { [IO.File]::Delete($tempPath) } catch { }
        }
        throw
    }

    return @{
        status = 'published'
        target_path = [IO.Path]::GetFullPath($targetPath)
        sha256 = $sourceHashStr
        release_plan = $plan
    }
    } finally {
        if ($null -ne $sourceStream) { $sourceStream.Dispose() }
        $hasher.Dispose()
    }
}
