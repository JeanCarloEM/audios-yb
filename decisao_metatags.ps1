#requires -Version 7.0
# RequestedSource follows string parameter binding: null becomes empty; tag values remain unchanged.
function Get-EditorialTagValueDecision {
    [CmdletBinding()]
    param(
        [AllowNull()][object] $CurrentValue = $null,
        [AllowNull()][object] $RequestedValue = $null,
        [AllowNull()][string] $RequestedSource = ''
    )

    # Regra 1: CurrentValue OU RequestedValue não é null nem string (incluindo arrays vazios)
    if (($null -ne $CurrentValue -and $CurrentValue -isnot [string]) -or ($null -ne $RequestedValue -and $RequestedValue -isnot [string])) {
        return [PSCustomObject]@{
            Action   = 'unsupported'
            Value    = $CurrentValue
            RequestedValue = $RequestedValue
            RequestedSource = $RequestedSource
            Reason   = 'non_scalar_value'
            Conflict = $false
        }
    }

    # Regra 2: RequestedValue null ou string somente whitespace
    if ($null -eq $RequestedValue -or [string]::IsNullOrWhiteSpace($RequestedValue)) {
        return [PSCustomObject]@{
            Action   = 'keep'
            Value    = $CurrentValue
            RequestedValue = $RequestedValue
            RequestedSource = $RequestedSource
            Reason   = 'absent'
            Conflict = $false
        }
    }

    # Regra 3: RequestedValue não vazio e RequestedSource null/whitespace
    if ($null -eq $RequestedSource -or [string]::IsNullOrWhiteSpace($RequestedSource)) {
        return [PSCustomObject]@{
            Action   = 'unsupported'
            Value    = $CurrentValue
            RequestedValue = $RequestedValue
            RequestedSource = $RequestedSource
            Reason   = 'missing_source'
            Conflict = $false
        }
    }

    # Regra 4: CurrentValue null ou whitespace e RequestedValue não vazio com origem
    if ($null -eq $CurrentValue -or [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return [PSCustomObject]@{
            Action   = 'apply'
            Value    = $RequestedValue
            RequestedValue = $RequestedValue
            RequestedSource = $RequestedSource
            Reason   = 'empty_field'
            Conflict = $false
        }
    }

    # Regra 5: Ambos não vazios com origem e iguais (Ordinal)
    if ([string]::Equals($CurrentValue, $RequestedValue, [System.StringComparison]::Ordinal)) {
        return [PSCustomObject]@{
            Action   = 'keep'
            Value    = $CurrentValue
            RequestedValue = $RequestedValue
            RequestedSource = $RequestedSource
            Reason   = 'already_present'
            Conflict = $false
        }
    }

    # Regra 6: Ambos não vazios com origem e diferentes (Ordinal)
    return [PSCustomObject]@{
        Action   = 'conflict'
        Value    = $CurrentValue
        RequestedValue = $RequestedValue
        RequestedSource = $RequestedSource
        Reason   = 'existing_value_differs'
        Conflict = $true
    }
}