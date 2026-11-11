#requires -Version 7.0
. (Join-Path $PSScriptRoot 'indice_artefatos_ffmpeg.ps1')
function Read-FfmpegManifestDescriptor {
    param([AllowNull()][object]$Json,[AllowNull()][object]$ExpectedTag)
    $index=Read-FfmpegAssetIndex -Json $Json
    if($ExpectedTag -isnot [string] -or $ExpectedTag -cne $index.release_tag){throw [ArgumentException]::new('Tag recebida diverge da solicitada')}
    $manifest=@($index.assets|Where-Object {$_.name -ceq 'checksums.sha256'})
    if($manifest.Count -ne 1 -or $manifest[0].size -lt 1 -or $manifest[0].size -gt 1048576 -or $manifest[0].sha256 -isnot [string]){throw [ArgumentException]::new('Descritor do manifesto ausente/incompleto/fora do limite')}
    return @{json=$Json;manifest_size=$manifest[0].size;manifest_sha256=$manifest[0].sha256;manifest_url=('https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/'+$index.release_tag+'/checksums.sha256')}
}
