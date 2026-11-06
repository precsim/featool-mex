param(
    [Parameter(Mandatory = $true)]
    [string]$Directory,
    [Parameter(Mandatory = $true)]
    [string]$ReportFile,
    [switch]$AllowOpenMP,
    [switch]$AllowCompilerRuntime
)

$ErrorActionPreference = "Stop"

$dumpbin = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
if (-not $dumpbin) {
    $programFilesX86 = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86)
    $vswhere = Join-Path $programFilesX86 "Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path -LiteralPath $vswhere)) {
        throw "dumpbin.exe is not on PATH and vswhere.exe is unavailable"
    }
    $vsInstall = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsInstall) {
        throw "Visual Studio C++ tools not found"
    }
    $candidate = Get-ChildItem -LiteralPath "$vsInstall\VC\Tools\MSVC" -Directory |
        Sort-Object Name -Descending |
        Select-Object -First 1
    $dumpbinPath = Join-Path $candidate.FullName "bin\Hostx64\x64\dumpbin.exe"
} else {
    $dumpbinPath = $dumpbin.Source
}

$files = @(
    Get-ChildItem -LiteralPath $Directory -File |
        Where-Object { $_.Extension -in @(".mexw64", ".mex") } |
        Sort-Object Name
)
if ($files.Count -eq 0) {
    throw "no Windows MEX binaries found in $Directory"
}

$reportParent = Split-Path -Parent $ReportFile
if ($reportParent) {
    New-Item -ItemType Directory -Force -Path $reportParent | Out-Null
}
Set-Content -LiteralPath $ReportFile -Value "" -Encoding utf8

$failed = $false
foreach ($file in $files) {
    $headers = (& $dumpbinPath /headers $file.FullName | Out-String)
    $dependents = (& $dumpbinPath /dependents $file.FullName | Out-String)

    Add-Content -LiteralPath $ReportFile -Value "===== $($file.Name) ====="
    Add-Content -LiteralPath $ReportFile -Value $headers
    Add-Content -LiteralPath $ReportFile -Value $dependents

    if ($headers -notmatch "8664 machine \(x64\)") {
        Write-Error "$($file.Name): expected PE x86-64 machine type" -ErrorAction Continue
        $failed = $true
    }

    if (-not $AllowOpenMP -and $dependents -match "(?i)(vcomp|libgomp|libomp|libiomp)") {
        Write-Error "$($file.Name): unexpected OpenMP runtime dependency" -ErrorAction Continue
        $failed = $true
    }

    if (-not $AllowCompilerRuntime -and $dependents -match "(?i)(libgcc|libstdc\+\+|libwinpthread)") {
        Write-Error "$($file.Name): unexpected external MinGW runtime dependency" -ErrorAction Continue
        $failed = $true
    }
}

if ($failed) {
    exit 1
}

Write-Host "Windows binary audit passed for $($files.Count) MEX binaries"
