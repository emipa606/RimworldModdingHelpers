@{
    # Include default rules. Disable noisy ones explicitly below.
    IncludeDefaultRules = $true

    ExcludeRules = @(
        'PSUseDeclaredVarsMoreThanAssignments',      # allow intentional pipelines
        'PSAvoidUsingWriteHost'                      # project uses WriteMessage wrapper; Write-Host allowed in wrapper
    )

    Rules = @{
        PSPlaceOpenBrace = @{ Enable = $true; OnSameLine = $true }
        PSPlaceCloseBrace = @{ Enable = $true; NewLine = $true }
        PSUseConsistentIndentation = @{ Enable = $true; IndentationSize = 4; Kind = 'space' }
        PSUseConsistentWhitespace = @{ Enable = $true }
        PSAvoidTrailingWhitespace = @{ Enable = $true }
        PSUseSingularNouns = @{ Enable = $true }
        PSUseApprovedVerbs = @{ Enable = $true }
    }
}
