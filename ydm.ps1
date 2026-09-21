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
    [string]$BaseDir = (Join-Path $HOME "music"),

    [Alias("o")]
    [Parameter(Mandatory = $false)]
    [string]$OutputDir,

    [Alias("i")]
    [Parameter(Mandatory = $false)]
    [string]$Items,

    # PowerShell ziet "-" en "--" als parameternaam, ook tussen quotes; gebruik
    # daarom -q:"--" met dubbele punt, of de aliassen 320/256/192/128/96.
    [Alias("q")]
    [Parameter(Mandatory = $false)]
    [ValidateSet('++', '+', '-', '--', '320', '256', '192', '128', '96')]
    [string]$Quality = '+',

    [Alias("x")]
    [Parameter(Mandatory = $false)]
    [ValidateSet('mp3', 'm4a')]
    [string]$Format = 'mp3',

    [Alias("s")]
    [Parameter(Mandatory = $false)]
    [switch]$Split,

    [Alias("ab")]
    [Parameter(Mandatory = $false)]
    [switch]$Audiobook,

    [Alias("pc")]
    [Parameter(Mandatory = $false)]
    [switch]$Podcast,

    [Alias("a")]
    [Parameter(Mandatory = $false)]
    [switch]$NoArt,

    [Alias("c")]
    [Parameter(Mandatory = $false)]
    [switch]$Crop,

    [Alias("n")]
    [Parameter(Mandatory = $false)]
    [switch]$NoIndex,

    [Alias("k")]
    [Parameter(Mandatory = $false)]
    [switch]$KeepText,

    [Alias("r")]
    [Parameter(Mandatory = $false)]
    [switch]$Reverse,

    [Alias("p")]
    [Parameter(Mandatory = $false)]
    [switch]$PrintOnly,

    [Parameter(Mandatory = $false)]
    [string]$Artist,

    [Parameter(Mandatory = $false)]
    [string]$Album,

    [Parameter(Mandatory = $false)]
    [switch]$KeepFull,

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
ydm.ps1 - Download YouTube audio als mp3 met tags en album art

Een losse video wordt een los nummer, een playlist of channel wordt een album
(<artiest>\<album>\01 Titel.mp3), en een lange video met chapters knip je met -s
op in losse tracks - net zoals YouTube de chapters toont.

De thumbnail gaat standaard als album art mee; -c maakt er een vierkant van.

GEBRUIK:
    ydm <URL> [OPTIES]
    ydm -BatchFile <bestand.txt> [OPTIES]

