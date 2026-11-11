#requires -Version 7.0
. (Join-Path $PSScriptRoot 'manifesto_sha256.ps1')
# Plano calculado; nao comprova transporte, assinatura, autenticidade ou instalacao.
function New-FfmpegReleasePlan {
    [CmdletBinding()]
    param([AllowNull()][object]$Tag,[AllowNull()][object]$ReleaseVersion,[AllowNull()][object]$BuildVersion,[AllowNull()][object]$Manifest,[AllowNull()][object]$Architecture)
    if($Tag -isnot [string] -or $Tag -cnotmatch '\Aautobuild-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}\z'){
        throw [ArgumentException]::new('Tag deve ser autobuild-YYYY-MM-DD-HH-mm.')
    }
    $datePart=$Tag.Substring(10)
    $dt=[DateTime]::MinValue
    $culture=[System.Globalization.CultureInfo]::InvariantCulture
    $style=[System.Globalization.DateTimeStyles]::None
    if(-not [DateTime]::TryParseExact($datePart,'yyyy-MM-dd-HH-mm',$culture,$style,[ref]$dt)){
        throw [ArgumentException]::new('Data na tag deve ser valida no formato yyyy-MM-dd-HH-mm.')
    }
    if($ReleaseVersion -isnot [string] -or $ReleaseVersion -cnotmatch '\A[1-9][0-9]*\.[0-9]+\z' -or $ReleaseVersion.Length -gt 32){
        throw [ArgumentException]::new('ReleaseVersion deve ser numerico sem zero inicial, max 32 caracteres.')
    }
    $bvPattern='n'+[regex]::Escape($ReleaseVersion)+'\.[0-9]+(?:-[0-9]+-g[0-9a-f]{7,40})?'
    if($BuildVersion -isnot [string] -or $BuildVersion -cnotmatch ('\A'+$bvPattern+'\z') -or $BuildVersion.Length -gt 96){
        throw [ArgumentException]::new('BuildVersion deve seguir n<ReleaseVersion>.<rev>-<commits>-g<hash> ou n<ReleaseVersion>.<rev>, max 96 caracteres.')
    }
    if($Architecture -isnot [string]){throw [ArgumentException]::new('Arquitetura Windows deve ser X64 ou Arm64.')}
    $platforms=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $platforms.Add('X64','win64');$platforms.Add('Arm64','winarm64')
    if(-not $platforms.ContainsKey($Architecture)){throw [ArgumentException]::new('Arquitetura Windows nao suportada neste plano.')}
    $platform=$platforms[$Architecture]
    $asset='ffmpeg-'+$BuildVersion+'-'+$platform+'-lgpl-'+$ReleaseVersion+'.zip'
    $hash=Get-ManifestAssetSha256 -Manifest $Manifest -AssetName $asset
    $base='https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/'+$Tag+'/'
    return @{
        tool='ffmpeg-suite';platform='Windows';architecture=$Architecture;release_tag=$Tag
        release_version=$ReleaseVersion;build_version=$BuildVersion;asset_name=$asset
        url=($base+$asset);manifest_url=($base+'checksums.sha256');sha256=$hash
        targets=@('ffmpeg.exe','ffprobe.exe')
    }
}
