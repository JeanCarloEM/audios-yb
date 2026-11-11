#requires -Version 7.0
. (Join-Path $PSScriptRoot 'transporte_documentos_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'selecao_release_ffmpeg.ps1')

function Get-FfmpegDatedReleaseTag {
    [CmdletBinding()]
    param(
        [ValidateRange(1,120)]
        [int]$TimeoutSeconds = 30,
        [System.Net.Http.HttpMessageHandler]$Handler = $null
    )

    $bytes = Get-FfmpegReleaseDocumentBytes -Uri 'https://api.github.com/repos/FFmpeg-Builds/FFmpeg-Builds/releases?per_page=3' -MaxBytes 2097152 -TimeoutSeconds $TimeoutSeconds -Handler $Handler
    $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    return Select-FfmpegDatedRelease -Json $text
}
