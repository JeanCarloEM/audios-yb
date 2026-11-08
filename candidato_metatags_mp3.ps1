#requires -Version 7.0
function New-Mp3EditorialTagCandidate {
    param(
        [string]$File,
        [string]$Output,
        [AllowNull()][hashtable]$Updates,
        [string]$Ffmpeg
    )

    # Passo 1: Validar Updates e criar cópia independente
    if ($null -eq $Updates) {
        throw New-Object System.ArgumentException("Updates não pode ser nulo.")
    }
    $working = @{}
    foreach ($key in $Updates.Keys) {
        $working[$key] = $Updates[$key]
    }

    # Passo 2: Gerar argumentos via Builder
    $argv = New-Mp3EditorialTagArguments -SourcePath $File -CandidatePath $Output -Updates $working

    # Passo 3: Validar e canonicalizar paths
    $sourcePath = $argv[6]
    $candidatePath = $argv[-1]

    if ([string]::IsNullOrWhiteSpace($Ffmpeg) -or -not [IO.Path]::IsPathFullyQualified($Ffmpeg)) { throw [ArgumentException]::new('Ffmpeg deve ser um caminho absoluto nao vazio.') }
    $ffmpegCanonical = [IO.Path]::GetFullPath($Ffmpeg)

    # Passo 4: Verificar pré-condições de IO
    if (-not [System.IO.File]::Exists($sourcePath)) {
        throw New-Object System.IO.FileNotFoundException("Arquivo fonte não encontrado.", $sourcePath)
    }
    if (-not [System.IO.File]::Exists($ffmpegCanonical)) {
        throw New-Object System.IO.FileNotFoundException("ffmpeg não encontrado no caminho especificado.", $ffmpegCanonical)
    }
    if (Test-Path -LiteralPath $candidatePath) {
        throw New-Object System.IO.IOException("Caminho de saída já existe. Preservar arquivo existente.")
    }

    # Passo 5: Executar única via Invoke-Ytdlp
    $run = Invoke-Ytdlp -Executable $ffmpegCanonical -Arguments $argv -TimeoutSeconds 180

    # Passo 6: Tratar erros de execução
    if ($run.timeout -eq $true) {
        throw New-Object System.TimeoutException("A execução do ffmpeg excedeu o tempo limite.")
    }
    if ($run.code -ne 0) {
        throw New-Object System.InvalidOperationException("ffmpeg falhou: $($run.err)")
    }

    # Passo 7: Validar resultado
    if (-not [System.IO.File]::Exists($candidatePath)) {
        throw New-Object System.IO.InvalidDataException("Arquivo de saída não foi gerado.")
    }
    $length = (Get-Item -LiteralPath $candidatePath).Length
    if ($length -le 0) {
        throw New-Object System.IO.InvalidDataException("Arquivo de saída está vazio.")
    }

    # Passo 8: Retornar resultado
    return [PSCustomObject]@{
        SourcePath   = $sourcePath
        CandidatePath = $candidatePath
        Updates      = $working
        Validated    = $false
    }
}