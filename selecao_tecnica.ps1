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


function Resolve-DirectAudioSelectionProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$VideoId = '',

        [Parameter(Mandatory = $false)]
        [string]$Artist = '',

        [Parameter(Mandatory = $false)]
        [string]$Song = '',

        [Parameter(Mandatory = $false)]
        [object]$StoredProof = $null
    )

    # Se StoredProof for nulo ou não for IDictionary, retorna null
    if ($null -eq $StoredProof) {
        return $null
    }

    $storedDict = $StoredProof -as [System.Collections.IDictionary]
    if ($null -eq $storedDict) {
        return $null
    }

    # Verifica exatamente 6 chaves no nível superior (Ordinal)
    if ($storedDict.Count -ne 6) {
        return $null
    }

    $requiredKeys = [Collections.Generic.HashSet[string]]::new([string[]]@('versao', 'tipo', 'video_id', 'criterio', 'metadados', 'referencia'), [StringComparer]::Ordinal)
    foreach ($key in $storedDict.Keys) {
        if ($key -isnot [string] -or -not $requiredKeys.Contains($key)) { return $null }
    }

    # versao: int/long exatamente 2 (não string/double/bool)
    $versao = $storedDict['versao']
    if ($versao -isnot [int] -and $versao -isnot [long]) {
        return $null
    }
    if ($versao -ne 2) {
        return $null
    }

    # tipo: string exatamente 'selecao_tecnica'
    $tipo = $storedDict['tipo']
    if ($tipo -isnot [string] -or -not [string]::Equals($tipo, 'selecao_tecnica', [StringComparison]::Ordinal)) {
        return $null
    }

    # video_id: string que deve cumprir regra ASCII 11 e ser igual a VideoId (Ordinal)
    $videoIdStored = $storedDict['video_id']
    if ($videoIdStored -isnot [string]) {
        return $null
    }
    if (-not [regex]::IsMatch($videoIdStored, '\A[A-Za-z0-9_-]{11}\z')) {
        return $null
    }
    if (-not [string]::Equals($videoIdStored, $VideoId, [StringComparison]::Ordinal)) {
        return $null
    }

    # criterio: string exatamente 'url_direta_id_literal'
    $criterio = $storedDict['criterio']
    if ($criterio -isnot [string] -or -not [string]::Equals($criterio, 'url_direta_id_literal', [StringComparison]::Ordinal)) {
        return $null
    }

    # metadados: IDictionary fechado com exatamente 2 chaves: id, title
    $metadados = $storedDict['metadados']
    if ($null -eq $metadados) {
        return $null
    }
    $metaDict = $metadados -as [System.Collections.IDictionary]
    if ($null -eq $metaDict) {
        return $null
    }
    if ($metaDict.Count -ne 2) {
        return $null
    }
    $allowedKeys = [Collections.Generic.HashSet[string]]::new([string[]]@('id', 'title'), [StringComparer]::Ordinal)
    foreach ($key in $metaDict.Keys) {
        if ($key -isnot [string] -or -not $allowedKeys.Contains($key)) { return $null }
    }
    # id: string igual a videoIdStored (Ordinal)
    $metaId = $metaDict['id']
    if ($metaId -isnot [string] -or -not [string]::Equals($metaId, $videoIdStored, [StringComparison]::Ordinal)) {
        return $null
    }
    # title: string não branco
    $metaTitle = $metaDict['title']
    if ($metaTitle -isnot [string] -or [string]::IsNullOrWhiteSpace($metaTitle)) {
        return $null
    }

    # referencia: IDictionary fechado com exatamente 2 chaves: artista, musica
    $referencia = $storedDict['referencia']
    if ($null -eq $referencia) {
        return $null
    }
    $refDict = $referencia -as [System.Collections.IDictionary]
    if ($null -eq $refDict) {
        return $null
    }
    if ($refDict.Count -ne 2) {
        return $null
    }
    $allowedKeys = [Collections.Generic.HashSet[string]]::new([string[]]@('artista', 'musica'), [StringComparer]::Ordinal)
    foreach ($key in $refDict.Keys) {
        if ($key -isnot [string] -or -not $allowedKeys.Contains($key)) { return $null }
    }
    # artista: string igual a Artist (Ordinal)
    $refArtist = $refDict['artista']
    if ($refArtist -isnot [string] -or -not [string]::Equals($refArtist, $Artist, [StringComparison]::Ordinal)) {
        return $null
    }
    # musica: string igual a Song (Ordinal)
    $refSong = $refDict['musica']
    if ($refSong -isnot [string] -or -not [string]::Equals($refSong, $Song, [StringComparison]::Ordinal)) {
        return $null
    }

    # Tudo válido: invoca construtor
    try {
        return New-DirectAudioSelectionProof -VideoId $VideoId -Info @{ id = $videoIdStored; title = $metaTitle } -Artist $Artist -Song $Song
    } catch [System.ArgumentException] {
        return $null
    }
}

function Resolve-PublicationSelectionProof {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$VideoId = '',

        [Parameter(Mandatory = $false)]
        [string]$Artist = '',

        [Parameter(Mandatory = $false)]
        [string]$Song = '',

        [Parameter(Mandatory = $false)]
        [object]$Record = $null
    )

    # Se Record for nulo ou não for IDictionary, retorna null
    if ($null -eq $Record) {
        return $null
    }

    $recordDict = $Record -as [System.Collections.IDictionary]
    if ($null -eq $recordDict) {
        return $null
    }

    # Os nomes dos campos persistidos devem ser exatamente canonicos.
    $hasTechnical = $false
    $hasMusical = $false
    foreach ($key in $recordDict.Keys) {
        if ($key -isnot [string]) { continue }
        foreach ($field in @('selecao_tecnica', 'aprovacao_musical')) {
            if ([string]::Equals($key, $field, [StringComparison]::OrdinalIgnoreCase)) {
                if (-not [string]::Equals($key, $field, [StringComparison]::Ordinal)) { return $null }
                if ($field -ceq 'selecao_tecnica') { $hasTechnical = $true }
                else { $hasMusical = $true }
            }
        }
    }

    # Se tiver selecao_tecnica, resolve SOMENTE por Resolve-DirectAudioSelectionProof
    if ($hasTechnical) {
        $storedProof = $recordDict['selecao_tecnica']
        $result = Resolve-DirectAudioSelectionProof -VideoId $VideoId -Artist $Artist -Song $Song -StoredProof $storedProof
        if ($null -eq $result) {
            return $null
        }
        # Retorna hashtable exatamente 3 chaves
        return @{
            Kind = 'technical_v2'
            Field = 'selecao_tecnica'
            Proof = $result
        }
    }

    # Se NÃO tem selecao_tecnica e tem aprovacao_musical, chama Resolve-MusicalApprovalProof
    if ($hasMusical) {
        $storedProof = $recordDict['aprovacao_musical']
        if ($storedProof -isnot [Collections.IDictionary]) { return $null }
        $result = Resolve-MusicalApprovalProof -VideoId $VideoId -Artist $Artist -Song $Song -StoredProof $storedProof
        if ($null -eq $result) {
            return $null
        }
        # Retorna hashtable exatamente 3 chaves
        return @{
            Kind = 'legacy_human_v1'
            Field = 'aprovacao_musical'
            Proof = $result
        }
    }

    # Se nenhum dos campos presentes, retorna null
    return $null
}