# decisao_vocal.ps1
# Módulo puro de decisão de preferência vocal. Nenhum I/O, detector, modelo ou rede.

function Get-VocalPreferenceDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Preference = 'indiferentes',

        [Parameter(Mandatory = $false)]
        [object]$Detection = $null
    )

    # Normalizar/validar preferência usando Resolve-VocalPreference -Global
    $normalizedPreference = Resolve-VocalPreference -Global $Preference

    # Inicializar saída padrão
    $result = @{
        versao   = [int]1
        permitido = $true
        status    = if ($normalizedPreference -ceq 'indiferentes') { 'sem_filtro' } else { 'nao_verificado' }
        esperado  = $normalizedPreference
        detectado = 'nao_verificado'
        motivo    = 'Detecção não fornecida ou inválida para análise'
    }

    # Verificar se Detection é hashtable com status 'conclusivo' (case-sensitive) e presenca bool real
    $isConclusive = $false
    if ($Detection -is [hashtable]) {
        $statusVal = $Detection['status']
        $presencaVal = $Detection['presenca']

        if ($statusVal -is [string] -and [string]::Equals($statusVal, 'conclusivo', [StringComparison]::Ordinal) -and $presencaVal -is [bool]) {
            $isConclusive = $true
        }
    }

    if (-not $isConclusive) {
        return $result
    }

    # Determinar detectado com base em presenca bool
    $detectedValue = if ($Detection['presenca'] -eq $true) { 'com_vocais' } else { 'sem_vocais' }

    # Lógica de compatibilidade
    $permitido = $false
    $statusOut = 'nao_verificado'
    $motivo = 'Detecção não fornecida ou inválida para análise'

    # Indiferentes => permitido true/status sem_filtro
    if ($normalizedPreference -eq 'indiferentes') {
        $permitido = $true
        $statusOut = 'sem_filtro'
        $motivo = 'Preferência indiferentes aceita qualquer detecção'
        return @{
            versao   = [int]1
            permitido = $true
            status    = $statusOut
            esperado  = $normalizedPreference
            detectado = $detectedValue
            motivo    = $motivo
        }
    }

    # Detectado conclusivo
    if ($isConclusive) {
        $detectado = $detectedValue

        # Vocais + true ou Instrumentais + false => true/compatível
        if (($normalizedPreference -eq 'vocais' -and $Detection['presenca'] -eq $true) -or
            ($normalizedPreference -eq 'instrumentais' -and $Detection['presenca'] -eq $false)) {
            $permitido = $true
            $statusOut = 'compativel'
            $motivo = "Preferência $normalizedPreference compatível com detecção $detectado"
        }
        # Vocais + false ou Instrumentais + true => false/incompatível
        elseif (($normalizedPreference -eq 'vocais' -and $Detection['presenca'] -eq $false) -or
                ($normalizedPreference -eq 'instrumentais' -and $Detection['presenca'] -eq $true)) {
            $permitido = $false
            $statusOut = 'incompativel'
            $motivo = "Preferência $normalizedPreference incompatível com detecção $detectado"
        }
        else {
            $motivo = "Preferência $normalizedPreference não se aplica à detecção $detectado"
        }
    }

    return @{
        versao   = [int]1
        permitido = $permitido
        status    = $statusOut
        esperado  = $normalizedPreference
        detectado = $detectado
        motivo    = $motivo
    }
}


function Get-SourceVocalPreferenceDecision {
    [CmdletBinding()]
    param(
        [string]$Preference = 'indiferentes',
        [object]$Detection = $null,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][string]$SourceSha256
    )
    if ([string]::IsNullOrEmpty($SourceSha256) -or
        -not [regex]::IsMatch($SourceSha256, '\A[0-9a-fA-F]{64}\z')) {
        throw [ArgumentException]::new('SourceSha256 deve ser SHA256 hexadecimal de 64 caracteres.')
    }
    $eligible = $null
    if ($Detection -is [hashtable]) {
        $declared = $Detection['origem_sha256']
        if ($declared -is [string] -and
            [regex]::IsMatch($declared, '\A[0-9a-fA-F]{64}\z') -and
            [string]::Equals($declared, $SourceSha256, [StringComparison]::OrdinalIgnoreCase)) {
            $eligible = $Detection
        }
    }
    return Get-VocalPreferenceDecision -Preference $Preference -Detection $eligible
}
