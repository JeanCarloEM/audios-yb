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