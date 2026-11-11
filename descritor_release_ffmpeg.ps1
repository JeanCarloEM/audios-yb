#requires -Version 7.0
. (Join-Path $PSScriptRoot 'indice_artefatos_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'selecao_artefato_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'plano_release_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'manifesto_ffmpeg_bytes.ps1')
# Vincula documentos; nao baixa/verifica bytesZIP nem comprova assinatura/origem.
function Resolve-FfmpegReleaseDescriptor {
    param([AllowNull()][object]$Json,[AllowNull()][object]$ExpectedTag,[AllowNull()][object]$ManifestBytes,[AllowNull()][object]$Architecture)
    $index=Read-FfmpegAssetIndex -Json $Json
    if($ExpectedTag -isnot [string] -or $ExpectedTag -cne $index.release_tag){throw [ArgumentException]::new('Tag recebida diverge da solicitada')}
    $manifest=@($index.assets|Where-Object {$_.name -ceq 'checksums.sha256'})
    if($manifest.Count -ne 1 -or $manifest[0].size -lt 1 -or $manifest[0].size -gt 1048576 -or $manifest[0].sha256 -isnot [string]){throw [ArgumentException]::new('Descritor do manifesto ausente/incompleto/fora do limite')}
    $checked=ConvertFrom-CheckedFfmpegManifest -Bytes $ManifestBytes -ExpectedSize $manifest[0].size -ExpectedSha256 $manifest[0].sha256
    $names=@($index.assets|ForEach-Object {$_.name})
    $candidate=Select-FfmpegAssetCandidate -Names $names -Architecture $Architecture
    $archive=@($index.assets|Where-Object {$_.name -ceq $candidate.asset_name})
    if($archive.Count -ne 1 -or $archive[0].size -lt 1 -or $archive[0].size -gt 536870912 -or $archive[0].sha256 -isnot [string]){throw [ArgumentException]::new('Descritor do ZIP ausente/incompleto/fora do limite')}
    $plan=New-FfmpegReleasePlan -Tag $index.release_tag -ReleaseVersion $candidate.release_version -BuildVersion $candidate.build_version -Manifest $checked.text -Architecture $Architecture
    if($plan.sha256 -cne $archive[0].sha256){throw [ArgumentException]::new('SHA256 do manifesto diverge do digestZIP publicado na API')}
    return @{release_plan=$plan;archive_size=$archive[0].size;manifest_size=$manifest[0].size;manifest_sha256=$checked.sha256}
}
