. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot '..\lib\nmap-common.ps1')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:TSB_TARGET_ARCH -ne 'x86') {
  throw "Ncat MSVC container build is currently only wired for x86, got $($env:TSB_TARGET_ARCH)"
}

$buildRoot = New-TsbTempDirectory

try {
  $layout = Get-NmapWindowsSourceLayout -BuildRoot $buildRoot -ToolName 'ncat'
  $solutionPath = Join-Path $layout.SourceDir 'mswin32\nmap.sln'
  $libluaProjectPath = Join-Path $layout.SourceDir 'liblua\liblua.vcxproj'
  $releaseDir = Join-Path $layout.SourceDir 'ncat\Release'

  Invoke-TsbNative -FilePath 'msbuild.exe' -ArgumentList @($libluaProjectPath, '/m', '/t:Build', '/p:Configuration=Release', '/p:Platform=Win32')
  Invoke-NmapMsbuild -SolutionPath $solutionPath -Target 'ncat' -Configuration 'Ncat Static' -Platform 'Win32'

  Copy-TsbArtifact -SourcePath (Join-Path $releaseDir 'ncat.exe') -DestinationName 'ncat.exe'
}
finally {
  Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
}