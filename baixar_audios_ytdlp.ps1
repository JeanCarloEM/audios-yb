#requires -Version 7.0
<#
.SYNOPSIS
    Audita um CSV e publica somente M4A/MP3 com fonte documentada e minimo medido de 128 kbps.
.EXAMPLE
    pwsh -NoProfile -ExecutionPolicy Bypass -File .\baixar_audios_ytdlp.ps1 -Csv .\coletanea_uber_instrumental_candidatas.csv
.EXAMPLE
    .\baixar_audios_ytdlp.ps1 -Csv '.\coletanea_uber_instrumental_candidatas.csv' -AprovacoesCsv '.\destino\.controle\sugestoes_aprovacao.csv' -ReavaliarPendentes
.NOTES
    Coloque yt-dlp.exe junto deste .ps1. Os arquivos ficam em .\destino.
    Sem auditoria de audio, metadados NAO comprovam ausencia de vocais.
    AprovacoesCsv: Ordem,VideoId,ArtistaMusicaConferidos,VersaoConferida,SemVocaisConferido
    Use SIM nas tres colunas de confirmacao SOMENTE apos ouvir e conferir.
    ffprobe/ffmpeg nativos adjacentes ou no PATH: validacao integral e conversao excepcional.
    EvidenciasJson documenta procedencia e historico, vinculados ao hash da fonte.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Csv,
    [string]$AprovacoesCsv,
    [string]$EvidenciasJson,
    [string]$CookiesArquivo,
    [string]$CookiesNavegador,
    [switch]$Interativo,
    [switch]$NaoInterativo,
    [switch]$SomenteAuditarExistentes,
    [switch]$ReavaliarPendentes,
    [ValidateRange(3, 12)][int]$ResultadosPorBusca = 7,
    [ValidateRange(1, 4)][int]$MaxTentativas = 2
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ambiente_portatil.ps1')
$script:Layout = Get-ScriptLayout -ScriptPath $PSCommandPath
$script:Root = $script:Layout.Root
# Fluxo interativo na mesma execucao.
. (Join-Path $script:Root 'execucao_unica.ps1')
. (Join-Path $script:Root 'evidencias_fonte.ps1')
. (Join-Path $script:Root 'autenticacao_ytdlp.ps1')
. (Join-Path $script:Root 'ferramentas_portateis.ps1')
$script:Out = Join-Path $script:Root 'destino'
$script:Control = Join-Path $script:Out '.controle'
$script:Utf8 = New-Object System.Text.UTF8Encoding -ArgumentList $false
$script:StateFile = Join-Path $script:Control 'estado.json'
$script:ReportFile = Join-Path $script:Control 'relatorio.csv'
$script:PendingFile = Join-Path $script:Control 'pendencias.csv'
$script:Lock = $null
$script:State = @{ versao = 1; registros = @{}; videos = @{}; buscas = @{} }
$script:RowsForReport = New-Object 'System.Collections.Generic.List[string]'
$script:RateLimitStreak = 0
$script:NetworkSuspended = $false
$script:Exe = Join-Path $script:Root 'yt-dlp.exe'
$script:JsArgs = @()
$script:AuthArgs = @()
$script:AuthRecoveryAttempted = $false
$script:Fatal = $false
$script:Evidencias = @{}
$script:Policy = 'fidelidade-128-v1'
$script:Ffmpeg = Join-Path $script:Root 'ffmpeg.exe'
$script:Ffprobe = Join-Path $script:Root 'ffprobe.exe'

