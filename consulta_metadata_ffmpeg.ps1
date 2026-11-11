#requires -Version 7.0
. (Join-Path $PSScriptRoot 'transporte_documentos_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'descritor_manifesto_ffmpeg.ps1')
function Get-FfmpegReleaseMetadataDocument {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Tag,
        [ValidateRange(1,120)][int]$TimeoutSeconds = 30,
        [System.Net.Http.HttpMessageHandler]$Handler = $null
    )
    if ($Tag -isnot [string] -or $Tag -cnotmatch '\Aautobuild-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}\z') {
        throw [ArgumentException]::new('Tag inválida')
    }
    $uri = 'https://api.github.com/repos/FFmpeg-Builds/FFmpeg-Builds/releases/tags/' + $Tag
    $bytes = Get-FfmpegReleaseDocumentBytes -Uri $uri -MaxBytes 2097152 -TimeoutSeconds $TimeoutSeconds -Handler $Handler
    $utf8 = [Text.UTF8Encoding]::new($false, $true)
    $json = $utf8.GetString($bytes)
    return Read-FfmpegManifestDescriptor -Json $json -ExpectedTag $Tag
}
