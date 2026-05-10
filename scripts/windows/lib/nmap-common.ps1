. (Join-Path $PSScriptRoot 'common.ps1')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-MsvcPlatformToolset {
  $toolsetsRoot = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\BuildTools\MSBuild\Microsoft\VC\v180\Platforms\Win32\PlatformToolsets'
  $toolset = Get-ChildItem -LiteralPath $toolsetsRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
  if ($null -eq $toolset) {
    throw "no MSVC platform toolset found in $toolsetsRoot"
  }

  $toolset.Name
}

function Update-NmapPlatformToolset {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir
  )

  $platformToolset = Get-MsvcPlatformToolset
  Get-ChildItem -LiteralPath $SourceDir -Recurse -File | Where-Object { $_.Extension -in @('.vcxproj', '.props') } | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw
    $updated = $content -replace '<PlatformToolset>[^<]+</PlatformToolset>', "<PlatformToolset>$platformToolset</PlatformToolset>"
    if ($updated -ne $content) {
      Set-Content -LiteralPath $_.FullName -Value $updated -Encoding UTF8
    }
  }
}

function Update-NcatStaticProject {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir
  )

  $projectPath = Join-Path $SourceDir 'ncat\ncat.vcxproj'
  [xml]$projectXml = Get-Content -LiteralPath $projectPath -Raw
  $namespaceManager = New-Object System.Xml.XmlNamespaceManager($projectXml.NameTable)
  $namespaceManager.AddNamespace('msb', $projectXml.DocumentElement.NamespaceURI)

  $itemDefinitionGroup = $projectXml.SelectSingleNode("//msb:ItemDefinitionGroup[contains(@Condition, 'Static|Win32')]", $namespaceManager)
  if ($null -eq $itemDefinitionGroup) {
    throw "could not find Static|Win32 configuration in $projectPath"
  }

  $clCompile = $itemDefinitionGroup.SelectSingleNode('msb:ClCompile', $namespaceManager)
  if ($null -ne $clCompile -and $clCompile.AdditionalIncludeDirectories -notmatch '\.\.\\liblua') {
    $clCompile.AdditionalIncludeDirectories = ($clCompile.AdditionalIncludeDirectories -replace ';%\(AdditionalIncludeDirectories\)', ';..\liblua;%(AdditionalIncludeDirectories)')
  }

  $link = $itemDefinitionGroup.SelectSingleNode('msb:Link', $namespaceManager)
  if ($null -ne $link) {
    if ($link.AdditionalDependencies -notmatch '(^|;)liblua\.lib($|;)') {
      $link.AdditionalDependencies = "$($link.AdditionalDependencies);liblua.lib"
    }

    if ($link.AdditionalLibraryDirectories -notmatch '\.\.\\liblua') {
      $link.AdditionalLibraryDirectories = ($link.AdditionalLibraryDirectories -replace ';%\(AdditionalLibraryDirectories\)', ';..\liblua;%(AdditionalLibraryDirectories)')
    }
  }

  $settings = New-Object System.Xml.XmlWriterSettings
  $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
  $settings.Indent = $true
  $writer = [System.Xml.XmlWriter]::Create($projectPath, $settings)
  try {
    $projectXml.Save($writer)
  }
  finally {
    $writer.Dispose()
  }
}

function Update-LibluaProject {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeLibrary
  )

  $projectPath = Join-Path $SourceDir 'liblua\liblua.vcxproj'
  Set-ProjectRuntimeLibrary -ProjectPath $projectPath -ConditionFragments @('Release|Win32') -RuntimeLibrary $RuntimeLibrary

  [xml]$projectXml = Get-Content -LiteralPath $projectPath -Raw
  $namespaceManager = New-Object System.Xml.XmlNamespaceManager($projectXml.NameTable)
  $namespaceManager.AddNamespace('msb', $projectXml.DocumentElement.NamespaceURI)
  $didChange = $false
  $releaseCondition = [string]::Concat([char]39, '$(Configuration)|$(Platform)', [char]39, '==', [char]39, 'Release|Win32', [char]39)

  foreach ($sourceName in @('lua.c', 'luac.c')) {
    $compileNode = $projectXml.SelectSingleNode("//msb:ClCompile[@Include='$sourceName']", $namespaceManager)
    if ($null -eq $compileNode) {
      throw "could not find $sourceName in $projectPath"
    }

    $excludedNode = @($compileNode.ChildNodes | Where-Object {
        $_.LocalName -eq 'ExcludedFromBuild' -and $_.GetAttribute('Condition') -eq $releaseCondition
      }) | Select-Object -First 1
    if ($null -eq $excludedNode) {
      $excludedNode = $projectXml.CreateElement('ExcludedFromBuild', $projectXml.DocumentElement.NamespaceURI)
      $excludedNode.SetAttribute('Condition', $releaseCondition)
      $excludedNode.InnerText = 'true'
      [void]$compileNode.AppendChild($excludedNode)
      $didChange = $true
      continue
    }

    if ($excludedNode.InnerText -ne 'true') {
      $excludedNode.InnerText = 'true'
      $didChange = $true
    }
  }

  if (-not $didChange) {
    return
  }

  $settings = New-Object System.Xml.XmlWriterSettings
  $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
  $settings.Indent = $true
  $writer = [System.Xml.XmlWriter]::Create($projectPath, $settings)
  try {
    $projectXml.Save($writer)
  }
  finally {
    $writer.Dispose()
  }
}

