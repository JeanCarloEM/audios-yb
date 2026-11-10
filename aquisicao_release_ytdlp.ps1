#requires -Version 7.0
. (Join-Path $PSScriptRoot 'transporte_release_ytdlp.ps1')
. (Join-Path $PSScriptRoot 'plano_release_ytdlp.ps1')

function Get-YtdlpReleasePackage {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Architecture,
        [System.Net.Http.HttpMessageHandler]$Handler = $null,
        [ValidateRange(1,120)][int]$TimeoutSeconds = 30
    )

    # Validar arquitetura ANTES de qualquer rede
    $validArchs = @('X64','X86','Arm64')
    if ($Architecture -isnot [string] -or $Architecture -cnotin $validArchs) {
        throw [ArgumentException]::new('Arquitetura inválida. Deve ser X64, X86 ou Arm64.')
    }

    $metadataUrl = 'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'
    $metadataBytes = $null
    $doc = $null
    $manifestUrl = $null
    $manifestBytes = $null
    $assetBytes = $null

    try {
        # Validar arquitetura antes de rede
        $validArchs = @('X64','X86','Arm64')
        if ($Architecture -isnot [string] -or $Architecture -cnotin $validArchs) {
            throw [ArgumentException]::new('Arquitetura inválida. Deve ser X64, X86 ou Arm64.')
        }

        # Obter metadata
        $metadataBytes = Get-YtdlpReleaseBytes -Uri $metadataUrl -MaxBytes 1048576 -Handler $Handler -TimeoutSeconds $TimeoutSeconds
        $metadataText = [Text.UTF8Encoding]::new($false,$true).GetString($metadataBytes)

        # Parse JSON com JsonDocument e verificar duplicatas
        $options = [System.Text.Json.JsonDocumentOptions]::new()
        $options.MaxDepth = 16
        $doc = [System.Text.Json.JsonDocument]::Parse($metadataText, $options)
        $root = $doc.RootElement
        if ($root.ValueKind -ne [Text.Json.JsonValueKind]::Object) { throw 'Metadata deve ser objeto JSON.' }

        $tag = $null
        $draft = $null
        $prerelease = $null
        $seenProps = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

        # package-canonical-fields-repaired-v1: campos desconhecidos ignorados; criticos exatos e unicos.
        foreach ($prop in $root.EnumerateObject()) {
            $canonical=@(@('tag_name','draft','prerelease')|Where-Object {[string]::Equals($_,$prop.Name,[StringComparison]::OrdinalIgnoreCase)})
            if($canonical.Count -eq 0){continue}
            if($prop.Name -cne $canonical[0]){throw 'Alias de campo critico nao e canonico.'}
            if (-not $seenProps.Add($prop.Name)) {
                throw 'Metadata contém campos duplicados.'
            }
            switch -CaseSensitive ($prop.Name) {
                'tag_name' {
                    if ($prop.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                        throw 'Campo tag_name deve ser string.'
                    }
                    $tag = $prop.Value.GetString()
                }
                'draft' {
                    if ($prop.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::False) {
                        throw 'Campo draft deve ser false.'
                    }
                    $draft = $false
                }
                'prerelease' {
                    if ($prop.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::False) {
                        throw 'Campo prerelease deve ser false.'
                    }
                    $prerelease = $false
                }
            }
        }

        if ($null -eq $tag) { throw 'Metadata deve conter tag_name.' }
        if ($null -eq $draft) { throw 'Metadata deve conter draft.' }
        if ($null -eq $prerelease) { throw 'Metadata deve conter prerelease.' }

        # Validar tag antes de outro pedido
        if ($tag -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,127}\z' -or $tag.ToLowerInvariant() -in @('latest','stable','nightly','master')) {
            throw 'Tag inválida.'
        }

        # Construir URLs
        $base = 'https://github.com/yt-dlp/yt-dlp/releases/download/' + $tag + '/'
        $manifestUrl = $base + 'SHA2-256SUMS'

        # Obter manifesto
        $manifestBytes = Get-YtdlpReleaseBytes -Uri $manifestUrl -MaxBytes 1048576 -Handler $Handler -TimeoutSeconds $TimeoutSeconds
        $manifestText = [Text.UTF8Encoding]::new($false,$true).GetString($manifestBytes)

        # Validar manifesto e obter hash do asset
        $plan = New-YtdlpReleasePlan -Tag $tag -Manifest $manifestText -Architecture $Architecture

        # Obter asset
        $assetBytes = Get-YtdlpReleaseBytes -Uri $plan.url -MaxBytes 67108864 -Handler $Handler -TimeoutSeconds $TimeoutSeconds

        # Validar SHA256
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha.ComputeHash($assetBytes)
            $hashStr = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
            if ($hashStr -cne $plan.sha256) {
                throw 'Checksum SHA256 diverge.'
            }
        } finally {
            $sha.Dispose()
        }

        # Calcular hashes dos bytes originais
        $shaMeta = [System.Security.Cryptography.SHA256]::Create()
        try {
            $metaHashBytes = $shaMeta.ComputeHash($metadataBytes)
            $metaHashStr = [System.BitConverter]::ToString($metaHashBytes).Replace('-', '').ToLowerInvariant()
        } finally {
            $shaMeta.Dispose()
        }

        $shaManifest = [System.Security.Cryptography.SHA256]::Create()
        try {
            $manifestHashBytes = $shaManifest.ComputeHash($manifestBytes)
            $manifestHashStr = [System.BitConverter]::ToString($manifestHashBytes).Replace('-', '').ToLowerInvariant()
        } finally {
            $shaManifest.Dispose()
        }

        return @{
            bytes = $assetBytes
            manifest = $manifestText
            release_plan = $plan
            metadata_url = $metadataUrl
            metadata_sha256 = $metaHashStr
            manifest_sha256 = $manifestHashStr
        }
    } finally {
        if ($null -ne $doc) { $doc.Dispose() }
    }
}
