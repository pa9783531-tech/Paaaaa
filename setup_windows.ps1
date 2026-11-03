# PakesY v3 - one-click Windows installation/startup.
# Downloads only from the FFmpeg.org-listed Windows build publisher (Gyan),
# its GitHub release mirror, or Windows Package Manager. Local install first.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-Location -LiteralPath $PSScriptRoot

$logFile = Join-Path $PSScriptRoot 'setup_log.txt'
$localBin = Join-Path $PSScriptRoot 'tools\ffmpeg\bin'
$ffmpegPath = Join-Path $localBin 'ffmpeg.exe'
$ffprobePath = Join-Path $localBin 'ffprobe.exe'
$venvDir = Join-Path $PSScriptRoot '.venv'
$venvPython = Join-Path $venvDir 'Scripts\python.exe'

function Log([string]$message) {
    $line = '[PakesY] ' + $message
    Write-Host $line
    try { Add-Content -LiteralPath $logFile -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $line) -Encoding UTF8 } catch {}
}

function Tools-Work([string]$folder) {
    if ([string]::IsNullOrWhiteSpace($folder)) { return $false }
    $ff = Join-Path $folder 'ffmpeg.exe'
    $fp = Join-Path $folder 'ffprobe.exe'
    if (!(Test-Path -LiteralPath $ff -PathType Leaf) -or !(Test-Path -LiteralPath $fp -PathType Leaf)) { return $false }
    try {
        & $ff -version 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return $false }
        & $fp -version 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Find-ExistingVideoTools {
    if (Tools-Work $localBin) { return $localBin }
    foreach ($exe in @('ffmpeg.exe', 'ffprobe.exe')) {
        $cmd = Get-Command $exe -ErrorAction SilentlyContinue
        if ($null -ne $cmd -and $cmd.Source) {
            $folder = Split-Path -Parent $cmd.Source
            if (Tools-Work $folder) { return $folder }
        }
    }
    return $null
}

function Download-File([string]$url, [string]$destination) {
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
    $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
    if ($null -ne $curl) {
        try {
            & $curl.Source --fail --location --retry 3 --retry-delay 2 --connect-timeout 30 --max-time 1800 --output $destination $url
            if (($LASTEXITCODE -eq 0) -and (Test-Path -LiteralPath $destination) -and ((Get-Item -LiteralPath $destination).Length -gt 1000000)) { return }
        } catch {}
        Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
    }
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $destination -TimeoutSec 1800
    if (!(Test-Path -LiteralPath $destination) -or (Get-Item -LiteralPath $destination).Length -lt 1000000) {
        throw 'Downloaded file was unexpectedly small.'
    }
}

function Read-Checksum([string]$url) {
    try {
        $raw = [string](Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 90).Content
    } catch {
        $curl = Get-Command 'curl.exe' -ErrorAction SilentlyContinue
        if ($null -eq $curl) { throw }
        $raw = (& $curl.Source --fail --silent --show-error --location --retry 2 --max-time 90 $url | Out-String)
        if ($LASTEXITCODE -ne 0) { throw 'Could not download SHA-256 checksum.' }
    }
    $hash = [regex]::Match($raw, '(?i)\b[a-f0-9]{64}\b')
    if (!$hash.Success) { throw 'Download provider did not return a valid SHA-256 checksum.' }
    return $hash.Value
}

function Extract-And-Install([string]$zipFile, [string]$extractPath) {
    Expand-Archive -LiteralPath $zipFile -DestinationPath $extractPath -Force
    $probe = Get-ChildItem -LiteralPath $extractPath -Filter 'ffprobe.exe' -File -Recurse -ErrorAction Stop | Select-Object -First 1
    if ($null -eq $probe) { throw 'FFprobe.exe was missing from archive.' }
    $sourceBin = $probe.Directory.FullName
    if (!(Tools-Work $sourceBin)) { throw 'Extracted FFmpeg/FFprobe cannot run on this Windows system.' }
    New-Item -ItemType Directory -Path $localBin -Force | Out-Null
    # Install both into project directory; they will be reused at every launch.
    Copy-Item -LiteralPath (Join-Path $sourceBin 'ffmpeg.exe') -Destination $ffmpegPath -Force
    Copy-Item -LiteralPath (Join-Path $sourceBin 'ffprobe.exe') -Destination $ffprobePath -Force
    if (!(Tools-Work $localBin)) { throw 'Local FFmpeg/FFprobe verification failed.' }
}

function Install-VideoFrom([string]$name, [string]$zipUrl, [string]$shaUrl) {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ('pakesy-video-' + [guid]::NewGuid().ToString('N'))
    $archive = Join-Path $temp 'ffmpeg.zip'
    $unpack = Join-Path $temp 'extracted'
    try {
        New-Item -Path $temp -ItemType Directory -Force | Out-Null
        Log ('Downloading FFmpeg + FFprobe from ' + $name + ' (~110 MB)...')
        $expected = Read-Checksum $shaUrl
        Download-File $zipUrl $archive
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        if ($actual -ine $expected) { throw ('SHA-256 mismatch from ' + $name + '. Download not installed.') }
        Log 'Checksum verified. Extracting video tools...'
        Extract-And-Install $archive $unpack
        return $true
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Try-VideoDownloads {
    try {
        if (Install-VideoFrom 'Gyan official build' `
            'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip' `
            'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip.sha256') { return $true }
    } catch { Log ('Primary download failed: ' + $_.Exception.Message) }

    # GitHub mirror asset is selected by name, rather than hard-coding a version.
    try {
        Log 'Trying the official Gyan GitHub release mirror...'
        $headers = @{ 'User-Agent' = 'PakesY-FFmpeg-Setup' }
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/GyanD/codexffmpeg/releases/latest' -Headers $headers -TimeoutSec 50
        $zipAsset = $release.assets | Where-Object { $_.name -match '(?i)essentials_build\.zip$' } | Select-Object -First 1
        if ($null -eq $zipAsset) { throw 'No Essentials ZIP asset on latest GitHub release.' }
        $hashName = $zipAsset.name + '.sha256'
        $hashAsset = $release.assets | Where-Object { $_.name -eq $hashName } | Select-Object -First 1
        if ($null -eq $hashAsset) { throw 'No matching SHA-256 asset on the GitHub release.' }
        if (Install-VideoFrom 'Gyan GitHub mirror' $zipAsset.browser_download_url $hashAsset.browser_download_url) { return $true }
    } catch { Log ('GitHub mirror failed: ' + $_.Exception.Message) }
    return $false
}

function Try-WingetVideo {
    $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($null -eq $winget) { Log 'Windows Package Manager (winget) is unavailable.'; return $false }
    Log 'Trying Windows Package Manager for FFmpeg Essentials...'
    try {
        & $winget.Source install --id Gyan.FFmpeg.Essentials --exact --silent --accept-source-agreements --accept-package-agreements
        Log ('winget finished with code ' + $LASTEXITCODE)
    } catch { Log ('winget error: ' + $_.Exception.Message) }

    # WinGet does not always refresh PATH within the running console.
    $found = Find-ExistingVideoTools
    if ($found) { $env:PATH = $found + ';' + $env:PATH; return $true }
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
    )
    if ($env:ProgramFiles) { $roots += (Join-Path $env:ProgramFiles 'WinGet\Packages') }
    foreach ($root in $roots) {
        if (!(Test-Path -LiteralPath $root)) { continue }
        $binaries = Get-ChildItem -LiteralPath $root -Filter ffmpeg.exe -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like '*Gyan.FFmpeg*' }
        foreach ($binary in $binaries) {
            if (Tools-Work $binary.Directory.FullName) {
                $env:PATH = $binary.Directory.FullName + ';' + $env:PATH
                return $true
            }
        }
    }
    Log 'winget did not expose a working ffmpeg/ffprobe pair.'
    return $false
}

function Is-PythonWorking([string]$exe, [string[]]$prefix) {
    try {
        & $exe @prefix -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 2)' 2>$null | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch { return $false }
}

function Find-Python {
    $launcher = Get-Command 'py.exe' -ErrorAction SilentlyContinue
    if ($null -ne $launcher -and (Is-PythonWorking $launcher.Source @('-3'))) { return @{ Exe = $launcher.Source; Args = @('-3') } }
    $candidates = @()
    if ($env:LOCALAPPDATA) {
        $dir = Join-Path $env:LOCALAPPDATA 'Programs\Python'
        if (Test-Path -LiteralPath $dir) {
            $candidates += @(Get-ChildItem -LiteralPath $dir -Filter python.exe -File -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.Directory.Name -match '^Python3' } | Select-Object -ExpandProperty FullName)
        }
    }
    $pythonCommand = Get-Command 'python.exe' -ErrorAction SilentlyContinue
    if ($null -ne $pythonCommand) { $candidates += $pythonCommand.Source }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Is-PythonWorking $candidate @()) { return @{ Exe = $candidate; Args = @() } }
    }
    return $null
}

