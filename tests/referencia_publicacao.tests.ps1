#requires -Version 7
param(
    [string]$TestDir = $PSScriptRoot
)

$scriptPath = Join-Path $TestDir "..\referencia_publicacao.ps1" -Resolve
. $scriptPath

$nodeExe = "C:\Program Files\nodejs\node.exe"

function Get-NodeSha256 {
    param([string]$InputString)
    $args = @("-e", "console.log(require('crypto').createHash('sha256').update('$InputString', 'utf8').digest('hex'))")
    & $nodeExe @args
    if ($LASTEXITCODE -ne 0) {
        throw "Node SHA256 falhou: $LASTEXITCODE"
    }
}

function Assert-Equal {
    param([object]$Expected, [object]$Actual, [string]$Message)
    if ($Expected -is [string] -and $Actual -is [string]) {
        if (-not [System.String]::Equals($Expected, $Actual, [System.StringComparison]::Ordinal)) {
            throw "FALHA: $Message`nEsperado: $Expected`nObtido: $Actual"
        }
    } else {
        if ($Expected -ne $Actual) {
            throw "FALHA: $Message`nEsperado: $Expected`nObtido: $Actual"
        }
    }
}

function Assert-NotNullOrEmpty {
    param($Value, $Name)
    if ([string]::IsNullOrEmpty($Value)) {
        throw "FALHA: $Name é nulo ou vazio"
    }
}

# Casos válidos
$validCases = @(
    @{ VideoId = "TestVideo01"; RecordKey = "a" * 64; IntentSha256 = "b" * 64 }
    @{ VideoId = "testVideo01"; RecordKey = "c" * 64; IntentSha256 = "d" * 64 }
    @{ VideoId = "AbC-_012345"; RecordKey = "e" * 64; IntentSha256 = "f" * 64 }
)

foreach ($case in $validCases) {
    $result = New-PublicationReference -VideoId $case.VideoId -RecordKey $case.RecordKey -IntentSha256 $case.IntentSha256

    Assert-NotNullOrEmpty $result "Resultado"
    Assert-Equal $result.versao 1 "versão incorreta para $($case.VideoId)"
    Assert-Equal $result.video_id $case.VideoId "video_id preservado para $($case.VideoId)"
    Assert-Equal $result.registro_chave $case.RecordKey "registro_chave incorreto para $($case.VideoId)"
    Assert-Equal $result.sha256 $case.IntentSha256 "sha256 incorreto para $($case.VideoId)"

    $expectedLeaf = (Get-NodeSha256 $case.VideoId) + ".json"
    Assert-Equal $result.arquivo $expectedLeaf "arquivo SHA256 incorreto para $($case.VideoId)"
}

Write-Host "IDENTIDADE_ORDINAL_PASS"

# Negativos tipados
$negativeCases = @(
    @{ VideoId = "short"; RecordKey = "a" * 64; IntentSha256 = "b" * 64; Description = "VideoId tamanho inválido" }
    @{ VideoId = "testVideo01"; RecordKey = "short"; IntentSha256 = "b" * 64; Description = "RecordKey hash curto" }
    @{ VideoId = "testVideo01"; RecordKey = "A" * 64; IntentSha256 = "b" * 64; Description = "RecordKey uppercase" }
    @{ VideoId = "testVideo01"; RecordKey = "a" * 64; IntentSha256 = "short"; Description = "IntentSha256 curto" }
    @{ VideoId = "testVideo01"; RecordKey = "a" * 64; IntentSha256 = "A" * 64; Description = "IntentSha256 uppercase" }
    @{ VideoId = "test/Video01"; RecordKey = "a" * 64; IntentSha256 = "b" * 64; Description = "VideoId com barra" }
    @{ VideoId = "têstVideo01"; RecordKey = "a" * 64; IntentSha256 = "b" * 64; Description = "VideoId não ASCII" }
)

$confirmedNegativeCount = 0
if ($negativeCases.Count -ne 7) { throw 'Faltam casos negativos' }
foreach ($case in $negativeCases) {
    $caught = $false
    try {
        $null = New-PublicationReference -VideoId $case.VideoId -RecordKey $case.RecordKey -IntentSha256 $case.IntentSha256
    } catch {
        if ([string]::Equals($_.Exception.GetType().FullName, 'System.Management.Automation.ParameterBindingValidationException', [StringComparison]::Ordinal)) {
            $caught = $true
            $confirmedNegativeCount++
        } else {
            throw "FALHA: Erro inesperado para $($case.Description): $($_.Exception.Message)"
        }
    }
    if (-not $caught) {
        throw "FALHA: Não capturou exceção para $($case.Description)"
    }
}

if ($confirmedNegativeCount -ne 7) { throw 'Faltam excecoes de validacao confirmadas' }
Write-Host "NEGATIVOS_TIPADOS_PASS: 7"

Write-Host "REFERENCIA_PUBLICACAO_PASS"
$LASTEXITCODE = 0
