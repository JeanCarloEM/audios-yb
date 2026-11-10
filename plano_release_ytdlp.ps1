#requires -Version 7.0
. (Join-Path $PSScriptRoot 'manifesto_sha256.ps1')
# Plano calculado; nao comprova transporte, assinatura, autenticidade ou instalacao.
function New-YtdlpReleasePlan {
    [CmdletBinding()]
    param([AllowNull()][object]$Tag,[AllowNull()][object]$Manifest,[AllowNull()][object]$Architecture)
    if($Tag -isnot [string] -or $Tag -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z' -or $Tag.ToLowerInvariant() -in @('latest','stable','nightly','master')){
        throw [ArgumentException]::new('Tag literal de release obrigatoria; canal mutavel nao e uma versao.')
    }
    if($Architecture -isnot [string]){throw [ArgumentException]::new('Arquitetura Windows deve ser X64, X86 ou Arm64.')}
    $assets=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $assets.Add('X64','yt-dlp.exe');$assets.Add('X86','yt-dlp_x86.exe');$assets.Add('Arm64','yt-dlp_arm64.exe')
    if(-not $assets.ContainsKey($Architecture)){throw [ArgumentException]::new('Arquitetura Windows nao suportada neste plano.')}
    $asset=$assets[$Architecture]
    $hash=Get-ManifestAssetSha256 -Manifest $Manifest -AssetName $asset
    $base='https://github.com/yt-dlp/yt-dlp/releases/download/'+$Tag+'/'
    return @{
        tool='yt-dlp';platform='Windows';architecture=$Architecture;release_tag=$Tag
        asset_name=$asset;target_name='yt-dlp.exe';url=($base+$asset)
        manifest_url=($base+'SHA2-256SUMS');sha256=$hash
    }
}