PARAMETERS:
    -Url  (-u)  URL van video, playlist of channel (mag ook positioneel)
    -BatchFile  (-f)  Tekstbestand met 1 URL per regel (# = commentaar). Een kopregel
                      "# Music", "# Podcasts" of "# Audiobooks" zet de modus voor alles
                      eronder, en achter een URL mag je dezelfde opties zetten als hier
                      (-s, -ab, -pc, -q 320, -c, ...). Zie ydm.md.
    -BaseDir  (-b)  Basis directory (default: `$HOME\music)
    -OutputDir  (-o)  Eigen output directory (genegeerd in batch-modus)
    -Items  (-i)  Selectie uit een playlist, yt-dlp syntax: "1-5", "3,7,9", "5-", ":10"
    -Quality  (-q)  Bitrate: ++/320, +/192 (default), -/128, --/96, of 256
                    Let op: -q "-" en -q "--" leest PowerShell als parameternaam;
                    gebruik -q:"--" (met dubbele punt) of -q 96
    -Format  (-x)  Audioformaat: mp3 (default) of m4a
    -Split  (-s)  Lange video opknippen in de chapters (losse track per hoofdstuk)
    -Audiobook  (-ab)  Luisterboek: naar `$HOME\Audiobooks, -s automatisch aan, genre Audiobook
    -Podcast  (-pc)  Podcast: naar `$HOME\Podcasts, datum voor de bestandsnaam, genre Podcast
    -NoArt  (-a)  Geen album art insluiten
    -Crop  (-c)  Album art vierkant bijsnijden (midden uit de thumbnail)
    -NoIndex  (-n)  Geen "01 " volgnummer voor de bestandsnaam
    -KeepText  (-k)  Titels niet opschonen (herhaalde tekst en "(Official Video)" blijven)
    -Reverse  (-r)  Playlist in omgekeerde volgorde downloaden
    -PrintOnly  (-p)  Toon de geplande bestanden en tags en stop
    -Artist  Artiest-tag forceren (anders uit de muziekmetadata, de titel of het kanaal)
    -Album  Album-tag forceren (anders de playlist- of videotitel)
    -KeepFull  Bij -s ook het complete bestand bewaren
    -LogFile  (-l)  Pad voor logbestand
    -Help  (-h)  Dit help bericht

VOORBEELDEN:
    ydm "https://www.youtube.com/watch?v=..."
    ydm "https://www.youtube.com/watch?v=..." -s -q 320
    ydm "https://www.youtube.com/playlist?list=PL..." -p
    ydm "https://www.youtube.com/playlist?list=PL..." -i "1-10" -c
    ydm "https://www.youtube.com/watch?v=..." -ab
    ydm "https://www.youtube.com/@DeShow/videos" -pc
    ydm -f "albums.txt" -s -q 320
"@
    return
}

if ($Audiobook -and $Podcast) {
    Write-Host "[ERROR] -Audiobook en -Podcast gaan niet samen; kies er een." -ForegroundColor Red
    exit 1
}

# Wat op de commandline staat is de basis; een batch-bestand mag er per regel
# overheen (zie Set-RunOptions en Read-BatchFile).
$BaseOptions = @{
    Split           = [bool]$Split
    Audiobook       = [bool]$Audiobook
    Podcast         = [bool]$Podcast
    Crop            = [bool]$Crop
    NoArt           = [bool]$NoArt
    NoIndex         = [bool]$NoIndex
    KeepText        = [bool]$KeepText
    Reverse         = [bool]$Reverse
    KeepFull        = [bool]$KeepFull
    Items           = $Items
    Artist          = $Artist
    Album           = $Album
    OutputDir       = $OutputDir
    Quality         = $Quality
    Format          = $Format
    BaseDir         = $BaseDir
    BaseDirExplicit = $PSBoundParameters.ContainsKey('BaseDir')
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

# Werkmap per video buiten de muziekmap, zodat een afgebroken run geen halve
# downloads tussen de nummers achterlaat.
$CacheRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ydm"

$ValidQuality = @('++', '+', '-', '--', '320', '256', '192', '128', '96')
$ValidFormat  = @('mp3', 'm4a')

# ============================================
# Opties voor één URL klaarzetten
# De basis is de commandline; $Override komt uit een regel van het batch-bestand.
# Alles wat de download-functies lezen wordt hier gezet, inclusief wat eruit
# volgt: de bitrate, de codec, de extensie, het genre en de doelmap.
# ============================================
function Set-RunOptions {
    param([hashtable]$Override = @{})

    $o = @{}
    foreach ($k in $BaseOptions.Keys)  { $o[$k] = $BaseOptions[$k] }
    foreach ($k in $Override.Keys)     { $o[$k] = $Override[$k] }

    $script:Split     = [bool]$o.Split
    $script:Audiobook = [bool]$o.Audiobook
    $script:Podcast   = [bool]$o.Podcast
    $script:Crop      = [bool]$o.Crop
    $script:NoArt     = [bool]$o.NoArt
    $script:NoIndex   = [bool]$o.NoIndex
    $script:KeepText  = [bool]$o.KeepText
    $script:Reverse   = [bool]$o.Reverse
    $script:KeepFull  = [bool]$o.KeepFull
    $script:Items     = [string]$o.Items
    $script:Artist    = [string]$o.Artist
    $script:Album     = [string]$o.Album
    $script:OutputDir = [string]$o.OutputDir
    $script:Format    = [string]$o.Format

    $script:bitrate = switch ("$($o.Quality)") {
        '++'  { 320 }
        '320' { 320 }
        '256' { 256 }
        '+'   { 192 }
        '192' { 192 }
        '-'   { 128 }
        '128' { 128 }
        '--'  { 96 }
        '96'  { 96 }
        default { 192 }
    }
    $script:audioCodec = if ($script:Format -eq 'm4a') { 'aac' } else { 'libmp3lame' }
    $script:ext = ".$($script:Format)"

    # Presets: alleen de standaardmap en een paar defaults. Een eigen -BaseDir
    # (op de commandline of op de regel zelf) gaat er altijd voor.
    # Onthouden of -s echt gevraagd is: bij -ab zetten we hem zelf aan, en dan
    # hoeft er geen "wordt genegeerd" over een playlist gemeld te worden.
    $script:SplitExplicit = $script:Split

    $script:genre = $null
    $script:BaseDir = [string]$o.BaseDir
    if ($script:Audiobook) {
        $script:genre = 'Audiobook'
        if (-not $o.BaseDirExplicit) { $script:BaseDir = Join-Path $HOME 'Audiobooks' }
        # Een luisterboek met chapters wil je per hoofdstuk; zonder chapters
        # blijft het gewoon één bestand (met een waarschuwing).
        $script:Split = $true
    }
    if ($script:Podcast) {
        $script:genre = 'Podcast'
        if (-not $o.BaseDirExplicit) { $script:BaseDir = Join-Path $HOME 'Podcasts' }
    }
}

function Get-ModeLabel {
    if ($Audiobook) { return 'luisterboek' }
    if ($Podcast)   { return 'podcast' }
    return 'muziek'
}

# ============================================
# Helper functies
# ============================================

# Mapnaam: zelfde stijl als split.ps1 / ypl.ps1 (underscores, geen spaties)
function Get-SafeDirName {
    param([string]$Name)
    return ($Name -replace ' - ', ' ' -replace '[\s\\/:*?"<>|]+', '_' -replace '_+', '_' -replace '(^_+|_+$)', '')
}

# Bestandsnaam: spaties blijven staan, alleen tekens die Windows verbiedt eruit
function Get-SafeFileName {
    param([string]$Name)
    $clean = $Name -replace '[\\/:*?"<>|]', ' ' -replace '\s+', ' '
    $clean = $clean.Trim().TrimEnd('.')
    if (-not $clean) { $clean = "track" }
    if ($clean.Length -gt 120) { $clean = $clean.Substring(0, 120).Trim() }
    return $clean
}

# <artiest>\<album>, maar één map als die twee hetzelfde heten - dat gebeurt bij
# een channel-upload waar de playlist naar het kanaal vernoemd is.
function Join-ArtistAlbumDir {
    param([string]$Base, [string]$ArtistName, [string]$AlbumTitle)
    $a = Get-SafeDirName -Name $ArtistName
    $b = Get-SafeDirName -Name $AlbumTitle
    if (-not $b -or $a -eq $b) { return (Join-Path $Base $a) }
    return (Join-Path $Base ($a + "\" + $b))
}

# ffmpeg wil een punt als decimaalteken, ongeacht de locale van de shell
function Format-Seconds {
    param([double]$Value)
    return $Value.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
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
        $m = [regex]::Match($Text, $sepClass)
        if (-not $m.Success) { return '' }
        return $Text.Substring($m.Index)
    } else {
        $m = [regex]::Matches($Text, $sepClass)
        if ($m.Count -eq 0) { return '' }
        $last = $m[$m.Count - 1]
        return $Text.Substring(0, $last.Index + $last.Length)
    }
}

# "Song (Official Music Video) [HD]" -> "Song"
$junkWords = 'official|music video|lyrics?|lyric video|visuali[sz]er|audio only|full album|remaster(ed)?|explicit|clean version|m/?v|hd|hq|4k|8k|free download|out now'

function Remove-TitleJunk {
    param([string]$Name)
    if (-not $Name) { return $Name }
    $n = [regex]::Replace($Name, "(?i)\s*[\(\[]\s*[^()\[\]]*\b(?:$junkWords)\b[^()\[\]]*\s*[\)\]]", '')
    $n = [regex]::Replace($n, "(?i)\s*[|/]\s*[^|/]*\b(?:$junkWords)\b[^|/]*\s*$", '')
    $n = $n -replace '\s{2,}', ' '
    $n = $n -replace '^[\s\-–—|]+', '' -replace '[\s\-–—|]+$', ''
    if (-not $n.Trim()) { return $Name }
    return $n.Trim()
}

# "Artiest - Nummer" opsplitsen; $null als er geen duidelijke scheiding is
function Split-ArtistTitle {
    param([string]$Name)
    $m = [regex]::Match($Name, '^\s*(.{1,60}?)\s+[-–—]\s+(.+?)\s*$')
    if (-not $m.Success) { return $null }
    $a = $m.Groups[1].Value.Trim()
    $t = $m.Groups[2].Value.Trim()
    if (-not $a -or -not $t) { return $null }
    return @{ Artist = $a; Title = $t }
}

function Get-Year {
    param($Info)
    if (-not $Info) { return $null }
    if ($Info.release_year) { return [string]$Info.release_year }
    $d = "$($Info.upload_date)"
    if ($d.Length -ge 4) { return $d.Substring(0, 4) }
    return $null
}

# ============================================
# Chapters uit de beschrijving
# YouTube maakt zelf chapters van een tracklist die op 0:00 begint; gebeurt dat
# niet (tijden beginnen later, of staan achteraan de regel), dan leest deze
# fallback de tracklist alsnog uit de beschrijving.
# ============================================
function ConvertFrom-Timestamp {
    param([string]$Text)
    $parts = $Text -split ':'
    $secs = 0.0
    foreach ($p in $parts) {
        $n = 0
        if (-not [int]::TryParse($p, [ref]$n)) { return -1 }
        $secs = $secs * 60 + $n
    }
    return $secs
}

function Get-ChaptersFromDescription {
    param([string]$Description, [double]$Duration)

    if (-not $Description) { return @() }

    $tsPattern = '\d{1,2}:\d{1,2}(?::\d{2})?'
    $found = [System.Collections.Generic.List[object]]::new()

    foreach ($line in ($Description -split "`r?`n")) {
        $l = $line.Trim()
        if (-not $l) { continue }

        $ts = $null
        $title = $null

        # "0:00 Titel", "1. 00:00 - Titel", "[01:02:03] Titel"
        $m = [regex]::Match($l, "^\s*(?:\d{1,3}[\.\)]\s*)?[\[\(]?($tsPattern)[\]\)]?\s*[-–—:.]?\s*(.+)$")
        if ($m.Success) {
            $ts = $m.Groups[1].Value
            $title = $m.Groups[2].Value
        } else {
            # "Titel 0:00" (tijd achteraan de regel)
            $m = [regex]::Match($l, "^(.+?)\s+[\[\(]?($tsPattern)[\]\)]?\s*$")
            if ($m.Success) {
                $ts = $m.Groups[2].Value
                $title = $m.Groups[1].Value
            }
        }
        if (-not $ts) { continue }

        $secs = ConvertFrom-Timestamp -Text $ts
        if ($secs -lt 0) { continue }
        if ($Duration -gt 0 -and $secs -ge $Duration) { continue }

        $title = $title -replace '^\s*\d{1,3}[\.\)]\s*', ''
        $title = $title -replace '^[\s\-–—|:.]+', '' -replace '[\s\-–—|:.]+$', ''
        if (-not $title) { continue }

        $null = $found.Add([pscustomobject]@{ Start = $secs; Title = $title })
    }

    if ($found.Count -lt 2) { return @() }

    $sorted = @($found | Sort-Object Start)
    $result = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $start = [double]$sorted[$i].Start
        $end = if ($i -lt $sorted.Count - 1) { [double]$sorted[$i + 1].Start } else { $Duration }
        if ($end -le $start) { continue }
        $null = $result.Add([pscustomobject]@{
            start_time = $start
            end_time   = $end
            title      = $sorted[$i].Title
        })
    }

    if ($result.Count -lt 2) { return @() }
    return @($result)
}

# ============================================
# Batch-bestand lezen
#
# Een kopregel zet de modus voor alles eronder, en achter een URL mag je
# dezelfde opties zetten als op de commandline:
#
#     # Podcasts
#     https://www.youtube.com/@DeShow/videos
#
#     # Music
#     https://www.youtube.com/watch?v=...  -s -q 320
#
#     # Audiobooks
#     https://www.youtube.com/watch?v=...
#
# Een "#"-regel die geen bekende sectienaam is blijft gewoon commentaar.
# ============================================
$SectionModes = @(
    @{ Pattern = '^(music|muziek|songs?|albums?|tracks?)$';                  Mode = @{ Audiobook = $false; Podcast = $false } }
    @{ Pattern = '^(podcasts?|shows?|afleveringen)$';                        Mode = @{ Audiobook = $false; Podcast = $true  } }
    @{ Pattern = '^(audiobooks?|luisterboeken?|boeken?|hoorboeken?)$';       Mode = @{ Audiobook = $true;  Podcast = $false } }
)

# Opties die een waarde achter zich hebben, en losse schakelaars
$ValueFlags = @{
    'q' = 'Quality'; 'quality' = 'Quality'
    'x' = 'Format';  'format'  = 'Format'
    'i' = 'Items';   'items'   = 'Items'
    'b' = 'BaseDir'; 'basedir' = 'BaseDir'
    'o' = 'OutputDir'; 'outputdir' = 'OutputDir'
    'artist' = 'Artist'; 'album' = 'Album'
}
$SwitchFlags = @{
    's' = 'Split';    'split'    = 'Split'
    'c' = 'Crop';     'crop'     = 'Crop'
    'a' = 'NoArt';    'noart'    = 'NoArt'
    'n' = 'NoIndex';  'noindex'  = 'NoIndex'
    'k' = 'KeepText'; 'keeptext' = 'KeepText'
    'r' = 'Reverse';  'reverse'  = 'Reverse'
    'keepfull' = 'KeepFull'
}

function Get-SectionMode {
    param([string]$Comment)
    $key = ($Comment -replace '[^\p{L}]', '').ToLowerInvariant()
    if (-not $key) { return $null }
    foreach ($s in $SectionModes) {
        if ($key -match $s.Pattern) { return $s.Mode }
    }
    return $null
}

# Woorden splitsen, maar "tussen quotes" bij elkaar houden
function Split-OptionTokens {
    param([string]$Text)
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($m in [regex]::Matches($Text, '"([^"]*)"|(\S+)')) {
        if ($m.Groups[1].Success) { $null = $tokens.Add($m.Groups[1].Value) }
        else                      { $null = $tokens.Add($m.Groups[2].Value) }
    }
    return $tokens.ToArray()
}

function ConvertTo-LineOptions {
    param([string[]]$Tokens, [int]$LineNo)

    $o = @{}
    $i = 0
    while ($i -lt $Tokens.Count) {
        $raw = $Tokens[$i]
        $i++

        if (-not $raw.StartsWith('-')) {
            Write-Host "[WARN] regel ${LineNo}: '$raw' is geen optie en wordt genegeerd" -ForegroundColor Yellow
            continue
        }

        $name = $raw.TrimStart('-').ToLowerInvariant()

        if ($ValueFlags.ContainsKey($name)) {
            if ($i -ge $Tokens.Count) {
                Write-Host "[WARN] regel ${LineNo}: '$raw' mist een waarde en wordt genegeerd" -ForegroundColor Yellow
                continue
            }
            $key = $ValueFlags[$name]
            $val = $Tokens[$i]
            $i++

            if ($key -eq 'Quality' -and $val -notin $ValidQuality) {
                Write-Host "[WARN] regel ${LineNo}: '$val' is geen geldige kwaliteit, genegeerd" -ForegroundColor Yellow
                continue
            }
            if ($key -eq 'Format' -and $val.ToLowerInvariant() -notin $ValidFormat) {
                Write-Host "[WARN] regel ${LineNo}: '$val' is geen geldig formaat, genegeerd" -ForegroundColor Yellow
                continue
            }
            if ($key -eq 'Format') { $val = $val.ToLowerInvariant() }

            $o[$key] = $val
            if ($key -eq 'BaseDir') { $o['BaseDirExplicit'] = $true }
        }
        elseif ($SwitchFlags.ContainsKey($name)) {
            $o[$SwitchFlags[$name]] = $true
        }
        elseif ($name -in @('ab', 'audiobook', 'luisterboek')) {
            $o['Audiobook'] = $true;  $o['Podcast'] = $false
        }
        elseif ($name -in @('pc', 'ps', 'podcast')) {
            $o['Podcast'] = $true;    $o['Audiobook'] = $false
        }
        elseif ($name -in @('m', 'music', 'muziek')) {
            $o['Podcast'] = $false;   $o['Audiobook'] = $false
        }
        else {
            Write-Host "[WARN] regel ${LineNo}: onbekende optie '$raw' genegeerd" -ForegroundColor Yellow
        }
    }
    return $o
}

function Read-BatchFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $jobs = [System.Collections.Generic.List[object]]::new()
    $section = @{}
    $lineNo = 0

    foreach ($rawLine in (Get-Content -LiteralPath $Path)) {
        $lineNo++
        $line = $rawLine.Trim()
        if (-not $line) { continue }

        if ($line.StartsWith('#')) {
            $mode = Get-SectionMode -Comment $line.TrimStart('#')
            if ($mode) {
                $section = @{}
                foreach ($k in $mode.Keys) { $section[$k] = $mode[$k] }
            }
            continue
        }

        # Commentaar achter de URL ("... -s  # favoriet"); een # in de URL zelf
        # heeft geen spatie ervoor en blijft dus staan.
        $line = [regex]::Replace($line, '\s+#.*$', '')

        $tokens = @(Split-OptionTokens -Text $line)
        if ($tokens.Count -eq 0) { continue }

        $url = $tokens[0]
        $opts = @{}
        foreach ($k in $section.Keys) { $opts[$k] = $section[$k] }

        if ($tokens.Count -gt 1) {
            $lineOpts = ConvertTo-LineOptions -Tokens $tokens[1..($tokens.Count - 1)] -LineNo $lineNo
            foreach ($k in $lineOpts.Keys) { $opts[$k] = $lineOpts[$k] }
        }

        $null = $jobs.Add([pscustomobject]@{ Url = $url; Options = $opts; Line = $lineNo })
    }

    return $jobs
}

# ============================================
# Bronbestand ophalen: beste audio + thumbnail + info.json in een werkmap
# ============================================
function Get-AudioSource {
    param(
        [Parameter(Mandatory = $true)][string]$VideoUrl,
        [Parameter(Mandatory = $true)][string]$WorkDir
    )

    if (Test-Path -LiteralPath $WorkDir) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null = New-Item -ItemType Directory -Force -Path $WorkDir

    $thumbArgs = if ($NoArt) { @() } else { @('--write-thumbnail', '--convert-thumbnail', 'jpg') }

    & yt-dlp `
        --no-playlist `
        -f 'bestaudio/best' `
        --force-ipv4 `
        --retries infinite `
        --fragment-retries infinite `
        --socket-timeout 30 `
        @jsRuntimeArgs `
        @thumbArgs `
        --write-info-json `
        --no-part `
        -o (Join-Path $WorkDir 'src.%(ext)s') `
        $VideoUrl

    if ($LASTEXITCODE -ne 0) { return $null }

    $files = @(Get-ChildItem -LiteralPath $WorkDir -File -ErrorAction SilentlyContinue)
    $audio = $files | Where-Object { $_.Extension -notin @('.jpg', '.json') } | Select-Object -First 1
    if (-not $audio) { return $null }

    $cover = $files | Where-Object { $_.Extension -eq '.jpg' } | Select-Object -First 1
    $infoFile = $files | Where-Object { $_.Name -like '*.info.json' } | Select-Object -First 1

    $info = $null
    if ($infoFile) {
        try { $info = Get-Content -LiteralPath $infoFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
        catch { $info = $null }
    }

    return [pscustomobject]@{
        Audio = $audio.FullName
        Cover = if ($cover) { $cover.FullName } else { $null }
        Info  = $info
    }
}

function Remove-WorkDir {
    param([string]$WorkDir)
    if ($WorkDir -and (Test-Path -LiteralPath $WorkDir)) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================
# Encoden: een (stuk van een) bronbestand naar mp3/m4a met tags en album art
# ============================================
function Convert-Audio {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Dest,
        [string]$Cover,
        [double]$Start = -1,
        [double]$Length = -1,
        [hashtable]$Tags = @{}
    )

    $useCover = (-not $NoArt) -and $Cover -and (Test-Path -LiteralPath $Cover)

    $ff = @('-y', '-hide_banner', '-loglevel', 'error', '-nostats')

    # -ss voor -i: ffmpeg spoelt door naar dat punt i.p.v. alles te decoderen
    if ($Start -gt 0) { $ff += @('-ss', (Format-Seconds $Start)) }
    $ff += @('-i', $Source)
    if ($useCover) { $ff += @('-i', $Cover) }

    $ff += @('-map', '0:a:0')
    if ($useCover) { $ff += @('-map', '1:v:0') }
    if ($Length -gt 0) { $ff += @('-t', (Format-Seconds $Length)) }

    $ff += @('-c:a', $audioCodec, '-b:a', "${bitrate}k")

    if ($useCover) {
        if ($Crop) {
            # midden uit de 16:9 thumbnail knippen; komma's in het filter escapen
            $ff += @('-c:v', 'mjpeg', '-vf', 'crop=min(iw\,ih):min(iw\,ih)')
        } else {
            $ff += @('-c:v', 'copy')
        }
        $ff += @('-disposition:v:0', 'attached_pic')
        $ff += @('-metadata:s:v', 'title=Album cover', '-metadata:s:v', 'comment=Cover (front)')
    }

    # id3v2.3 i.p.v. 2.4: Windows Verkenner en oudere spelers lezen alleen die
    if ($Format -eq 'mp3') { $ff += @('-id3v2_version', '3', '-write_id3v1', '1') }

    foreach ($key in ($Tags.Keys | Sort-Object)) {
        $val = "$($Tags[$key])"
        if ($val.Trim()) { $ff += @('-metadata', "$key=$val") }
    }

    $ff += @($Dest)

    & ffmpeg @ff
    return ($LASTEXITCODE -eq 0)
}

# ============================================
# Eén losse video (eventueel opgeknipt in chapters)
# ============================================
function Invoke-DownloadTrack {
    param(
        [Parameter(Mandatory = $true)][string]$VideoUrl,
        [string]$OutDirOverride
    )

    Write-Host ""
    Write-Host "=== Metadata ophalen ===" -ForegroundColor Cyan

    $meta = & yt-dlp @jsRuntimeArgs --no-playlist --dump-json $VideoUrl | ConvertFrom-Json
    if (-not $meta) { throw "Kon metadata niet ophalen" }

    $channel = if ($meta.channel) { "$($meta.channel)" }
               elseif ($meta.uploader) { "$($meta.uploader)" }
               else { 'Onbekend' }

    Write-Host "[x] Metadata opgehaald" -ForegroundColor Green
    Write-Host ""
    Write-Host $meta.title
    Write-Host $channel
    Write-Host ""

    $year = Get-Year -Info $meta
    $watchUrl = "https://www.youtube.com/watch?v=$($meta.id)"

    # --------------------------------------------
    # Chapters
    # --------------------------------------------
    $chapters = @()
    if ($meta.chapters) { $chapters = @($meta.chapters) }
    $fromDescription = $false

    if ($Split -and $chapters.Count -lt 2) {
        $dur = if ($meta.duration) { [double]$meta.duration } else { 0 }
        $chapters = @(Get-ChaptersFromDescription -Description "$($meta.description)" -Duration $dur)
        if ($chapters.Count -ge 2) {
            $fromDescription = $true
            Write-Host "[i] Geen chapters op YouTube; $($chapters.Count) tracks uit de beschrijving gelezen" -ForegroundColor DarkCyan
        }
    }

    $doSplit = $Split -and $chapters.Count -ge 2
    if ($Split -and -not $doSplit) {
        Write-Host "[WARN] Geen chapters gevonden - de video wordt als één bestand opgeslagen." -ForegroundColor Yellow
    }
    if (-not $Split -and $chapters.Count -ge 2) {
        Write-Host "[i] Deze video heeft $($chapters.Count) chapters. Gebruik -s om er losse tracks van te maken." -ForegroundColor DarkCyan
        Write-Host ""
    }

    # --------------------------------------------
    # Chapters opschonen: eigen nummering eruit, "Artiest - Nummer" gesplitst
    # --------------------------------------------
    $chapterPlan = [System.Collections.Generic.List[object]]::new()
    if ($doSplit) {
        $n = 0
        foreach ($c in $chapters) {
            $start = [double]$c.start_time
            $end   = [double]$c.end_time
            if ($end -le $start) { continue }
            $n++

            $ct = "$($c.title)"
            if (-not $KeepText) {
                $ct = Remove-TitleJunk $ct
                # Nummer vooraan dat het chapternummer herhaalt ("01. Sunrise") weg
                $m = [regex]::Match($ct, '^(\d{1,3})\s*[\.\)\-:_]?\s+(.+)$')
                if ($m.Success -and [int]$m.Groups[1].Value -eq $n) { $ct = $m.Groups[2].Value }
            }
            if (-not "$ct".Trim()) { $ct = "$($c.title)" }

            # Een tracklist schrijft vaak "Artiest - Nummer" per regel
            $chapArtist = $null
            if (-not $KeepText -and -not $Artist) {
                $sp = Split-ArtistTitle -Name $ct
                if ($sp) { $chapArtist = $sp.Artist; $ct = $sp.Title }
            }

            $null = $chapterPlan.Add([pscustomobject]@{
                Index  = $n
                Title  = $ct
                Artist = $chapArtist
                Start  = $start
                Length = $end - $start
            })
        }
        if ($chapterPlan.Count -lt 2) { $doSplit = $false }
    }

    # --------------------------------------------
    # Artiest / album / titel bepalen
    # YouTube Music vult artist/track/album; anders "Artiest - Nummer" uit de titel
    # --------------------------------------------
    $cleanTitle = if ($KeepText) { "$($meta.title)" } else { Remove-TitleJunk "$($meta.title)" }

    $trackTitle  = if ($meta.track)  { "$($meta.track)" }  else { $null }
    $trackArtist = if ($meta.artist) { "$($meta.artist)" } else { $null }
    $trackAlbum  = if ($meta.album)  { "$($meta.album)" }  else { $null }
    $haveArtist  = [bool]$trackArtist

    $albumBase = $cleanTitle
    if ($doSplit -and -not $KeepText) {
        # "... - Full Album" is een omschrijving, geen albumnaam
        $albumBase = $albumBase -replace '(?i)\s*[-–—|(\[]*\s*\bfull\s+album(\s+stream)?\b\s*[)\]]*\s*$', ''
        if (-not $albumBase.Trim()) { $albumBase = $cleanTitle }
    }

    # Staat de artiest in de videotitel? Bij -s alleen als de chapters zelf geen
    # artiest noemen - anders is "X - Y" de albumtitel, niet artiest + nummer.
    # Bij een podcast nooit: daar is het kanaal de show, en "Ep 12 - Iets" zou
    # anders "Ep 12" als artiest opleveren.
    $namedByChapters = $doSplit -and
                       ((@($chapterPlan | Where-Object { $_.Artist }).Count * 2) -ge $chapterPlan.Count)

    if (-not $haveArtist -and -not $KeepText -and -not $Artist -and -not $namedByChapters -and -not $Podcast) {
        $sp = Split-ArtistTitle -Name $albumBase
        if ($sp) {
            $trackArtist = $sp.Artist
            $haveArtist  = $true
            if ($doSplit) { $albumBase = $sp.Title }
            elseif (-not $trackTitle) { $trackTitle = $sp.Title }
        }
    }

    if (-not $trackTitle) { $trackTitle = $cleanTitle }
    if ($Artist) { $trackArtist = $Artist; $haveArtist = $true }
    if (-not $trackArtist) { $trackArtist = $channel }

    # --------------------------------------------
    # Doelmap en bestandsnamen
    # --------------------------------------------
    # Bij een podcast is het album de show, niet de aflevering
    $albumName = if ($Album) { $Album }
                 elseif ($doSplit) { $albumBase }
                 elseif ($Podcast) { $channel }
                 elseif ($trackAlbum) { $trackAlbum }
                 else { $cleanTitle }

    $OutDir = if ($OutDirOverride) {
        $OutDirOverride
    } elseif ($doSplit) {
        Join-ArtistAlbumDir -Base $BaseDir -ArtistName $trackArtist -AlbumTitle $albumName
    } else {
        Join-Path $BaseDir (Get-SafeDirName -Name $trackArtist)
    }

    $planned = [System.Collections.Generic.List[object]]::new()

    if ($doSplit) {
        $width = ([string]$chapterPlan.Count).Length
        if ($width -lt 2) { $width = 2 }
        foreach ($cp in $chapterPlan) {
            $name = Get-SafeFileName -Name $cp.Title
            if (-not $NoIndex) { $name = ("{0:D$width} {1}" -f $cp.Index, $name) }
            $cpArtist = if ($cp.Artist) { $cp.Artist } else { $trackArtist }

            $null = $planned.Add([pscustomobject]@{
                File   = "$name$ext"
                Title  = $cp.Title
                Artist = $cpArtist
                Track  = $cp.Index
                Start  = $cp.Start
                Length = $cp.Length
            })
        }
    } else {
        $name = if ($haveArtist) { "$trackArtist - $trackTitle" } else { $trackTitle }

        # Afleveringen sorteren op datum, niet op titel
        if ($Podcast) {
            $d = "$($meta.upload_date)"
            if ($d -match '^\d{8}$') {
                $name = "{0}-{1}-{2} {3}" -f $d.Substring(0, 4), $d.Substring(4, 2), $d.Substring(6, 2), $trackTitle
            }
        }

        $null = $planned.Add([pscustomobject]@{
            File   = (Get-SafeFileName -Name $name) + $ext
            Title  = $trackTitle
            Artist = $trackArtist
            Track  = 0
            Start  = -1
            Length = -1
        })
    }

    if ($planned.Count -eq 0) { throw "Geen bruikbare tracks" }

    # --------------------------------------------
    # Print Only
    # --------------------------------------------
    if ($PrintOnly) {
        Write-Host "=== Geplande bestanden ===" -ForegroundColor Green
        Write-Host "Map    : $OutDir"
        Write-Host "Artiest: $trackArtist"
        if ($doSplit) {
            $bron = if ($fromDescription) { 'uit de beschrijving' } else { 'chapters' }
            Write-Host "Album  : $albumName ($bron)"
        }
        if ($year) { Write-Host "Jaar   : $year" }
        Write-Host ""
        $planned | ForEach-Object { Write-Host "  $($_.File)" }
        Write-Host ""
        return
    }

    # --------------------------------------------
    # Bestaat alles al?
    # --------------------------------------------
    $todo = @($planned | Where-Object { -not (Test-Path -LiteralPath (Join-Path $OutDir $_.File)) })
    $skipped = $planned.Count - $todo.Count
    if ($todo.Count -eq 0) {
        Write-Host "Alles bestaat al in $OutDir - niets te doen" -ForegroundColor DarkGray
        return
    }

    $null = New-Item -ItemType Directory -Force -Path $OutDir

    # --------------------------------------------
    # Downloaden en encoden
    # --------------------------------------------
    Write-Host "=== Downloaden ===" -ForegroundColor Cyan
    Write-Host "Map: $OutDir" -ForegroundColor DarkGray
    Write-Host ""

    $workDir = Join-Path $CacheRoot "$($meta.id)"
    $src = Get-AudioSource -VideoUrl $watchUrl -WorkDir $workDir
    if (-not $src) { Remove-WorkDir $workDir; throw "Download gefaald" }

    if (-not $year) { $year = Get-Year -Info $src.Info }

    Write-Host ""
    if ($doSplit) { Write-Host "=== Splitsen ===" -ForegroundColor Cyan }
    else          { Write-Host "=== Omzetten naar $Format ===" -ForegroundColor Cyan }

    $failed = [System.Collections.Generic.List[string]]::new()
    $total = $todo.Count
    $i = 0

    foreach ($p in $todo) {
        $i++
        $out = Join-Path $OutDir $p.File

        Write-Progress -Activity "Omzetten" -Status $p.File -PercentComplete (($i - 1) / $total * 100)
        Write-Host "[$i/$total] $($p.File)" -ForegroundColor Yellow

        $tags = @{
            title        = $p.Title
            artist       = $p.Artist
            album_artist = $trackArtist
            album        = $albumName
            comment      = $watchUrl
        }
        if ($year) { $tags['date'] = $year }
        if ($genre) { $tags['genre'] = $genre }
        if ($p.Track -gt 0) { $tags['track'] = "$($p.Track)/$($planned.Count)" }

        $ok = Convert-Audio -Source $src.Audio -Dest $out -Cover $src.Cover `
                            -Start $p.Start -Length $p.Length -Tags $tags
        if (-not $ok) {
            Write-Host "  [ERROR] ffmpeg gefaald: $($p.File)" -ForegroundColor Red
            $null = $failed.Add($p.File)
        }
    }

    Write-Progress -Activity "Omzetten" -Completed

    # --------------------------------------------
    # Compleet bestand bewaren (-KeepFull)
    # --------------------------------------------
    if ($doSplit -and $KeepFull) {
        $fullOut = Join-Path $OutDir ((Get-SafeFileName -Name $cleanTitle) + $ext)
        if (-not (Test-Path -LiteralPath $fullOut)) {
            Write-Host "  -> $(Split-Path -Leaf $fullOut) (compleet)" -ForegroundColor DarkGray
            $fullTags = @{
                title        = $cleanTitle
                artist       = $trackArtist
                album_artist = $trackArtist
                album        = $albumName
                comment      = $watchUrl
            }
            if ($year) { $fullTags['date'] = $year }
            if ($genre) { $fullTags['genre'] = $genre }
            $null = Convert-Audio -Source $src.Audio -Dest $fullOut -Cover $src.Cover -Tags $fullTags
        }
    }

    Remove-WorkDir $workDir

    Write-Host ""
    Write-Host "=== Gereed! ===" -ForegroundColor Green
    Write-Host "Output: $OutDir"
    $ok = $total - $failed.Count
    Write-Host "$ok omgezet, $skipped overgeslagen, $($failed.Count) mislukt"
    if ($failed.Count -gt 0) {
        $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        throw "$($failed.Count) track(s) mislukt"
    }
}