function Resolve-Input([string]$Path) { return Resolve-ScriptInput -Path $Path -Root $script:Root }
function Normal([string]$Value) {
    if ($null -eq $Value) { return '' }
    $decomposed = $Value.Normalize([Text.NormalizationForm]::FormD).ToLowerInvariant()
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $decomposed.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -eq [Globalization.UnicodeCategory]::NonSpacingMark) { continue }
        if ([char]::IsLetterOrDigit($c)) { [void]$sb.Append($c) }
        else { [void]$sb.Append(' ') }
    }
    return ([regex]::Replace($sb.ToString(), '\s+', ' ')).Trim()
}
function Is-SameText([string]$Text, [string]$Needle) {
    $s = ' ' + (Normal $Text) + ' '
    $n = ' ' + (Normal $Needle) + ' '
    return ($n.Trim().Length -gt 0 -and $s.Contains($n))
}
function Hash-Text([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function To-Hashtable($Item) {
    if ($null -eq $Item) { return $null }
    # No Windows PowerShell, arrays JSON podem manter o wrapper PSObject.
    # Testar arrays antes de PSCustomObject evita serializar suas propriedades CLR.
    if ($Item -is [array]) { return , @($Item | ForEach-Object { To-Hashtable $_ }) }
    if ($Item -is [System.Collections.IDictionary]) {
        $h = @{}; foreach ($k in $Item.Keys) { $h[[string]$k] = To-Hashtable $Item[$k] }; return $h
    }
    if ($Item -is [pscustomobject]) {
        $h = @{}; foreach ($p in $Item.PSObject.Properties) { $h[$p.Name] = To-Hashtable $p.Value }; return $h
    }
    return $Item
}
function Save-State {
    $tmp = Join-Path $script:Control ('.estado.' + [guid]::NewGuid().ToString('N') + '.tmp')
    $backup = Join-Path $script:Control ('.estado.' + [guid]::NewGuid().ToString('N') + '.bak')
    [IO.File]::WriteAllText($tmp, ($script:State | ConvertTo-Json -Depth 25), $script:Utf8)
    try {
        # PowerShell 7/.NET atual rejeita backup nulo em File.Replace.
        if ([IO.File]::Exists($script:StateFile)) { [IO.File]::Replace($tmp, $script:StateFile, $backup) }
        else { [IO.File]::Move($tmp, $script:StateFile) }
    }
    finally {
        if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) }
        if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) }
    }
}
function Quote-WindowsArg([string]$Argument) {
    # Quoting Win32 equivalente a CommandLineToArgvW; nunca executar por shell.
    if ($Argument -notmatch '[\s"]' -and $Argument.Length -gt 0) { return $Argument }
    $x = '"'; $backslashes = 0
    foreach ($ch in $Argument.ToCharArray()) {
        if ($ch -eq '\') { $backslashes++; continue }
        if ($ch -eq '"') { $x += ('\' * ($backslashes * 2 + 1)) + '"' }
        else { $x += ('\' * $backslashes) + $ch }
        $backslashes = 0
    }
    return ($x + ('\' * ($backslashes * 2)) + '"')
}
function Invoke-Ytdlp([string[]]$Arguments, [int]$TimeoutSeconds = 90, [string]$Executable = $script:Exe) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Executable
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.WorkingDirectory = $script:Root
    foreach ($argument in $Arguments) { $psi.ArgumentList.Add([string]$argument) }
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
        $outTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch {}
            try { $p.WaitForExit(5000) | Out-Null } catch {}
            return @{ code = -1; out = ''; err = 'TIMEOUT: processo excedeu o limite'; timeout = $true }
        }
        $p.WaitForExit()
        return @{ code = $p.ExitCode; out = $outTask.GetAwaiter().GetResult(); err = $errTask.GetAwaiter().GetResult(); timeout = $false }
    }
    finally { $p.Dispose() }
}
function Base-Args {
    # Restringir configuracoes externas e nao ativar qualquer pos-processamento.
    return @('--ignore-config', '--no-plugin-dirs', '--encoding', 'utf-8', '--no-playlist', '--no-warnings',
        '--cache-dir', (Join-Path $script:Control 'cache')) + $script:JsArgs + @('--socket-timeout', '20',
        '--retries', '2', '--fragment-retries', '2', '--extractor-retries', '2',
        '--retry-sleep', 'http:exp=2:10', '--abort-on-unavailable-fragments',
        '--fixup', 'never', '--no-embed-metadata')
}
function Diagnose([string]$ErrorText, [bool]$TimedOut) {
    if ($TimedOut) { return @{ tipo = 'timeout'; transiente = $true } }
    $e = $ErrorText.ToLowerInvariant()
    if ($e -match 'private video|is private|video is private|this video is unavailable|video unavailable|not available anymore|has been removed|copyright|does not exist|video has been deleted') { return @{ tipo = 'indisponivel'; transiente = $false } }
    if ($e -match 'geo.restrict|not available in your country|not available in your region|geo.block') { return @{ tipo = 'restricao_geografica'; transiente = $false } }
    if ($e -match 'failed to decrypt with dpapi') { return @{ tipo = 'falha_cookies_dpapi'; transiente = $false } }
    if ($e -match 'confirm you.re not a bot|unusual traffic|automated queries') { return @{ tipo = 'confirmacao_anti_bot'; transiente = $false } }
    if ($e -match 'sign in|login|members.only|age.restrict|authentication|required.*cookie|confirm you.re not a bot') { return @{ tipo = 'autenticacao_ou_controle_de_acesso'; transiente = $false } }
    if ($e -match '429|too many requests|rate.limit') { return @{ tipo = 'http_429'; transiente = $true } }
    if ($e -match 'http error 5\d\d|server error|bad gateway|service unavailable|gateway timeout') { return @{ tipo = 'http_5xx'; transiente = $true } }
    if ($e -match 'timed out|timeout|connection reset|connection aborted|temporary failure|network is unreachable|remote end closed|connection refused|ssl.*error') { return @{ tipo = 'rede_ou_timeout'; transiente = $true } }
    if ($e -match 'name or service not known|dns|name resolution|nodename nor servname|getaddrinfo|no such host') { return @{ tipo = 'dns'; transiente = $true } }
    if ($e -match 'requested format is not available|no video formats|no audio formats|format is not available') { return @{ tipo = 'formato_indisponivel'; transiente = $false } }
    if ($e -match '403|forbidden|access denied') { return @{ tipo = 'acesso_limitado_http_403'; transiente = $false } }
    if ($e -match 'permission denied|access is denied|no space left|disk full|file name too long|filename too long|path too long') { return @{ tipo = 'erro_local'; transiente = $false } }
    return @{ tipo = 'falha_nao_classificada'; transiente = $false }
}
function Invoke-Checked([string[]]$Arguments, [int]$Timeout = 100) {
    $last = $null
    $calls = 0
    for ($a = 1; $a -le $MaxTentativas; $a++) {
        $last = Invoke-Ytdlp -Arguments (@($script:AuthArgs) + $Arguments) -TimeoutSeconds $Timeout
        $calls++
        $last['tentativas'] = $calls
        if ($last.code -eq 0) { $script:RateLimitStreak = 0; return $last }
        $d = Diagnose ($last.err + [Environment]::NewLine + $last.out) $last.timeout
        $last['diagnostico'] = $d.tipo
        if ($d.tipo -in @('falha_cookies_dpapi','confirmacao_anti_bot','autenticacao_ou_controle_de_acesso')) {
            if (-not $NaoInterativo -and -not $script:AuthRecoveryAttempted) {
                $script:AuthRecoveryAttempted = $true
                if ($d.tipo -eq 'falha_cookies_dpapi') {
                    Write-Warning 'yt-dlp nao conseguiu descriptografar a sessao escolhida (DPAPI). Se autenticacao for indispensavel, use arquivo:CAMINHO com cookies Netscape validos.'
                } else {
                    Write-Warning 'O servico exige autenticacao. Um arquivo Netscape valido permite usar sessao sem depender de navegador instalado; vazio cancela.'
                }
                $auth = @()
                for ($inputTry = 0; $inputTry -lt 3; $inputTry++) {
                    $choice = Read-InRunValue -Prompt 'Sessao opcional: arquivo:CAMINHO Netscape ou navegador:NOME (vazio cancela)' -NonInteractive:$NaoInterativo
                    if ([string]::IsNullOrWhiteSpace($choice)) { break }
                    try {
                        if ($choice -match '^navegador:(.+)$') { $auth = @(Get-YtdlpAuthArgs -CookiesNavegador $Matches[1]) }
                        elseif ($choice -match '^arquivo:(.+)$') { $auth = @(Get-YtdlpAuthArgs -CookiesArquivo (Resolve-Input $Matches[1])) }
                        else { throw 'Formato de entrada invalido' }
                        break
                    } catch { Write-Warning 'Sessao invalida ou arquivo de cookies indisponivel. Confira a entrada.' }
                }
                if ($auth.Count -gt 0) { $script:AuthArgs = $auth; $a--; continue }
            }
            $script:NetworkSuspended = $true
            Write-Warning 'Acesso suspenso: autenticacao cancelada ou ainda bloqueada pelo YouTube.'
            break
        }
        if ($d.tipo -eq 'http_429') {
            $script:RateLimitStreak++
            if ($script:RateLimitStreak -ge 3) { $script:NetworkSuspended = $true; break }
        }
        if (-not $d.transiente -or $a -eq $MaxTentativas) { break }
        Start-Sleep -Seconds ([Math]::Min(20, [Math]::Pow(2, $a) * 3))
    }
    return $last
}
function Get-UrlInfo([string]$Text) {
    $uri = $null
    if (-not [uri]::TryCreate($Text, [UriKind]::Absolute, [ref]$uri)) { throw 'URL sem sintaxe valida' }
    $hostName = $uri.Host.ToLowerInvariant()
    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Port -ne 443 -or
        $hostName -notin @('www.youtube.com', 'youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be')) {
        throw 'URL rejeitada: exigir HTTPS em dominio oficial YouTube, sem credenciais/porta alternativa'
    }
    $params = @{}
    foreach ($fragment in $uri.Query.TrimStart('?').Split('&')) {
        if ($fragment -eq '') { continue }
        $parts = @($fragment -split '=', 2)
        $key = [Net.WebUtility]::UrlDecode($parts[0])
        if ($params.ContainsKey($key)) { throw ('Parametro de URL duplicado: ' + $key) }
        $params[$key] = if ($parts.Count -eq 2) { [Net.WebUtility]::UrlDecode($parts[1]) } else { '' }
    }
    $id = ''
    if ($hostName -eq 'youtu.be') { $id = $uri.AbsolutePath.Trim('/') }
    elseif ($uri.AbsolutePath -eq '/watch') { if ($params.ContainsKey('v')) { $id = $params['v'] } }
    elseif ($uri.AbsolutePath -match '^/(shorts|live)/([a-zA-Z0-9_-]{11})/?$') { $id = $Matches[2] }
    elseif ($uri.AbsolutePath -eq '/results' -and $params.ContainsKey('search_query')) {
        $q = [string]$params['search_query']
        if ($q.Length -lt 3 -or $q.Length -gt 220 -or $q -match '[\x00-\x1F]') { throw 'Termo de pesquisa invalido/abusivo' }
        return @{ tipo = 'busca'; query = $q; url = $Text }
    }
    if ($id -notmatch '^[a-zA-Z0-9_-]{11}$') { throw 'Pagina de pesquisa sem search_query ou URL sem ID de video valido' }
    return @{ tipo = 'video'; id = $id; url = ('https://www.youtube.com/watch?v=' + $id) }
}
function File-Base([string]$Order, [string]$Artist, [string]$Song, [string]$Id) {
    $value = "$Order - $Artist - $Song [$Id]"
    $value = [regex]::Replace($value, '[<>:"/\\|?*\x00-\x1F]', '_')
    $value = [regex]::Replace($value, '[\s\.]+$', '')
    $value = [regex]::Replace($value, '\s+', ' ')
    # A folga inclui extensao, sufixos .part e sistemas Windows sem long paths.
    $maxLength = [Math]::Min(145, (237 - $script:Out.Length))
    if ($maxLength -lt 38) { throw 'Caminho ate destino muito longo para escrita segura em Windows' }
    if ($value.Length -gt $maxLength) {
        $reserve = (' [' + $Id + ']').Length
        $value = $value.Substring(0, $maxLength - $reserve).TrimEnd(' ', '.') + ' [' + $Id + ']'
    }
    if ($value -match '^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])($|\.)') { $value = '_' + $value }
    return $value
}
function Verify-Signature([string]$File, [string]$Ext) {
    try {
        $f = [IO.File]::Open($File, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            if ($f.Length -lt 2048) { return $false }
            $b = New-Object byte[] 16
            [void]$f.Read($b, 0, 16)
            $head = [Text.Encoding]::ASCII.GetString($b)
            switch ($Ext.ToLowerInvariant()) {
                { $_ -in @('m4a', 'mp4') } { return ($head.Substring(4, 4) -eq 'ftyp') }
                { $_ -in @('webm', 'mka') } { return (($b[0] -eq 0x1A) -and ($b[1] -eq 0x45) -and ($b[2] -eq 0xDF) -and ($b[3] -eq 0xA3)) }
                { $_ -in @('opus', 'ogg', 'oga') } { return ($head.StartsWith('OggS') -or (($b[0] -eq 0x1A) -and ($b[1] -eq 0x45))) }
                'mp3' { return ($head.StartsWith('ID3') -or ($b[0] -eq 0xFF -and ($b[1] -band 0xE0) -eq 0xE0)) }
                'aac' { return ($b[0] -eq 0xFF -and ($b[1] -band 0xF0) -eq 0xF0) }
                'flac' { return $head.StartsWith('fLaC') }
                'wav' { return ($head.StartsWith('RIFF') -and $head.Substring(8, 4) -eq 'WAVE') }
                default { return $false }
            }
        }
        finally { $f.Dispose() }
    }
    catch { return $false }
}
function Probe-Audio([string]$File) {
    $run = Invoke-Ytdlp -Executable $script:Ffprobe -Arguments @('-v', 'error', '-protocol_whitelist', 'file',
        '-show_streams', '-show_format', '-show_packets', '-show_entries',
        'packet=size,duration_time:stream=codec_type,codec_name,sample_rate,channels,bit_rate:format=format_name,duration,bit_rate',
        '-of', 'json', '-i', $File) -TimeoutSeconds 180
    if ($run.code -ne 0) { throw ('ffprobe: ' + $run.err) }
    $p = $run.out | ConvertFrom-Json
    $streams = @($p.streams)
    if ($streams.Count -ne 1 -or $streams[0].codec_type -ne 'audio') { throw 'Exigir exatamente um fluxo de audio e nenhum outro fluxo' }
    $bytes = 0.0; $seconds = 0.0; $rates = @{}
    foreach ($packet in @($p.packets)) {
        $duration = 0.0; $size = 0.0
        if (-not [double]::TryParse([string]$packet.duration_time, [Globalization.NumberStyles]::Float,
                [Globalization.CultureInfo]::InvariantCulture, [ref]$duration) -or $duration -le 0 -or
            -not [double]::TryParse([string]$packet.size, [ref]$size) -or $size -le 0) { throw 'Pacotes sem tamanho/duracao mensuraveis' }
        $bytes += $size; $seconds += $duration
        $rates[[Math]::Round($size * 8 / $duration / 1000, 1)] = $true
    }
    if ($seconds -le 0 -or [double]$p.format.duration -le 0) { throw 'Duracao de audio invalida' }
    $stream = $streams[0]
    $codec = [string]$stream.codec_name
    $lossless = $codec -in @('flac', 'alac', 'wavpack', 'ape') -or $codec.StartsWith('pcm_')
    $decode = Invoke-Ytdlp -Executable $script:Ffmpeg -Arguments @('-nostdin', '-v', 'error', '-xerror',
        '-protocol_whitelist', 'file', '-i', $File, '-map', '0:a:0', '-f', 'null', '-') -TimeoutSeconds 300
    if ($decode.code -ne 0 -or $decode.err.Trim()) { throw ('Decodificacao integral falhou: ' + $decode.err) }
    return @{ codec = $codec; container = [string]$p.format.format_name; lossless = $lossless;
        bitrate_medido_kbps = ($bytes * 8 / $seconds / 1000); bitrate_nominal_bps = [string]$stream.bit_rate;
        variacao_pacotes = ($rates.Count -gt 1); duracao = [double]$p.format.duration;
        canais = [int]$stream.channels; amostragem = [int]$stream.sample_rate; integridade = 'decodificacao_integral_ok' 
    }
}
function Test-FinalAudio([string]$File, $Probe) {
    $ext = [IO.Path]::GetExtension($File).ToLowerInvariant()
    $compatible = ($ext -eq '.m4a' -and $Probe.container -match '(^|,)mov(,|$)' -and $Probe.codec -in @('aac', 'alac')) -or
    ($ext -eq '.mp3' -and $Probe.container -eq 'mp3' -and $Probe.codec -eq 'mp3')
    # O resultado final tambem obedece ao piso absoluto; nao adicionar padding.
    return ($compatible -and $Probe.bitrate_medido_kbps -ge 128)
}
function Test-SourceEvidence([string]$Id, [string]$FormatId, [string]$Hash, $Probe) {
    if (-not $Probe.lossless -and $Probe.bitrate_medido_kbps -lt 128) { return @{ok = $false; motivo = 'Fonte comprimida medida abaixo de 128 kbps; proibido inflar bitrate' } }
    $nominal = 0.0
    if (-not $Probe.lossless -and [double]::TryParse([string]$Probe.bitrate_nominal_bps, [ref]$nominal) -and $nominal -gt 0 -and $nominal -lt 128000) {
        return @{ok = $false; motivo = 'Bitrate nominal inferior ao minimo contradiz a admissibilidade da fonte' }
    }
    $key = $Id + '|' + $FormatId + '|' + $Hash
    if (-not $script:Evidencias.ContainsKey($key)) { return @{ok = $false; requer_evidencia = $true; motivo = 'Procedencia/historico da fonte nao comprovados; bitrate e analise tecnica isolados nao atestam fidelidade' } }
    $e = $script:Evidencias[$key]
    if ([double]$e.bitrate_minimo_historico_kbps -gt 0 -and [double]$e.bitrate_minimo_historico_kbps -lt 128) {
        return @{ok = $false; motivo = 'Historico inclui etapa comprimida inferior a 128 kbps; contêiner sem perdas nao recupera qualidade' }
    }
    if ($e.qualidade -eq 'sem_perdas_verificada') {
        if (-not $Probe.lossless) { return @{ok = $false; motivo = 'Evidencia sem perdas contradiz o codec real da fonte' } }
    }
    elseif ($e.qualidade -ne 'perdas_verificadas' -or [double]$e.bitrate_minimo_historico_kbps -lt 128) {
        return @{ok = $false; motivo = 'Historico documentado indica fonte inferior ou qualidade nao comprovada' }
    }
    return @{ok = $true; evidencia = $e; motivo = 'Evidencia externa vinculada ao hash; validacao tecnica independente concluida' }
}
function Complete-Audio([string]$Source, [string]$TargetBase, [string]$Id, $Fmt, [switch]$SolicitarEvidencia) {
    $sourceProbe = Probe-Audio $Source
    if ([double]$Fmt.duracao_origem -gt 0 -and
        [Math]::Abs($sourceProbe.duracao - [double]$Fmt.duracao_origem) -gt [Math]::Max(0.5, [double]$Fmt.duracao_origem * 0.01)) {
        return @{ok = $false; motivo = 'Duracao da fonte diverge dos metadados; possivel truncamento ou fonte incorreta';
            auditoria = @{politica = $script:Policy; validado = $false; origem = $sourceProbe; duracao_esperada = $Fmt.duracao_origem }
        }
    }
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash.ToLowerInvariant()
    $evidence = Test-SourceEvidence $Id $Fmt.id $sourceHash $sourceProbe

    $audit = @{ politica = $script:Policy; origem_sha256 = $sourceHash; origem_formato_id = $Fmt.id;
        origem_url = ('https://www.youtube.com/watch?v=' + $Id); origem = $sourceProbe; conversao = 'nenhuma';
        evidencia = $evidence; validado = $false 
    }
    if (-not $evidence.ok) { return @{ok = $false; motivo = $evidence.motivo; auditoria = $audit } }
    $ext = [IO.Path]::GetExtension($Source).ToLowerInvariant()
    if ($Fmt.operacao -eq 'nativo') {
        if (-not (Test-FinalAudio $Source $sourceProbe)) { return @{ok = $false; motivo = 'Formato nativo contradiz codec, extensao ou minimo medido'; auditoria = $audit } }
        $ready = $Source
    }
    else {
        $work = Join-Path ([IO.Path]::GetDirectoryName($Source)) ('resultado-' + [guid]::NewGuid().ToString('N') + '.m4a')
        $ready = $null
        if ($sourceProbe.codec -in @('aac', 'alac', 'mp3')) {
            if ($sourceProbe.codec -eq 'mp3') { $work = [IO.Path]::ChangeExtension($work, 'mp3') }
            $encoding = @('-c:a', 'copy'); $audit.conversao = 'remux_sem_recodificacao'
            $rates = @(0)
        }
        else {
            $rates = @(128, 136, 160); $audit.conversao = 'transcodificacao_excepcional_aac'
        }
        foreach ($rate in $rates) {
            if ($rate -gt 0) { $encoding = @('-c:a', 'aac', '-b:a', ([string]$rate + 'k')) }
            $convert = Invoke-Ytdlp -Executable $script:Ffmpeg -Arguments (@('-nostdin', '-v', 'error', '-xerror', '-n',
                    '-protocol_whitelist', 'file', '-i', $Source, '-map', '0:a:0', '-map_metadata', '-1', '-vn', '-sn', '-dn') + $encoding + @($work)) -TimeoutSeconds 600
            if ($convert.code -eq 0) {
                $resultProbe = Probe-Audio $work
                if (Test-FinalAudio $work $resultProbe) { $ready = $work; break }
            }
            if ([IO.File]::Exists($work)) { [IO.File]::Delete($work) }
            if ($rate -eq 0) { break }
        }
        if (-not $ready) { return @{ok = $false; motivo = 'Conversao/remux nao produziu resultado admissivel; fonte preservada'; auditoria = $audit } }
    }
    $resultProbe = Probe-Audio $ready
    if (-not (Test-FinalAudio $ready $resultProbe) -or
        [Math]::Abs($resultProbe.duracao - $sourceProbe.duracao) -gt [Math]::Max(0.25, $sourceProbe.duracao * 0.005) -or
        $resultProbe.canais -ne $sourceProbe.canais -or $resultProbe.amostragem -ne $sourceProbe.amostragem) {
        return @{ok = $false; motivo = 'Resultado diverge de duracao, canais, amostragem ou formato exigido'; auditoria = $audit }
    }
    $target = $TargetBase + [IO.Path]::GetExtension($ready).ToLowerInvariant()
    if ([IO.File]::Exists($target)) { return @{ok = $false; motivo = 'Colisao: arquivo final existente preservado'; auditoria = $audit } }
    $audit.resultado = $resultProbe; $audit.validado = $true
    $audit.resultado_sha256 = (Get-FileHash -LiteralPath $ready -Algorithm SHA256).Hash.ToLowerInvariant()
    # Publicar apenas depois de todas as verificacoes. A fonte excepcional fica no controle.
    [IO.File]::Move($ready, $target)
    return @{ok = $true; arquivo = [IO.Path]::GetFileName($target); auditoria = $audit; probe = $resultProbe }
}
function Audit-Legacy {
    foreach ($id in @($script:State.videos.Keys)) {
        $v = $script:State.videos[$id]
        if ($v.auditoria -and $v.auditoria.politica -eq $script:Policy -and $v.auditoria.validado) { continue }
        $name = [string]$v.arquivo
        if ($name -and $name -eq [IO.Path]::GetFileName($name)) {
            $file = Join-Path $script:Out $name
            if ([IO.File]::Exists($file)) {
                $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
                $dir = Join-Path $script:Control 'legado'
                New-Item -ItemType Directory -Force -Path $dir | Out-Null
                $archive = Join-Path $dir ($hash + '-' + $name)
                # Nunca sobrescrever um arquivo preservado.
                if ([IO.File]::Exists($archive)) { throw ('Colisao ao preservar legado: ' + $name) }
                $v.arquivo_legado = 'legado/' + [IO.Path]::GetFileName($archive)
                $v.sha256_legado = $hash
                $v.auditoria_legado = @{ motivo = 'Historico/procedencia nao comprovados na politica atual' }
                try { $v.auditoria_legado.tecnica = Probe-Audio $file } catch { $v.auditoria_legado.erro = $_.Exception.Message }
                # Persistir a intencao antes do movimento permite recuperar interrupcoes.
                Save-State
                [IO.File]::Move($file, $archive)
                $v.arquivo = ''
            }
        }
        foreach ($record in $script:State.registros.Values) {
            if ($record.video_id -eq $id -and $record.resultado -in @('baixado', 'existente')) {
                $record.resultado = 'pendente_qualidade'; $record.arquivo = ''
                $record.motivo = 'Legado preservado no controle; falta comprovar procedencia e conformidade com a politica de 128 kbps'
                $record.auditoria = $v.auditoria_legado
            }
        }
        Save-State
    }
    # Arquivos sem estado tambem nao podem herdar uma conformidade presumida.
    $trusted = @{}
    foreach ($v in $script:State.videos.Values) {
        if ($v.arquivo -and $v.auditoria -and $v.auditoria.validado -and $v.auditoria.politica -eq $script:Policy) { $trusted[[string]$v.arquivo] = $true }
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $script:Out -File)) {
        if ($trusted.ContainsKey($file.Name) -or $file.Extension.ToLowerInvariant() -notin @('.m4a', '.mp3', '.webm', '.mp4', '.opus', '.ogg', '.oga', '.aac', '.flac', '.wav', '.mka')) { continue }
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $dir = Join-Path $script:Control 'nao_rastreados'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $name = [guid]::NewGuid().ToString('N') + $file.Extension.ToLowerInvariant()
        if (-not $script:State.ContainsKey('arquivos_preservados')) { $script:State.arquivos_preservados = @{} }
        $script:State.arquivos_preservados[$name] = @{nome_original = $file.Name; sha256 = $hash;
            caminho = ('nao_rastreados/' + $name); motivo = 'Arquivo sem estado de conformidade; preservado sem atestar qualidade'
        }
        Save-State
        [IO.File]::Move($file.FullName, (Join-Path $dir $name))
    }
}
function Existing-Video([string]$Id, [string]$Order, [string]$Artist, [string]$Song) {
    if (-not $script:State.videos.ContainsKey($Id)) { return $null }
    $v = $script:State.videos[$Id]
    if (-not $v.auditoria -or $v.auditoria.politica -ne $script:Policy -or -not $v.auditoria.validado) {
        if ($script:Evidencias.Count -gt 0 -and -not $SomenteAuditarExistentes) { return $null }
        return @{conflito = $true; qualidade = $true; motivo = 'Download legado sem validacao da procedencia e do minimo de 128 kbps; arquivo preservado no controle' }
    }
    if ([string]$v.artista -ne $Artist -or [string]$v.musica -ne $Song) {
        return @{ conflito = $true; motivo = 'Mesmo ID aprovado para artistas/musicas diferentes; revisar identificacao' }
    }
    $name = [string]$v.arquivo
    if ($name -ne [IO.Path]::GetFileName($name) -or [string]::IsNullOrWhiteSpace($name)) {
        return @{ conflito = $true; motivo = 'Entrada de estado com caminho inseguro' }
    }
    $file = Join-Path $script:Out $name
    if (-not [IO.File]::Exists($file)) { return $null }
    $fi = New-Object System.IO.FileInfo -ArgumentList $file
    if ($fi.Length -ne [long]$v.tamanho -or -not (Verify-Signature $file ([IO.Path]::GetExtension($file).TrimStart('.')))) { return $null }
    if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne [string]$v.sha256) { return $null }
    $probe = Probe-Audio $file
    if (-not (Test-FinalAudio $file $probe)) { return @{conflito = $true; qualidade = $true; motivo = 'Arquivo existente reprovado na politica de qualidade atual' } }
    return @{ conflito = $false; arquivo = $name; formato = [string]$v.formato }
}
function Sort-AudioFormats([object[]]$Items) {
    $sorted = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Items) { if ($null -ne $item) { $sorted.Add($item) } }
    $sorted.Sort([System.Comparison[object]]{
        param($left, $right)
        $cmp = ([int]$left.tier).CompareTo([int]$right.tier)
        if ($cmp -ne 0) { return $cmp }
        $cmp = ([double]$left.quality).CompareTo([double]$right.quality)
        if ($cmp -ne 0) { return $cmp }
        return [System.StringComparer]::Ordinal.Compare([string]$left.id, [string]$right.id)
    })
    return $sorted.ToArray()
}

