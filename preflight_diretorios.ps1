#requires -Version 7.0
. (Join-Path -Path $PSScriptRoot -ChildPath 'acesso_diretorio.ps1')

function Initialize-OutputWriteAccess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Out
    )

    # Rejeitar vazio/whitespace
    if ([string]::IsNullOrWhiteSpace($Out)) {
        throw 'Parâmetro Out vazio ou whitespace.'
    }

    # Rejeitar caminho não totalmente qualificado
    if (-not [IO.Path]::IsPathFullyQualified($Out)) {
        throw 'Parâmetro Out deve ser caminho absoluto.'
    }

    # Criar diretório de saída
    $directory = [IO.Directory]::CreateDirectory($Out)

    # Criar diretório de controle
    $control = Join-Path -Path $directory.FullName -ChildPath '.controle'
    [void][IO.Directory]::CreateDirectory($control)

    # Descartar retornos de Invoke-DirectoryWriteProbe
    $null = Invoke-DirectoryWriteProbe -Root $directory.FullName
    $null = Invoke-DirectoryWriteProbe -Root $control

    # Retornar hashtable exata
    return @{Out = $directory.FullName; Control = $control}
}
