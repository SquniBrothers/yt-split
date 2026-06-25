[CmdletBinding()]
param(
    [Alias("u")]
    [Parameter(Mandatory = $false)]
    [string]$Url,

    [Alias("f")]
    [Parameter(Mandatory = $false)]
    [string]$BatchFile,

    [Alias("b")]
    [Parameter(Mandatory = $false)]
    [string]$BaseDir = (Join-Path $HOME "videos"),

    [Alias("k")]
    [Parameter(Mandatory = $false)]
    [switch]$KeepDownloads,

    [Alias("s")]
    [Parameter(Mandatory = $false)]
    [switch]$SelectChapters,

    [Alias("a")]
    [Parameter(Mandatory = $false)]
    [switch]$AccurateCut,

    [Alias("t")]
    [Parameter(Mandatory = $false)]
    [switch]$Thumbnails,

    [Alias("l")]
    [Parameter(Mandatory = $false)]
    [string]$LogFile,

    [Alias("o")]
    [Parameter(Mandatory = $false)]
    [string]$OutputDir,

    [Alias("p")]
    [Parameter(Mandatory = $false)]
    [switch]$PrintChapters,

    [Alias("d")]
    [Parameter(Mandatory = $false)]
    [switch]$DownloadOnly,

    [Alias("q")]
    [Parameter(Mandatory = $false)]
    [ValidateSet('++', '+', '-', '--')]
    [string]$Quality = '+',

    [Alias("h")]
    [Parameter(Mandatory = $false)]
    [switch]$Help
)

