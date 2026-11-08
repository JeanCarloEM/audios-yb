function Get-MusicalNameComponents {
    [CmdletBinding()]
    param(
        [string] $Autor,
        [string] $Track,
        [string] $Titulo,
        [Nullable[int]] $LarguraTrack = $null
    )

    # Normalizar whitespace de todos os campos ANTES de decidir presença
    $AutorNormalizado = if (-not [string]::IsNullOrEmpty($Autor)) { ($Autor -replace '\s+', ' ').Trim() } else { $null }
    $TrackNormalizado = if (-not [string]::IsNullOrEmpty($Track)) { ($Track -replace '\s+', ' ').Trim() } else { $null }
    $TituloNormalizado = if (-not [string]::IsNullOrEmpty($Titulo)) { ($Titulo -replace '\s+', ' ').Trim() } else { $null }

    # Validar LarguraTrack se explicitamente fornecido (não $null)
    if ($null -ne $LarguraTrack) {
        if ($LarguraTrack -lt 1 -or $LarguraTrack -gt 145) {
            throw New-Object ArgumentOutOfRangeException('LarguraTrack', 'Valor deve estar entre 1 e 145.')
        }
    }

    # Se Titulo vazio ou nulo → legado
    if ([string]::IsNullOrEmpty($TituloNormalizado)) {
        return @{
            'usar_legado' = $true
            'componentes' = [string[]]@()
            'motivo' = 'Título ausente ou vazio.'
        }
    }

    # Processar Autor
    $AutorProcessado = $null
    if ($null -ne $AutorNormalizado -and $AutorNormalizado.Length -gt 0) {
        $AutorProcessado = $AutorNormalizado
    }

    # Processar Track
    $TrackProcessado = $null
    if ($null -ne $TrackNormalizado -and $TrackNormalizado.Length -gt 0) {
        if ($TrackNormalizado -match '^[0-9]+$') {
            # Normalizar zeros à esquerda, preservando pelo menos '0'
            $TrackProcessado = $TrackNormalizado -replace '^0+(\d)', '$1'
            if ($TrackProcessado.Length -eq 0) {
                $TrackProcessado = '0'
            }
            if ($TrackProcessado.Length -gt 145) {
                return @{
                    'usar_legado' = $true
                    'componentes' = [string[]]@()
                    'motivo' = 'Número de track normalizado excede 145 dígitos.'
                }
            }
            # Aplicar PadLeft apenas se LarguraTrack for explicitamente fornecido (não $null)
            if ($null -ne $LarguraTrack) {
                $TrackProcessado = $TrackProcessado.PadLeft([int]$LarguraTrack, '0')
            }
        } else {
            return @{
                'usar_legado' = $true
                'componentes' = [string[]]@()
                'motivo' = 'Track inválido: deve conter apenas dígitos ASCII.'
            }
        }
    }

    # Construir componentes (Ordem Autor/Track/Titulo)
    $componentes = [string[]]@()
    if ($null -ne $AutorProcessado) { $componentes += $AutorProcessado }
    if ($null -ne $TrackProcessado) { $componentes += $TrackProcessado }
    $componentes += $TituloNormalizado

    return @{
        'usar_legado' = $false
        'componentes' = [string[]]$componentes
        'motivo' = ''
    }
}