# ============================================
# Een hele playlist / channel als album
# ============================================
function Invoke-DownloadAlbum {
    param(
        [Parameter(Mandatory = $true)][string]$ListUrl,
        [Parameter(Mandatory = $true)][object[]]$Entries,
        [string]$OutDirOverride
    )

    $channelName  = $Entries[0].Channel
    $playlistName = $Entries[0].Playlist

    Write-Host "[x] $($Entries.Count) video's gevonden" -ForegroundColor Green
    Write-Host ""
    Write-Host $channelName
    Write-Host $playlistName
    Write-Host ""

    # --------------------------------------------
    # Herhaalde tekst bepalen (zelfde aanpak als ypl.ps1)
    # --------------------------------------------
    $titles = @($Entries | ForEach-Object { $_.Title })
    $prefix = ''
    $suffix = ''

    if (-not $KeepText -and $Entries.Count -ge 2) {
        $suffix = Get-TrimmedAffix -Text (Get-CommonSuffix -Titles $titles) -Kind 'Suffix'
        if ($suffix.Trim().Length -lt 3) { $suffix = '' }

        $rest = @($titles | ForEach-Object {
            if ($suffix -and $_.EndsWith($suffix)) { $_.Substring(0, $_.Length - $suffix.Length) } else { $_ }
        })
        $prefix = Get-TrimmedAffix -Text (Get-CommonPrefix -Titles $rest) -Kind 'Prefix'
        if ($prefix.Trim().Length -lt 3) { $prefix = '' }

        foreach ($t in $rest) {
            $stripped = $t
            if ($prefix -and $stripped.StartsWith($prefix)) { $stripped = $stripped.Substring($prefix.Length) }
            if (-not $stripped.Trim()) { $prefix = ''; break }
        }

        if ($suffix) { Write-Host "Herhaalde staart : '$suffix'" -ForegroundColor DarkGray }
        if ($prefix) { Write-Host "Herhaalde kop    : '$prefix'" -ForegroundColor DarkGray }
        if ($suffix -or $prefix) { Write-Host "" }
    }

    # --------------------------------------------
    # Bestandsnamen en tags bepalen
    # --------------------------------------------
    $albumName   = if ($Album)  { $Album }  else { $playlistName }
    $albumArtist = if ($Artist) { $Artist } else { $channelName }

    $width = ([string]$Entries.Count).Length
    if ($width -lt 2) { $width = 2 }

    foreach ($e in $Entries) {
        $t = $e.Title
        if ($suffix -and $t.EndsWith($suffix)) { $t = $t.Substring(0, $t.Length - $suffix.Length) }
        if ($prefix -and $t.StartsWith($prefix)) { $t = $t.Substring($prefix.Length) }
        $t = $t -replace '^[\s\-–—|:,.]+', '' -replace '[\s\-–—|:,.]+$', ''

        # Nummer vooraan dat de playlist-index herhaalt ("3 Connecting...") weg
        $m = [regex]::Match($t, '^(\d{1,3})\s*[\.\)\-:_]?\s+(.+)$')
        if ($m.Success -and [int]$m.Groups[1].Value -eq $e.Index) {
            $t = $m.Groups[2].Value
        }

        if (-not $KeepText) { $t = Remove-TitleJunk $t }
        if (-not $t.Trim()) { $t = $e.Title }

        # "Artiest - Nummer" in de titel: de artiest hoort in de tag, niet in de
        # naam. Bij een podcast niet: daar is het kanaal de show.
        $trackArtist = $albumArtist
        $trackTitle  = $t
        if (-not $KeepText -and -not $Artist -and -not $Podcast) {
            $sp = Split-ArtistTitle -Name $t
            if ($sp) { $trackArtist = $sp.Artist; $trackTitle = $sp.Title }
        }

        $name = Get-SafeFileName -Name $trackTitle
        if (-not $NoIndex) { $name = ("{0:D$width} {1}" -f $e.Index, $name) }

        $e | Add-Member -NotePropertyName File        -NotePropertyValue "$name$ext"  -Force
        $e | Add-Member -NotePropertyName TrackTitle  -NotePropertyValue $trackTitle  -Force
        $e | Add-Member -NotePropertyName TrackArtist -NotePropertyValue $trackArtist -Force
    }

    # --------------------------------------------
    # Selectie (-Items) - yt-dlp rekent zelf uit welke items erbij horen
    # --------------------------------------------
    $selected = @($Entries)
    if ($Items) {
        $ids = @(& yt-dlp @jsRuntimeArgs --flat-playlist --ignore-no-formats-error `
                    --playlist-items $Items --print "%(id)s" $ListUrl | Where-Object { $_ })
        if ($ids.Count -eq 0) { throw "Selectie '$Items' levert geen video's op" }
        $wanted = @{}
        foreach ($id in $ids) { $wanted[$id.Trim()] = $true }
        $selected = @($Entries | Where-Object { $wanted.ContainsKey($_.Id) })
        if ($selected.Count -eq 0) { throw "Selectie '$Items' levert geen video's op" }
        Write-Host "Selectie '$Items': $($selected.Count) van $($Entries.Count) video's" -ForegroundColor DarkGray
        Write-Host ""
    }

    # --------------------------------------------
    # Output directory
    # --------------------------------------------
    $OutDir = if ($OutDirOverride) {
        $OutDirOverride
    } else {
        Join-ArtistAlbumDir -Base $BaseDir -ArtistName $albumArtist -AlbumTitle $albumName
    }

    # --------------------------------------------
    # Print Only
    # --------------------------------------------
    if ($PrintOnly) {
        Write-Host "=== Geplande bestanden ===" -ForegroundColor Green
        Write-Host "Map    : $OutDir"
        Write-Host "Album  : $albumName"
        Write-Host "Artiest: $albumArtist"
        Write-Host ""
        $selected | ForEach-Object { Write-Host "  $($_.File)" }
        Write-Host ""
        return
    }

    $null = New-Item -ItemType Directory -Force -Path $OutDir

    $jsonFile = Join-Path $OutDir "album.json"
    [pscustomobject]@{
        url      = $ListUrl
        artist   = $albumArtist
        album    = $albumName
        format   = $Format
        bitrate  = $bitrate
        stripped = [pscustomobject]@{ prefix = $prefix; suffix = $suffix }
        count    = $Entries.Count
        entries  = $Entries
        selected = @($selected | ForEach-Object { $_.File })
    } | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 $jsonFile

    # --------------------------------------------
    # Downloaden
    # --------------------------------------------
    Write-Host "=== Downloaden ===" -ForegroundColor Cyan
    Write-Host "Map: $OutDir" -ForegroundColor DarkGray
    Write-Host ""

    $order = @($selected)
    if ($Reverse) { [array]::Reverse($order) }

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

        Write-Progress -Activity "Album downloaden" -Status $e.File -PercentComplete (($i - 1) / $total * 100)
        Write-Host "[$i/$total] $($e.File)" -ForegroundColor Yellow

        $watchUrl = "https://www.youtube.com/watch?v=$($e.Id)"
        $workDir  = Join-Path $CacheRoot "$($e.Id)"

        $src = Get-AudioSource -VideoUrl $watchUrl -WorkDir $workDir
        if (-not $src) {
            Write-Host "  [ERROR] Download gefaald: $($e.File)" -ForegroundColor Red
            $null = $failed.Add($e.File)
            Remove-WorkDir $workDir
            continue
        }

        $tags = @{
            title        = $e.TrackTitle
            artist       = $e.TrackArtist
            album_artist = $albumArtist
            album        = $albumName
            track        = "$($e.Index)/$($Entries.Count)"
            comment      = $watchUrl
        }
        $year = Get-Year -Info $src.Info
        if ($year) { $tags['date'] = $year }
        if ($genre) { $tags['genre'] = $genre }

        $ok = Convert-Audio -Source $src.Audio -Dest $out -Cover $src.Cover -Tags $tags
        if (-not $ok) {
            Write-Host "  [ERROR] ffmpeg gefaald: $($e.File)" -ForegroundColor Red
            $null = $failed.Add($e.File)
        }

        Remove-WorkDir $workDir
    }

    Write-Progress -Activity "Album downloaden" -Completed

    Write-Host ""
    Write-Host "=== Gereed! ===" -ForegroundColor Green
    Write-Host "Output: $OutDir"
    $ok = $total - $failed.Count - $skipped
    Write-Host "$ok gedownload, $skipped overgeslagen, $($failed.Count) mislukt"
    if ($failed.Count -gt 0) {
        $failed | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        throw "$($failed.Count) track(s) mislukt"
    }
}

# ============================================
# Eén URL verwerken: playlist of losse video?
# ============================================
function Invoke-DownloadUrl {
    param(
        [Parameter(Mandatory = $true)][string]$TargetUrl,
        [string]$OutDirOverride
    )

    # Een kale watch-/shorts-URL zonder list= is altijd één video; dan hoeft de
    # playlist-probe niet.
    $looksSingle = ($TargetUrl -notmatch '[?&]list=') -and
                   ($TargetUrl -match '(youtu\.be/|[?&]v=|/shorts/|/live/)')

    if ($looksSingle) {
        Invoke-DownloadTrack -VideoUrl $TargetUrl -OutDirOverride $OutDirOverride
        return
    }

    Write-Host ""
    Write-Host "=== Playlist ophalen ===" -ForegroundColor Cyan

    $sep = [string][char]0x1F
    $template = "%(playlist_index)s${sep}%(id)s${sep}%(playlist_channel,playlist_uploader,channel,uploader|Onbekend)s${sep}%(playlist_title,playlist,title|Playlist)s${sep}%(title)s"

    # Altijd de hele playlist ophalen: de herhaalde tekst en de nummering volgen
    # uit alle titels, ook als er met -Items maar een paar nummers gehaald worden.
    $listArgs = @('--flat-playlist', '--ignore-no-formats-error', '--print', $template)

    $lines = @(& yt-dlp @jsRuntimeArgs @listArgs $TargetUrl | Where-Object { $_ -and $_.Contains($sep) })
    if ($LASTEXITCODE -ne 0 -and $lines.Count -eq 0) { throw "Kon playlist niet ophalen" }
    if ($lines.Count -eq 0) { throw "Geen video's gevonden" }

    $entries = [System.Collections.Generic.List[object]]::new()
    $pos = 0
    $unavailable = 0
    foreach ($line in $lines) {
        $pos++
        $f = $line -split $sep
        if ($f.Count -lt 5) { continue }

        $title = ($f[4..($f.Count - 1)] -join $sep)

        # Privé, verwijderd of region-locked: yt-dlp geeft dan "NA" terug. Die
        # eruit filteren scheelt een reeks mislukte downloads.
        if (-not $f[1] -or $f[1] -eq 'NA' -or -not $title -or $title -eq 'NA') {
            $unavailable++
            continue
        }

        $idx = 0
        if (-not [int]::TryParse($f[0], [ref]$idx)) { $idx = $pos }
        $null = $entries.Add([pscustomobject]@{
            Index    = $idx
            Id       = $f[1]
            Channel  = $f[2]
            Playlist = $f[3]
            Title    = $title
        })
    }

    if ($unavailable -gt 0) {
        Write-Host "[i] $unavailable niet-beschikbare video('s) overgeslagen" -ForegroundColor DarkGray
    }

    if ($entries.Count -eq 0) { throw "Geen bruikbare video's gevonden" }

    # Eén video (of een playlist van één): als losse track behandelen, zodat -s
    # en de chapters gewoon werken.
    if ($entries.Count -eq 1) {
        Invoke-DownloadTrack -VideoUrl "https://www.youtube.com/watch?v=$($entries[0].Id)" -OutDirOverride $OutDirOverride
        return
    }

    if ($SplitExplicit) {
        Write-Host "[WARN] -s geldt alleen voor losse video's; voor een playlist wordt het genegeerd." -ForegroundColor Yellow
    }

    Invoke-DownloadAlbum -ListUrl $TargetUrl -Entries @($entries) -OutDirOverride $OutDirOverride
}

# ============================================
# Takenlijst opbouwen (enkele URL en/of batch-bestand)
# ============================================
$jobs = [System.Collections.Generic.List[object]]::new()
if ($Url) { $null = $jobs.Add([pscustomobject]@{ Url = $Url; Options = @{}; Line = 0 }) }
if ($BatchFile) {
    if (-not (Test-Path $BatchFile)) {
        Write-Host "[ERROR] Batch-bestand niet gevonden: $BatchFile" -ForegroundColor Red
        if ($LogFile) { Stop-Transcript }
        exit 1
    }
    foreach ($job in (Read-BatchFile -Path $BatchFile)) { $null = $jobs.Add($job) }
}

if ($jobs.Count -eq 0) {
    Write-Host "[ERROR] Geen URL opgegeven. Gebruik -Url <URL> of -BatchFile <bestand>." -ForegroundColor Red
    Write-Host "        Help: ydm -h" -ForegroundColor Yellow
    if ($LogFile) { Stop-Transcript }
    exit 1
}

if ($BatchFile -and $OutputDir) {
    Write-Host "[WARN] -OutputDir geldt niet voor een hele lijst; zet er per regel een -o achter als je dat wil." -ForegroundColor Yellow
}

# ============================================
# Main loop
# ============================================
$exitCode = 0
$failedUrls = [System.Collections.Generic.List[string]]::new()
$idx = 0

try {
    foreach ($job in $jobs) {
        $idx++

        # Opties van deze regel klaarzetten; de volgende regel begint weer bij
        # wat er op de commandline stond.
        Set-RunOptions -Override $job.Options

        if ($jobs.Count -gt 1) {
            Write-Host ""
            Write-Host "############################################" -ForegroundColor Magenta
            Write-Host "# [$idx/$($jobs.Count)] $($job.Url)  ($(Get-ModeLabel))" -ForegroundColor Magenta
            Write-Host "############################################" -ForegroundColor Magenta
        }

        if ($job.Url -notmatch '^https?://') {
            Write-Host "[ERROR] Ongeldige URL overgeslagen: $($job.Url)" -ForegroundColor Red
            $failedUrls.Add($job.Url)
            continue
        }

        # Een -o op de regel zelf telt altijd; de globale -o alleen bij één URL
        $outOverride = if ($job.Options.ContainsKey('OutputDir') -or $jobs.Count -eq 1) { $OutputDir } else { $null }

        try {
            Invoke-DownloadUrl -TargetUrl $job.Url -OutDirOverride $outOverride
        }
        catch {
            Write-Host ""
            Write-Host "[ERROR] $($job.Url) : $_" -ForegroundColor Red
            $failedUrls.Add($job.Url)
        }
    }

    if ($jobs.Count -gt 1) {
        Write-Host ""
        $ok = $jobs.Count - $failedUrls.Count
        Write-Host "=== Batch klaar: $ok/$($jobs.Count) URL's gelukt ===" -ForegroundColor Green
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
