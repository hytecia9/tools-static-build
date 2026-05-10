$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$toolName = $env:TSB_TOOL_NAME
if ([string]::IsNullOrWhiteSpace($toolName)) {
  throw 'TSB_TOOL_NAME is required'
}

$toolScript = Join-Path $PSScriptRoot "tools\$toolName.ps1"
if (-not (Test-Path -LiteralPath $toolScript)) {
  throw "missing tool script: $toolScript"
}

& $toolScript
exit $LASTEXITCODE