function Get-Formats($Info) {
    $formats = New-Object 'System.Collections.Generic.List[object]'
    foreach ($f in @($Info.formats)) {
        if ($null -eq $f) { continue }
        $ext = [string]$f.ext
        if ($ext -notin @('m4a', 'mp3', 'webm', 'opus', 'ogg', 'oga', 'aac', 'flac', 'wav', 'mp4', 'mka')) { continue }
        if ([string]$f.vcodec -ne 'none' -or -not $f.acodec -or [string]$f.acodec -eq 'none') { continue }
        # -f aceita expressoes (+,/,...): permitir apenas IDs literais.
        if (-not $f.format_id -or [string]$f.format_id -notmatch '^[A-Za-z0-9_-]{1,45}$') { continue }
        $abr = 0.0
        if ($null -ne $f.abr -and [string]$f.abr -ne '') { $abr = [double]$f.abr }
        elseif ($null -ne $f.tbr -and [string]$f.tbr -ne '') { $abr = [double]$f.tbr }
        $lossless = [string]$f.acodec -match '^(flac|alac|wavpack|ape|pcm_)'
        # Declaracoes baixas sao rejeitadas antes do download; desconhecidas exigem medicao.
        if (-not $lossless -and $abr -gt 0 -and $abr -lt 128) { continue }
        $native = ($ext -eq 'm4a' -and [string]$f.acodec -match '^(mp4a|aac|alac)') -or
        ($ext -eq 'mp3' -and [string]$f.acodec -match '^mp3')
        $operation = if ($native) { 'nativo' } elseif ([string]$f.acodec -match '^(mp4a|aac|alac|mp3)') { 'remux' } else { 'transcodificacao' }
        $tier = if ($native) { 0 } elseif ($operation -eq 'remux') { 1 } else { 2 }
        $distance = if ($lossless) { 0 } elseif ($abr -ge 128) { $abr - 128 } else { [double]::MaxValue }
        $formats.Add([pscustomobject]@{ id = [string]$f.format_id; ext = $ext; codec = [string]$f.acodec;
                abr = $abr; tier = $tier; quality = $distance; operacao = $operation; filesize = $f.filesize; duracao_origem = $Info.duration 
            })
    }
    return @(Sort-AudioFormats -Items ($formats.ToArray()))
}
function Get-Info([string]$Id) {
    $url = 'https://www.youtube.com/watch?v=' + $Id
    $requestArgs = @(Base-Args) + @('--dump-single-json', '--skip-download', '--', $url)
    $result = Invoke-Checked -Arguments $requestArgs -Timeout 105
    if ($result.code -ne 0) { return @{ ok = $false; run = $result } }
    try {
        $info = $result.out | ConvertFrom-Json
        if ([string]$info.id -ne $Id -or $info.is_live -eq $true -or $info.live_status -eq 'is_live') {
            return @{ ok = $false; run = @{ diagnostico = 'metadados_inconsistentes_ou_live'; err = 'ID/live incompativel'; tentativas = $result.tentativas } }
        }
        $formats = @(Get-Formats $info)
        if ($formats.Count -eq 0) { return @{ ok = $false; run = @{ diagnostico = 'sem_fonte_admissivel'; err = 'Nenhuma fonte de audio admissivel: formatos ausentes ou comprimidos declarados abaixo de 128 kbps'; tentativas = $result.tentativas } } }
        return @{ ok = $true; info = $info; formats = $formats; run = $result }
    }
    catch { return @{ ok = $false; run = @{ diagnostico = 'json_ou_metadados_invalidos'; err = $_.Exception.Message; tentativas = $result.tentativas } } }
}
function Identity-Matches($Info, [string]$Artist, [string]$Song) {
    $title = [string]$Info.title
    $owner = ([string]$Info.channel + ' ' + [string]$Info.uploader + ' ' + [string]$Info.artist)
    $track = [string]$Info.track
    $songOk = (Is-SameText $title $Song) -or ((Normal $track) -eq (Normal $Song))
    $artistOk = (Is-SameText $title $Artist) -or (Is-SameText $owner $Artist)
    return ($songOk -and $artistOk)
}
function Candidate-Score($Candidate, [string]$Artist, [string]$Song) {
    $title = [string]$Candidate.title
    $owner = ([string]$Candidate.channel + ' ' + [string]$Candidate.uploader)
    if (-not (Is-SameText $title $Song)) { return -1 }
    if (-not ((Is-SameText $title $Artist) -or (Is-SameText $owner $Artist))) { return -1 }
    $t = Normal $title
    # Nao rejeitar palavras que pertencem ao nome da faixa (ex.: Chain Reaction).
    $noise = (' ' + $t + ' ').Replace((' ' + (Normal $Song) + ' '), ' ').Replace((' ' + (Normal $Artist) + ' '), ' ')
    if ($noise -match '\b(cover|tribute|karaoke|reaction|tutorial|remix|sped up|slowed|nightcore|mashup|live|concert|8d|reverb|lyrics)\b') { return -1 }
    $score = 20
    if (Is-SameText $owner $Artist) { $score += 20 }
    if (Is-SameText $title $Artist) { $score += 10 }
    if ($t -match '\binstrumental\b') { $score += 8 }
    if ($t -match '\b(official audio|topic|audio oficial)\b') { $score += 4 }
    return $score
}
function Is-ExactArtistAudio([string]$Title, [string]$Channel, [string]$Artist, [string]$Song) {
    $a = Normal $Artist; $s = Normal $Song
    $c = Normal $Channel; $t = Normal $Title
    if ($c -notin @($a, ($a + ' topic'))) { return $false }
    return ($t -in @($s, ($s + ' audio'), ($a + ' ' + $s),
            ($a + ' ' + $s + ' audio'), ($a + ' ' + $s + ' official audio')))
}
function Select-AutoCandidate($Items, [string]$Artist, [string]$Song) {
    $exact = @($Items | Where-Object { Is-ExactArtistAudio ([string]$_.titulo) ([string]$_.canal) $Artist $Song })
    if ($exact.Count -ne 1) { return $null }
    return $exact[0]
}
function Search-Candidates([string]$Query, [string]$Artist, [string]$Song) {
    $cacheKey = Hash-Text ($Query + '|' + $Artist + '|' + $Song)
    if (-not $ReavaliarPendentes -and $script:State.buscas.ContainsKey($cacheKey)) {
        return @{ ok = $true; items = @($script:State.buscas[$cacheKey]); tentativas = 0; cache = $true }
    }
    $search = 'ytsearch' + $ResultadosPorBusca + ':' + $Query
    $requestArgs = @('--ignore-config', '--no-plugin-dirs', '--encoding', 'utf-8', '--no-warnings',
        '--cache-dir', (Join-Path $script:Control 'cache')) + $script:JsArgs + @('--flat-playlist', '--dump-single-json',
        '--socket-timeout', '20', '--retries', '2', '--extractor-retries', '2',
        '--retry-sleep', 'http:exp=2:10', '--', $search)
    $result = Invoke-Checked -Arguments $requestArgs -Timeout 105
    if ($result.code -ne 0) { return @{ ok = $false; run = $result; tentativas = $result.tentativas } }
    try {
        $data = $result.out | ConvertFrom-Json
        $found = New-Object 'System.Collections.Generic.List[object]'
        foreach ($c in @($data.entries)) {
            if ($null -eq $c -or [string]$c.id -notmatch '^[a-zA-Z0-9_-]{11}$') { continue }
            $score = Candidate-Score $c $Artist $Song
            if ($score -lt 0) { continue }
            $found.Add(@{ id = [string]$c.id; titulo = [string]$c.title; canal = [string]$c.channel;
                    pontuacao = $score; url = ('https://www.youtube.com/watch?v=' + [string]$c.id) 
                })
        }
        $items = @($found | Sort-Object -Property @{Expression = 'pontuacao'; Descending = $true }, @{Expression = 'id'; Ascending = $true })
        $script:State.buscas[$cacheKey] = $items
        return @{ ok = $true; items = $items; tentativas = $result.tentativas; cache = $false }
    }
    catch { return @{ ok = $false; run = @{diagnostico = 'json_de_busca_invalido'; err = $_.Exception.Message; tentativas = $result.tentativas }; tentativas = $result.tentativas } }
}
function Approved($Row, $Approvals) {
    $order = [string]$Row.Ordem
    if (-not $Approvals.ContainsKey($order)) { return $null }
    $r = $Approvals[$order]
    $id = ([string]$r.VideoId).Trim()
    $flags = @('ArtistaMusicaConferidos', 'VersaoConferida', 'SemVocaisConferido')
    $valid = ($id -match '^[a-zA-Z0-9_-]{11}$')
    foreach ($f in $flags) { if (([string]$r[$f]).Trim().ToUpperInvariant() -notin @('SIM', 'S', 'TRUE', '1')) { $valid = $false } }
    return @{ id = $id; valid = $valid }
}
function New-Record($Row, [string]$Key) {
    return @{ chave = $Key; ordem = [string]$Row.Ordem; artista = [string]$Row.Artista;
        musica = [string]$Row.Musica; url_original = [string]$Row.Link_YouTube;
        tipo_link = [string]$Row.Tipo_link; verificacao_csv = [string]$Row.Verificacao;
        observacoes = [string]$Row.Observacoes; video_id = ''; url_video = ''; titulo_video = '';
        auditoria = @{}; rejeicoes = @(); candidatos = @(); criterio_selecao = ''; formato = ''; codec = ''; bitrate_kbps = ''; arquivo = '';
        tentativas = 0; tentativas_download = 0; resultado = ''; motivo = ''; atualizado_utc = '' 
    }
}
function Finalize-Record($R, [string]$Result, [string]$Reason) {
    $R.resultado = $Result; $R.motivo = $Reason
    $R.atualizado_utc = [DateTime]::UtcNow.ToString('o')
    $script:State.registros[$R.chave] = $R
    Save-State
    $message = ('[{0}] {1} - {2}: {3} | {4}' -f $R.ordem, $R.artista, $R.musica, $Result, $Reason)
    Write-Host $message
}
function Safe-Cell([string]$String) {
    if ($String -match '^\s*[=+@-]') { return "'" + $String }
    return $String
}
function Export-Reports {
    $report = New-Object 'System.Collections.Generic.List[object]'
    $pending = New-Object 'System.Collections.Generic.List[object]'
    foreach ($k in $script:RowsForReport) {
        if (-not $script:State.registros.ContainsKey($k)) { continue }
        $r = $script:State.registros[$k]
        $urls = @($r.candidatos | ForEach-Object { [string]$_.url })
        $rec = [pscustomobject][ordered]@{
            Ordem = $r.ordem; Artista = (Safe-Cell $r.artista); Musica = (Safe-Cell $r.musica)
            URL_original = (Safe-Cell $r.url_original); Tipo_link = (Safe-Cell $r.tipo_link)
            Verificacao_csv = (Safe-Cell $r.verificacao_csv); Observacoes = (Safe-Cell $r.observacoes)
            VideoId = $r.video_id; URL_video_resolvida = $r.url_video; Titulo_video_resolvido = (Safe-Cell $r.titulo_video)
            Auditoria = (Safe-Cell ($r.auditoria | ConvertTo-Json -Depth 15 -Compress)); Rejeicoes = (Safe-Cell ($r.rejeicoes | ConvertTo-Json -Depth 15 -Compress)); Criterio_selecao = $r.criterio_selecao; Formato = $r.formato; Codec = $r.codec; Bitrate_kbps = $r.bitrate_kbps; Arquivo = $r.arquivo
            Tentativas = $r.tentativas; Tentativas_download = $r.tentativas_download; Resultado = $r.resultado
            Motivo = (Safe-Cell $r.motivo); Candidatos = ($urls -join ' | '); Atualizado_UTC = $r.atualizado_utc
        }
        $report.Add($rec)
        if ($r.resultado -notin @('baixado', 'existente')) {
            $pending.Add([pscustomobject][ordered]@{
                    Ordem = $r.ordem; Artista = (Safe-Cell $r.artista); Musica = (Safe-Cell $r.musica);
                    VideoId_sugerido = $(if ($r.video_id) { $r.video_id } elseif (@($r.candidatos).Count -gt 0) { [string]$r.candidatos[0].id } else { '' });
                    Candidato_1 = $(if ($urls.Count -gt 0) { $urls[0] } else { '' });
                    Candidato_2 = $(if ($urls.Count -gt 1) { $urls[1] } else { '' });
                    Candidato_3 = $(if ($urls.Count -gt 2) { $urls[2] } else { '' });
                    Motivo = (Safe-Cell $r.motivo)
                })
        }
    }
    if ($report.Count -gt 0) { $report | Export-Csv -LiteralPath $script:ReportFile -NoTypeInformation -Encoding UTF8 }
    if ($pending.Count -gt 0) { $pending | Export-Csv -LiteralPath $script:PendingFile -NoTypeInformation -Encoding UTF8 }
    elseif (Test-Path -LiteralPath $script:PendingFile) { Remove-Item -LiteralPath $script:PendingFile -Force }
    # Arquivo sugerido e REGENERADO em cada execucao: copie para aprovacoes.csv
    # antes de editar. Campos de atestacao sao sempre deixados vazios.
    $suggestions = New-Object 'System.Collections.Generic.List[object]'
    foreach ($r in $pending) {
        $suggestions.Add([pscustomobject][ordered]@{
                Ordem = $r.Ordem; VideoId = $r.VideoId_sugerido;
                ArtistaMusicaConferidos = ''; VersaoConferida = ''; SemVocaisConferido = '';
                URL_para_ouvir = $r.Candidato_1; Artista = $r.Artista; Musica = $r.Musica
            })
    }
    if ($suggestions.Count -gt 0) {
        $suggestions | Export-Csv -LiteralPath (Join-Path $script:Control 'sugestoes_aprovacao.csv') -NoTypeInformation -Encoding UTF8
    }
    $exampleFile = Join-Path $script:Control 'aprovacoes_modelo.csv'
    if (-not [IO.File]::Exists($exampleFile)) {
        @([pscustomobject][ordered]@{Ordem = ''; VideoId = ''; ArtistaMusicaConferidos = ''; VersaoConferida = ''; SemVocaisConferido = '' }) |
        Export-Csv -LiteralPath $exampleFile -NoTypeInformation -Encoding UTF8
    }
}

