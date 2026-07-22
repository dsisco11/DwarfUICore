[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $DwarfSpecArgs
)

& dwarfspec run @DwarfSpecArgs
exit $LASTEXITCODE
