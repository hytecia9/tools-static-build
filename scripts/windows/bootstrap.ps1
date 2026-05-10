$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$vsDevCmd = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\BuildTools\Common7\Tools\VsDevCmd.bat'
$entrypoint = 'C:\tsb\windows\entrypoint.ps1'

$archArgument = switch ($env:TSB_TARGET_ARCH) {
  'x86' { '-arch=x86' }
  'x64' { '-arch=amd64' }
  default { throw "unsupported MSVC target arch: $($env:TSB_TARGET_ARCH)" }
}

$command = ('call "{0}" {1} && powershell.exe -NoLogo -ExecutionPolicy Bypass -File "{2}"' -f $vsDevCmd, $archArgument, $entrypoint)

cmd.exe /S /C $command
exit $LASTEXITCODE