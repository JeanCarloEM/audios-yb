#requires -Version 7.0
<#
.SYNOPSIS
    Validação final de codecs com mídia sintética FFmpeg/ffprobe (12 casos).
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\tests\codecs_validacao_final.tests.ps1
.NOTES
    Gera pasta tests/.runtime-final-codecs-GUID com provas JSON.
#>

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# Configuração de raiz e caminhos absolutos
$script:Root = Split-Path -Parent $PSScriptRoot
$script:Ffmpeg = Join-Path $script:Root 'ffmpeg.exe'
$script:Ffprobe = Join-Path $script:Root 'ffprobe.exe'
$script:Exe = Join-Path $script:Root 'yt-dlp.exe'

# Dot-source helper real (apenas funções reais, sem principal)
. (Join-Path $script:Root 'codecs_permitidos.ps1')

# Carregar definições de funções reais do principal via AST
$principalPath = Join-Path $script:Root 'baixar_audios_ytdlp.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($principalPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) { throw 'Parser errors no principal' }

$funcoesNecessarias = @('Invoke-Ytdlp', 'Probe-Audio', 'Verify-Signature', 'Test-FinalAudio')
$definicoes = @{}
foreach ($nome in $funcoesNecessarias) {
    $def = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $nome }, $true))
    if ($def.Count -ne 1) { throw "Função $nome não encontrada ou duplicada no principal" }
    $definicoes[$nome] = [scriptblock]::Create($def[0].Extent.Text)
}

# Carregar definições no escopo atual via dot-source
foreach ($nome in $funcoesNecessarias) {
    . $definicoes[$nome]
}

# Funções auxiliares locais
function Get-GuidSafe {
    return [System.Guid]::NewGuid().ToString('N')
}

function New-RuntimeFolder {
    $guid = Get-GuidSafe
    $folder = Join-Path $PSScriptRoot ".runtime-final-codecs-$guid"
    if (-not (Test-Path $folder)) { New-Item -ItemType Directory -Path $folder | Out-Null }
    return $folder
}

# Gerar pasta de runtime
$runtimeFolder = New-RuntimeFolder

# Definição dos 12 casos (expectativas literais)
$casos = @(
    @{ nome = 'AAC192.m4a'; codec = 'aac'; container = 'mov'; taxa = 192; expectativa = 'ACEITAR' },
    @{ nome = 'AAC192.aac'; codec = 'aac'; container = 'aac'; taxa = 192; expectativa = 'ACEITAR' },
    @{ nome = 'AC3_192.ac3'; codec = 'ac3'; container = 'ac3'; taxa = 192; expectativa = 'ACEITAR' },
    @{ nome = 'AC3_192.m4a'; codec = 'ac3'; container = 'mov'; taxa = 192; expectativa = 'ACEITAR' },
    @{ nome = 'MP3_192.mp3'; codec = 'mp3'; container = 'mp3'; taxa = 192; expectativa = 'REJEITAR' },
    @{ nome = 'Opus_192.opus'; codec = 'opus'; container = 'ogg'; taxa = 192; expectativa = 'REJEITAR' },
    @{ nome = 'ALAC.m4a'; codec = 'alac'; container = 'mov'; taxa = 128; expectativa = 'REJEITAR' },
    @{ nome = 'FLAC.flac'; codec = 'flac'; container = 'flac'; taxa = 128; expectativa = 'REJEITAR' },
    @{ nome = 'EAC3_192.eac3'; codec = 'eac3'; container = 'eac3'; taxa = 192; expectativa = 'REJEITAR' },
    @{ nome = 'AAC96.m4a'; codec = 'aac'; container = 'mov'; taxa = 96; expectativa = 'REJEITAR' },
    @{ nome = 'copiar_MP3_renomeada.m4a'; codec = 'mp3'; container = 'mp3'; taxa = 192; expectativa = 'REJEITAR' },
    @{ nome = 'copiar_EAC3_renomeada.ac3'; codec = 'eac3'; container = 'eac3'; taxa = 192; expectativa = 'REJEITAR' }
)

