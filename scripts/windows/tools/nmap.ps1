. (Join-Path $PSScriptRoot '..\lib\common.ps1')
. (Join-Path $PSScriptRoot '..\lib\nmap-common.ps1')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($env:TSB_TARGET_ARCH -ne 'x86') {
  throw "Nmap MSVC container build is currently only wired for x86, got $($env:TSB_TARGET_ARCH)"
}

$buildRoot = New-TsbTempDirectory

try {
  $layout = Get-NmapWindowsSourceLayout -BuildRoot $buildRoot -ToolName 'nmap'
  $solutionPath = Join-Path $layout.SourceDir 'mswin32\nmap.sln'
  $releaseDir = Join-Path $layout.SourceDir 'mswin32\Release'

  Initialize-NmapPcre2Build -SourceDir $layout.SourceDir -StaticRuntime $false
  Invoke-NmapMsbuild -SolutionPath $solutionPath -Target 'nmap' -Configuration 'Release' -Platform 'Win32'

  Copy-TsbArtifact -SourcePath (Join-Path $releaseDir 'nmap.exe') -DestinationName 'nmap.exe'
  Copy-NmapRuntimeFiles -SourceDir $layout.SourceDir
}
finally {
  Remove-Item -LiteralPath $buildRoot -Recurse -Force -ErrorAction SilentlyContinue
}