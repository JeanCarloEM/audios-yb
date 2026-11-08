#requires -Version 7.0
function New-Mp3EditorialTagArguments {
    [CmdletBinding()]
    param(
        [string]$SourcePath,

        [string]$CandidatePath,

        [AllowNull()][hashtable]$Updates
    )

    # Validar paths não nulos/whitespace
    if ([string]::IsNullOrWhiteSpace($SourcePath) -or [string]::IsNullOrWhiteSpace($CandidatePath)) {
        throw New-Object ArgumentException("SourcePath e CandidatePath não podem ser nulos ou whitespace.")
    }

    # Validar paths não contêm NUL
    if ($SourcePath.Contains("`0") -or $CandidatePath.Contains("`0")) {
        throw New-Object ArgumentException("SourcePath e CandidatePath não podem conter caracteres NUL.")
    }

    if (-not [IO.Path]::IsPathFullyQualified($SourcePath) -or -not [IO.Path]::IsPathFullyQualified($CandidatePath)) { throw [ArgumentException]::new('Paths devem ser absolutos.') }

    # Canonicalizar paths
    $sourceCanonical = [IO.Path]::GetFullPath($SourcePath)
    $candidateCanonical = [IO.Path]::GetFullPath($CandidatePath)

    # Validar extensão .mp3 (OrdinalIgnoreCase)
    if (-not [string]::Equals([IO.Path]::GetExtension($sourceCanonical), '.mp3', [StringComparison]::OrdinalIgnoreCase) -or -not [string]::Equals([IO.Path]::GetExtension($candidateCanonical), '.mp3', [StringComparison]::OrdinalIgnoreCase)) {
        throw New-Object ArgumentException("Ambos os paths devem ter extensão .mp3.")
    }

    # Validar paths distintos (OrdinalIgnoreCase no Windows)
    $pathComparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    if ([string]::Equals($sourceCanonical, $candidateCanonical, $pathComparison)) {
        throw New-Object ArgumentException("SourcePath e CandidatePath devem ser paths distintos.")
    }

    # Validar Updates não nulo e Count > 0
    if ($null -eq $Updates -or $Updates.Count -le 0) {
        throw New-Object ArgumentException("Updates deve ser um hashtable não vazio.")
    }

    # Validar keys de Updates
    $validKeys = @("artist", "title", "album", "track", "composer")
    foreach ($key in $Updates.Keys) {
        if ($key -isnot [string]) {
            throw New-Object ArgumentException("Chave '$key' deve ser do tipo string.")
        }
        if ([Array]::IndexOf($validKeys, $key) -lt 0) {
            throw New-Object ArgumentException("Chave '$key' inválida. Keys válidas: artist, title, album, track, composer.")
        }
    }

    # Validar values de Updates
    foreach ($key in $Updates.Keys) {
        $value = $Updates[$key]
        if ($null -eq $value) {
            throw New-Object ArgumentException("Value para chave '$key' não pode ser nulo.")
        }
        if ($value -isnot [string]) {
            throw New-Object ArgumentException("Value para chave '$key' deve ser string (sem conversão).")
        }
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw New-Object ArgumentException("Value para chave '$key' não pode ser whitespace.")
        }
        if ($value.Contains("`0")) {
            throw New-Object ArgumentException("Value para chave '$key' não pode conter caracteres NUL.")
        }
    }

    # Montar argv
    $argv = @()
    $argv += "-nostdin"
    $argv += "-v"
    $argv += "error"
    $argv += "-protocol_whitelist"
    $argv += "file"
    $argv += "-i"
    $argv += $sourceCanonical
    $argv += "-map"
    $argv += "0:a:0"
    $argv += "-map_metadata"
    $argv += "0"
    $argv += "-c:a"
    $argv += "copy"
    $argv += "-id3v2_version"
    $argv += "3"

    # Adicionar metadados na ordem fixa
    $ordemFixa = @("artist", "title", "album", "track", "composer")
    foreach ($field in $ordemFixa) {
        if ($Updates.ContainsKey($field)) {
            $argv += "-metadata"
            $argv += ($field + "=" + $Updates[$field])
        }
    }

    $argv += "-n"
    $argv += $candidateCanonical

    # Retornar array de strings como objeto único
    return ,([string[]]$argv)
}