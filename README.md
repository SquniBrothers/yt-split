# split

Download een YouTube-video en/of splitst deze in losse bestanden op basis van chapters.

Twee versies met identieke functionaliteit:
- **`split.ps1`** — Windows (PowerShell)
- **`split.sh`** — Linux / macOS (bash)

Twee workflows:
- **Zonder `-s`** — download de hele video, splitst met ffmpeg in chapters
- **Met `-s`** — kies interactief chapters, download alleen die stukken via `--download-sections`

## Voorbeelden

```powershell
# Alle chapters, standaard instellingen
.\split.ps1 -u "https://www.youtube.com/watch?v=C03L903xe4w"

# Interactief chapters selecteren + thumbnails
.\split.ps1 -u "https://www.youtube.com/watch?v=C03L903xe4w" -s -t

# Chapters previewen (geen download)
.\split.ps1 -u "https://www.youtube.com/watch?v=C03L903xe4w" -p

# Alleen downloaden, 4K kwaliteit
.\split.ps1 -u "https://www.youtube.com/watch?v=C03L903xe4w" -d -q "++"

# Frame-accurate cuts + eigen output map
.\split.ps1 -u "https://www.youtube.com/watch?v=C03L903xe4w" -a -o "D:\bewerkt"

# 720p, interactief chapters selecteren
.\split.ps1 -u "https://www.youtube.com/watch?v=C03L903xe4w" -q "-" -s

# Batch: alle URL's uit een tekstbestand (1 per regel) + thumbnails
.\split.ps1 -f "urls.txt" -t
```

## Inhoud

