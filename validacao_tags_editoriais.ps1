#requires -Version 7
function Assert-EditorialTagSnapshot {
 [CmdletBinding()]
 param([AllowNull()][object]$Before,[AllowNull()][object]$After,[AllowNull()][hashtable]$Updates)
 $expected=New-EditorialTagMap -Before $Before -Updates $Updates
 $actual=New-EditorialTagMap -Before $After -Updates @{}
 return (Assert-OrdinalStringMap -Expected $expected -Actual $actual)
}
