#requires -Version 7.0
function Get-WindowsElevationFacts {
    if ($PSVersionTable.Platform -ne 'Win32NT') {
        throw [PlatformNotSupportedException]::new('Consulta de elevacao exige Windows.')
    }

    # elevation-local-identity-v1: tipo proprio; identidade/token pertencem a cada consulta.
    if(-not ('AudiosYb.Security.WindowsElevationNativeV1' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace AudiosYb.Security {
public static class WindowsElevationNativeV1 {



    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(SafeHandle TokenHandle, int TokenInformationClass, IntPtr TokenInformation, int TokenInformationLength, out int ReturnLength);

    public static int[] ReadCurrent() {
        using (var identity = System.Security.Principal.WindowsIdentity.GetCurrent(System.Security.Principal.TokenAccessLevels.Query)) {
            return new int[] { ReadTokenDword(identity.AccessToken,18), ReadTokenDword(identity.AccessToken,20) };
        }
    }
    private static int ReadTokenDword(SafeHandle token,int kind) {


        IntPtr buffer = Marshal.AllocHGlobal(4);
        try {
            int required;
            if (!GetTokenInformation(token, kind, buffer, 4, out required)) {
                int err = Marshal.GetLastWin32Error();
                throw new Win32Exception(err);
            }
            if (required != 4) {
                throw new InvalidOperationException("Tamanho retornado diferente de 4 bytes");
            }
            return Marshal.ReadInt32(buffer);
        } finally {
            Marshal.FreeHGlobal(buffer);
        }
    }
}
}

'@
    }

    $values = [AudiosYb.Security.WindowsElevationNativeV1]::ReadCurrent()
    $elevationTypeNative = $values[0]
    if ($elevationTypeNative -lt 1 -or $elevationTypeNative -gt 3) {
        throw [InvalidOperationException]::new('Tipo de elevacao nativo desconhecido; nao presumir Default.')
    }
    return @{
        platform='Windows'
        is_elevated=($values[1] -ne 0)
        elevation_type=@('Default','Full','Limited')[$elevationTypeNative-1]
    }
}
