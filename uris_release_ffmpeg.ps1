#requires -Version 7.0
. (Join-Path $PSScriptRoot 'selecao_release_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'nome_artefato_ffmpeg.ps1')

function Test-FfmpegRequestUri {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Uri,
        [switch]$Redirect
    )

    try {
        if ($null -eq $Uri) {
            return $false
        }

        $uriString = $null
        if ($Uri -is [string]) {
            $uriString = $Uri
        } elseif ($Uri -is [uri]) {
            $uriString = $Uri.ToString()
        } else {
            return $false
        }

        if ([string]::IsNullOrWhiteSpace($uriString)) {
            return $false
        }

        if ($uriString.Length -gt 16384) {
            return $false
        }

        $uriObj = $null
        if (-not [uri]::TryCreate($uriString, [UriKind]::Absolute, [ref]$uriObj)) {
            return $false
        }

        if (-not $uriObj.IsAbsoluteUri) {
            return $false
        }

        if ($uriObj.Scheme -ne 'https') {
            return $false
        }

        if ($uriObj.Port -ne 443) {
            return $false
        }

        if ($uriObj.UserInfo.Length -ne 0) {
            return $false
        }

        if ($uriObj.Fragment.Length -ne 0) {
            return $false
        }

        $hostName = $uriObj.DnsSafeHost
        if ($Redirect) {
            return ($hostName -ceq 'release-assets.githubusercontent.com')
        }
        $path = $uriObj.AbsolutePath
        $query = $uriObj.Query
        if ($hostName -ceq 'api.github.com') {
            if ($path -ceq '/repos/FFmpeg-Builds/FFmpeg-Builds/releases') {
                return ($query -ceq '?per_page=3')
            }
            if ($query.Length -ne 0) { return $false }
            $route = [regex]::Match($path, '\A/repos/FFmpeg-Builds/FFmpeg-Builds/releases/tags/(?<tag>autobuild-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2})\z')
        } elseif ($hostName -ceq 'github.com') {
            if ($query.Length -ne 0) { return $false }
            $route = [regex]::Match($path, '\A/FFmpeg-Builds/FFmpeg-Builds/releases/download/(?<tag>autobuild-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2})/(?<asset>[^/]+)\z')
        } else {
            return $false
        }
        if (-not $route.Success) { return $false }
        $tag = $route.Groups['tag'].Value
        # A captura ASCII acima permite interpolar o header sem escape JSON.
        $header = '[{"tag_name":"' + $tag + '","draft":false,"prerelease":false}]'
        $null = Select-FfmpegDatedRelease -Json $header
        if ($hostName -ceq 'api.github.com') { return $true }
        $asset = $route.Groups['asset'].Value
        if ($asset -ceq 'checksums.sha256') { return $true }
        $candidate = ConvertFrom-FfmpegAssetName -Name $asset -Architecture 'X64'
        if ($null -eq $candidate) {
            $candidate = ConvertFrom-FfmpegAssetName -Name $asset -Architecture 'Arm64'
        }
        return ($null -ne $candidate)
    } catch {
        return $false
    }
}