try {
    if ($Interativo -and $NaoInterativo) { throw 'Use apenas um modo: Interativo ou NaoInterativo' }
    $NaoInterativo = -not [bool]$Interativo
    $tools = Resolve-ScriptTools -Root $script:Root
    $script:Exe = $tools.Exe
    $script:Ffmpeg = $tools.Ffmpeg
    $script:Ffprobe = $tools.Ffprobe
    $versions = Test-ScriptTools -Tools $tools
    Write-Host ('yt-dlp: ' + $versions.Exe)
    if ($tools.Node) {
        try {
            $nodeRun = Invoke-Ytdlp -Executable $tools.Node -Arguments @('--version') -TimeoutSeconds 15
            if ($nodeRun.code -eq 0 -and -not [string]::IsNullOrWhiteSpace($nodeRun.out)) {
                $script:JsArgs = @('--js-runtimes', ('node:' + $tools.Node))
                Write-Host 'Runtime JavaScript local: Node.js'
            } else { Write-Warning 'Node.js encontrado mas indisponivel; continuando sem runtime explicito.' }
        } catch { Write-Warning 'Node.js incompativel; continuando sem runtime explicito.' }
    } else { Write-Warning 'Node.js ausente; o YouTube pode oferecer menos formatos de audio.' }
    $script:AuthArgs = @(Get-YtdlpAuthArgs -CookiesArquivo $(if ($CookiesArquivo) { Resolve-Input $CookiesArquivo }) -CookiesNavegador $CookiesNavegador)
    $csvPath = Find-ScriptCsv -Root $script:Root -Csv $Csv
    $delim = Get-ScriptCsvDelimiter -Path $csvPath
    if (-not (Test-Path -LiteralPath $csvPath -PathType Leaf)) { throw "CSV nao encontrado: $csvPath" }
    $rows = @(Import-Csv -LiteralPath $csvPath -Delimiter $delim -Encoding UTF8)
    if ($rows.Count -eq 0) { throw 'CSV vazio' }
    $expected = @('Ordem', 'Artista', 'Musica', 'Link_YouTube', 'Tipo_link', 'Verificacao', 'Observacoes')
    foreach ($col in $expected) {
        if ($col -notin @($rows[0].PSObject.Properties.Name)) { throw ('Coluna obrigatoria ausente: ' + $col) }
    }
    $seenOrders = @{}
    foreach ($r in $rows) {
        $o = ([string]$r.Ordem).Trim()
        if ($o -notmatch '^\d+$') { continue }
        if (-not $seenOrders.ContainsKey($o)) { $seenOrders[$o] = 0 }
        $seenOrders[$o]++
    }
    $approvals = @{}
    if ($AprovacoesCsv) {
        $appPath = Resolve-Input $AprovacoesCsv
        if (-not (Test-Path -LiteralPath $appPath -PathType Leaf)) { throw ('Arquivo de aprovacoes inexistente: ' + $appPath) }
        foreach ($item in @(Import-Csv -LiteralPath $appPath -Encoding UTF8)) {
            foreach ($col in @('Ordem', 'VideoId', 'ArtistaMusicaConferidos', 'VersaoConferida', 'SemVocaisConferido')) {
                if ($col -notin @($item.PSObject.Properties.Name)) { throw ('Coluna ausente em aprovacoes: ' + $col) }
            }
            $order = ([string]$item.Ordem).Trim()
            if ($approvals.ContainsKey($order)) { throw ('Aprovacao duplicada para ordem ' + $order) }
            $approvals[$order] = @{ VideoId = $item.VideoId; ArtistaMusicaConferidos = $item.ArtistaMusicaConferidos;
                VersaoConferida = $item.VersaoConferida; SemVocaisConferido = $item.SemVocaisConferido 
            }
        }
    }
    if ($EvidenciasJson) { $script:Evidencias = Import-SourceEvidence $EvidenciasJson } else { $script:Evidencias = Get-LocalSourceEvidence -Root $script:Root -Control $script:Control }
    New-Item -ItemType Directory -Force -Path $script:Control | Out-Null
    # Bloqueia execucoes simultaneas; nao excluir o arquivo de lock para evitar corridas.
    $lockPath = Join-Path $script:Control 'execucao.lock'
    try { $script:Lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { throw 'Outra instancia esta usando este destino (ou lock indisponivel).' }
    if ([IO.File]::Exists($script:StateFile)) {
        $script:State = To-Hashtable (Get-Content -LiteralPath $script:StateFile -Raw -Encoding UTF8 | ConvertFrom-Json)
        foreach ($section in @('registros', 'videos', 'buscas')) { if (-not $script:State.ContainsKey($section)) { $script:State[$section] = @{} } }
    }
    foreach ($tool in @($script:Ffmpeg, $script:Ffprobe)) {
        if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw ('Ferramenta de validacao ausente: ' + $tool) }
    }

    Audit-Legacy
    Write-Host ("Registros: $($rows.Count) | Aprovacoes: $($approvals.Count) | Destino: $script:Out")
    $index = 0
    foreach ($row in $rows) {
        $index++
        $order = ([string]$row.Ordem).Trim()
        $artist = ([string]$row.Artista).Trim()
        $song = ([string]$row.Musica).Trim()
        $url = ([string]$row.Link_YouTube).Trim()
        $key = Hash-Text ($order + [char]31 + $artist + [char]31 + $song + [char]31 + $url)
        $script:RowsForReport.Add($key)
        $rec = if ($script:State.registros.ContainsKey($key)) { $script:State.registros[$key] } else { New-Record $row $key }
        Write-Progress -Activity 'Auditoria/download de audio original' -Status "$index/$($rows.Count): $artist - $song" -PercentComplete (100.0 * $index / $rows.Count)
        try {
            if ($order -notmatch '^\d+$' -or ($seenOrders.ContainsKey($order) -and $seenOrders[$order] -gt 1)) {
                Finalize-Record $rec 'falha' 'Ordem invalida ou duplicada no CSV; demais linhas serao processadas'; continue
            }
            if (-not $artist -or -not $song -or -not $url -or $artist.Length -gt 180 -or $song.Length -gt 180) {
                Finalize-Record $rec 'falha' 'Campos obrigatorios vazios ou muito extensos'; continue
            }
            $urlInfo = Get-UrlInfo $url
            if (($urlInfo.tipo -eq 'busca' -and [string]$row.Tipo_link -notmatch 'Busca') -or
                ($urlInfo.tipo -eq 'video' -and [string]$row.Tipo_link -notmatch 'direto')) {
                Finalize-Record $rec 'falha' 'Tipo_link contradiz a URL real'; continue
            }
            $approval = Approved $row $approvals
            if ($null -ne $approval -and -not $approval.valid) {
                Finalize-Record $rec 'pendente_auditoria' 'Aprovacao incompleta ou ID invalido: exigidos tres SIM'; continue
            }
            if ($null -ne $approval -and $urlInfo.tipo -eq 'video' -and $approval.id -cne $urlInfo.id) {
                Finalize-Record $rec 'falha' 'Aprovacao nao corresponde ao ID da URL direta'; continue
            }
            if ($SomenteAuditarExistentes) {
                if ($rec.resultado -notin @('baixado', 'existente')) {
                    if (-not $rec.resultado) { Finalize-Record $rec 'pendente_qualidade' 'Auditoria local: nenhuma consulta remota realizada' }
                    else { Finalize-Record $rec $rec.resultado $rec.motivo }
                    continue
                }
            }
            # Um estado de sucesso so pode ser reutilizado se o arquivo continuar integro.
            if ($rec.resultado -in @('baixado', 'existente') -and $rec.video_id -match '^[a-zA-Z0-9_-]{11}$' -and
                ($null -eq $approval -or $approval.id -ceq $rec.video_id)) {
                $reuseId = [string]$rec.video_id
                if ($urlInfo.tipo -eq 'video' -and $urlInfo.id -cne $reuseId) {
                    Finalize-Record $rec 'falha' 'Registro anterior nao corresponde ao ID da URL direta'; continue
                }
                $reuseRaw = if ($approvals.ContainsKey($order)) { $approvals[$order] } else { $null }
                $reuseStored = $null
                if ($script:State.videos.ContainsKey($reuseId)) {
                    $reuseVideo = $script:State.videos[$reuseId]
                    if ([string]$reuseVideo.auditoria.origem_url -cne ('https://www.youtube.com/watch?v=' + $reuseId)) {
                        Finalize-Record $rec 'falha' 'Estado existente pertence a outro ID literal de video; arquivo preservado'; continue
                    }
                    $reuseStored = $reuseVideo['aprovacao_musical']
                }
                $reuseProof = Resolve-MusicalApprovalProof -VideoId $reuseId -Artist $artist -Song $song -RawApproval $reuseRaw -StoredProof $reuseStored
                if ($null -eq $reuseProof -and $null -eq $reuseRaw -and -not $NaoInterativo) {
                    $decision = Request-InRunApproval -Order $order -Artist $artist -Song $song -VideoId $reuseId -NonInteractive:$NaoInterativo
                    if ($null -ne $decision) {
                        $approvals[$order] = $decision
                        $reuseProof = Resolve-MusicalApprovalProof -VideoId $reuseId -Artist $artist -Song $song -RawApproval $decision -Origin interativo
                        if ($null -ne $reuseProof) { $rec.criterio_selecao = 'aprovacao_na_execucao' }
                    }
                }
                if ($null -eq $reuseProof) {
                    Finalize-Record $rec 'pendente_auditoria' 'Arquivo preservado: versao e ausencia de vocais sem aprovacao musical valida'; continue
                }
                $prior = Existing-Video $reuseId $order $artist $song
                if ($prior -and -not $prior.conflito) {
                    $script:State.videos[$reuseId].aprovacao_musical = $reuseProof
                    $rec.aprovacao_musical = $reuseProof
                    $rec.auditoria = $script:State.videos[$reuseId].auditoria
                    $rec.auditoria['aprovacao_musical'] = $reuseProof
                    $rec.arquivo = $prior.arquivo; $rec.formato = $prior.formato
                    Finalize-Record $rec 'existente' 'Reexecucao: arquivo integro e aprovacao musical revalidados'
                    continue
                }
                $reason = if ($prior -and $prior.qualidade) { $prior.motivo }else { 'Registro anterior sem arquivo integro; investigar antes de baixar novamente' }
                Finalize-Record $rec 'pendente_qualidade' $reason
                continue
            }

            # Candidatos em cache podem ser reavaliados sem nova consulta remota.
            # Pendencias de acesso e falhas locais devem ser recuperaveis na reexecucao.
            $preserve = $rec.resultado -in @('nao_identificado', 'indisponivel') -or
            ($rec.resultado -eq 'pendente_auditoria' -and @($rec.candidatos).Count -eq 0)
            if ($NaoInterativo -and -not $ReavaliarPendentes -and $null -eq $approval -and $preserve) {
                Write-Host "[$order] Estado anterior preservado; use -ReavaliarPendentes para reconsultar."
                continue
            }
            $videoId = ''
            $autoCandidate = $null
            if ($approval) {
                $videoId = $approval.id
                $rec.criterio_selecao = 'aprovacao_manual'
                if ($urlInfo.tipo -eq 'video' -and $urlInfo.id -cne $videoId) {
                    Finalize-Record $rec 'falha' 'Aprovacao nao corresponde ao ID da URL direta'; continue
                }
            }
            elseif ($urlInfo.tipo -eq 'video') {
                $videoId = $urlInfo.id
                $rec.criterio_selecao = 'url_direta_metadados'
            }
            else {
                if (-not (Is-SameText $urlInfo.query $artist) -or -not (Is-SameText $urlInfo.query $song)) {
                    Finalize-Record $rec 'nao_identificado' 'Pesquisa fornecida nao corresponde claramente a artista e musica'; continue
                }
                if ($script:NetworkSuspended) { Finalize-Record $rec 'pendente_acesso' 'Acesso remoto suspenso apos limite de acesso ou confirmacao anti-bot'; continue }
                $search = Search-Candidates $urlInfo.query $artist $song
                $rec.tentativas = [int]$rec.tentativas + [int]$search.tentativas
                if (-not $search.ok) {
                    $reason = [string]$search.run.diagnostico + ': ' + [string]$search.run.err
                    $status = if ($search.run.diagnostico -in @('http_429', 'dns', 'rede_ou_timeout', 'timeout', 'http_5xx', 'confirmacao_anti_bot', 'autenticacao_ou_controle_de_acesso', 'acesso_limitado_http_403')) { 'pendente_acesso' } else { 'falha' }
                    Finalize-Record $rec $status $reason; continue
                }
                $rec.candidatos = @($search.items)
                if (@($search.items).Count -eq 0) {
                    Finalize-Record $rec 'nao_identificado' 'Busca sem candidatos com titulo e artista coerentes; nenhum resultado escolhido arbitrariamente'; continue
                }
                $autoCandidate = Select-AutoCandidate $search.items $artist $song
                if ($null -eq $autoCandidate) {
                    $decision = Request-InRunApproval -Order $order -Artist $artist -Song $song -Candidates @($search.items) -NonInteractive:$NaoInterativo
                    if ($null -eq $decision) {
                        $rec.video_id = ''; $rec.url_video = ''; $rec.titulo_video = ''
                        Finalize-Record $rec 'pendente_auditoria' 'Selecao nao confirmada nesta execucao; nenhum candidato aprovado automaticamente'; continue
                    }
                    $approvals[$order] = $decision
                    $approval = Approved $row $approvals
                    if ($null -eq $approval -or -not $approval.valid) { throw 'Confirmacao de selecao invalida' }
                    $videoId = $approval.id
                    $rec.criterio_selecao = 'aprovacao_na_execucao'
                }
                else {
                    $videoId = [string]$autoCandidate.id
                    $rec.criterio_selecao = 'busca_exata_canal_artista_unica'
                }
            }
            $rec.video_id = $videoId
            $rec.url_video = 'https://www.youtube.com/watch?v=' + $videoId
            if ($urlInfo.tipo -eq 'busca' -and $approval) {
                # O usuario atesta a escolha; nao tratar resultado de busca como video.
                $rec.candidatos = @(@{id = $videoId; url = $rec.url_video; titulo = 'Aprovado pelo usuario' })
            }
            $rawMusicalApproval = if ($approvals.ContainsKey($order)) { $approvals[$order] } else { $null }
            $storedMusicalProof = $null
            if ($script:State.videos.ContainsKey($videoId)) {
                $storedVideo = $script:State.videos[$videoId]
                if ([string]$storedVideo.auditoria.origem_url -cne $rec.url_video) {
                    Finalize-Record $rec 'falha' 'Estado existente pertence a outro ID literal de video; arquivo preservado'
                    continue
                }
                $storedMusicalProof = $storedVideo['aprovacao_musical']
            }
            $musicalOrigin = if ($rec.criterio_selecao -eq 'aprovacao_na_execucao') { 'interativo' } else { 'arquivo_aprovacoes' }
            $musicalProof = Resolve-MusicalApprovalProof -VideoId $videoId -Artist $artist -Song $song -RawApproval $rawMusicalApproval -StoredProof $storedMusicalProof -Origin $musicalOrigin
            if ($null -eq $musicalProof -and $null -eq $rawMusicalApproval -and -not $NaoInterativo) {
                $decision = Request-InRunApproval -Order $order -Artist $artist -Song $song -VideoId $videoId -NonInteractive:$NaoInterativo
                if ($null -ne $decision) {
                    $approvals[$order] = $decision
                    $musicalProof = Resolve-MusicalApprovalProof -VideoId $videoId -Artist $artist -Song $song -RawApproval $decision -Origin interativo
                    if ($null -ne $musicalProof) { $rec.criterio_selecao = 'aprovacao_na_execucao' }
                }
            }
            if ($null -eq $musicalProof) {
                Finalize-Record $rec 'pendente_auditoria' 'Versao e ausencia de vocais sem aprovacao explicita; metadados nao substituem auditoria musical'
                continue
            }
            $rec.aprovacao_musical = $musicalProof
            $prev = Existing-Video $videoId $order $artist $song
            if ($prev -and $prev.conflito) { $status = if ($prev.qualidade) { 'pendente_qualidade' }else { 'falha' }; Finalize-Record $rec $status $prev.motivo; continue }
            if ($prev) {
                $script:State.videos[$videoId].aprovacao_musical = $musicalProof
                $rec.arquivo = $prev.arquivo; $rec.formato = $prev.formato
                Finalize-Record $rec 'existente' 'Arquivo auditado, tamanho e SHA-256 preservados; download dispensado'; continue
            }
            if ($script:NetworkSuspended) { Finalize-Record $rec 'pendente_acesso' 'Acesso remoto suspenso apos limite de acesso ou confirmacao anti-bot'; continue }
            $infoCheck = Get-Info $videoId
            $rec.tentativas = [int]$rec.tentativas + [int]$infoCheck.run.tentativas
            if (-not $infoCheck.ok) {
                $diag = [string]$infoCheck.run.diagnostico
                $status = if ($diag -in @('indisponivel', 'restricao_geografica', 'sem_audio_nativo')) { 'indisponivel' }
                elseif ($diag -eq 'sem_fonte_admissivel') { 'pendente_qualidade' }
                elseif ($diag -in @('http_429', 'dns', 'rede_ou_timeout', 'timeout', 'http_5xx', 'confirmacao_anti_bot', 'autenticacao_ou_controle_de_acesso', 'acesso_limitado_http_403')) { 'pendente_acesso' } else { 'falha' }
                Finalize-Record $rec $status ($diag + ': ' + [string]$infoCheck.run.err); continue
            }
            $rec.titulo_video = [string]$infoCheck.info.title
            if (-not (Identity-Matches $infoCheck.info $artist $song)) {
                Finalize-Record $rec 'nao_identificado' 'Metadados do video nao confirmam artista e titulo; revisar manualmente'; continue
            }
            if ($null -ne $autoCandidate -and -not (Is-ExactArtistAudio ([string]$infoCheck.info.title) ([string]$infoCheck.info.channel) $artist $song)) {
                Finalize-Record $rec 'pendente_auditoria' 'Metadados completos nao confirmam faixa exata e canal do artista/Topic; revisar manualmente'; continue
            }
            # Somente usar formatos nativos e o ID de formato retornado para ESTE video.
            $formatQueue = New-Object 'System.Collections.Generic.List[object]'
            foreach ($form in @($infoCheck.formats)) { $formatQueue.Add($form) }
            $refreshed = $false
            $attemptedFormats = [System.Collections.Generic.Dictionary[string,bool]]::new([System.StringComparer]::Ordinal)
            $baseName = File-Base $order $artist $song $videoId
            $completed = $false
            $lastError = ''
            $lastDiagnostic = ''
            $fiIndex = 0
            while ($fiIndex -lt $formatQueue.Count) {
                $fmt = $formatQueue[$fiIndex]; $fiIndex++
                if ($attemptedFormats.ContainsKey($fmt.id)) { continue }
                $attemptedFormats[$fmt.id] = $true
                $sourceDir = Join-Path (Join-Path $script:Control 'fontes') $videoId
                New-Item -ItemType Directory -Force -Path $sourceDir | Out-Null
                $filename = $fmt.id + '.' + $fmt.ext
                $target = Join-Path $sourceDir $filename
                $template = Join-Path $sourceDir ($fmt.id + '.%(ext)s')
                $opts = @(Base-Args) + @('--format', $fmt.id, '--output', $template,
                    '--no-overwrites', '--continue', '--part', '--downloader', 'native',
                    '--no-write-info-json', '--no-write-thumbnail', '--no-write-description',
                    '--no-write-subs', '--no-write-auto-subs', '--no-write-comments',
                    '--no-mtime', '--', $rec.url_video)
                $dl = Invoke-Checked -Arguments $opts -Timeout 1800
                $rec.tentativas = [int]$rec.tentativas + [int]$dl.tentativas
                $rec.tentativas_download = [int]$rec.tentativas_download + [int]$dl.tentativas
                if ($dl.code -ne 0) {
                    $lastDiagnostic = [string]$dl.diagnostico
                    $lastError = [string]$dl.diagnostico + ': ' + [string]$dl.err
                    $rec.rejeicoes += @(@{formato_id = $fmt.id; etapa = 'download'; diagnostico = [string]$dl.diagnostico; tentativas = [int]$dl.tentativas })
                    # 403 apos metadados validos pode ser especifico do formato/CDN.
                    # Tentar outros formatos nativos, sem credenciais nem contorno de acesso.
                    if ($dl.diagnostico -in @('formato_indisponivel', 'acesso_limitado_http_403') -and -not $refreshed) {
                        $refreshed = $true
                        $fresh = Get-Info $videoId
                        $rec.tentativas = [int]$rec.tentativas + [int]$fresh.run.tentativas
                        if ($fresh.ok) {
                            foreach ($candidateFmt in @($fresh.formats)) {
                                if (-not $attemptedFormats.ContainsKey($candidateFmt.id)) { $formatQueue.Add($candidateFmt) }
                            }
                            $sorted = @(Sort-AudioFormats -Items ($formatQueue.ToArray()))
                            $formatQueue.Clear()
                            foreach ($candidateFmt in $sorted) { $formatQueue.Add($candidateFmt) }
                            $fiIndex = 0
                        }
                        if ($script:NetworkSuspended) { $lastDiagnostic = [string]$fresh.run.diagnostico; $lastError = [string]$fresh.run.err; break }
                    }
                    if ($dl.diagnostico -notin @('formato_indisponivel', 'acesso_limitado_http_403')) { break }
                    continue
                }
                if (-not [IO.File]::Exists($target) -or -not (Verify-Signature $target $fmt.ext)) {
                    $lastError = 'yt-dlp retornou zero, porem arquivo ausente, pequeno ou com assinatura incompativel'
                    break
                }
                $size = (Get-Item -LiteralPath $target).Length
                if ($null -ne $fmt.filesize -and [string]$fmt.filesize -ne '' -and
                    [double]$fmt.filesize -gt 0 -and $size -lt ([double]$fmt.filesize * 0.97)) {
                    $lastError = 'Arquivo inferior a 97% do tamanho informado pela origem; nao aceitar como completo'
                    break
                }
                try { $result = Complete-Audio $target (Join-Path $script:Out $baseName) $videoId $fmt -SolicitarEvidencia:(-not $NaoInterativo) }
                catch {
                    $result = @{ok = $false; motivo = ('Validacao/conversao rejeitada: ' + $_.Exception.Message);
                        auditoria = @{politica = $script:Policy; validado = $false; origem_formato_id = $fmt.id; erro = $_.Exception.Message }
                    } 
                }
                $rec.auditoria = $result.auditoria
                $rec.auditoria['aprovacao_musical'] = $musicalProof
                if (-not $result.ok) {
                    $lastDiagnostic = 'qualidade'; $lastError = $result.motivo
                    $rec.rejeicoes += @(@{formato_id = $fmt.id; motivo = $lastError; auditoria = $result.auditoria })
                    continue
                }
                $filename = $result.arquivo
                $target = Join-Path $script:Out $filename
                $size = (Get-Item -LiteralPath $target).Length
                $sha = $result.auditoria.resultado_sha256
                $script:State.videos[$videoId] = @{ artista = $artist; musica = $song; arquivo = $filename;
                    tamanho = $size; sha256 = $sha; formato = [IO.Path]::GetExtension($filename).TrimStart('.');
                    codec = $result.probe.codec; bitrate_kbps = $result.probe.bitrate_medido_kbps;
                    auditoria = $result.auditoria; aprovacao_musical = $musicalProof; verificado_utc = [DateTime]::UtcNow.ToString('o') 
                }
                $rec.formato = [IO.Path]::GetExtension($filename).TrimStart('.'); $rec.codec = $result.probe.codec
                $rec.bitrate_kbps = [string]$result.probe.bitrate_medido_kbps; $rec.arquivo = $filename
                $completed = $true
                Finalize-Record $rec 'baixado' 'M4A/MP3 validado; fonte documentada; origem e resultado auditados; detalhes no estado'
                break
            }
            if (-not $completed) {
                $finalStatus = if ($lastDiagnostic -in @('acesso_limitado_http_403', 'confirmacao_anti_bot', 'autenticacao_ou_controle_de_acesso', 'http_429', 'http_5xx', 'dns', 'rede_ou_timeout', 'timeout')) { 'pendente_acesso' } elseif ($lastDiagnostic -eq 'qualidade') { 'pendente_qualidade' } else { 'falha' }
                Finalize-Record $rec $finalStatus $lastError
            }
        }
        catch {
            try { Finalize-Record $rec 'falha' ('Excecao isolada: ' + $_.Exception.Message) }
            catch { Write-Warning ('Falha ao registrar ordem ' + $order + ': ' + $_.Exception.Message) }
        }
    }
}
catch {
    Write-Error ('Erro de inicializacao ou de integridade do lote: ' + $_.Exception.Message) -ErrorAction Continue
    $script:Fatal = $true
}
finally {
    Write-Progress -Activity 'Auditoria/download de audio original' -Completed
    try { if ($script:Lock) { Export-Reports } } catch { Write-Warning ('Falha ao exportar relatorio: ' + $_.Exception.Message) }
    if ($script:Lock) { $script:Lock.Dispose() }
    if ($script:RowsForReport.Count -gt 0) {
        $counts = @{}; foreach ($k in $script:RowsForReport) {
            if (-not $script:State.registros.ContainsKey($k)) { continue }
            $status = [string]$script:State.registros[$k].resultado
            if (-not $counts.ContainsKey($status)) { $counts[$status] = 0 }
            $counts[$status]++
        }
        Write-Host '--- RESUMO ---'
        foreach ($s in @('baixado', 'existente', 'nao_identificado', 'indisponivel', 'pendente_auditoria', 'pendente_acesso', 'pendente_qualidade', 'falha')) {
            $n = if ($counts.ContainsKey($s)) { $counts[$s] } else { 0 }
            Write-Host (('{0}: {1}' -f $s, $n))
        }
        Write-Host ('Relatorio: ' + $script:ReportFile)
        Write-Host ('Pendencias: ' + $script:PendingFile)
    }
}

if ($script:Fatal) { exit 2 }
