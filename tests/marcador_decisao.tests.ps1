#requires -Version 7.0
# RCF 7.3: testes determinísticos Get-CollectionMarkerDecision, sem I/O/midia/main.
$ErrorActionPreference = 'Stop'
$script:root = $PSScriptRoot
$script:parent = Split-Path -Path $script:root -Parent
$script:initialCulture = [Globalization.CultureInfo]::CurrentCulture.Name
$script:initialUICulture = [Globalization.CultureInfo]::CurrentUICulture.Name
. (Join-Path -Path $script:parent -ChildPath 'editorial_audio.ps1')

$script:passCount = 0
function Assert-Eq {
    param([string]$label, $actual, $expected)
    if ([string]::Equals([string]$actual, [string]$expected, [StringComparison]::Ordinal)) {
        $script:passCount++
    } else {
        throw "FALHA ${label}: esperado '$expected', obtido '$actual'"
    }
}

# Casos da matriz determinística
Assert-Eq 'pedido vazio => keep + current' (Get-CollectionMarkerDecision -CurrentValue 'AC/DC' -RequestedValue '').Action 'keep'
Assert-Eq 'pedido vazio => keep + current' (Get-CollectionMarkerDecision -CurrentValue 'AC/DC' -RequestedValue '').Value 'AC/DC'
Assert-Eq 'pedido vazio => keep + current' (Get-CollectionMarkerDecision -CurrentValue 'AC/DC' -RequestedValue '').Reason 'absent'

Assert-Eq 'current null => apply pedido' (Get-CollectionMarkerDecision -CurrentValue $null -RequestedValue 'ac/dc').Action 'apply'
Assert-Eq 'current null => apply pedido' (Get-CollectionMarkerDecision -CurrentValue $null -RequestedValue 'ac/dc').Value 'Ac/dc'
Assert-Eq 'current null => apply pedido' (Get-CollectionMarkerDecision -CurrentValue $null -RequestedValue 'ac/dc').Reason 'empty_field'

Assert-Eq 'pedido igual current => keep' (Get-CollectionMarkerDecision -CurrentValue 'Ac/dc' -RequestedValue 'ac/dc').Action 'keep'
Assert-Eq 'pedido igual current => keep' (Get-CollectionMarkerDecision -CurrentValue 'Ac/dc' -RequestedValue 'ac/dc').Value 'Ac/dc'
Assert-Eq 'pedido igual current => keep' (Get-CollectionMarkerDecision -CurrentValue 'Ac/dc' -RequestedValue 'ac/dc').Reason 'already_present'

Assert-Eq 'pedido diferente current => unsupported' (Get-CollectionMarkerDecision -CurrentValue 'AC/DC' -RequestedValue 'ac/dc').Action 'unsupported'
Assert-Eq 'pedido diferente current => unsupported' (Get-CollectionMarkerDecision -CurrentValue 'AC/DC' -RequestedValue 'ac/dc').Value 'AC/DC'
Assert-Eq 'pedido diferente current => unsupported' (Get-CollectionMarkerDecision -CurrentValue 'AC/DC' -RequestedValue 'ac/dc').Reason 'multiple_values_not_validated'

Assert-Eq 'current somente espaço => unsupported' (Get-CollectionMarkerDecision -CurrentValue '   ' -RequestedValue 'ac/dc').Action 'unsupported'
Assert-Eq 'current somente espaço => unsupported' (Get-CollectionMarkerDecision -CurrentValue '   ' -RequestedValue 'ac/dc').Value '   '
Assert-Eq 'current somente espaço => unsupported' (Get-CollectionMarkerDecision -CurrentValue '   ' -RequestedValue 'ac/dc').Reason 'multiple_values_not_validated'

Assert-Eq 'current ponto-e-vírgula => unsupported' (Get-CollectionMarkerDecision -CurrentValue 'Um; Dois' -RequestedValue 'um;dois').Action 'unsupported'
Assert-Eq 'current ponto-e-vírgula => unsupported' (Get-CollectionMarkerDecision -CurrentValue 'Um; Dois' -RequestedValue 'um;dois').Value 'Um; Dois'
Assert-Eq 'current ponto-e-vírgula => unsupported' (Get-CollectionMarkerDecision -CurrentValue 'Um; Dois' -RequestedValue 'um;dois').Reason 'multiple_values_not_validated'

Assert-Eq 'current vazio + pedido vazio => keep' (Get-CollectionMarkerDecision -CurrentValue '' -RequestedValue '').Action 'keep'
Assert-Eq 'current vazio + pedido vazio => keep' (Get-CollectionMarkerDecision -CurrentValue '' -RequestedValue '').Value ''
Assert-Eq 'current vazio + pedido vazio => keep' (Get-CollectionMarkerDecision -CurrentValue '' -RequestedValue '').Reason 'absent'

Assert-Eq 'current null + pedido null => keep' (Get-CollectionMarkerDecision -CurrentValue $null -RequestedValue $null).Action 'keep'
Assert-Eq 'current null + pedido null => keep' (Get-CollectionMarkerDecision -CurrentValue $null -RequestedValue $null).Value ''
Assert-Eq 'current null + pedido null => keep' (Get-CollectionMarkerDecision -CurrentValue $null -RequestedValue $null).Reason 'absent'

$additional = @(
 @{Name='pedido branco';Current='AC/DC';Requested='   ';Action='keep';Value='AC/DC';Reason='absent'}
 @{Name='igual apos normalizar';Current='Colecao';Requested=' COLECAO ';Action='keep';Value='Colecao';Reason='already_present'}
 @{Name='campo vazio';Current='';Requested='COLECAO';Action='apply';Value='Colecao';Reason='empty_field'}
 @{Name='ambos brancos';Current='';Requested='   ';Action='keep';Value='';Reason='absent'}
)
foreach($case in $additional){
 $decision=Get-CollectionMarkerDecision -CurrentValue $case.Current -RequestedValue $case.Requested
 foreach($field in @('Action','Value','Reason')){Assert-Eq ($case.Name+':'+$field) $decision.$field $case.$field}
}
Assert-Eq 'Culture inalterada' ([Globalization.CultureInfo]::CurrentCulture.Name) $script:initialCulture
Assert-Eq 'UICulture inalterada' ([Globalization.CultureInfo]::CurrentUICulture.Name) $script:initialUICulture
$ordinalCases=@(
 @{Current=('A'+[char]0x00AD);Requested='A';Value=('A'+[char]0x00AD)}
 @{Current=('A'+[char]0x0000);Requested='A';Value=('A'+[char]0x0000)}
)
foreach($case in $ordinalCases){
 $decision=Get-CollectionMarkerDecision -CurrentValue $case.Current -RequestedValue $case.Requested
 Assert-Eq 'Ordinal controle Action' $decision.Action 'unsupported'
 Assert-Eq 'Ordinal controle Value' $decision.Value $case.Value
 Assert-Eq 'Ordinal controle Reason' $decision.Reason 'multiple_values_not_validated'
}
Write-Output "PASS $script:passCount"