# Gerar mídia sintética e validar
$resultados = @()
$passCount = 0
$gerados = @{}

$provaFile = Join-Path $runtimeFolder 'provas.json'
try {
foreach ($caso in $casos) {
    $arquivo = Join-Path $runtimeFolder $caso.nome
    $extSemPonto = [IO.Path]::GetExtension($arquivo).ToLowerInvariant().TrimStart('.')

    # Casos renomeados: copiar de fontes já geradas
    if ($caso.nome -eq 'copiar_MP3_renomeada.m4a') {
        $fonte = $gerados['MP3_192.mp3']
        if (-not $fonte -or -not (Test-Path $fonte)) {
            throw 'Fonte MP3_192.mp3 não encontrada para cópia'
        }
        [IO.File]::Copy($fonte, $arquivo, $false)
        $hashFonte = (Get-FileHash -LiteralPath $fonte -Algorithm SHA256).Hash
        $hashDest = (Get-FileHash -LiteralPath $arquivo -Algorithm SHA256).Hash
        if ($hashFonte -ne $hashDest) {
            throw 'Divergência de hash após cópia de MP3 renomeada'
        }
    }
    elseif ($caso.nome -eq 'copiar_EAC3_renomeada.ac3') {
        $fonte = $gerados['EAC3_192.eac3']
        if (-not $fonte -or -not (Test-Path $fonte)) {
            throw 'Fonte EAC3_192.eac3 não encontrada para cópia'
        }
        [IO.File]::Copy($fonte, $arquivo, $false)
        $hashFonte = (Get-FileHash -LiteralPath $fonte -Algorithm SHA256).Hash
        $hashDest = (Get-FileHash -LiteralPath $arquivo -Algorithm SHA256).Hash
        if ($hashFonte -ne $hashDest) {
            throw 'Divergência de hash após cópia de EAC3 renomeada'
        }
    }

    else {
    # Gerar áudio sintético com FFmpeg (lavfi, seed fixo, 2s, stereo, 48k, -ac 2)
    $argsGen = @()
    switch ($caso.codec) {
        'aac' {
            $argsGen = @('-f', 'lavfi', '-i', 'anoisesrc=d=2:r=48000:a=0.5:seed=42', '-c:a', 'aac', '-b:a', "$($caso.taxa)k", '-ac', '2', '-n', '-nostdin', $arquivo)
        }
        'ac3' {
            $argsGen = @('-f', 'lavfi', '-i', 'anoisesrc=d=2:r=48000:a=0.5:seed=42', '-c:a', 'ac3', '-b:a', "$($caso.taxa)k", '-ac', '2', '-n', '-nostdin', $arquivo)
        }
        'mp3' {
            $argsGen = @('-f', 'lavfi', '-i', 'anoisesrc=d=2:r=48000:a=0.5:seed=42', '-c:a', 'libmp3lame', '-b:a', "$($caso.taxa)k", '-ac', '2', '-n', '-nostdin', $arquivo)
        }
        'opus' {
            $argsGen = @('-f', 'lavfi', '-i', 'anoisesrc=d=2:r=48000:a=0.5:seed=42', '-c:a', 'libopus', '-b:a', "$($caso.taxa)k", '-ac', '2', '-n', '-nostdin', $arquivo)
        }
        'alac' {
            $argsGen = @('-f', 'lavfi', '-i', 'anoisesrc=d=2:r=48000:a=0.5:seed=42', '-c:a', 'alac', '-ac', '2', '-n', '-nostdin', $arquivo)
        }
        'flac' {
            $argsGen = @('-f', 'lavfi', '-i', 'anoisesrc=d=2:r=48000:a=0.5:seed=42', '-c:a', 'flac', '-ac', '2', '-n', '-nostdin', $arquivo)
        }
        'eac3' {
            $argsGen = @('-f', 'lavfi', '-i', 'anoisesrc=d=2:r=48000:a=0.5:seed=42', '-c:a', 'eac3', '-b:a', "$($caso.taxa)k", '-ac', '2', '-n', '-nostdin', $arquivo)
        }
    }

    $runGen = Invoke-Ytdlp -Executable $script:Ffmpeg -Arguments $argsGen -TimeoutSeconds 120
    if ($runGen.code -ne 0) {
        throw "Erro na geração de áudio para $($caso.nome): $($runGen.err)"
    }

    }

    # Registrar geração para cópia futura
    $gerados[$caso.nome] = $arquivo

    # Probe real: exigir codec/container literais esperados
    try {
        $probe = Probe-Audio -File $arquivo
        if ($probe.codec -ne $caso.codec) {
            throw "Codec esperado '$($caso.codec)', obtido '$($probe.codec)'"
        }
        if (-not ($probe.container -split ',' -contains $caso.container)) {
            throw "Container esperado '$($caso.container)', obtido '$($probe.container)'"
        }
        if ($probe.integridade -ne 'decodificacao_integral_ok') {
            throw "Integridade decodificação falhou"
        }
        if ($probe.canais -ne 2) {
            throw "Canais esperado 2, obtido $($probe.canais)"
        }
        if ($probe.amostragem -ne 48000) {
            throw "Amostragem esperado 48000, obtido $($probe.amostragem)"
        }
        if ($probe.duracao -le 0) {
            throw "Duração esperada positiva, obtida $($probe.duracao)"
        }
    } catch {
        $resultados += @{ caso = $caso.nome; codec_esperado = $caso.codec; container_esperado = $caso.container; taxa_medida = $null; taxa_esperada = $caso.taxa; expectativa = $caso.expectativa; obtido = 'ERRO_PROBE'; hash = $null; assinatura = $null; erro = $_.Exception.Message }
        continue
    }

    # Verify-Signature real: extensão SEM ponto
    $assinatura = Verify-Signature -File $arquivo -Ext $extSemPonto
    if ($caso.expectativa -eq 'ACEITAR' -and -not $assinatura) { throw ('Assinatura positiva invalida: ' + $caso.nome) }

    # Test-FinalAudio real: exigir retorno bool e valor esperado literal
    try {
        $finalResult = Test-FinalAudio -File $arquivo -Probe $probe
        if ($finalResult -isnot [bool]) {
            throw "Test-FinalAudio deve retornar bool, obtido $($finalResult.GetType().Name)"
        }
        $obtido = if ($finalResult) { 'ACEITAR' } else { 'REJEITAR' }
        if ($obtido -ne $caso.expectativa) {
            throw "Esperado $($caso.expectativa), obtido $obtido"
        }
    } catch {
        $resultados += @{ caso = $caso.nome; codec_esperado = $caso.codec; container_esperado = $caso.container; taxa_medida = $null; taxa_esperada = $caso.taxa; expectativa = $caso.expectativa; obtido = 'ERRO_TESTE'; hash = $null; assinatura = $null; erro = $_.Exception.Message }
        continue
    }

    # Hash do arquivo
    $hash = (Get-FileHash -Path $arquivo -Algorithm SHA256).Hash

    $resultados += @{
        caso = $caso.nome
        codec = $probe.codec
        container = $probe.container
        taxa_medida = [math]::Round($probe.bitrate_medido_kbps, 1)
        taxa_esperada = $caso.taxa
        expectativa = $caso.expectativa
        obtido = $obtido
        hash = $hash
        assinatura = $assinatura
        integridade = $probe.integridade
        duracao = $probe.duracao
        canais = $probe.canais
        amostragem = $probe.amostragem
    }

    if ($obtido -eq $caso.expectativa) { $passCount++ }
}

} finally {
    [IO.File]::WriteAllText($provaFile, (ConvertTo-Json -InputObject @($resultados) -Depth 10), [Text.UTF8Encoding]::new($false))
}

# Guarda de conclusão: todos os contadores devem ser 12
if ($casos.Count -ne 12 -or $resultados.Count -ne 12 -or $passCount -ne 12) {
    throw "Conclusão inválida: casos=$($casos.Count), resultados=$($resultados.Count), passCount=$passCount"
}

Write-Host "FINAL_CODEC_NATIVE_PASS: $passCount/$($casos.Count) casos"
