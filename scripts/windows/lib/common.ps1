$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-TsbNative {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$ArgumentList = @()
  )

  & $FilePath @ArgumentList
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath exited with code $LASTEXITCODE"
  }
}

function New-TsbTempDirectory {
  $workRoot = Join-Path $env:SystemDrive 'tsb-work'
  $buildRoot = Join-Path $workRoot ([System.Guid]::NewGuid().ToString())
  New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
  $buildRoot
}

function Invoke-TsbDownloadFile {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath
  )

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutputPath) | Out-Null
  Invoke-TsbNative -FilePath 'curl.exe' -ArgumentList @('-SL', '--output', $OutputPath, $Url)
}

function Expand-TsbArchive {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ArchivePath,
    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null

  if ($ArchivePath.EndsWith('.tar.bz2')) {
    $archiveDirectory = Split-Path -Parent $ArchivePath
    $tarPath = Join-Path $archiveDirectory ([System.IO.Path]::GetFileNameWithoutExtension($ArchivePath))
    Invoke-TsbNative -FilePath '7z.exe' -ArgumentList @('x', $ArchivePath, "-o$archiveDirectory", '-y')
    Invoke-TsbNative -FilePath '7z.exe' -ArgumentList @('x', $tarPath, "-o$DestinationPath", '-y')
    Remove-Item -LiteralPath $tarPath -Force
    return
  }

  throw "unsupported archive format: $ArchivePath"
}

function Get-TsbSingleDirectory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RootPath
  )

  $directory = Get-ChildItem -LiteralPath $RootPath -Directory | Select-Object -First 1
  if ($null -eq $directory) {
    throw "no directory found in $RootPath"
  }

  $directory.FullName
}

function Copy-TsbArtifact {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $true)]
    [string]$DestinationName
  )

  New-Item -ItemType Directory -Force -Path $env:TSB_OUTPUT_DIR | Out-Null
  Copy-Item -LiteralPath $SourcePath -Destination (Join-Path $env:TSB_OUTPUT_DIR $DestinationName) -Force
}

function Copy-TsbDirectory {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,
    [Parameter(Mandatory = $true)]
    [string]$DestinationPath
  )

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $DestinationPath) | Out-Null
  Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Recurse -Force
}