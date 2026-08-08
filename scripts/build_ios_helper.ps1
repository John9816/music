param(
  [Parameter(Mandatory = $true)]
  [string]$OutputPath
)

$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null
dart compile exe tool/duckmusic_ios_helper.dart -o $OutputPath