function Set-ProjectRuntimeLibrary {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,
    [Parameter(Mandatory = $true)]
    [string[]]$ConditionFragments,
    [Parameter(Mandatory = $true)]
    [string]$RuntimeLibrary
  )

  [xml]$projectXml = Get-Content -LiteralPath $ProjectPath -Raw
  $namespaceManager = New-Object System.Xml.XmlNamespaceManager($projectXml.NameTable)
  $namespaceManager.AddNamespace('msb', $projectXml.DocumentElement.NamespaceURI)
  $didChange = $false

  foreach ($conditionFragment in $ConditionFragments) {
    $itemDefinitionGroup = $projectXml.SelectSingleNode("//msb:ItemDefinitionGroup[contains(@Condition, '$conditionFragment')]", $namespaceManager)
    if ($null -eq $itemDefinitionGroup) {
      throw "could not find $conditionFragment configuration in $ProjectPath"
    }

    $clCompile = $itemDefinitionGroup.SelectSingleNode('msb:ClCompile', $namespaceManager)
    if ($null -eq $clCompile) {
      throw "missing ClCompile node in $ProjectPath for $conditionFragment"
    }

    $runtimeLibraryNode = $clCompile.SelectSingleNode('msb:RuntimeLibrary', $namespaceManager)
    if ($null -eq $runtimeLibraryNode) {
      $runtimeLibraryNode = $projectXml.CreateElement('RuntimeLibrary', $projectXml.DocumentElement.NamespaceURI)
      $runtimeLibraryNode.InnerText = $RuntimeLibrary
      [void]$clCompile.AppendChild($runtimeLibraryNode)
      $didChange = $true
      continue
    }

    if ($runtimeLibraryNode.InnerText -ne $RuntimeLibrary) {
      $runtimeLibraryNode.InnerText = $RuntimeLibrary
      $didChange = $true
    }
  }

  if (-not $didChange) {
    return
  }

  $settings = New-Object System.Xml.XmlWriterSettings
  $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
  $settings.Indent = $true
  $writer = [System.Xml.XmlWriter]::Create($ProjectPath, $settings)
  try {
    $projectXml.Save($writer)
  }
  finally {
    $writer.Dispose()
  }
}

function Update-Libssh2Project {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir
  )

  $projectPath = Join-Path $SourceDir 'libssh2\win32\libssh2.vcxproj'
  Set-ProjectRuntimeLibrary -ProjectPath $projectPath -ConditionFragments @('Release|Win32') -RuntimeLibrary 'MultiThreaded'
}

function Update-NsockSources {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir
  )

  $sourcePath = Join-Path $SourceDir 'nsock\src\nsock_proxy.c'
  $content = Get-Content -LiteralPath $sourcePath -Raw
  $updated = $content -replace 'if \(end - proxystr > prefix_len &&', 'if ((size_t) (end - proxystr) > prefix_len &&'
  if ($updated -ne $content) {
    Set-Content -LiteralPath $sourcePath -Value $updated -Encoding UTF8
  }
}

