#requires -Version 7.0
function ConvertFrom-FfmpegAssetName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [AllowNull()][AllowEmptyString()][object]$Name,
        [Parameter(Mandatory=$true)]
        [AllowNull()][AllowEmptyString()][object]$Architecture
    )

    if ($Name -isnot [string] -or [string]::IsNullOrWhiteSpace($Name)) {
        throw [ArgumentException]::new('Name deve ser uma string não vazia.')
    }
    if ($Name.Length -gt 255) {
        throw [ArgumentException]::new('Name não pode exceder 255 caracteres.')
    }

    if ($Architecture -isnot [string]) {
        throw [ArgumentException]::new('Architecture deve ser uma string.')
    }

    $platform = switch -CaseSensitive ($Architecture) {
        'X64' { 'win64' }
        'Arm64' { 'winarm64' }
        default { throw [ArgumentException]::new('Architecture deve ser X64 ou Arm64.') }
    }

    $pattern = '\Affmpeg-(?<build>n(?<buildbranch>[1-9][0-9]*\.[0-9]+)\.[0-9]+(?:-[0-9]+-g[0-9a-f]{7,40})?)-(?<platform>win64|winarm64)-lgpl-(?<branch>[1-9][0-9]*\.[0-9]+)\.zip\z'
    $match = [regex]::Match($Name, $pattern)

    if (-not $match.Success) {
        return $null
    }


    $buildBranch = $match.Groups['buildbranch'].Value
    $branch = $match.Groups['branch'].Value

    if ($branch.Length -gt 32) {
        throw [FormatException]::new('Release version excede 32 caracteres.')
    }

    $build = $match.Groups['build'].Value
    if ($build.Length -gt 96) {
        throw [FormatException]::new('Build version excede 96 caracteres.')
    }

    if ($buildBranch -cne $branch) {
        throw [FormatException]::new('Build branch diverge da release version.')
    }

    if ($match.Groups['platform'].Value -ne $platform) {
        return $null
    }

    return @{
        architecture = $Architecture
        release_version = $branch
        build_version = $build
        asset_name = $Name
    }
}
