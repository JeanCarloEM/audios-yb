#requires -Version 5.1
<#
.SYNOPSIS
    Helpers para execução única: leitura interativa e confirmação de seleção de vídeo.
.DESCRIPTION
    Helpers PS5.1/7 para seleção de vídeo, confirmação de metadados e caminho de evidência.
    Dot-source sem efeitos colaterais. Não invoca rede, FFmpeg ou dependências externas.
#>

function Read-InRunValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [switch]$NonInteractive,
        [scriptblock]$ReadInput = $null
    )

    if ($NonInteractive) { return '' }
    if ($null -ne $ReadInput) { return (& $ReadInput $Prompt) }
    try { if ([Console]::IsInputRedirected) { return '' }; return (Read-Host -Prompt $Prompt) } catch { return '' }
}

function Request-InRunApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Order,
        [Parameter(Mandatory = $true)][string]$Artist,
        [Parameter(Mandatory = $true)][string]$Song,
        [array]$Candidates = @(),
        [string]$VideoId,
        [switch]$NonInteractive,
        [scriptblock]$ReadInput = $null
    )

    $selected = $null
    $idx = 0

    if ($NonInteractive) {
        return $null
    }

    if (-not [string]::IsNullOrWhiteSpace($VideoId)) {
        if (-not ($VideoId -match '^[A-Za-z0-9_-]{11}$')) {
            return $null
        }
        $selected = @{
            id = $VideoId
            titulo = "$Artist - $Song"
            url = "https://www.youtube.com/watch?v=$VideoId"
        }
        Write-Host "ID fixo [$VideoId] selecionado automaticamente."
        Write-Host "Título: $($selected.titulo)"
    } else {
        if ($Candidates.Count -eq 0) {
            return $null
        }

        Write-Host "`n[$Order] $Artist - $Song"
        Write-Host "Candidatos:"
        for ($i = 0; $i -lt $Candidates.Count; $i++) {
            Write-Host "  [$i] $($Candidates[$i].id) - $($Candidates[$i].titulo)"
        }
        Write-Host "  [x] Cancelar"

        $attempts = 0
        while ($attempts -lt 3) {
            $input = Read-InRunValue -Prompt "Escolha índice ou ID de 11 caracteres: " -NonInteractive:$NonInteractive -ReadInput $ReadInput
            if ([string]::IsNullOrWhiteSpace($input)) {
                return $null
            }

            $input = $input.Trim()
            if ($input -eq 'x') {
                return $null
            }

            if ($input.Length -eq 11 -and $input -match '^[A-Za-z0-9_-]{11}$') {
                $selected = $Candidates | Where-Object { $_.id -eq $input }
                if ($null -ne $selected) {
                    break
                }
                Write-Host "ID inválido. Tente novamente."
                $attempts++
                continue
            }

            if ($input -match '^\d+$') {
                if ([int]::TryParse($input, [ref]$idx)) {
                    if ($idx -ge 0 -and $idx -lt $Candidates.Count) {
                        $selected = $Candidates[$idx]
                        break
                    }
                }
            }

            Write-Host "Entrada inválida. Tente novamente."
            $attempts++
        }

        if ($null -eq $selected) {
            return $null
        }
    }

    if ($null -eq $selected -or -not ($selected.id -match '^[A-Za-z0-9_-]{11}$')) {
        return $null
    }

    Write-Host "`nSelecionado: $($selected.titulo)"
    Write-Host "ID: $($selected.id)"
    Write-Host "URL: $($selected.url)"

    $confirmArtistSong = Read-InRunValue -Prompt "Artista e música corretos? (SIM/NÃO): " -NonInteractive:$NonInteractive -ReadInput $ReadInput
    if ($confirmArtistSong -ne 'SIM') {
        return $null
    }

    $confirmVersion = Read-InRunValue -Prompt "Versão correta? (SIM/NÃO): " -NonInteractive:$NonInteractive -ReadInput $ReadInput
    if ($confirmVersion -ne 'SIM') {
        return $null
    }

    $confirmVocals = Read-InRunValue -Prompt "Ausência de vocais confirmada? (SIM/NÃO): " -NonInteractive:$NonInteractive -ReadInput $ReadInput
    if ($confirmVocals -ne 'SIM') {
        return $null
    }

    return @{
        Ordem = $Order
        VideoId = $selected.id
        ArtistaMusicaConferidos = 'SIM'
        VersaoConferida = 'SIM'
        SemVocaisConferido = 'SIM'
    }
}

function Request-InRunEvidencePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$VideoId,
        [Parameter(Mandatory = $true)][string]$FormatId,
        [Parameter(Mandatory = $true)][string]$Hash,
        [switch]$NonInteractive,
        [scriptblock]$ReadInput = $null
    )

    if ($NonInteractive) {
        return ''
    }

    Write-Host "`nFonte: $Source"
    Write-Host "Vídeo: $VideoId"
    Write-Host "Formato: $FormatId"
    Write-Host "SHA256: $Hash"
    Write-Host "Forneça caminho JSON de evidência ou vazio para cancelar."

    $input = Read-InRunValue -Prompt "Caminho JSON: " -NonInteractive:$NonInteractive -ReadInput $ReadInput
    if ([string]::IsNullOrWhiteSpace($input)) {
        return ''
    }

    $path = $input.Trim()
    if ([string]::IsNullOrWhiteSpace($path)) {
        return ''
    }

    return $path
}


function Resolve-MusicalApprovalProof {
    [CmdletBinding()]
    param(
        [string]$VideoId,
        [string]$Artist,
        [string]$Song,
        [System.Collections.IDictionary]$RawApproval = $null,
        [System.Collections.IDictionary]$StoredProof = $null,
        [ValidateSet('arquivo_aprovacoes', 'interativo')][string]$Origin = 'arquivo_aprovacoes'
    )
    if ($VideoId -notmatch '^[A-Za-z0-9_-]{11}$' -or
        [string]::IsNullOrWhiteSpace($Artist) -or [string]::IsNullOrWhiteSpace($Song)) { return $null }
    $artistText = $Artist.Trim()
    $songText = $Song.Trim()
    if ($null -ne $RawApproval) {
        if (([string]$RawApproval['VideoId']).Trim() -cne $VideoId) { return $null }
        foreach ($field in @('ArtistaMusicaConferidos', 'VersaoConferida', 'SemVocaisConferido')) {
            if (([string]$RawApproval[$field]).Trim().ToUpperInvariant() -notin @('SIM', 'S', 'TRUE', '1')) { return $null }
        }
        return @{
            versao = 1; video_id = $VideoId; artista = $artistText; musica = $songText
            artista_musica_conferidos = $true; versao_conferida = $true; sem_vocais_conferido = $true
            origem = $Origin
        }
    }
    if ($null -eq $StoredProof -or
        ($StoredProof['versao'] -isnot [int] -and $StoredProof['versao'] -isnot [long]) -or
        $StoredProof['versao'] -ne 1 -or
        ([string]$StoredProof['video_id']) -cne $VideoId -or
        ([string]$StoredProof['artista']) -cne $artistText -or
        ([string]$StoredProof['musica']) -cne $songText -or
        $StoredProof['origem'] -notin @('arquivo_aprovacoes', 'interativo')) { return $null }
    foreach ($field in @('artista_musica_conferidos', 'versao_conferida', 'sem_vocais_conferido')) {
        if ($StoredProof[$field] -isnot [bool] -or -not $StoredProof[$field]) { return $null }
    }
    $copy = @{}
    foreach ($key in $StoredProof.Keys) { $copy[$key] = $StoredProof[$key] }
    return $copy
}

