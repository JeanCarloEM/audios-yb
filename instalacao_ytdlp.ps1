#requires -Version 7.0
. (Join-Path $PSScriptRoot 'candidato_ytdlp.ps1')
. (Join-Path $PSScriptRoot 'verificacao_candidato_ytdlp.ps1')
. (Join-Path $PSScriptRoot 'aquisicao_release_ytdlp.ps1')
. (Join-Path $PSScriptRoot 'publicacao_artefato_ytdlp.ps1')

function Install-YtdlpDependency {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [AllowNull()][object]$Architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString(),
        [System.Net.Http.HttpMessageHandler]$Handler = $null,
        [ValidateRange(1,120)][int]$TimeoutSecondsHTTP = 30
    )

    if (-not $IsWindows) { throw [PlatformNotSupportedException]::new('Bootstrap yt-dlp disponivel somente para Windows nesta etapa.') }
    if ($Architecture -isnot [string] -or $Architecture -cnotin @('X64','X86','Arm64')) { throw [ArgumentException]::new('Arquitetura Windows invalida.') }
    $null = Get-Command -Name Invoke-Ytdlp -CommandType Function -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Root não pode ser branco' }
    $directory = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    if (-not $directory.Exists -or $directory -isnot [System.IO.DirectoryInfo]) { throw 'Root deve ser diretório existente' }
    $Root = $directory.FullName

    $targetPath = Join-Path $Root 'yt-dlp.exe'
    if ([System.IO.File]::Exists($targetPath) -or [System.IO.Directory]::Exists($targetPath)) {
        throw 'Destino preexistente preservado; bootstrap nao substitui arquivos existentes'
    }

    # install-nested-lifetime-v1: verificar/publicar antes de sair da Action proprietaria.
    return Invoke-YtdlpCandidateFile -Root $Root -Action {
        param($candidatePath, $writer)
        $package = Get-YtdlpReleasePackage -Architecture $Architecture -Handler $Handler -TimeoutSeconds $TimeoutSecondsHTTP
        $writer.Write($package.bytes, 0, $package.bytes.Length)
        $writer.Flush($true)
        $writer.Dispose()

        return Invoke-YtdlpVerifiedCandidate -Path $candidatePath -ExpectedSha256 $package.release_plan.sha256 -ExpectedVersion $package.release_plan.release_tag -Action {
            param($version, $verifiedPath)
            $publication = Publish-YtdlpReleaseArtifact -Root $Root -SourcePath $verifiedPath -Tag $package.release_plan.release_tag -Manifest $package.manifest -Architecture $Architecture

            return @{
                publication = $publication
                version = $version
                metadata_url = $package.metadata_url
                metadata_sha256 = $package.metadata_sha256
                manifest_sha256 = $package.manifest_sha256
            }
        }
    }
}
