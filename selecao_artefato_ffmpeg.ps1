#requires -Version 7.0
. (Join-Path $PSScriptRoot 'nome_artefato_ffmpeg.ps1')

function Select-FfmpegAssetCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()][AllowEmptyCollection()][AllowEmptyString()][object]$Names,
        [Parameter(Mandatory = $true)]
        [AllowNull()][AllowEmptyString()][object]$Architecture
    )

    # Validação de Architecture
    if ($Architecture -isnot [string]) {
        throw [ArgumentException]::new('Architecture deve ser uma string.')
    }
    if ($Architecture -cne 'X64' -and $Architecture -cne 'Arm64') {
        throw [ArgumentException]::new('Architecture deve ser X64 ou Arm64.')
    }

    # Validação de Names
    if ($Names -isnot [System.Array]) {
        throw [ArgumentException]::new('Names deve ser um array.')
    }
    $count = $Names.Count
    if ($count -lt 1 -or $count -gt 256) {
        throw [ArgumentException]::new('Names deve conter entre 1 e 256 elementos.')
    }

    # Validação de cada nome e extração de candidatos
    $hashSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $candidates = @{}
    $errors = @()

    foreach ($item in $Names) {
        $name = $item
        if ($name -isnot [string] -or [string]::IsNullOrWhiteSpace($name)) {
            throw [ArgumentException]::new('Cada elemento de Names deve ser uma string não vazia.')
        }

        try {
            $candidate = ConvertFrom-FfmpegAssetName -Name $name -Architecture $Architecture
        } catch {
            throw $_
        }


        # Unicidade ordinal de nomes
        $assetName = $name
        if (-not $hashSet.Add($assetName)) {
            throw [FormatException]::new("Nome duplicado detectado: $assetName")
        }

        if ($null -eq $candidate) {
            continue
        }

        # Agrupamento por branch numérica (release_version)
        $releaseVersion = $candidate.release_version
        $versionObj = [version]$releaseVersion

        if (-not $candidates.ContainsKey($versionObj)) {
            $candidates[$versionObj] = @{
                version = $versionObj
                candidates = @()
            }
        }
        $candidates[$versionObj].candidates += $candidate
    }

    # Verificação de unicidade por branch
    $validBranches = @()
    foreach ($key in $candidates.Keys) {
        $group = $candidates[$key]
        if ($group.candidates.Count -gt 1) {
            throw [FormatException]::new("Branch $key tem mais de um candidato.")
        }
        $validBranches += $group
    }

    if ($validBranches.Count -eq 0) {
        throw [InvalidOperationException]::new('Nenhum candidato elegível encontrado.')
    }

    # Seleção da maior branch por Version.CompareTo
    $bestGroup = $validBranches | Sort-Object -Property @{Expression = { $_.version }; Descending = $true } | Select-Object -First 1
    return $bestGroup.candidates[0]
}
