# tests/relatorios_falha_io.tests.ps1
# Teste PS7: falha de I/O ao abrir relatorio.csv (bloqueio real)
# Requisitos: StrictMode 1, ErrorAction Stop, fixture em tests/.runtime-reports-GUID
# Critério: exceção esperada, sentinelas intactas, modelo ausente, estado preservado

Set-StrictMode -Version 1
$ErrorActionPreference = 'Stop'

# Funcoes reais extraidas por AST da fonte de producao, sem executar o principal.
$productionPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'baixar_audios_ytdlp.ps1'
$productionTokens = $null
$productionErrors = $null
$productionAst = [Management.Automation.Language.Parser]::ParseFile($productionPath,[ref]$productionTokens,[ref]$productionErrors)
if ($productionErrors.Count) { throw 'Parser da fonte de producao' }
foreach ($functionName in @('Safe-Cell','Export-Reports')) {
    $productionFunctions = @($productionAst.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName},$true))
    if ($productionFunctions.Count -ne 1) { throw ('Funcao de producao nao unica: '+$functionName) }
    . ([scriptblock]::Create($productionFunctions[0].Extent.Text))
}

$scriptDir = $PSScriptRoot
$guid = [System.Guid]::NewGuid().ToString()
$controlDir = Join-Path $scriptDir ".runtime-reports-$guid"
$reportFile = Join-Path $controlDir 'relatorio.csv'
$pendingFile = Join-Path $controlDir 'pendencias.csv'
$suggestionsFile = Join-Path $controlDir 'sugestoes_aprovacao.csv'
$modeloFile = Join-Path $controlDir 'aprovacoes_modelo.csv'

# Criar diretório fixture
New-Item -ItemType Directory -Path $controlDir | Out-Null

# Fixture: State.registros com 1 pendente e 1 candidato sintético
$script:State = [pscustomobject]@{ registros = @{} }
$script:State.registros['row1'] = [pscustomobject]@{
    ordem = '001'
    artista = 'Artista Teste'
    musica = 'Música Teste'
    url_original = 'https://example.com/1'
    tipo_link = 'vídeo'
    verificacao_csv = 'ok'
    observacoes = ''
    video_id = 'abc123'
    url_video = 'https://youtu.be/abc123'
    titulo_video = 'Título do Vídeo'
    auditoria = @{}
    rejeicoes = @()
    criterio_selecao = 'manual'
    formato = 'mp3'
    codec = 'libmp3lame'
    bitrate_kbps = 128
    arquivo = '001 - Artista Teste - Música Teste.mp3'
    tentativas = 1
    tentativas_download = 1
    resultado = 'falha'
    motivo = 'Erro de rede'
    candidatos = @([pscustomobject]@{ id = 'xyz789'; url = 'https://example.com/2' })
    atualizado_utc = (Get-Date).ToUniversalTime().ToString('o')
}

# Fixture: RowsForReport
$script:RowsForReport = @('row1')

# Sentinelas criadas abaixo para os tres CSVs anteriores.
# modelo ausente (não criado)
$script:ReportFile = $reportFile
$script:PendingFile = $pendingFile
$script:Control = $controlDir

# Salvar estado memória para verificação pós-falha
$memState = $script:State.registros | ConvertTo-Json -Depth 15
$memRows = $script:RowsForReport | ConvertTo-Json -Depth 15
[IO.File]::WriteAllText((Join-Path $controlDir 'State.registros.json'), $memState, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $controlDir 'RowsForReport.json'), $memRows, [Text.UTF8Encoding]::new($false))

