# ypl

Download een complete YouTube **playlist** (of channel) naar `<kanaal>\<playlist>\`, met
de tekst die in élke videotitel terugkomt eruit gestript.

Waar [`split.ps1`](README.md) één video in chapters knipt, doet `ypl.ps1` het omgekeerde:
het haalt een hele playlist op en zorgt dat je er een nette, genummerde reeks bestanden
aan overhoudt.

> Wil je alleen de audio als mp3, met tags en album art? Dan is [`ydm.md`](ydm.md) wat je
> zoekt: dezelfde playlist-aanpak, maar dan als album.

```
1 Creating projects and jobs - Trimble Access - Getting Started     ->  01 Creating projects and jobs.mp4
2 Linking and Importing Files - Trimble Access - Getting Started    ->  02 Linking and Importing Files.mp4
3 Connecting to a Total Station - Trimble Access - Getting Started  ->  03 Connecting to a Total Station.mp4
```

## Voorbeelden

```powershell
# Hele playlist, 1080p, naar $HOME\videos\<kanaal>\<playlist>\
ypl "https://www.youtube.com/playlist?list=PLHyRBPzaNWTma3XcBD2xbpxRzctC2K028"

# Eerst kijken wat de bestandsnamen worden (geen download)
ypl "https://www.youtube.com/playlist?list=PL..." -p

# Alleen video 1 t/m 5, in 4K
ypl "https://www.youtube.com/playlist?list=PL..." -i "1-5" -q 2160

# Een channel i.p.v. een playlist, met ondertitels
ypl "https://www.youtube.com/@TrimbleAccess/videos" -s

# Originele titels behouden, zonder volgnummer
ypl "https://www.youtube.com/playlist?list=PL..." -k -n

# Batch: alle playlists uit een tekstbestand (1 per regel)
ypl -f "playlists.txt"
```

## Voorbeeld-run

```
=== Playlist ophalen ===
[x] 10 video's gevonden

Trimble Access
Getting Started with Trimble Access

Herhaalde staart : ' - Trimble Access - Getting Started'

=== Downloaden ===
Map: C:\Users\User\videos\Trimble_Access\Getting_Started_with_Trimble_Access

[1/10] 01 Creating projects and jobs.mp4
[2/10] 02 Linking and Importing Files.mp4
[3/10] 03 Connecting to a Total Station.mp4
...
[10/10] 10 GNSS Site Calibration.mp4

