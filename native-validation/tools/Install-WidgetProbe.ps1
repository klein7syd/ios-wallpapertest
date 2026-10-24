param([string]$IpaPath, [string]$IPASideDirectory)
$ErrorActionPreference = 'Stop'
try {
    $roots = @()
    if ($IPASideDirectory) { $roots += $IPASideDirectory }
    foreach ($registry in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $roots += Get-ItemProperty $registry -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*iPASide*' } |
            ForEach-Object { $_.InstallLocation }
    }
    $roots += @("$env:LOCALAPPDATA\Programs\iPASide", "$env:LOCALAPPDATA\iPASide", "$env:ProgramFiles\iPASide")
    $install = $roots | Where-Object { $_ -and (Test-Path (Join-Path $_ 'engine\python\python.exe')) } | Select-Object -First 1
    if (-not $install) {
        $install = Read-Host 'Paste the iPASide installation folder (contains iPASide.exe)'
        $install = $install.Trim('"')
    }
    $python = Join-Path $install 'engine\python\python.exe'
    if (-not (Test-Path $python)) { throw 'Cannot find the installed iPASide Python engine.' }
    $package = Get-ChildItem (Join-Path $install 'engine') -Directory -Filter ipaside_engine -Recurse | Select-Object -First 1
    if (-not $package) { throw 'Cannot find ipaside_engine. Send this error and your iPASide version.' }
    if (-not $IpaPath) { $IpaPath = Join-Path $PSScriptRoot 'NativeInstallProbe-unsigned.ipa' }
    if (-not (Test-Path $IpaPath)) {
        $IpaPath = (Read-Host 'Paste the path of NativeInstallProbe-unsigned.ipa').Trim('"')
    }
    $IpaPath = (Resolve-Path $IpaPath).Path
    $bootstrap = "import sys,runpy; sys.path[:0]=sys.argv[2:4]; p=sys.argv[1]; sys.argv=[p]+sys.argv[4:]; runpy.run_path(p,run_name='__main__')"
    & $python -c $bootstrap (Join-Path $PSScriptRoot 'sign_widget_probe.py') $PSScriptRoot $package.Parent.FullName $IpaPath
    if ($LASTEXITCODE -ne 0) { throw 'Probe stopped. Keep the existing iPhone app; send the visible error.' }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
