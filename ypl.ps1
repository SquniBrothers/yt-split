[CmdletBinding()]
param(
    [Alias("u")]
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$Url,

    [Alias("f")]
    [Parameter(Mandatory = $false)]
    [string]$BatchFile,

    [Alias("b")]
    [Parameter(Mandatory = $false)]
    [string]$BaseDir = (Join-Path $HOME "videos"),

    [Alias("o")]
    [Parameter(Mandatory = $false)]
    [string]$OutputDir,

    [Alias("i")]
    [Parameter(Mandatory = $false)]
    [string]$Items,

    # PowerShell ziet "-" en "--" als parameternaam, ook tussen quotes; gebruik
    # daarom -q:"--" met dubbele punt, of de aliassen 2160/1080/720/480.
    [Alias("q")]
    [Parameter(Mandatory = $false)]
    [ValidateSet('++', '+', '-', '--', '4k', '2160', '1080', '720', '480')]
    [string]$Quality = '+',

    [Alias("n")]
    [Parameter(Mandatory = $false)]
    [switch]$NoIndex,

    [Alias("k")]
    [Parameter(Mandatory = $false)]
    [switch]$KeepText,

    [Alias("r")]
    [Parameter(Mandatory = $false)]
    [switch]$Reverse,

    [Alias("s")]
    [Parameter(Mandatory = $false)]
    [switch]$Subs,

    [Alias("p")]
    [Parameter(Mandatory = $false)]
    [switch]$PrintOnly,

    [Alias("l")]
    [Parameter(Mandatory = $false)]
    [string]$LogFile,

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
ypl.ps1 - Download een complete YouTube playlist (of channel) naar <channel>\<playlist>

Titels van een playlist bevatten vrijwel altijd dezelfde staart of kop
("... - Trimble Access - Getting Started"). Die herhaalde tekst wordt
automatisch gestript, net als een nummer vooraan dat al gelijk is aan de
playlist-index. Resultaat: "01 Creating projects and jobs.mp4".

GEBRUIK:
    ypl <URL> [OPTIES]
    ypl -BatchFile <bestand.txt> [OPTIES]

PARAMETERS:
    -Url  (-u)  URL van de playlist of channel (mag ook positioneel)
    -BatchFile  (-f)  Tekstbestand met 1 playlist-URL per regel (# = commentaar)
    -BaseDir  (-b)  Basis directory (default: `$HOME\videos)
    -OutputDir  (-o)  Eigen output directory (genegeerd in batch-modus)
    -Items  (-i)  Selectie, yt-dlp syntax: "1-5", "3,7,9", "5-" , ":10"
    -Quality  (-q)  Kwaliteit: ++/2160, +/1080, -/720, --/480
                    Let op: -q "-" en -q "--" leest PowerShell als parameternaam;
                    gebruik -q:"--" (met dubbele punt) of -q 480
    -NoIndex  (-n)  Geen "01 " volgnummer voor de bestandsnaam
    -KeepText  (-k)  Herhaalde tekst NIET strippen (originele titels)
    -Reverse  (-r)  Playlist in omgekeerde volgorde downloaden
    -Subs  (-s)  Ondertitels meenemen (incl. auto-gegenereerd, .srt)
    -PrintOnly  (-p)  Toon alleen de geplande bestandsnamen en stop
    -LogFile  (-l)  Pad voor logbestand
    -Help  (-h)  Dit help bericht

VOORBEELDEN:
    ypl "https://www.youtube.com/playlist?list=PL..."
    ypl "https://www.youtube.com/playlist?list=PL..." -p
    ypl "https://www.youtube.com/@Trimble/videos" -q "++" -i "1-20"
    ypl -f "playlists.txt" -s
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
$requiredCmds = @("yt-dlp", "ffmpeg")
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
$maxHeight = switch ($Quality) {
    '++'   { 2160 }
    '4k'   { 2160 }
    '2160' { 2160 }
    '+'    { 1080 }
    '1080' { 1080 }
    '-'    { 720 }
    '720'  { 720 }
    '--'   { 480 }
    '480'  { 480 }
}
$qualityFormat = "bestvideo[height<=$maxHeight]+bestaudio/best[height<=$maxHeight]"

# ============================================
# Helper functies
# ============================================

# Mapnaam: zelfde stijl als split.ps1 (underscores, geen spaties)
function Get-SafeDirName {
    param([string]$Name)
    return ($Name -replace ' - ', ' ' -replace '[\s\\/:*?"<>|]+', '_' -replace '_+', '_' -replace '(^_+|_+$)', '')
}

# Bestandsnaam: spaties blijven staan, alleen tekens die Windows verbiedt eruit
function Get-SafeFileName {
    param([string]$Name)
    $clean = $Name -replace '[\\/:*?"<>|]', ' ' -replace '\s+', ' '
    $clean = $clean.Trim().TrimEnd('.')
    if (-not $clean) { $clean = "video" }
    if ($clean.Length -gt 120) { $clean = $clean.Substring(0, 120).Trim() }
    return $clean
}

# Langste gemeenschappelijke kop van alle titels
function Get-CommonPrefix {
    param([string[]]$Titles)
    if ($Titles.Count -lt 2) { return '' }
    $common = $Titles[0]
    foreach ($t in $Titles) {
        $max = [Math]::Min($common.Length, $t.Length)
        $i = 0
        while ($i -lt $max -and $common[$i] -eq $t[$i]) { $i++ }
        $common = $common.Substring(0, $i)
        if (-not $common) { break }
    }
    return $common
}

# Langste gemeenschappelijke staart van alle titels
function Get-CommonSuffix {
    param([string[]]$Titles)
    if ($Titles.Count -lt 2) { return '' }
    $common = $Titles[0]
    foreach ($t in $Titles) {
        $max = [Math]::Min($common.Length, $t.Length)
        $i = 0
        while ($i -lt $max -and $common[$common.Length - 1 - $i] -eq $t[$t.Length - 1 - $i]) { $i++ }
        $common = $common.Substring($common.Length - $i)
        if (-not $common) { break }
    }
    return $common
}

# Een gemeenschappelijk stuk mag niet midden in een woord beginnen/eindigen:
# "ing Started" wordt teruggebracht tot " Started".
$sepClass = '[\s\-–—|:;,.!?/\\()\[\]{}#~*+_]'

function Get-TrimmedAffix {
    param([string]$Text, [ValidateSet('Prefix', 'Suffix')][string]$Kind)
    if (-not $Text) { return '' }
    if ($Kind -eq 'Suffix') {
        # knip vooraan bij tot het fragment op een scheidingsteken begint
        $m = [regex]::Match($Text, $sepClass)
        if (-not $m.Success) { return '' }
        return $Text.Substring($m.Index)
    } else {
        # knip achteraan af tot het fragment op een scheidingsteken eindigt
        $m = [regex]::Matches($Text, $sepClass)
        if ($m.Count -eq 0) { return '' }
        $last = $m[$m.Count - 1]
        return $Text.Substring(0, $last.Index + $last.Length)
    }
}

# ============================================
# Eén playlist verwerken
# ============================================
function Invoke-DownloadPlaylist {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [string]$OutDirOverride
    )

    Write-Host ""
    Write-Host "=== Playlist ophalen ===" -ForegroundColor Cyan

    $sep = [string][char]0x1F
    $template = "%(playlist_index)s${sep}%(id)s${sep}%(playlist_channel,playlist_uploader,channel,uploader|Onbekend)s${sep}%(playlist_title,playlist,title|Playlist)s${sep}%(title)s"

    # Altijd de hele playlist ophalen: de herhaalde tekst en de nummering volgen
    # uit alle titels, ook als er met -Items maar een paar video's gehaald worden.
    $listArgs = @('--flat-playlist', '--ignore-no-formats-error', '--print', $template)

    $lines = @(& yt-dlp @jsRuntimeArgs @listArgs $Url | Where-Object { $_ -and $_.Contains($sep) })
    if ($LASTEXITCODE -ne 0 -and $lines.Count -eq 0) { throw "Kon playlist niet ophalen" }
    if ($lines.Count -eq 0) { throw "Playlist bevat geen video's" }

    $entries = [System.Collections.Generic.List[object]]::new()
    $pos = 0
    foreach ($line in $lines) {
        $pos++
        $f = $line -split $sep
        if ($f.Count -lt 5) { continue }
        $idx = 0
        if (-not [int]::TryParse($f[0], [ref]$idx)) { $idx = $pos }
        $null = $entries.Add([pscustomobject]@{
            Index   = $idx
            Id      = $f[1]
            Channel = $f[2]
            Playlist= $f[3]
            Title   = ($f[4..($f.Count - 1)] -join $sep)
        })
    }

    if ($entries.Count -eq 0) { throw "Playlist bevat geen bruikbare video's" }

    $ChannelName  = $entries[0].Channel
    $PlaylistName = $entries[0].Playlist

    Write-Host "[x] $($entries.Count) video's gevonden" -ForegroundColor Green
    Write-Host ""
    Write-Host $ChannelName
    Write-Host $PlaylistName
    Write-Host ""

    # ============================================
    # Herhaalde tekst bepalen
    # ============================================
    $titles = @($entries | ForEach-Object { $_.Title })
    $prefix = ''
    $suffix = ''

    if (-not $KeepText -and $entries.Count -ge 2) {
        $suffix = Get-TrimmedAffix -Text (Get-CommonSuffix -Titles $titles) -Kind 'Suffix'
        if ($suffix.Trim().Length -lt 3) { $suffix = '' }

        $rest = @($titles | ForEach-Object {
            if ($suffix -and $_.EndsWith($suffix)) { $_.Substring(0, $_.Length - $suffix.Length) } else { $_ }
        })
        $prefix = Get-TrimmedAffix -Text (Get-CommonPrefix -Titles $rest) -Kind 'Prefix'
        if ($prefix.Trim().Length -lt 3) { $prefix = '' }

        # Nooit strippen als er een lege titel overblijft
        foreach ($t in $rest) {
            $stripped = $t
            if ($prefix -and $stripped.StartsWith($prefix)) { $stripped = $stripped.Substring($prefix.Length) }
            if (-not $stripped.Trim()) { $prefix = ''; break }
        }

        if ($suffix) { Write-Host "Herhaalde staart : '$suffix'" -ForegroundColor DarkGray }
        if ($prefix) { Write-Host "Herhaalde kop    : '$prefix'" -ForegroundColor DarkGray }
        if ($suffix -or $prefix) { Write-Host "" }
    }

    # ============================================
    # Bestandsnamen bepalen
    # ============================================
    $width = ([string]$entries.Count).Length
    if ($width -lt 2) { $width = 2 }

    foreach ($e in $entries) {
        $t = $e.Title
        if ($suffix -and $t.EndsWith($suffix)) { $t = $t.Substring(0, $t.Length - $suffix.Length) }
        if ($prefix -and $t.StartsWith($prefix)) { $t = $t.Substring($prefix.Length) }
        $t = $t -replace '^[\s\-–—|:,.]+', '' -replace '[\s\-–—|:,.]+$', ''

        # Nummer vooraan dat de playlist-index herhaalt ("3 Connecting...") weg
        $m = [regex]::Match($t, '^(\d{1,3})\s*[\.\)\-:_]?\s+(.+)$')
        if ($m.Success -and [int]$m.Groups[1].Value -eq $e.Index) {
            $t = $m.Groups[2].Value
        }

        if (-not $t.Trim()) { $t = $e.Title }

        $name = Get-SafeFileName -Name $t
        if (-not $NoIndex) {
            $name = ("{0:D$width} {1}" -f $e.Index, $name)
        }
        $e | Add-Member -NotePropertyName File -NotePropertyValue "$name.mp4" -Force
    }

    # ============================================
    # Selectie (-Items) - yt-dlp bepaalt zelf welke items binnen de selectie
    # vallen, zodat "1-5", "3,7,9", "5-" en ":10" werken zoals in yt-dlp.
    # ============================================
    $selected = @($entries)
    if ($Items) {
        $ids = @(& yt-dlp @jsRuntimeArgs --flat-playlist --ignore-no-formats-error `
                    --playlist-items $Items --print "%(id)s" $Url | Where-Object { $_ })
        if ($ids.Count -eq 0) { throw "Selectie '$Items' levert geen video's op" }
        $wanted = @{}
        foreach ($id in $ids) { $wanted[$id.Trim()] = $true }
        $selected = @($entries | Where-Object { $wanted.ContainsKey($_.Id) })
        if ($selected.Count -eq 0) { throw "Selectie '$Items' levert geen video's op" }
        Write-Host "Selectie '$Items': $($selected.Count) van $($entries.Count) video's" -ForegroundColor DarkGray
        Write-Host ""
    }

    # ============================================
    # Output directory
    # ============================================
    $OutDir = if ($OutDirOverride) {
        $OutDirOverride
    } else {
        Join-Path $BaseDir ((Get-SafeDirName -Name $ChannelName) + "\" + (Get-SafeDirName -Name $PlaylistName))
    }

    # ============================================
    # Print Only
    # ============================================
    if ($PrintOnly) {
        Write-Host "=== Geplande bestanden ===" -ForegroundColor Green
        Write-Host "Map: $OutDir"
        Write-Host ""
        $selected | ForEach-Object { Write-Host "  $($_.File)" }
        Write-Host ""
        return
    }

    $null = New-Item -ItemType Directory -Force -Path $OutDir

    $JsonFile = Join-Path $OutDir "playlist.json"
    [pscustomobject]@{
        url      = $Url
        channel  = $ChannelName
        playlist = $PlaylistName
        stripped = [pscustomobject]@{ prefix = $prefix; suffix = $suffix }
        count    = $entries.Count
        entries  = $entries
        selected = @($selected | ForEach-Object { $_.File })
    } | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 $JsonFile

    # ============================================
    # Downloaden
    # ============================================
    Write-Host "=== Downloaden ===" -ForegroundColor Cyan
    Write-Host "Map: $OutDir" -ForegroundColor DarkGray
    Write-Host ""

    $order = @($selected)
    if ($Reverse) { [array]::Reverse($order) }

    $subArgs = @()
    if ($Subs) {
        $subArgs = @('--write-subs', '--write-auto-subs', '--sub-langs', 'en.*,nl.*', '--convert-subs', 'srt')
    }

    $total = $order.Count
    $i = 0
    $skipped = 0
    $failed = [System.Collections.Generic.List[string]]::new()

    foreach ($e in $order) {
        $i++
        $out = Join-Path $OutDir $e.File

        if (Test-Path -LiteralPath $out) {
            Write-Host "[$i/$total] $($e.File) - bestaat al, overgeslagen" -ForegroundColor DarkGray
            $skipped++
            continue
        }

        Write-Progress -Activity "Playlist downloaden" -Status $e.File -PercentComplete (($i - 1) / $total * 100)
        Write-Host "[$i/$total] $($e.File)" -ForegroundColor Yellow

        & yt-dlp `
            --no-playlist `
            -f $qualityFormat `
            --merge-output-format mp4 `
            --force-ipv4 `
            --retries infinite `
            --fragment-retries infinite `
            --socket-timeout 30 `
            @jsRuntimeArgs `
            @subArgs `
            --no-part `
            -o $out `
            "https://www.youtube.com/watch?v=$($e.Id)"

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [ERROR] Download gefaald: $($e.File)" -ForegroundColor Red
            $null = $failed.Add($e.File)
        }
    }

    Write-Progress -Activity "Playlist downloaden" -Completed

    Write-Host ""
    Write-Host "=== Gereed! ===" -ForegroundColor Green
    Write-Host "Output: $OutDir"
    $ok = $total - $failed.Count - $skipped
    Write-Host "$ok gedownload, $skipped overgeslagen, $($failed.Count) mislukt"
    if ($failed.Count -gt 0) {
        $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        throw "$($failed.Count) video(s) mislukt"
    }
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
    Write-Host "        Help: ypl -h" -ForegroundColor Yellow
    if ($LogFile) { Stop-Transcript }
    exit 1
}