function Update-NmapDependencyProjects {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir
  )

  $liblinearProjectPath = Join-Path $SourceDir 'liblinear\liblinear.vcxproj'
  $liblinearContent = Get-Content -LiteralPath $liblinearProjectPath -Raw
  $liblinearUpdated = $liblinearContent -replace 'WIN32;NDEBUG;_LIB;%\(PreprocessorDefinitions\)', 'WIN32;NDEBUG;_LIB;_CRT_NONSTDC_NO_DEPRECATE;%(PreprocessorDefinitions)'
  if ($liblinearUpdated -ne $liblinearContent) {
    Set-Content -LiteralPath $liblinearProjectPath -Value $liblinearUpdated -Encoding UTF8
  }

  $libdnetProjectPath = Join-Path $SourceDir 'libdnet-stripped\libdnet-stripped.vcxproj'
  $libdnetContent = Get-Content -LiteralPath $libdnetProjectPath -Raw
  $libdnetUpdated = $libdnetContent -replace 'WIN32;_LIB;BPF_MAJOR_VERSION;%\(PreprocessorDefinitions\)', 'WIN32;_LIB;BPF_MAJOR_VERSION;_WINSOCK_DEPRECATED_NO_WARNINGS;%(PreprocessorDefinitions)'
  if ($libdnetUpdated -ne $libdnetContent) {
    Set-Content -LiteralPath $libdnetProjectPath -Value $libdnetUpdated -Encoding UTF8
  }

  $libssh2ProjectPath = Join-Path $SourceDir 'libssh2\win32\libssh2.vcxproj'
  $libssh2Content = Get-Content -LiteralPath $libssh2ProjectPath -Raw
  $libssh2Updated = $libssh2Content -replace 'WIN32;NDEBUG;LIBSSH2_WIN32;LIBSSH2_OPENSSL;_LIB;LIBSSH2_LIBRARY;%\(PreprocessorDefinitions\)', 'WIN32;NDEBUG;LIBSSH2_OPENSSL;_LIB;%(PreprocessorDefinitions)'
  if ($libssh2Updated -ne $libssh2Content) {
    Set-Content -LiteralPath $libssh2ProjectPath -Value $libssh2Updated -Encoding UTF8
  }
}

function Get-MsvcCmakeGenerator {
  $capabilitiesJson = & cmake.exe -E capabilities | Out-String
  $capabilities = $capabilitiesJson | ConvertFrom-Json
  $generator = $capabilities.generators |
    Where-Object { $_.name -like 'Visual Studio *' } |
    Sort-Object {
      $match = [regex]::Match($_.name, 'Visual Studio\s+(\d+)')
      if ($match.Success) { [int]$match.Groups[1].Value } else { 0 }
    } -Descending |
    Select-Object -First 1 -ExpandProperty name

  if ([string]::IsNullOrWhiteSpace($generator)) {
    throw 'could not determine a Visual Studio CMake generator'
  }

  $generator
}

function Initialize-NmapPcre2Build {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,
    [Parameter(Mandatory = $true)]
    [bool]$StaticRuntime
  )

  $pcreSourceDir = Join-Path $SourceDir 'libpcre'
  $pcreBuildDir = Join-Path $SourceDir 'mswin32\build-pcre2'
  $pcreReleaseDir = Join-Path $pcreBuildDir 'Release'

  Invoke-TsbNative -FilePath 'cmake.exe' -ArgumentList @(
    '-S', $pcreSourceDir,
    '-B', $pcreBuildDir,
    '-G', 'NMake Makefiles',
    '-Wno-deprecated',
    '-DCMAKE_C_COMPILER=cl.exe',
    '-DCMAKE_BUILD_TYPE=Release',
    '-DBUILD_SHARED_LIBS=OFF',
    '-DPCRE2_BUILD_PCRE2_8=ON',
    '-DPCRE2_BUILD_PCRE2_16=OFF',
    '-DPCRE2_BUILD_PCRE2_32=OFF',
    '-DPCRE2_BUILD_PCRE2GREP=OFF',
    '-DPCRE2_BUILD_TESTS=OFF',
    "-DPCRE2_STATIC_RUNTIME=$($(if ($StaticRuntime) { 'ON' } else { 'OFF' }))",
    '-DPCRE2_SUPPORT_UNICODE=ON'
  )
  Invoke-TsbNative -FilePath 'cmake.exe' -ArgumentList @('--build', $pcreBuildDir, '--target', 'pcre2-8-static')

  New-Item -ItemType Directory -Force -Path $pcreReleaseDir | Out-Null
  Copy-Item -LiteralPath (Join-Path $pcreBuildDir 'pcre2-8-static.lib') -Destination (Join-Path $pcreReleaseDir 'pcre2-8-static.lib') -Force
}

