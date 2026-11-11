#requires -Version 7.0
. (Join-Path $PSScriptRoot 'consulta_tag_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'consulta_metadata_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'descritor_release_ffmpeg.ps1')
function Get-FfmpegReleaseDescriptor {
    param([AllowNull()][object]$Architecture,[ValidateRange(1,120)]
        [int]$TimeoutSeconds = 30,[System.Net.Http.HttpMessageHandler]$Handler = $null)
    if ($Architecture -isnot [string]) {
        throw [ArgumentException]::new('Architecture deve ser uma string.')
    }
    if ($Architecture -cne 'X64' -and $Architecture -cne 'Arm64') {
        throw [ArgumentException]::new('Architecture deve ser X64 ou Arm64.')
    }
    $tag=Get-FfmpegDatedReleaseTag -TimeoutSeconds $TimeoutSeconds -Handler $Handler
    $meta=Get-FfmpegReleaseMetadataDocument -Tag $tag -TimeoutSeconds $TimeoutSeconds -Handler $Handler
    $manifestBytes=Get-FfmpegReleaseDocumentBytes -Uri $meta.manifest_url -MaxBytes $meta.manifest_size -TimeoutSeconds $TimeoutSeconds -Handler $Handler
    return Resolve-FfmpegReleaseDescriptor -Json $meta.json -ExpectedTag $tag -ManifestBytes $manifestBytes -Architecture $Architecture
}
