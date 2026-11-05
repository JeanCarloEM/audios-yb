#requires -Version 7.0
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'editorial_audio.ps1')
# Expectativas do RCF7.3, com pares Unicode explicitos, independentes do helper.
$smallDeseret = [char]::ConvertFromUtf32(0x10428)
$capitalDeseret = [char]::ConvertFromUtf32(0x10400)
$emoji = [char]::ConvertFromUtf32(0x1F600)
$cases = @(
    @{Input=$null; Expected=''},
    @{Input=''; Expected=''},
    @{Input=" "+[char]9+[char]10; Expected=''},
    @{Input='  MINHA COLETÂNEA  '; Expected='Minha coletânea'},
    @{Input='123 - COLETÂNEA'; Expected='123 - Coletânea'},
    @{Input=' MINHA  COLETÂNEA '; Expected='Minha  coletânea'},
    @{Input=(' MINHA COLETA'+[char]0x302+'NEA '); Expected='Minha coletânea'},
    @{Input=' ação '; Expected='Ação'},
    @{Input='---aÇÃO!?'; Expected='---Ação!?'},
    @{Input=' 123  - ? '; Expected='123  - ?'},
    @{Input=($emoji+' ABC'); Expected=($emoji+' Abc')},
    @{Input=($smallDeseret+' ABC'); Expected=($capitalDeseret+' abc')},
    @{Input=('a '+$capitalDeseret); Expected=('A '+$smallDeseret)},
    @{Input='Ⅻ'; Expected='Ⅻ'},
    @{Input='Ⅻ ABC'; Expected='Ⅻ Abc'},
    @{Input=([string][char]0xA0+'COLETÂNEA'+[char]0xA0); Expected='Coletânea'}
)
$savedCulture = [Globalization.CultureInfo]::CurrentCulture
$savedUiCulture = [Globalization.CultureInfo]::CurrentUICulture
$count = 0
try {
    foreach ($culture in @('pt-BR','tr-TR','en-US')) {
        [Globalization.CultureInfo]::CurrentCulture = [Globalization.CultureInfo]::GetCultureInfo($culture)
        [Globalization.CultureInfo]::CurrentUICulture = [Globalization.CultureInfo]::GetCultureInfo($culture)
        foreach ($case in $cases) {
            $actual = ConvertTo-CollectionMarker -Value $case.Input
            if ($actual -isnot [string] -or $actual -cne $case.Expected) { throw ('Marcador divergente: cultura='+$culture+'; esperado='+$case.Expected+'; obtido='+$actual) }
            if (-not $actual.IsNormalized([Text.NormalizationForm]::FormC)) { throw 'Saida sem NFC' }
            if ([Globalization.CultureInfo]::CurrentCulture.Name -cne $culture -or [Globalization.CultureInfo]::CurrentUICulture.Name -cne $culture) { throw 'Helper mudou cultura global' }
            $count++
        }
    }
} finally {
    [Globalization.CultureInfo]::CurrentCulture = $savedCulture
    [Globalization.CultureInfo]::CurrentUICulture = $savedUiCulture
}
Write-Output ('MARCADOR_CONTRATO_PASS checks='+$count+'; NFC/invariante/prefixos/suplementar; -Marcador ainda indisponivel no principal')