function Update-NmapProjectForExternalPcre2 {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir
  )

  $projectPath = Join-Path $SourceDir 'mswin32\nmap.vcxproj'
  [xml]$projectXml = Get-Content -LiteralPath $projectPath -Raw
  $namespaceManager = New-Object System.Xml.XmlNamespaceManager($projectXml.NameTable)
  $namespaceManager.AddNamespace('msb', $projectXml.DocumentElement.NamespaceURI)

  $projectReference = $projectXml.SelectSingleNode("//msb:ProjectReference[@Include='build-pcre2\pcre2-8-static.vcxproj']", $namespaceManager)
  if ($null -ne $projectReference) {
    [void]$projectReference.ParentNode.RemoveChild($projectReference)

    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $settings.Indent = $true
    $writer = [System.Xml.XmlWriter]::Create($projectPath, $settings)
    try {
      $projectXml.Save($writer)
    }
    finally {
      $writer.Dispose()
    }
  }
}

function Get-NmapWindowsSourceLayout {
  param(
    [Parameter(Mandatory = $true)]
    [string]$BuildRoot,
    [Parameter(Mandatory = $true)]
    [ValidateSet('nmap', 'ncat')]
    [string]$ToolName
  )

  $version = if ([string]::IsNullOrWhiteSpace($env:NMAP_VERSION)) { '7.99' } else { $env:NMAP_VERSION }
  $sourceUrl = if ([string]::IsNullOrWhiteSpace($env:NMAP_SOURCE_URL)) { "https://nmap.org/dist/nmap-$version.tar.bz2" } else { $env:NMAP_SOURCE_URL }
  $archivePath = Join-Path $BuildRoot ([System.IO.Path]::GetFileName($sourceUrl))

  Invoke-TsbDownloadFile -Url $sourceUrl -OutputPath $archivePath | Out-Host
  Expand-TsbArchive -ArchivePath $archivePath -DestinationPath $BuildRoot | Out-Host

  $sourceDir = Get-TsbSingleDirectory -RootPath $BuildRoot
  $auxDir = Join-Path (Split-Path -Parent $sourceDir) 'nmap-mswin32-aux'
  Invoke-TsbNative -FilePath 'svn.exe' -ArgumentList @('export', '--force', '--non-interactive', 'https://svn.nmap.org/nmap-mswin32-aux', $auxDir) | Out-Host
  Update-NmapPlatformToolset -SourceDir $sourceDir
  if ($ToolName -eq 'ncat') {
    Update-LibluaProject -SourceDir $sourceDir -RuntimeLibrary 'MultiThreaded'
  }
  else {
    Update-LibluaProject -SourceDir $sourceDir -RuntimeLibrary 'MultiThreadedDLL'
    Update-NmapDependencyProjects -SourceDir $sourceDir
  }
  Update-NsockSources -SourceDir $sourceDir
  Update-NcatStaticProject -SourceDir $sourceDir
  Update-NmapProjectForExternalPcre2 -SourceDir $sourceDir

  [pscustomobject]@{
    SourceDir = $sourceDir
    AuxDir = $auxDir
  }
}

function Invoke-NmapMsbuild {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SolutionPath,
    [Parameter(Mandatory = $true)]
    [string]$Target,
    [Parameter(Mandatory = $true)]
    [string]$Configuration,
    [string]$Platform = 'Win32'
  )

  if ($Platform -ne 'Win32') {
    throw "unsupported Nmap MSVC platform: $Platform"
  }

  Invoke-TsbNative -FilePath 'msbuild.exe' -ArgumentList @($SolutionPath, '/m', "/t:$Target", "/p:Configuration=$Configuration", "/p:Platform=$Platform")
}

function Copy-NmapRuntimeFiles {
  param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir
  )

  foreach ($fileName in @(
      'nmap.dtd',
      'nmap-mac-prefixes',
      'nmap-os-db',
      'nmap-protocols',
      'nmap-rpc',
      'nmap-service-probes',
      'nmap-services',
      'nmap.xsl',
      'nse_main.lua')) {
    $match = Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Filter $fileName | Select-Object -First 1
    if ($null -eq $match) {
      throw "missing Nmap runtime file: $fileName"
    }

    Copy-TsbArtifact -SourcePath $match.FullName -DestinationName $fileName
  }

  Copy-TsbDirectory -SourcePath (Join-Path $SourceDir 'scripts') -DestinationPath (Join-Path $env:TSB_OUTPUT_DIR 'scripts')
  Copy-TsbDirectory -SourcePath (Join-Path $SourceDir 'nselib') -DestinationPath (Join-Path $env:TSB_OUTPUT_DIR 'nselib')
  Copy-TsbArtifact -SourcePath (Join-Path $SourceDir 'mswin32\nmap_performance.reg') -DestinationName 'nmap_performance.reg'
}