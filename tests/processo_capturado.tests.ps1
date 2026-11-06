$ErrorActionPreference = 'Stop'
$script:Root = $PSScriptRoot
$script:HelperPath = Join-Path $script:Root 'processo_capturado.ps1'
$script:ChildPwsh = Join-Path $PSHOME $(if ($IsWindows) { 'pwsh.exe' } else { 'pwsh' })
$script:FixtureDir = Join-Path $script:Root ".runtime-processo-capturado-$([Guid]::NewGuid()) com espacos"
New-Item -ItemType Directory -Path $script:FixtureDir | Out-Null
try {
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $script:ArgvScript = Join-Path $script:FixtureDir 'argv.ps1'
    $script:ArgvContent = @'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
ConvertTo-Json -InputObject @($args) -Compress
'@
    [System.IO.File]::WriteAllText($script:ArgvScript, $script:ArgvContent, $utf8)
    $script:CargaScript = Join-Path $script:FixtureDir 'carga.ps1'
    $script:CargaContent = @'
[Console]::Out.Write(('o' * 100000))
[Console]::Error.Write(('e' * 100000))
'@
    [System.IO.File]::WriteAllText($script:CargaScript, $script:CargaContent, $utf8)
    $script:ErroScript = Join-Path $script:FixtureDir 'erro.ps1'
    $script:ErroContent = @'
[Console]::Error.Write('ERRO_SENTINELA')
exit 7
'@
    [System.IO.File]::WriteAllText($script:ErroScript, $script:ErroContent, $utf8)
    $script:TimeoutScript = Join-Path $script:FixtureDir 'timeout.ps1'
    $script:TimeoutContent = 'Start-Sleep -Seconds 10'
    [System.IO.File]::WriteAllText($script:TimeoutScript, $script:TimeoutContent, $utf8)
    . $script:HelperPath
    $script:ExpectedArgs = @('a b', '', '-literal', 'AC/DC', ('a' + [char]0x00E2 + ' ' + [char]0x00E7), $script:FixtureDir)
    $result = (Invoke-CapturedTestProcess -Program $script:ChildPwsh -Arguments (@('-NoLogo','-NoProfile','-NonInteractive','-File',$script:ArgvScript) + $script:ExpectedArgs)).Stdout
    $received = $result | ConvertFrom-Json
    if ($received.Count -ne $script:ExpectedArgs.Count) { throw "argv count mismatch: $($received.Count) vs $($script:ExpectedArgs.Count)" }
    for ($i = 0; $i -lt $script:ExpectedArgs.Count; $i++) {
        if ($received[$i] -cne $script:ExpectedArgs[$i]) { throw "argv[$i] mismatch: '$($received[$i])' vs '$($script:ExpectedArgs[$i])'" }
    }
    $captured = Invoke-CapturedTestProcess -Program $script:ChildPwsh -Arguments @('-File', $script:CargaScript) -TimeoutMs 30000
    if ($captured.Stdout -cne ('o' * 100000)) { throw "stdout length mismatch: $($captured.Stdout.Length)" }
    if ($captured.Stderr -cne ('e' * 100000)) { throw "stderr length mismatch: $($captured.Stderr.Length)" }
    try {
        Invoke-CapturedTestProcess -Program $script:ChildPwsh -Arguments @('-File', $script:ErroScript) -TimeoutMs 30000
        throw "Deveria lançar por exit 7"
    } catch {
        if (-not ($_.Exception.Message -match 'ExitCode 7' -and $_.Exception.Message -match 'ERRO_SENTINELA')) {
            throw "Mensagem incorreta: $($_.Exception.Message)"
        }
    }
    try {
        Invoke-CapturedTestProcess -Program $script:ChildPwsh -Arguments @('-File', $script:TimeoutScript) -TimeoutMs 300
        throw "Deveria lançar TimeoutException"
    } catch [System.TimeoutException] {
    }
    Write-Host 'PASS' -ForegroundColor Green
    $receipt = [PSCustomObject]@{
        checks = @('argv', 'stdout', 'stderr', 'exit', 'timeout')
        version = $PSVersionTable.PSVersion.ToString()
        os = [Runtime.InteropServices.RuntimeInformation]::OSDescription
    } | ConvertTo-Json -Compress
    $receiptPath = Join-Path $script:FixtureDir 'receipt.json'
    [System.IO.File]::WriteAllText($receiptPath, $receipt, $utf8)
    Write-Host "Receipt: $receiptPath"
}
finally {
}