=== Gereed! ===
Output: C:\Users\User\videos\Trimble_Access\Getting_Started_with_Trimble_Access
10 gedownload, 0 overgeslagen, 0 mislukt
```

## Inhoud

- [Vereisten](#vereisten)
- [Alias instellen](#alias-instellen)
- [Parameters](#parameters)
- [Herhaalde tekst strippen](#herhaalde-tekst-strippen)
- [Output structuur](#output-structuur)
- [Selectie met `-i`](#selectie-met--i)
- [Hervatten](#hervatten)
- [Batch (meerdere playlists)](#batch-meerdere-playlists)
- [Kwaliteitsniveaus](#kwaliteitsniveaus)
- [Veelgemaakte fouten](#veelgemaakte-fouten)

## Vereisten

Zelfde als `split.ps1` (zie [README.md](README.md#vereisten)):

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [ffmpeg](https://ffmpeg.org/) — voor het mergen van video+audio
- Een JavaScript runtime voor YouTube-extractie: [node](https://nodejs.org/), [deno](https://deno.com/) of bun (wordt automatisch gedetecteerd)

## Alias instellen

Net als `ys` voor `split.ps1`. Open je profiel met `notepad $PROFILE` en voeg toe:

```powershell
function ytplaylist {
    & "C:\Users\User\scripts\yt-split\ypl.ps1" @args
}
Set-Alias ypl ytplaylist
```

> Een directe `Set-Alias ypl "...\ypl.ps1"` werkt niet met argumenten — vandaar het
> wrapper-functietje dat `@args` doorgeeft. Herstart de terminal of run `. $PROFILE`.

## Parameters

| Parameter | Alias | Type | Default | Beschrijving |
|---|---|---|---|---|
| `-Url` | `-u` | string | — | Playlist- of channel-URL (mag ook positioneel: `ypl "https://..."`) |
| `-BatchFile` | `-f` | string | — | Tekstbestand met 1 playlist-URL per regel; lege regels en regels die met `#` beginnen worden genegeerd |
| `-BaseDir` | `-b` | string | `$HOME\videos` | Basis directory voor de output |
| `-OutputDir` | `-o` | string | `$BaseDir\<kanaal>\<playlist>` | Eigen output directory (genegeerd in batch-modus) |
| `-Items` | `-i` | string | — | Selectie in yt-dlp syntax: `"1-5"`, `"3,7,9"`, `"5-"`, `":10"` |
| `-Quality` | `-q` | string | `+` | Kwaliteit: `++`/`2160`, `+`/`1080`, `-`/`720`, `--`/`480` |
| `-NoIndex` | `-n` | switch | — | Geen `01 ` volgnummer voor de bestandsnaam |
| `-KeepText` | `-k` | switch | — | Herhaalde tekst **niet** strippen (originele titels) |
| `-Reverse` | `-r` | switch | — | Playlist in omgekeerde volgorde downloaden (oudste eerst bij een channel) |
| `-Subs` | `-s` | switch | — | Ondertitels meenemen (incl. auto-gegenereerd, omgezet naar `.srt`) |
| `-PrintOnly` | `-p` | switch | — | Toon de geplande bestandsnamen en stop (geen download) |
| `-LogFile` | `-l` | string | — | Pad voor logbestand (via `Start-Transcript`) |
| `-Help` | `-h` | switch | — | Help bericht |

## Herhaalde tekst strippen

Playlist-uploaders zetten vrijwel altijd dezelfde reeksnaam in elke titel. Dat is precies
de tekst die je in een bestandsnaam niet wil.

`ypl` bepaalt de herhaalde tekst uit **alle** titels van de playlist:

1. **Staart** — de langste tekst die alle titels gemeen hebben aan het eind.
2. **Kop** — idem aan het begin, berekend op wat er na stap 1 overblijft.
3. Kop en staart worden teruggeknipt tot een woordgrens, zodat `"ing Started"` nooit
   midden in een woord begint maar `" Started"` wordt.
4. Een fragment van minder dan 3 tekens telt niet mee, en er wordt nooit gestript als
   er een lege titel zou overblijven.
5. Een nummer vooraan dat de playlist-index hérhaalt (`"3 Connecting to..."` als item 3)
   verdwijnt; het volgnummer komt er zero-padded weer voor.

| Titels in de playlist | Resultaat |
|---|---|
| `6 Measure Codes - Trimble Access - Getting Started` | `06 Measure Codes.mp4` |
| `Python Tutorial #1 - Variables` | `01 Variables.mp4` |
| `Ep 2: Setup \| Deep Dive Podcast` | `02 Ep 2 Setup.mp4` |
| Titels zonder gemeenschappelijke tekst | onveranderd, alleen genummerd |

De gevonden kop/staart wordt vóór het downloaden getoond. Zie je iets dat je niet wil
laten strippen, gebruik dan `-k`. Twijfel je over de namen: `-p` laat ze zien zonder te
downloaden.

> De herhaalde tekst wordt altijd uit de **hele** playlist bepaald, ook met `-i`. Zo
> krijgen video's 3 en 7 dezelfde behandeling als bij een volledige download.

## Output structuur

```
$HOME\videos\Trimble_Access\Getting_Started_with_Trimble_Access\01 Creating projects and jobs.mp4
$HOME\videos\Trimble_Access\Getting_Started_with_Trimble_Access\02 Linking and Importing Files.mp4
...
$HOME\videos\Trimble_Access\Getting_Started_with_Trimble_Access\playlist.json
```