# Sentinelas reais: os tres arquivos anteriores precisam permanecer byte a byte.
$sentinelHashes = @{}
foreach ($sentinelPath in @($reportFile,$pendingFile,$suggestionsFile)) {
    [IO.File]::WriteAllText($sentinelPath,('SENTINEL::'+[IO.Path]::GetFileName($sentinelPath)),[Text.UTF8Encoding]::new($false))
    $sentinelHashes[$sentinelPath] = (Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash
}
$fs = $null
$ex = $null
try {
    $fs = [IO.File]::Open($reportFile,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try { Export-Reports } catch { $ex = $_ }
} finally {
    if ($null -ne $fs) { $fs.Dispose() }
}
if ($null -eq $ex) { throw 'Nenhuma excecao no arquivo bloqueado' }
$ioFound = $false
$cursorException = $ex.Exception
while ($null -ne $cursorException) {
    if ($cursorException -is [IO.IOException]) { $ioFound = $true }
    $cursorException = $cursorException.InnerException
}
if (-not $ioFound) { throw ('Excecao sem IOException: '+$ex.Exception.GetType().FullName) }
$sentinelAfter = @{}
foreach ($sentinelPath in @($reportFile,$pendingFile,$suggestionsFile)) {
    $sentinelAfter[$sentinelPath] = (Get-FileHash -LiteralPath $sentinelPath -Algorithm SHA256).Hash
    if (-not [string]::Equals($sentinelAfter[$sentinelPath],$sentinelHashes[$sentinelPath],[StringComparison]::Ordinal)) { throw ('Sentinela alterada: '+$sentinelPath) }
}
if ([IO.File]::Exists($modeloFile)) { throw 'Modelo criado apos falha do primeiro CSV' }
$afterMemoryState = $script:State.registros | ConvertTo-Json -Depth 15
$afterMemoryRows = $script:RowsForReport | ConvertTo-Json -Depth 15
if (-not [string]::Equals($afterMemoryState,$memState,[StringComparison]::Ordinal)) { throw 'Estado em memoria alterado' }
if (-not [string]::Equals($afterMemoryRows,$memRows,[StringComparison]::Ordinal)) { throw 'RowsForReport em memoria alterado' }
$diskState = [IO.File]::ReadAllText((Join-Path $controlDir 'State.registros.json'))
$diskRows = [IO.File]::ReadAllText((Join-Path $controlDir 'RowsForReport.json'))
if (-not [string]::Equals($diskState,$memState,[StringComparison]::Ordinal)) { throw 'Estado persistido alterado' }
if (-not [string]::Equals($diskRows,$memRows,[StringComparison]::Ordinal)) { throw 'RowsForReport persistido alterado' }
$proof = [ordered]@{
    SourceSHA256 = (Get-FileHash -LiteralPath $productionPath -Algorithm SHA256).Hash
    IOExceptionObserved = $ioFound
    ExceptionType = $ex.Exception.GetType().FullName
    SentinelBefore = $sentinelHashes
    SentinelAfter = $sentinelAfter
    MemoryStateUnchanged = $true
    DiskStateUnchanged = $true
    ModelAbsent = (-not [IO.File]::Exists($modeloFile))
}
[IO.File]::WriteAllText((Join-Path $controlDir 'proof.json'),($proof | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
Write-Host ('Artefatos em: '+$controlDir)
Write-Host 'REPORTS_LOCKED_FILE_PASS'

# Recuperacao apos liberar bloqueio: executar a chamada real do finally.
$recoveryNodes = @($productionAst.FindAll({param($node)
    $node -is [Management.Automation.Language.TryStatementAst] -and $node.Body.Extent.Text -ceq '{ if ($script:Lock) { Export-Reports } }'
},$true))
if ($recoveryNodes.Count -ne 1) { throw 'Chamada real de relatorios nao unica' }
$recoveryCall = [scriptblock]::Create($recoveryNodes[0].Extent.Text)
$script:Lock = $true
$recoveryWarnings = @(& $recoveryCall 3>&1)
if ($recoveryWarnings.Count -ne 0) { throw 'Aviso inesperado depois de liberar bloqueio' }
$reportRows = @(Import-Csv -LiteralPath $reportFile -Encoding UTF8)
$pendingRows = @(Import-Csv -LiteralPath $pendingFile -Encoding UTF8)
$suggestionRows = @(Import-Csv -LiteralPath $suggestionsFile -Encoding UTF8)
$modelRows = @(Import-Csv -LiteralPath $modeloFile -Encoding UTF8)
foreach ($count in @($reportRows.Count,$pendingRows.Count,$suggestionRows.Count,$modelRows.Count)) {
    if ($count -ne 1) { throw 'Quantidade de linhas CSV inesperada' }
}
if ($reportRows[0].Ordem -cne '001' -or $reportRows[0].Artista -cne 'Artista Teste' -or $reportRows[0].Musica -cne 'Música Teste' -or $reportRows[0].Resultado -cne 'falha') { throw 'Relatorio divergente da fixture literal' }
if ($pendingRows[0].Ordem -cne '001' -or $pendingRows[0].VideoId_sugerido -cne 'abc123' -or $pendingRows[0].Candidato_1 -cne 'https://example.com/2') { throw 'Pendencias divergentes da fixture literal' }
if ($suggestionRows[0].Ordem -cne '001' -or $suggestionRows[0].VideoId -cne 'abc123' -or $suggestionRows[0].URL_para_ouvir -cne 'https://example.com/2') { throw 'Sugestoes divergentes da fixture literal' }
foreach ($row in @($suggestionRows[0],$modelRows[0])) {
    foreach ($field in @('ArtistaMusicaConferidos','VersaoConferida','SemVocaisConferido')) {
        if ([string]$row.$field -cne '') { throw ('Confirmacao humana preenchida: '+$field) }
    }
}
if ($modelRows[0].Ordem -cne '' -or $modelRows[0].VideoId -cne '') { throw 'Modelo de aprovacao preenchido' }
$recoveredState = $script:State.registros | ConvertTo-Json -Depth 15
$recoveredRows = $script:RowsForReport | ConvertTo-Json -Depth 15
if (-not [string]::Equals($recoveredState,$memState,[StringComparison]::Ordinal) -or -not [string]::Equals($recoveredRows,$memRows,[StringComparison]::Ordinal)) { throw 'Memoria alterada na recuperacao dos relatorios' }
if (-not [string]::Equals([IO.File]::ReadAllText((Join-Path $controlDir 'State.registros.json')),$memState,[StringComparison]::Ordinal) -or -not [string]::Equals([IO.File]::ReadAllText((Join-Path $controlDir 'RowsForReport.json')),$memRows,[StringComparison]::Ordinal)) { throw 'Estado persistido alterado na recuperacao' }
$recoveryProof = [ordered]@{
    SourceSHA256 = (Get-FileHash -LiteralPath $productionPath -Algorithm SHA256).Hash
    CallSiteLine = $recoveryNodes[0].Extent.StartLineNumber
    CSVRowCounts = @($reportRows.Count,$pendingRows.Count,$suggestionRows.Count,$modelRows.Count)
    HumanConfirmationsBlank = $true
    NoWarningAfterUnlock = ($recoveryWarnings.Count -eq 0)
    MemoryStateUnchanged = $true
    DiskStateUnchanged = $true
}
[IO.File]::WriteAllText((Join-Path $controlDir 'recovery-proof.json'),($recoveryProof | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
Write-Host 'REPORTS_RECOVERY_PASS'
