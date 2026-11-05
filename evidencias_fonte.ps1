#requires -Version 5.1
function Import-SourceEvidence([string]$Path) {
    $entries = @{}

        $document = ConvertFrom-Json -InputObject (Get-Content -LiteralPath (Resolve-Input $Path) -Raw -Encoding UTF8)
        foreach ($e in $document) {
            if ([string]$e.video_id -notmatch '^[A-Za-z0-9_-]{11}$' -or [string]$e.formato_id -notmatch '^[A-Za-z0-9_-]{1,45}$' -or
                [string]$e.sha256 -notmatch '^[a-fA-F0-9]{64}$' -or ([string]$e.origem).Length -lt 15 -or
                ([string]$e.historico).Length -lt 20 -or $e.qualidade -notin @('perdas_verificadas', 'sem_perdas_verificada')) {
                throw 'Evidencia invalida: exigir video_id, formato_id, SHA256, origem, historico documentado e qualidade conhecida'
            }
            if ([string]$e.documento_sha256 -notmatch '^[a-fA-F0-9]{64}$' -or -not $e.documento) { throw 'Evidencia exige documento de procedencia e seu SHA256' }
            $docPath = Resolve-Input ([string]$e.documento)
            if (-not (Test-Path -LiteralPath $docPath -PathType Leaf) -or
                (Get-FileHash -LiteralPath $docPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne ([string]$e.documento_sha256).ToLowerInvariant()) {
                throw 'Documento de procedencia ausente ou hash divergente'
            }
            $key = [string]$e.video_id + '|' + [string]$e.formato_id + '|' + ([string]$e.sha256).ToLowerInvariant()
            if ($entries.ContainsKey($key)) { throw 'Evidencia duplicada' }
            $entries[$key] = To-Hashtable $e
        }
    
    return $entries
}

function Find-SourceEvidencePaths([string]$Root, [string]$Control) {
    $candidates = @()

    $dirs = @($Root, $Control)

    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            continue
        }

        $jsonFiles = Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Where-Object { $_.Name -notmatch '\.exemplo\.json$' }

        foreach ($file in $jsonFiles) {
            try {
                $content = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
                $document = ConvertFrom-Json -InputObject $content
                if ($null -eq $document -or -not ($document -is [array] -or $document -is [psobject])) {
                    Write-Warning "JSON ilegível: $($file.FullName)"
                    continue
                }

                $hasValidEntry = $false
                $items = if ($document -is [array]) { $document } else { @($document) }
                foreach ($item in $items) {
                    if ($item.PSObject.Properties.Name -contains 'video_id' -and
                        $item.PSObject.Properties.Name -contains 'formato_id' -and
                        $item.PSObject.Properties.Name -contains 'sha256') {
                        $hasValidEntry = $true
                        break
                    }
                }

                if ($hasValidEntry) {
                    $candidates += $file.FullName
                }
            }
            catch {
                Write-Warning "Falha ao parsear JSON: $($file.FullName) - $($_.Exception.Message)"
                continue
            }
        }
    }

    return ($candidates | Select-Object -Unique | Sort-Object)
}

function Get-LocalSourceEvidence([string]$Root, [string]$Control) {
    $entries = @{}
    $fingerprints = @{}
    $blocked = @{}
    foreach ($path in @(Find-SourceEvidencePaths -Root $Root -Control $Control)) {
        try { $loaded = Import-SourceEvidence $path }
        catch { Write-Warning ('Manifesto rejeitado: ' + $path + ': ' + $_.Exception.Message); continue }
        foreach ($key in $loaded.Keys) {
            if ($blocked.ContainsKey($key)) { continue }
            $canonical = [ordered]@{}
            foreach ($field in @($loaded[$key].Keys | Sort-Object)) { $canonical[$field] = $loaded[$key][$field] }
            $fingerprint = ConvertTo-Json -InputObject $canonical -Depth 30 -Compress
            if ($entries.ContainsKey($key)) {
                if ($fingerprints[$key] -cne $fingerprint) {
                    $entries.Remove($key)
                    $fingerprints.Remove($key)
                    $blocked[$key] = $true
                    Write-Warning ('Evidencias conflitantes; chave excluida: ' + $key)
                }
                continue
            }
            $entries[$key] = $loaded[$key]
            $fingerprints[$key] = $fingerprint
        }
    }
    return $entries
}