- [Vereisten](#vereisten)
- [Installatie](#installatie)
  - [Windows (winget)](#windows-winget)
  - [macOS (Homebrew)](#macos-homebrew)
  - [Debian / Ubuntu (apt)](#debian--ubuntu-apt)
  - [Arch Linux (pacman)](#arch-linux-pacman)
- [Linux / macOS (`split.sh`)](#linux--macos-splitsh)
- [Parameters](#parameters)
- [Workflows](#workflows)
  - [Zonder `-s` (hele video + ffmpeg split)](#zonder--s-hele-video--ffmpeg-split)
  - [Met `-s` (download-sections per chapter)](#met--s-download-sections-per-chapter)
  - [`-d` (download only)](#-d-download-only)
  - [`-p` (preview)](#-p-preview)
- [Batch (meerdere video's)](#batch-meerdere-videos)
- [Output structuur](#output-structuur)
- [Bestandsnamen](#bestandsnamen)
- [Kwaliteitsniveaus](#kwaliteitsniveaus)
- [Best practices](#best-practices)
  - [Wanneer welke workflow?](#wanneer-welke-workflow)
  - [`-s` vs geen `-s`: afweging](#-s-vs-geen--s-afweging)
  - [Kwaliteit advies](#kwaliteit-advies)
  - [Veelgemaakte fouten](#veelgemaakte-fouten)

## Vereisten

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [ffmpeg](https://ffmpeg.org/) (met ffprobe)
- Een JavaScript runtime voor YouTube-extractie: [node](https://nodejs.org/), [deno](https://deno.com/) of bun (wordt automatisch gedetecteerd)
- **Alleen `split.sh`:** [jq](https://jqlang.github.io/jq/) voor het parsen van de metadata

## Installatie

> `ffprobe` zit in het `ffmpeg`-pakket. `node` levert de JavaScript runtime (mag ook `deno`).
> Houd **yt-dlp** up-to-date — YouTube wijzigt vaak en oude versies breken.

### Windows (winget)

Voor `split.ps1`. `jq` is hier niet nodig (PowerShell parset de JSON zelf).

```powershell
winget install Git.Git
winget install yt-dlp.yt-dlp
winget install Gyan.FFmpeg
winget install OpenJS.NodeJS
# Herstart hierna de terminal zodat de PATH bijgewerkt is.

git clone https://github.com/SquniBrothers/yt-split.git
cd yt-split
.\split.ps1 -u "https://www.youtube.com/watch?v=..." -s -t
# updaten kan later met: yt-dlp -U
```

### macOS (Homebrew)

[Homebrew](https://brew.sh) vereist.

```bash
brew install git yt-dlp ffmpeg jq node

git clone https://github.com/SquniBrothers/yt-split.git
cd yt-split
chmod +x split.sh
```

### Debian / Ubuntu (apt)

```bash
sudo apt update
sudo apt install -y git ffmpeg jq nodejs

# yt-dlp rechtstreeks (apt-versie is vaak verouderd):
sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
sudo chmod a+rx /usr/local/bin/yt-dlp
# updaten kan later met: sudo yt-dlp -U

git clone https://github.com/SquniBrothers/yt-split.git
cd yt-split
chmod +x split.sh
```

### Arch Linux (pacman)

```bash
sudo pacman -S --needed git yt-dlp ffmpeg jq nodejs

git clone https://github.com/SquniBrothers/yt-split.git
cd yt-split
chmod +x split.sh
```

## Linux / macOS (`split.sh`)

```bash
chmod +x split.sh
./split.sh -u "https://www.youtube.com/watch?v=..." -s -t
```

`split.sh` gebruikt dezelfde flags, maar in lange vorm beschikbaar:
`-u/--url`, `-f/--batch-file`, `-b/--base-dir`, `-o/--output-dir`, `-s/--select`, `-t/--thumbnails`,
`-a/--accurate`, `-k/--keep`, `-l/--log`, `-p/--print-chapters`, `-d/--download-only`,
`-q/--quality`, `-h/--help`. Paden gebruiken `/` i.p.v. `\` (default basis: `$HOME/videos`).

## Parameters

| Parameter | Alias | Type | Default | Beschrijving |
|---|---|---|---|---|
| `-Url` | `-u` | string | — | YouTube video URL (`-u` óf `-f` verplicht) |
| `-BatchFile` | `-f` | string | — | Tekstbestand met 1 URL per regel; lege regels en regels die met `#` beginnen worden genegeerd |
| `-BaseDir` | `-b` | string | `$HOME\videos` | Basis directory voor downloads/output |
| `-OutputDir` | `-o` | string | `$BaseDir\<kanaal>\<titel>` | Eigen output directory (overschrijft default; genegeerd in batch-modus) |
| `-SelectChapters` | `-s` | switch | — | Toon chapters, selecteer interactief (V/n), download alleen geselecteerde met `--download-sections` |
| `-Thumbnails` | `-t` | switch | — | Genereer een JPG thumbnail per chapter (midpoint) |
| `-AccurateCut` | `-a` | switch | — | Re-encode voor frame-accurate cuts (langzamer, alleen zonder `-s`) |
| `-KeepDownloads` | `-k` | switch | — | Verwijder downloads directory niet na afloop |
| `-LogFile` | `-l` | string | — | Pad voor logbestand (via Start-Transcript) |
| `-PrintChapters` | `-p` | switch | — | Toon chapter lijst en stop (geen download) |
| `-DownloadOnly` | `-d` | switch | — | Alleen downloaden, niet splitsen |
| `-Quality` | `-q` | string | `+` | Kwaliteit: `++` (4K), `+` (1080p), `-` (720p), `--` (480p) |
| `-Help` | `-h` | switch | — | Dit help bericht |

## Workflows

### Zonder `-s` (hele video + ffmpeg split)

```
metadata → download hele video → ffmpeg split alle chapters → thumbs → cleanup
```

- Downloadt de volledige video naar `$BaseDir\downloads\...`
- Splitst met ffmpeg naar `$BaseDir\<kanaal>\<titel>\`
- `-a` schakelt re-encode in voor frame-accurate cuts
- `-k` behoudt de downloads na afloop

### Met `-s` (download-sections per chapter)

```
metadata → toon alle chapters → selecteer V/n → download alleen geselecteerde → thumbs
```

- Chapters worden **vóór** het downloaden getoond, je kiest welke je wil
- Per chapter: `yt-dlp --download-sections "*start-end" --force-keyframes-at-cuts`
- Alleen de geselecteerde stukken worden gedownload — kleinere download
- Bestanden gaan direct naar `$BaseDir\<kanaal>\<titel>\`
- Geen ffmpeg split nodig (yt-dlp knipt zelf), geen cleanup nodig

### `-d` (download only)

```
metadata → download 1 bestand → klaar
```

- Enkel bestand: `$BaseDir\<kanaal>\<titel>\{titel}.mp4`
- Geen chapters, geen split

### `-p` (preview)

```
metadata → print chapters → stoppen
```

- Alle chapters in een tabel zien zonder iets te downloaden

## Batch (meerdere video's)

Met `-f` / `-BatchFile` (PowerShell) of `-f` / `--batch-file` (bash) verwerk je een
heel tekstbestand aan video's achter elkaar. Het bestand bevat **één URL per regel**:

```text
# urls.txt — alles na een # en lege regels worden genegeerd
https://www.youtube.com/watch?v=C03L903xe4w
https://www.youtube.com/watch?v=dQw4w9WgXcQ

# losse video die je later wil toevoegen:
https://youtu.be/9bZkp7q19f0
```

```powershell
# Windows
.\split.ps1 -f "urls.txt" -t
```

```bash
# Linux / macOS
./split.sh -f urls.txt -t
```

- Alle andere flags (`-s`, `-t`, `-d`, `-q`, …) gelden voor **elke** video in de lijst.
- Een mislukte video stopt de batch niet; aan het eind komt een overzicht met
  `X/Y gelukt` en een lijst van wat faalde (exit-code 1 als er iets misging).
- **`-o`/`-OutputDir` wordt genegeerd in batch-modus** — elke video krijgt zijn eigen
  map `BaseDir\<kanaal>\<titel>\`, zodat ze elkaar niet overschrijven.
- Je kunt `-u` en `-f` ook combineren; alle URL's worden samengevoegd.
- Met `-s` (interactief chapters kiezen) word je **per video** om een selectie gevraagd.

## Output structuur

Allebij (`zonder -s` en `met -s`) eindigen in dezelfde output map:

```
$HOME\videos\De_Nieuwe_Wereld_TV\De_Stille_Opmars_van_een_Nieuwe_Geopolitieke_Gigant_#2306\01_Hoofdstuk.mp4
$HOME\videos\De_Nieuwe_Wereld_TV\De_Stille_Opmars_van_een_Nieuwe_Geopolitieke_Gigant_#2306\meta.json
```

Thumbnails (met `-t`):
```
$HOME\videos\De_Nieuwe_Wereld_TV\De_Stille_Opmars_van_een_Nieuwe_Geopolitieke_Gigant_#2306\01_Hoofdstuk.jpg
```

> **Let op:** `$BaseDir` is standaard `$HOME\videos`. De output komt in `$BaseDir\<kanaal>\<titel>\` (géén dubbel `videos\videos\`).

## Bestandsnamen

Chapters worden opgeslagen als `01_titel.mp4`, `02_titel.mp4`, etc.
Spaties en speciale tekens worden vervangen door underscores.
Bijv. `"How to Code - Part 1"` wordt `01_How_to_Code_Part_1.mp4`.

## Kwaliteitsniveaus

| Flag | Resolutie | yt-dlp format |
|---|---|---|
| `++` | 4K (2160p) | `bestvideo[height<=2160]+bestaudio/best[height<=2160]` |
| `+` | 1080p (default) | `bestvideo[height<=1080]+bestaudio/best[height<=1080]` |
| `-` | 720p | `bestvideo[height<=720]+bestaudio/best[height<=720]` |
| `--` | 480p | `bestvideo[height<=480]+bestaudio/best[height<=480]` |

## Best practices

### Wanneer welke workflow?

| Situatie | Aanbevolen |
|---|---|
| Je wilt alle chapters | Zonder `-s` — downloadt 1x de hele video, snelle ffmpeg split |
| Je wilt een paar specifieke chapters | `-s` — downloadt alleen die stukken, geen ffmpeg nodig |
| Je weet nog niet welke chapters | `-p` eerst previewen, dan `-s` met de juiste keuze |
| Alleen de video (niet splitsen) | `-d` — 1 bestand, schone naam |

### `-s` vs geen `-s`: afweging

**Zonder `-s`**:
- + Sneller als je alle chapters wil (1x downloaden)
- + `-a` voor frame-accurate re-encode beschikbaar
- - Grote download (hele video)
- - Tijdelijke `downloads\` map, cleanup nodig

**Met `-s`**:
- + Kleinere download (alleen geselecteerde stukken)
- + Geen tijdelijke bestanden, geen cleanup
- + Chapters worden getoond vóór downloaden
- - Iets trager per chapter (yt-dlp init overhead)
- - Enkel formaat (`best[...]`) i.p.v. gescheiden video+audio — stabieler voor `--download-sections`

### Kwaliteit advies

- `+` (1080p) is voor de meeste video's de beste balans tussen kwaliteit en bestandsgrootte
- `++` (4K) alleen bij korte video's of als je écht 4K nodig hebt — bestanden worden snel >5GB
- `-` (720p) of `--` (480p) voor podcasts/talks — klein bestand, geen visuele kwaliteit nodig

### Veelgemaakte fouten

- **`--download-sections` blijft hangen** — als yt-dlp vastloopt met `bestvideo+bestaudio`, gebruik dan `-s` die automatisch `best[...]` single format gebruikt
- **Geen chapters** — niet elke video heeft chapters. Gebruik `-p` om te checken
- **Grote bestanden** — 4K video's van >1 uur kunnen 10-20GB zijn. Zorg dat je genoeg schijfruimte hebt
- **Geen JS runtime** — yt-dlp heeft sinds kort een JavaScript runtime nodig voor YouTube-extractie. Beide scripts detecteren automatisch `deno`, `node` of `bun` en geven die door via `--js-runtimes`. Zie je een warning over "No supported JavaScript runtime", installeer dan [Node.js](https://nodejs.org/) of [deno](https://deno.com/) (zie de [EJS wiki](https://github.com/yt-dlp/yt-dlp/wiki/EJS))