function Ensure-Python {
    $existing = Find-Python
    if ($null -ne $existing) { return $existing }
    $winget = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($null -eq $winget) { throw 'Python 3.10+ was not found and winget is unavailable. Install Python from python.org.' }
    Log 'Python is missing. Installing Python 3.13 for this Windows user...'
    & $winget.Source install --id Python.Python.3.13 --exact --scope user --silent --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw ('Python installation failed, winget exit code: ' + $LASTEXITCODE) }
    $existing = Find-Python
    if ($null -eq $existing) { throw 'Python installation finished, but python.exe was not located. Restart and retry.' }
    return $existing
}

function Start-PakesY {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This startup script is for Windows.' }
    if (-not [Environment]::Is64BitOperatingSystem) { throw '64-bit Windows 10/11 is required.' }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $folder = Find-ExistingVideoTools
    if ($null -eq $folder) {
        Log 'FFmpeg/FFprobe not found. Starting automatic installation.'
        if (Try-VideoDownloads) {
            $folder = $localBin
        } elseif (Try-WingetVideo) {
            $folder = Find-ExistingVideoTools
            if (-not $folder) {
                # winget fallback may have set PATH to the newly found binary directory
                $folder = Find-ExistingVideoTools
            }
        }
    }
    if (-not $folder) { throw 'FFmpeg/FFprobe could not be installed. Check setup_log.txt and your internet connection.' }
    $env:PATH = $folder + ';' + $env:PATH
    Log 'FFmpeg and FFprobe verified and ready.'

    if (!(Test-Path -LiteralPath $venvPython)) {
        $python = Ensure-Python
        Log 'Creating a local Python environment...'
        $pythonExe = [string]$python.Exe
        [string[]]$pythonArgs = $python.Args
        & $pythonExe @pythonArgs -m venv $venvDir
        if ($LASTEXITCODE -ne 0) { throw 'Could not create Python environment.' }
    }
    if (!(Test-Path -LiteralPath $venvPython)) { throw 'Local Python executable was not created.' }

    $requirements = Join-Path $PSScriptRoot 'requirements.txt'
    $reqHash = (Get-FileHash -LiteralPath $requirements -Algorithm SHA256).Hash
    $doneMarker = Join-Path $venvDir 'pakesy_requirements.sha256'
    $installedHash = if (Test-Path -LiteralPath $doneMarker) { (Get-Content -LiteralPath $doneMarker -Raw).Trim() } else { '' }
    if ($installedHash -ne $reqHash) {
        Log 'Installing required Python libraries (first start or after update)...'
        & $venvPython -m pip install --disable-pip-version-check -r $requirements
        if ($LASTEXITCODE -ne 0) { throw 'Installing Python libraries failed.' }
        Set-Content -LiteralPath $doneMarker -Value $reqHash -Encoding ASCII
    }

    Log 'PakesY is starting at http://127.0.0.1:8765'
    Write-Host 'Keep this window open while using the site.'
    try { Start-Process 'http://127.0.0.1:8765' | Out-Null } catch { Log 'Open http://127.0.0.1:8765 manually in your browser.' }
    & $venvPython -m uvicorn app:app --host 127.0.0.1 --port 8765
    if ($LASTEXITCODE -ne 0) { throw ('PakesY server exited with code ' + $LASTEXITCODE) }
}

try {
    Log '----- Windows setup v3 started -----'
    Start-PakesY
    exit 0
} catch {
    Log ('ERROR: ' + $_.Exception.Message)
    Write-Host ''
    Write-Host 'Something failed. A readable error was saved to setup_log.txt.' -ForegroundColor Red
    Write-Host 'PakesY has not disabled Windows security or installed anything without a verification step.'
    exit 1
}