[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

$ErrorActionPreference = "Stop"

# ============================================
# Help
# ============================================
if ($Help) {
    Write-Host @"
split.ps1 - Download en split YouTube video's op basis van chapters

GEBRUIK:
    .\split.ps1 -Url <URL> [OPTIES]
    .\split.ps1 -BatchFile <bestand.txt> [OPTIES]

PARAMETERS:
    -Url  (-u)  URL van de YouTube video (of gebruik -BatchFile)
    -BatchFile  (-f)  Tekstbestand met 1 URL per regel (lege regels en regels die met # beginnen worden genegeerd)
    -BaseDir  (-b)  Basis directory (default: `$HOME\videos)
    -OutputDir  (-o)  Eigen output directory (genegeerd in batch-modus)
    -SelectChapters  (-s)  Toon chapters, selecteer interactief (V/n), download alleen geselecteerde
    -Thumbnails  (-t)  Genereer JPG thumbnails per chapter
    -AccurateCut  (-a)  Frame-accurate cuts (re-encode, langzamer)
    -KeepDownloads  (-k)  Bewaar downloads directory na splitsen
    -LogFile  (-l)  Pad voor logbestand
    -PrintChapters  (-p)  Toon chapter lijst en stop
    -DownloadOnly  (-d)  Alleen downloaden (niet splitsen)
    -Quality  (-q)  Kwaliteit: ++ (4K), + (1080p), - (720p), -- (480p)
    -Help  (-h)  Dit help bericht

VOORBEELDEN:
    .\split.ps1 -u "https://youtube.com/watch?v=..."
    .\split.ps1 -u "..." -s -t
    .\split.ps1 -u "..." -d -q "++"
    .\split.ps1 -u "..." -p
    .\split.ps1 -f "urls.txt" -t
"@
    return
}

# ============================================
# Logging
# ============================================
if ($LogFile) {
    Start-Transcript -Path $LogFile -Append | Out-Null
}

# ============================================
# Vereisten check
# ============================================
$requiredCmds = @("yt-dlp", "ffmpeg", "ffprobe")
$missing = @()
foreach ($cmd in $requiredCmds) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        $missing += $cmd
    }
}
if ($missing) {
    Write-Host "[ERROR] Ontbrekende programma's: $($missing -join ', ')" -ForegroundColor Red
    Write-Host "Installeer ze voordat je dit script runt." -ForegroundColor Yellow
    exit 1
}

# ============================================
# JavaScript runtime detectie
# YouTube extractie vereist nu een JS runtime (deno/node/bun).
# Zonder runtime valt yt-dlp terug op beperkte clients en mist formats.
# ============================================
$jsRuntime = $null
foreach ($rt in @('deno', 'node', 'bun')) {
    if (Get-Command $rt -ErrorAction SilentlyContinue) { $jsRuntime = $rt; break }
}
$jsRuntimeArgs = if ($jsRuntime) { @('--js-runtimes', $jsRuntime) } else { @() }
if (-not $jsRuntime) {
    Write-Host "[WARN] Geen JavaScript runtime (deno/node/bun) gevonden." -ForegroundColor Yellow
    Write-Host "       YouTube kan formats missen. Installeer node of deno:" -ForegroundColor Yellow
    Write-Host "       https://github.com/yt-dlp/yt-dlp/wiki/EJS" -ForegroundColor Yellow
}

# ============================================
# Quality mapping
# ============================================
$qualityFormat = switch ($Quality) {
    '++' { "bestvideo[height<=2160]+bestaudio/best[height<=2160]" }
    '+'  { "bestvideo[height<=1080]+bestaudio/best[height<=1080]" }
    '-'  { "bestvideo[height<=720]+bestaudio/best[height<=720]" }
    '--' { "bestvideo[height<=480]+bestaudio/best[height<=480]" }
}

# ============================================
# Helper functies
# ============================================
function Get-SafeFileName {
    param([string]$Name)
    return ($Name -replace ' - ', ' ' -replace '[\s\\/:*?"<>|]+', '_' -replace '_+', '_' -replace '(^_+|_+$)', '')
}

# ============================================
# Eén video verwerken (download + split + thumbnails)
# ============================================
function Invoke-SplitVideo {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$OutDirOverride
    )

    Write-Host ""
    Write-Host "=== Metadata ophalen ===" -ForegroundColor Cyan

    $meta = & yt-dlp @jsRuntimeArgs --dump-json $Url | ConvertFrom-Json
    if (-not $meta) { throw "Kon metadata niet ophalen" }

    $VideoTitle   = $meta.title   -replace '[\\/:*?"<>| ]', '_' -replace '_+', '_' -replace '(^_+|_+$)', ''
    $ChannelName  = $meta.channel -replace '[\\/:*?"<>| ]', '_' -replace '_+', '_' -replace '(^_+|_+$)', ''

    Write-Host "[x] Metadata opgehaald" -ForegroundColor Green
    Write-Host ""
    Write-Host $meta.title
    Write-Host ""
    Write-Host $meta.channel
    Write-Host ""

    $Chapters = $meta.chapters

    # ============================================
    # Print Chapters
    # ============================================
    if ($PrintChapters) {
        if (-not $Chapters) {
            Write-Host "Geen chapters gevonden" -ForegroundColor Yellow
        } else {
            Write-Host "=== Chapters ===" -ForegroundColor Green
            $Chapters | Format-Table start_time, end_time, title
        }
        return
    }

    $OutDir = if ($OutDirOverride) { $OutDirOverride } else { Join-Path $BaseDir "$ChannelName\$VideoTitle" }
    $null = New-Item -ItemType Directory -Force -Path $OutDir

    $JsonFile = Join-Path $OutDir "meta.json"
    $meta | ConvertTo-Json -Depth 20 | Out-File -Encoding utf8 $JsonFile
    Write-Host "[x] Metadata opgeslagen" -ForegroundColor Green
    Write-Host ""

    # ============================================
    # Select Chapters flow — download-sections per chapter
    # ============================================
    if ($SelectChapters) {
        if (-not $Chapters) {
            Write-Host "Geen chapters gevonden" -ForegroundColor Yellow
            return
        }

        Write-Host "=== Chapters ===" -ForegroundColor Green
        Write-Host ""
        $Chapters | Format-Table start_time, end_time, title | Out-Host

        Write-Host ""
        Write-Host "=== Chapters selecteren ===" -ForegroundColor Cyan
        Write-Host "  Typ 'V' voor elke chapter die je wilt downloaden" -ForegroundColor Yellow
        $selected = [System.Collections.Generic.List[object]]::new()
        for ($j = 0; $j -lt $Chapters.Count; $j++) {
            $c = $Chapters[$j]
            Write-Host ("[$($j+1)] ") -NoNewline
            $response = Read-Host "$($c.title) [V/]"
            if ($response -eq 'V' -or $response -eq 'v') {
                $null = $selected.Add($c)
            }
        }

        if ($selected.Count -eq 0) {
            Write-Host "  Geen chapters geselecteerd" -ForegroundColor Yellow
            return
        }
        Write-Host "  -> $($selected.Count) chapter(s) geselecteerd" -ForegroundColor Green

        Write-Host ""
        Write-Host "=== Chapters downloaden ===" -ForegroundColor Cyan
        $i = 1
        $downloaded = @()

        foreach ($c in $selected) {
            $duration = $c.end_time - $c.start_time
            if ($duration -le 0) { continue }

            $safeTitle = Get-SafeFileName -Name $c.title
            $file = "{0:D2}_{1}.mp4" -f $i, $safeTitle
            $out  = Join-Path $OutDir $file

            Write-Progress -Activity "Chapters downloaden" -Status $file -PercentComplete (($i - 1) / $selected.Count * 100)
            Write-Host "[$i/$($selected.Count)] $file" -ForegroundColor Yellow

            $sectionQualityFormat = if ($qualityFormat -match '\[height<=(\d+)\]') {
                "best[height<=$($Matches[1])]"
            } else {
                $qualityFormat
            }

            & yt-dlp `
                --download-sections "*$($c.start_time)-$($c.end_time)" `
                --force-keyframes-at-cuts `
                -f $sectionQualityFormat `
                --force-ipv4 `
                --retries infinite `
                --fragment-retries infinite `
                --socket-timeout 30 `
                @jsRuntimeArgs `
                --no-part `
                -o $out `
                $Url

            if ($LASTEXITCODE -ne 0) {
                Write-Host "  [ERROR] Download gefaald voor: $file" -ForegroundColor Red
                continue
            }

            $downloaded += @{Path=$out; Chapter=$c; Index=$i}
            $i++
        }

        Write-Progress -Activity "Chapters downloaden" -Completed

        # ============================================
        # Thumbnails (select flow)
        # ============================================
        if ($Thumbnails) {
            Write-Host ""
            Write-Host "=== Thumbnails genereren ===" -ForegroundColor Cyan
            $t = 1
            foreach ($item in $downloaded) {
                $c = $item.Chapter
                $duration = $c.end_time - $c.start_time
                if ($duration -le 0) { continue }

                $mid = $duration / 2
                $safeTitle = Get-SafeFileName -Name $c.title
                $thumbFile = "{0:D2}_{1}.jpg" -f $item.Index, $safeTitle
                $thumbOut  = Join-Path $OutDir $thumbFile

                Write-Progress -Activity "Thumbnails genereren" -Status $thumbFile -PercentComplete (($t - 1) / $downloaded.Count * 100)
                Write-Host "  -> $thumbFile" -ForegroundColor DarkGray

                & ffmpeg -y -ss $mid -i $item.Path -vframes 1 -q:v 2 $thumbOut -hide_banner -loglevel error -nostats

                $t++
            }

            Write-Progress -Activity "Thumbnails genereren" -Completed
        }

        Write-Host ""
        Write-Host "=== Gereed! ===" -ForegroundColor Green
        Write-Host "Output: $OutDir"
        return
    }

    # ============================================
    # Non-select flow: download hele video
    # ============================================
    $WorkDir = Join-Path $BaseDir "downloads\$ChannelName\$VideoTitle"
    $null = New-Item -ItemType Directory -Force -Path $WorkDir

    if ($DownloadOnly) {
        $VideoFile = Join-Path $OutDir "$VideoTitle.mp4"
    } else {
        $VideoFile = "$WorkDir\video.mp4"
    }

    if (Test-Path $VideoFile) {
        Write-Host "Video bestaat al, download wordt overgeslagen" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "=== Video downloaden ===" -ForegroundColor Cyan
        yt-dlp `
            -f $qualityFormat `
            --merge-output-format mp4 `
            --force-ipv4 `
            --retries infinite `
            --fragment-retries infinite `
            --socket-timeout 30 `
            @jsRuntimeArgs `
            --no-part `
            -o $VideoFile `
            $Url
        if ($LASTEXITCODE -ne 0) { throw "yt-dlp download gefaald" }
        Write-Host "[x] Video gedownload" -ForegroundColor Green
    }

    # ============================================
    # Download Only: klaar
    # ============================================
    if ($DownloadOnly) {
        Write-Host ""
        Write-Host "=== Gereed! ===" -ForegroundColor Green
        Write-Host "Output: $VideoFile"
        return
    }

    # ============================================
    # Chapters verwerken
    # ============================================
    Write-Host ""
    Write-Host "=== Chapters verwerken ===" -ForegroundColor Cyan

    if (-not $Chapters) { Write-Host "Geen chapters gevonden" -ForegroundColor Yellow; return }

    Write-Host ""
    Write-Host "=== Chapter Index ===" -ForegroundColor Green
    $Chapters | Format-Table start_time, end_time, title | Out-Host

    # ============================================
    # Split
    # ============================================
    Write-Host ""
    Write-Host "=== Video splitsen ===" -ForegroundColor Cyan
    $total = $Chapters.Count
    $i = 1

    foreach ($c in $Chapters) {
        $duration = $c.end_time - $c.start_time
        if ($duration -le 0) { continue }

        $safeTitle = Get-SafeFileName -Name $c.title
        $file = "{0:D2}_{1}.mp4" -f $i, $safeTitle
        $out  = Join-Path $OutDir $file

        Write-Progress -Activity "Video splitsen" -Status $file -PercentComplete (($i - 1) / $total * 100)
        Write-Host "[$i/$total] $file" -ForegroundColor Yellow

        if ($AccurateCut) {
            & ffmpeg -y -i $VideoFile -ss $c.start_time -t $duration `
                -c:v libx264 -preset fast -crf 22 -c:a aac -b:a 192k `
                $out -hide_banner -loglevel error -nostats
        } else {
            & ffmpeg -y -ss $c.start_time -i $VideoFile -t $duration `
                -c copy $out -hide_banner -loglevel error -nostats
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [ERROR] ffmpeg gefaald voor: $file" -ForegroundColor Red
        }

        $i++
    }

    Write-Progress -Activity "Video splitsen" -Completed

    # ============================================
    # Thumbnails
    # ============================================
    if ($Thumbnails) {
        Write-Host ""
        Write-Host "=== Thumbnails genereren ===" -ForegroundColor Cyan
        $i = 1

        foreach ($c in $Chapters) {
            $duration = $c.end_time - $c.start_time
            if ($duration -le 0) { continue }

            $mid = ($c.start_time + $c.end_time) / 2
            $safeTitle = Get-SafeFileName -Name $c.title
            $thumbFile = "{0:D2}_{1}.jpg" -f $i, $safeTitle
            $thumbOut  = Join-Path $OutDir $thumbFile

            Write-Progress -Activity "Thumbnails genereren" -Status $thumbFile -PercentComplete (($i - 1) / $total * 100)
            Write-Host "  -> $thumbFile" -ForegroundColor DarkGray

            & ffmpeg -y -ss $mid -i $VideoFile -vframes 1 -q:v 2 $thumbOut -hide_banner -loglevel error -nostats

            $i++
        }

        Write-Progress -Activity "Thumbnails genereren" -Completed
    }

    # ============================================
    # Cleanup
    # ============================================
    if (-not $KeepDownloads) {
        Write-Host ""
        Write-Host "=== Opruimen ===" -ForegroundColor Cyan
        Remove-Item $WorkDir -Recurse -Force -ErrorAction Continue
        Write-Host "[x] Downloads verwijderd" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "=== Gereed! ===" -ForegroundColor Green
    Write-Host "Output: $OutDir"
}

# ============================================
# URL-lijst opbouwen (enkele URL en/of batch-bestand)
# ============================================
$urls = [System.Collections.Generic.List[string]]::new()
if ($Url) { $urls.Add($Url) }
if ($BatchFile) {
    if (-not (Test-Path $BatchFile)) {
        Write-Host "[ERROR] Batch-bestand niet gevonden: $BatchFile" -ForegroundColor Red
        if ($LogFile) { Stop-Transcript }
        exit 1
    }
    Get-Content -Path $BatchFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith('#')) { $urls.Add($line) }
    }
}

if ($urls.Count -eq 0) {
    Write-Host "[ERROR] Geen URL opgegeven. Gebruik -Url <URL> of -BatchFile <bestand>." -ForegroundColor Red
    if ($LogFile) { Stop-Transcript }
    exit 1
}

if ($BatchFile -and $OutputDir) {
    Write-Host "[WARN] -OutputDir wordt genegeerd in batch-modus; elke video krijgt een eigen map onder -BaseDir." -ForegroundColor Yellow
}

# ============================================
# Main loop
# ============================================
$exitCode = 0
$failed = [System.Collections.Generic.List[string]]::new()
$idx = 0

try {
    foreach ($currentUrl in $urls) {
        $idx++

        if ($urls.Count -gt 1) {
            Write-Host ""
            Write-Host "############################################" -ForegroundColor Magenta
            Write-Host "# [$idx/$($urls.Count)] $currentUrl" -ForegroundColor Magenta
            Write-Host "############################################" -ForegroundColor Magenta
        }

        if ($currentUrl -notmatch '^https?://') {
            Write-Host "[ERROR] Ongeldige URL overgeslagen: $currentUrl" -ForegroundColor Red
            $failed.Add($currentUrl)
            continue
        }

        # In batch-modus negeren we -OutputDir zodat video's elkaar niet overschrijven
        $outOverride = if ($urls.Count -gt 1) { $null } else { $OutputDir }

        try {
            Invoke-SplitVideo -Url $currentUrl -OutDirOverride $outOverride
        }
        catch {
            Write-Host ""
            Write-Host "[ERROR] $currentUrl : $_" -ForegroundColor Red
            $failed.Add($currentUrl)
        }
    }

    if ($urls.Count -gt 1) {
        Write-Host ""
        $ok = $urls.Count - $failed.Count
        Write-Host "=== Batch klaar: $ok/$($urls.Count) gelukt ===" -ForegroundColor Green
        if ($failed.Count -gt 0) {
            Write-Host "Mislukt:" -ForegroundColor Red
            $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
    }

    if ($failed.Count -gt 0) { $exitCode = 1 }
}
finally {
    if ($LogFile) {
        Stop-Transcript
    }
}

exit $exitCode
