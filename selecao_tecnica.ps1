function New-DirectAudioSelectionProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$VideoId = '',

        [Parameter(Mandatory = $false)]
        [object]$Info = $null,

        [Parameter(Mandatory = $false)]
        [string]$Artist = '',

        [Parameter(Mandatory = $false)]
        [string]$Song = ''
    )

    # Validação de ausência de parâmetros obrigatórios
    if ([string]::IsNullOrEmpty($VideoId)) {
        throw New-Object System.ArgumentException('VideoId é obrigatório')
    }
    if ($null -eq $Info) {
        throw New-Object System.ArgumentException('Info é obrigatório')
    }
    # Validação de Info como IDictionary
    $dict = $Info -as [System.Collections.IDictionary]
    if ($null -eq $dict) {
        throw New-Object System.ArgumentException('Info deve ser um objeto que implemente System.Collections.IDictionary')
    }

    # Validação de VideoId: exatamente 11 caracteres ASCII [A-Za-z0-9_-]
    if (-not [regex]::IsMatch($VideoId, '\A[A-Za-z0-9_-]{11}\z')) {
        throw New-Object System.ArgumentException('VideoId inválido: deve ter exatamente 11 caracteres ASCII [A-Za-z0-9_-]')
    }

    # Validação de Info.id: deve ser string e idêntica ao VideoId (Ordinal)
    $dict = $Info -as [System.Collections.IDictionary]
    if ($null -eq $dict -or -not $dict.Contains('id') -or -not ($dict['id'] -is [string])) {
        throw New-Object System.ArgumentException('Info.id deve ser uma string')
    }
    if (-not [string]::Equals($dict['id'], $VideoId, [StringComparison]::Ordinal)) {
        throw New-Object System.ArgumentException('Info.id deve ser idêntico a VideoId (Ordinal)')
    }

    # Validação de Info.title: deve ser string e não branca
    if (-not $dict.Contains('title') -or -not ($dict['title'] -is [string])) {
        throw New-Object System.ArgumentException('Info.title deve ser uma string')
    }
    if ([string]::IsNullOrWhiteSpace($dict['title'])) {
        throw New-Object System.ArgumentException('Info.title não pode ser branco')
    }

    # Construção do retorno ( hashtable literal, sem mutação/alias )
    return @{
        versao = [int]2
        tipo = 'selecao_tecnica'
        video_id = $VideoId
        criterio = 'url_direta_id_literal'
        metadados = @{
            id = $Info['id']
            title = $Info['title']
        }
        referencia = @{
            artista = $Artist
            musica = $Song
        }
    }
}
