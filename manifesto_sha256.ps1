#requires -Version 7.0
# GNU SHA256 de assets: apenas sintaxe/correspondencia, sem autenticar origem ou assinatura.
function Get-ManifestAssetSha256 {
    [CmdletBinding()]
    param([AllowNull()][object]$Manifest,[AllowNull()][object]$AssetName)
    if($AssetName -isnot [string] -or $AssetName -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,254}\z'){
        throw [ArgumentException]::new('Nome de asset deve ser um basename ASCII literal de ate 255 caracteres.')
    }
    if($Manifest -isnot [string] -or $Manifest.Length -eq 0 -or $Manifest.Length -gt 1MB){
        throw [ArgumentException]::new('Manifesto deve ser texto nao vazio de ate 1048576 caracteres.')
    }
    $count=0;$hash=''
    foreach($line in ($Manifest -split '\r?\n')){
        if($line -ceq ''){continue}
        $match=[regex]::Match($line,'\A([0-9a-fA-F]{64}) [ *]([A-Za-z0-9][A-Za-z0-9._-]{0,254})\z',[Text.RegularExpressions.RegexOptions]::CultureInvariant)
        if(-not $match.Success){throw [ArgumentException]::new('Linha de manifesto GNU SHA256 de assets invalida.')}
        if([string]::Equals($match.Groups[2].Value,$AssetName,[StringComparison]::Ordinal)){
            $count++;$hash=$match.Groups[1].Value.ToLowerInvariant()
        }
    }
    if($count -ne 1){throw [ArgumentException]::new('Asset deve ocorrer exatamente uma vez no manifesto.')}
    return $hash
}