- Mapnamen krijgen underscores (zoals in `split.ps1`), bestandsnamen houden hun spaties.
- `playlist.json` bewaart de URL, het kanaal, de gestripte kop/staart en alle entries —
  handig om achteraf te zien waar een bestandsnaam vandaan komt.
- Met `-o` kies je zelf een map; `<kanaal>\<playlist>` wordt dan niet aangemaakt.

## Selectie met `-i`

`-i` gebruikt de yt-dlp syntax en wordt door yt-dlp zelf uitgerekend:

```powershell
ypl "https://www.youtube.com/playlist?list=PL..." -i "1-5"     # de eerste vijf
ypl "https://www.youtube.com/playlist?list=PL..." -i "3,7,9"   # drie losse items
ypl "https://www.youtube.com/playlist?list=PL..." -i "5-"      # vanaf 5 tot het eind
ypl "https://www.youtube.com/playlist?list=PL..." -i ":10"     # t/m 10
```

De nummering in de bestandsnaam blijft de échte playlist-index, dus `-i "7"` levert
`07 ...mp4` op.

## Hervatten

Bestaat een bestand al in de output map, dan wordt die video overgeslagen:

```
[4/10] 04 Total Station Setup.mp4 - bestaat al, overgeslagen
```

Een afgebroken download pak je dus op door hetzelfde commando opnieuw te draaien. Aan het
eind volgt altijd een telling: `7 gedownload, 3 overgeslagen, 0 mislukt`. Video's die
mislukken (privé, region-locked, verwijderd) stoppen de rest niet — ze worden na afloop
opgesomd.

## Batch (meerdere playlists)

```powershell
# playlists.txt — alles na een # en lege regels worden genegeerd
# Trimble Access
https://www.youtube.com/playlist?list=PLHyRBPzaNWTma3XcBD2xbpxRzctC2K028
https://www.youtube.com/@freecodecamp/videos
```

```powershell
ypl -f "playlists.txt"
```

Elke playlist krijgt zijn eigen `<kanaal>\<playlist>\` map, dus `-o` wordt in batch-modus
genegeerd.

## Kwaliteitsniveaus

| Flag | Alias | Resolutie | yt-dlp format |
|---|---|---|---|
| `++` | `4k`, `2160` | 4K | `bestvideo[height<=2160]+bestaudio/best[height<=2160]` |
| `+` | `1080` | 1080p (default) | `bestvideo[height<=1080]+bestaudio/best[height<=1080]` |
| `-` | `720` | 720p | `bestvideo[height<=720]+bestaudio/best[height<=720]` |
| `--` | `480` | 480p | `bestvideo[height<=480]+bestaudio/best[height<=480]` |

> **PowerShell leest `-q "-"` en `-q "--"` als parameternaam**, ook tussen quotes. Gebruik
> daarom `-q 720` / `-q 480`, of schrijf het met een dubbele punt: `-q:"--"`.

## Veelgemaakte fouten

- **Er wordt niets gestript** — dan hebben de titels geen gemeenschappelijke kop of staart
  van 3+ tekens. Check met `-p` wat `ypl` ziet.
- **Er wordt te veel gestript** — bij korte playlists kan een toevallige overlap groot
  lijken. `-k` houdt de originele titels.
- **Een channel-URL levert een rare playlistnaam** — YouTube noemt de tabs `<kanaal> - Videos`
  / `- Shorts` / `- Live`. Gebruik `-o` als je een eigen mapnaam wil.
- **Geen JS runtime** — yt-dlp heeft een JavaScript runtime nodig voor YouTube-extractie.
  `ypl` detecteert `deno`, `node` of `bun` en geeft die door via `--js-runtimes`. Zie de
  [EJS wiki](https://github.com/yt-dlp/yt-dlp/wiki/EJS).
- **Grote playlists** — een channel met honderden video's in `++` loopt snel in de
  honderden GB's. Begin met `-p` en `-i`.