if ($BatchFile -and $OutputDir) {
    Write-Host "[WARN] -OutputDir wordt genegeerd in batch-modus; elke playlist krijgt een eigen map onder -BaseDir." -ForegroundColor Yellow
}

# ============================================
# Main loop
# ============================================
$exitCode = 0
$failedUrls = [System.Collections.Generic.List[string]]::new()
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
            $failedUrls.Add($currentUrl)
            continue
        }

        $outOverride = if ($urls.Count -gt 1) { $null } else { $OutputDir }

        try {
            Invoke-DownloadPlaylist -Url $currentUrl -OutDirOverride $outOverride
        }
        catch {
            Write-Host ""
            Write-Host "[ERROR] $currentUrl : $_" -ForegroundColor Red
            $failedUrls.Add($currentUrl)
        }
    }

    if ($urls.Count -gt 1) {
        Write-Host ""
        $ok = $urls.Count - $failedUrls.Count
        Write-Host "=== Batch klaar: $ok/$($urls.Count) playlists gelukt ===" -ForegroundColor Green
        if ($failedUrls.Count -gt 0) {
            Write-Host "Mislukt:" -ForegroundColor Red
            $failedUrls | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        }
    }

    if ($failedUrls.Count -gt 0) { $exitCode = 1 }
}
finally {
    if ($LogFile) {
        Stop-Transcript
    }
}

exit $exitCode
