[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('windows-x86_64')]
    [string]$Platform,

    [Parameter(Mandatory = $true)]
    [string]$RunnerDir,

    [Parameter(Mandatory = $true)]
    [string]$RepositoryUrl,

    [string]$RegistrationToken = $env:GITHUB_RUNNER_REGISTRATION_TOKEN,

    [Parameter(Mandatory = $true)]
    [string]$RunnerName,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [switch]$NoService
)

$ErrorActionPreference = 'Stop'

if (-not $RegistrationToken) {
    throw 'Set -RegistrationToken or GITHUB_RUNNER_REGISTRATION_TOKEN'
}

if (-not [Environment]::Is64BitOperatingSystem) {
    throw 'windows-x86_64 requires a 64-bit Windows controller host'
}
$Processors = @(Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop)
if ($Processors.Count -eq 0 -or $Processors[0].Architecture -ne 9) {
    throw 'windows-x86_64 requires an x64 (AMD64) Windows controller host, not ARM64'
}

$RunnerDir = (Resolve-Path -LiteralPath $RunnerDir).Path
$ConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Controller config must be a file: $ConfigPath"
}
$ConfigCmd = Join-Path $RunnerDir 'config.cmd'
if (-not (Test-Path -LiteralPath $ConfigCmd -PathType Leaf)) {
    throw "Expected $ConfigCmd"
}
if (Test-Path -LiteralPath (Join-Path $RunnerDir '.runner')) {
    throw 'Runner directory is already configured. Remove the existing runner before reprovisioning.'
}

if (-not $NoService) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Windows service provisioning must run from an elevated PowerShell session'
    }
}

function Set-ControllerEnvironment {
    $EnvPath = Join-Path $RunnerDir '.env'
    $Existing = @()
    if (Test-Path -LiteralPath $EnvPath) {
        $Existing = Get-Content -LiteralPath $EnvPath |
            Where-Object { $_ -notmatch '^MEX_LEGACY_APPLIANCES_CONFIG=' }
    }
    $Existing += "MEX_LEGACY_APPLIANCES_CONFIG=$ConfigPath"
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($EnvPath, [string[]]$Existing, $Utf8NoBom)
}

# config.cmd may regenerate runner environment files. Seed the value for
# configuration and then write it again after registration before service use.
Set-ControllerEnvironment

$ConfigArgs = @(
    '--unattended',
    '--replace',
    '--url', $RepositoryUrl,
    '--token', $RegistrationToken,
    '--name', $RunnerName,
    '--labels', 'mex-controller',
    '--work', '_work'
)
if (-not $NoService) {
    $ConfigArgs += '--runasservice'
}

Push-Location $RunnerDir
try {
    & $ConfigCmd @ConfigArgs
    if ($LASTEXITCODE -ne 0) {
        throw "config.cmd failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

Set-ControllerEnvironment

if (-not $NoService) {
    $ServiceMarker = Join-Path $RunnerDir '.service'
    if (-not (Test-Path -LiteralPath $ServiceMarker)) {
        throw 'Runner configuration did not create the expected .service marker'
    }
    $ServiceName = (Get-Content -LiteralPath $ServiceMarker -Raw).Trim()
    if (-not $ServiceName) {
        throw 'Runner .service marker is empty'
    }
    $Service = Get-Service -Name $ServiceName
    if ($Service.Status -eq 'Running') {
        Restart-Service -Name $ServiceName
    } else {
        Start-Service -Name $ServiceName
    }
    $Service = Get-Service -Name $ServiceName
    if ($Service.Status -ne 'Running') {
        throw "GitHub Actions runner service $ServiceName is not running"
    }
}

Write-Host "Controller runner '$RunnerName' registered for $Platform."
Write-Host 'No MATLAB/Octave build was executed. Run the MEX controller check workflow next.'
