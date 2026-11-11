#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'elevacao_windows.ps1')
# Oracle independente: buffer nativo, separado da implementacao do helper.
# ABI/semantica: Microsoft Learn GetTokenInformation, TOKEN_ELEVATION(_TYPE).
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class ElevationOracle {
 [DllImport("advapi32.dll",SetLastError=true)]
 [return:MarshalAs(UnmanagedType.Bool)]
 private static extern bool GetTokenInformation(SafeHandle token,int kind,IntPtr buffer,int size,out int required);
 public static int Read(SafeHandle token,int kind) {
  IntPtr buffer=Marshal.AllocHGlobal(4);
  try {
   int required;
   if(!GetTokenInformation(token,kind,buffer,4,out required)) throw new Win32Exception(Marshal.GetLastWin32Error());
   if(required!=4) throw new InvalidOperationException("ABI DWORD inesperada");
   return Marshal.ReadInt32(buffer);
  }finally{Marshal.FreeHGlobal(buffer);}
 }
}
'@
$identity=[Security.Principal.WindowsIdentity]::GetCurrent([Security.Principal.TokenAccessLevels]::Query)
try{
 # TOKEN_INFORMATION_CLASS: User=1; ElevationType=18; Elevation=20.
 $nativeType=[ElevationOracle]::Read($identity.AccessToken,18)
 $nativeFlag=[ElevationOracle]::Read($identity.AccessToken,20)
}finally{$identity.Dispose()}
if($nativeType -lt 1 -or $nativeType -gt 3){throw 'Tipo nativo nao documentado; nao inventar expectativa'}
$expectedType=@('Default','Full','Limited')[$nativeType-1]
$script:Checks=0
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
$first=Get-WindowsElevationFacts
Assert ($first -is [Collections.IDictionary] -and (($first.Keys|Sort-Object) -join '|') -ceq 'elevation_type|is_elevated|platform') 'Envelope factual exato'
Assert ($first.platform -ceq 'Windows' -and $first.is_elevated -is [bool]) 'Plataforma/bool exatos'
Assert ($first.elevation_type -ceq $expectedType) 'Tipo deve vir do token atual, nao do username/grupo'
Assert ($first.is_elevated -eq ($nativeFlag -ne 0)) 'TokenIsElevated deve vir da API nativa'
Assert (-not $first.ContainsKey('needs_elevation') -and -not $first.ContainsKey('can_write')) 'Fatos nao decidem necessidade/permissao de caminho'
$second=Get-WindowsElevationFacts
Assert ($second.platform -ceq $first.platform -and $second.elevation_type -ceq $first.elevation_type -and $second.is_elevated -eq $first.is_elevated) 'Nova chamada sem redefinir tipo/alterar estado'
Assert ([Diagnostics.Process]::GetCurrentProcess().Id -gt 0) 'Consulta permanece no processo atual'
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path -Parent $PSScriptRoot) 'elevacao_windows.ps1'),[ref]$t,[ref]$e)
$f=@($a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-WindowsElevationFacts'},$false))
if($e.Count -or $f.Count -ne 1){throw 'Probe de plataforma ambiguo'}
$platform='$PSVersionTable.Platform'
if(([regex]::Matches($f[0].Extent.Text,[regex]::Escape($platform))).Count -ne 1){throw 'Guard de plataforma nao unico'}
$probe=[regex]::Replace($f[0].Extent.Text,'\Afunction\s+Get-WindowsElevationFacts\b','function Get-UnsupportedElevationProbe')
if($probe -ceq $f[0].Extent.Text){throw 'Probe nao renomeado'}
. ([scriptblock]::Create($probe.Replace($platform,"'Unix'")))
$unsupported=$false
try{$null=Get-UnsupportedElevationProbe}catch [PlatformNotSupportedException]{$unsupported=$true}
Assert $unsupported 'Plataforma recusada com tipo correto, antes da API nativa'
'WINDOWS_ELEVATION_FACTS_PASS checks'+$script:Checks+'; leitura do token atual/oracle independente, sem UAC/permissoes/rede'
