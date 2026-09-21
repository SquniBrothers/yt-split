# ydm

Download YouTube-**audio** als mp3, met tags en de thumbnail als album art.

Waar [`split.ps1`](README.md) video's knipt en [`ypl.ps1`](ypl.md) een playlist als video's
ophaalt, levert `ydm.ps1` muziek: één video wordt één nummer, een playlist of channel wordt
een album, en een lange video met chapters knip je met `-s` op in losse tracks — precies
zoals YouTube de chapters onder de tijdbalk toont.

```
Daft Punk - Around the World (Official Music Video)   ->  Daft Punk\Daft Punk - Around the World.mp3
Pink Floyd - The Wall (Full Album)   -s              ->  Pink Floyd\The_Wall\01 In the Flesh.mp3
                                                          Pink Floyd\The_Wall\02 The Thin Ice.mp3
```

## Voorbeelden

```powershell
# Eén nummer, 192 kbit/s, album art uit de thumbnail
ydm "https://www.youtube.com/watch?v=..."

# Lange video (album, mix, dj-set) opknippen in de chapters, 320 kbit/s
ydm "https://www.youtube.com/watch?v=..." -s -q 320

# Eerst kijken wat het wordt (geen download)
ydm "https://www.youtube.com/watch?v=..." -s -p

# Hele playlist als album, met vierkante album art
ydm "https://www.youtube.com/playlist?list=PL..." -c

# Alleen nummer 1 t/m 10 uit een playlist
ydm "https://www.youtube.com/playlist?list=PL..." -i "1-10"

# Luisterboek: naar ~\Audiobooks, automatisch per hoofdstuk
ydm "https://www.youtube.com/watch?v=..." -ab

# Podcast: naar ~\Podcasts, datum voor de bestandsnaam
ydm "https://www.youtube.com/@DeShow/videos" -pc

# Artiest en album zelf bepalen
ydm "https://www.youtube.com/watch?v=..." -s -Artist "Various Artists" -Album "Zomer 2026"

# Batch: een lijst met secties (# Music / # Podcasts / # Audiobooks) en
# opties achter losse URLs
ydm -f "lijst.txt"
```

## Voorbeeld-run

```
=== Metadata ophalen ===
[x] Metadata opgehaald

Pink Floyd - The Wall (Full Album)
SomeUploader

=== Downloaden ===
Map: C:\Users\User\music\Pink_Floyd\The_Wall

=== Splitsen ===
[1/26] 01 In the Flesh.mp3
[2/26] 02 The Thin Ice.mp3
[3/26] 03 Another Brick in the Wall, Pt. 1.mp3
...

=== Gereed! ===
Output: C:\Users\User\music\Pink_Floyd\The_Wall
26 omgezet, 0 overgeslagen, 0 mislukt
```

## Inhoud

- [Vereisten](#vereisten)
- [Alias instellen](#alias-instellen)
- [Parameters](#parameters)
- [Wat wordt wat](#wat-wordt-wat)
- [Presets: `-ab` en `-pc`](#presets--ab-en--pc)
- [Lange video's splitsen (`-s`)](#lange-videos-splitsen--s)
  - [Hoofdstukken bewaren en later splitsen](#hoofdstukken-bewaren-en-later-splitsen)
- [Album art](#album-art)
- [Tags](#tags)
- [Titels opschonen](#titels-opschonen)
- [Output structuur](#output-structuur)
- [Hervatten](#hervatten)
- [Batch (meerdere URL's)](#batch-meerdere-urls)
- [Kwaliteit](#kwaliteit)
- [Veelgemaakte fouten](#veelgemaakte-fouten)

## Vereisten

Zelfde als `split.ps1` (zie [README.md](README.md#vereisten)):

- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [ffmpeg](https://ffmpeg.org/) — doet het omzetten, knippen en taggen
- Een JavaScript runtime voor YouTube-extractie: [node](https://nodejs.org/), [deno](https://deno.com/) of bun (wordt automatisch gedetecteerd)

## Alias instellen

Net als `ys` en `ypl`. Open je profiel met `notepad $PROFILE` en voeg toe:

```powershell
function ytmusic {
    & "C:\Users\User\scripts\ydm.ps1" @args
}
Set-Alias ydm ytmusic
```

> Een directe `Set-Alias ydm "...\ydm.ps1"` werkt niet met argumenten — vandaar het
> wrapper-functietje dat `@args` doorgeeft. Herstart de terminal of run `. $PROFILE`.

## Parameters

| Parameter | Alias | Type | Default | Beschrijving |
|---|---|---|---|---|
| `-Url` | `-u` | string | — | URL van video, playlist of channel (mag ook positioneel: `ydm "https://..."`) |
| `-BatchFile` | `-f` | string | — | Tekstbestand met 1 URL per regel, met [secties en opties per regel](#batch-meerdere-urls) |
| `-BaseDir` | `-b` | string | `$HOME\music` | Basis directory voor de output |
| `-OutputDir` | `-o` | string | zie [output](#output-structuur) | Eigen output directory (genegeerd in batch-modus) |
| `-Items` | `-i` | string | — | Selectie uit een playlist, yt-dlp syntax: `"1-5"`, `"3,7,9"`, `"5-"`, `":10"` |
| `-Quality` | `-q` | string | `+` | Bitrate: `++`/`320`, `256`, `+`/`192`, `-`/`128`, `--`/`96` |
| `-Format` | `-x` | string | `mp3` | `mp3` of `m4a` |
| `-Split` | `-s` | switch | — | Lange video opknippen in de chapters |
| `-ChapterFile` | `-ch` | string | — | Hoofdstukken uit een JSON-bestand, zie [hieronder](#hoofdstukken-bewaren-en-later-splitsen) |
| `-Audiobook` | `-ab` | switch | — | Luisterboek-preset, zie [presets](#presets--ab-en--pc) |
| `-Podcast` | `-pc` | switch | — | Podcast-preset, zie [presets](#presets--ab-en--pc) |
| `-NoArt` | `-a` | switch | — | Geen album art insluiten |
| `-Crop` | `-c` | switch | — | Album art vierkant bijsnijden |
| `-NoIndex` | `-n` | switch | — | Geen `01 ` volgnummer voor de bestandsnaam |
| `-KeepText` | `-k` | switch | — | Titels **niet** opschonen |
| `-Reverse` | `-r` | switch | — | Playlist in omgekeerde volgorde downloaden |
| `-PrintOnly` | `-p` | switch | — | Toon de geplande bestanden en tags en stop (geen download) |
| `-Artist` | — | string | — | Artiest-tag forceren |
| `-Album` | — | string | — | Album-tag forceren |
| `-KeepFull` | — | switch | — | Bij `-s` ook het complete bestand bewaren |
| `-LogFile` | `-l` | string | — | Pad voor logbestand (via `Start-Transcript`) |
| `-Help` | `-h` | switch | — | Help bericht |

## Wat wordt wat

`ydm` kijkt naar de URL en kiest zelf de modus:

| URL | Modus | Resultaat |
|---|---|---|
| `watch?v=...` (zonder `list=`) | losse track | één bestand in `<artiest>\` |
| `watch?v=...` **met** `-s` | album uit chapters | `<artiest>\<album>\01 ...mp3` |
| `playlist?list=...` | album | `<kanaal>\<playlist>\01 ...mp3` |
| `@kanaal/videos` | album | `<kanaal>\<tab>\01 ...mp3` |

`-s` geldt alleen voor losse video's; bij een playlist wordt het genegeerd (met een
waarschuwing). Wil je een lijst lange video's elk apart laten splitsen, zet die dan in een
batch-bestand: elke regel is dan een losse video.

## Presets: `-ab` en `-pc`

Muziek is de standaard. Voor de twee andere dingen die je van YouTube plukt zijn er
presets, die alleen de standaardmap en een paar defaults omzetten — alle andere opties
blijven gewoon werken.

| | `-Audiobook` (`-ab`) | `-Podcast` (`-pc`) |
|---|---|---|
| Map | `$HOME\Audiobooks` | `$HOME\Podcasts` |
| Structuur | `<kanaal>\<videotitel>\01 Chapter 1.mp3` | `<show>\2026-09-18 Aflevering 12.mp3` |
| `-s` | automatisch aan | uit (podcast-chapters zijn meestal reclame) |
| `genre`-tag | `Audiobook` | `Podcast` |
| `album`-tag | de boektitel | de show (het kanaal) |
| `artist`-tag | de auteur uit `"Auteur - Titel"`, anders het kanaal | altijd het kanaal |

```powershell
ydm "https://www.youtube.com/watch?v=..." -ab      # -> C:\Users\User\Audiobooks\Ancient_Recitations\The_Prince\01 Chapter 1.mp3
ydm "https://www.youtube.com/@DeShow/videos" -pc   # -> C:\Users\User\Podcasts\De_Show\...
```

Elk luisterboek krijgt zijn eigen map onder het kanaal, met de volledige videotitel —
ook als het maar één bestand is. Zo staat elk boek apart en zie je aan het pad waar het
vandaan komt. De artiest uit `"Auteur - Titel"` blijft wel in de tags staan; alleen het
pad volgt het kanaal.

Twee details die het verschil maken:

- **Bij een podcast wordt de titel niet uit elkaar getrokken.** Zonder `-pc` leest `ydm`
  `Aflevering 12 - Over van alles` als artiest + nummer, en krijg je `Aflevering 12` als
  artiest. Met `-pc` blijft de titel heel en is het kanaal de artiest én het album.
- **Afleveringen krijgen de uploaddatum vooraan**, zodat ze chronologisch sorteren in
  plaats van alfabetisch. Bij een playlist blijft het gewone volgnummer staan.

`-ab` en `-pc` gaan niet samen. Een eigen `-b` of `-o` gaat altijd voor de preset-map, en
`-Artist` / `-Album` overrulen de tags:

```powershell
ydm "https://www.youtube.com/watch?v=..." -ab -b "D:\luisterboeken"
ydm "https://www.youtube.com/watch?v=..." -ab -Artist "Frank Herbert" -Album "Dune Messiah"
```

## Lange video's splitsen (`-s`)

Met `-s` wordt de audio één keer gedownload en daarna per chapter weggeschreven — dus één
download, geen 26 losse. De chapters komen uit twee bronnen, in deze volgorde:

1. **De chapters van YouTube zelf** (dezelfde die je onder de tijdbalk ziet).
2. **De watch-pagina**, als yt-dlp er geen meekreeg. Dat gebeurt regelmatig zodra je veel
   achter elkaar downloadt: YouTube geeft dan een uitgeklede player-response terug zonder
   de markers. De pagina zelf heeft ze meestal nog wel, al is ook die wisselvallig —
   dezelfde URL levert de ene keer wel en de andere keer niets, dus `ydm` probeert het
   een paar keer.
3. **De tracklist uit de beschrijving**. Regels als `0:00 Intro`, `1. 02:30 - Titel`,
   `[1:05:00] Titel` en `Titel 2:30` worden herkend; er zijn minstens twee tijden nodig.
   Handig bij album-uploads waar de tijden niet op `0:00` beginnen, want dan maakt YouTube
   zelf geen chapters.

Zonder chapters valt `ydm` terug op één bestand, met een waarschuwing. Andersom: heeft een
video chapters maar gebruik je `-s` niet, dan zegt `ydm` dat erbij:

```
[i] Deze video heeft 26 chapters. Gebruik -s om er losse tracks van te maken.
```

De knip gaat op de chapter-grens zoals YouTube die opgeeft; er wordt één keer geëncodeerd,
dus je verliest geen extra kwaliteit ten opzichte van een gewone download. Wil je náást de
losse tracks ook het complete bestand houden: `-KeepFull`.

Chapternummers die de tracklist zelf al heeft (`01. Sunrise`) verdwijnen — het volgnummer
komt er zero-padded weer voor: `01 Sunrise.mp3`.

### Hoofdstukken bewaren en later splitsen

De gebruikte hoofdstukken worden altijd als `chapters.json` naast de tracks weggeschreven.
Dat is je vangnet: YouTube geeft ze niet altijd, dus zodra je ze één keer binnen hebt kun
je er altijd op terugvallen.

```powershell
ydm "https://www.youtube.com/watch?v=..." -ab -ch "chapters.json"
```

`-ChapterFile` (`-ch`) slikt zowel een kale lijst als de complete uitvoer van
`yt-dlp --dump-json`:

```json
[ { "start_time": 0,   "end_time": 137, "title": "Introduction" },
  { "start_time": 137, "end_time": 228, "title": "Sayings of Persian monarchs" } ]
```

Een meegegeven bestand gaat voor alle andere bronnen. Ontbreekt `end_time`, dan loopt het
laatste hoofdstuk door tot het eind van de video.

Staat het **complete bestand** al in de doelmap — van `-KeepFull`, of van een eerdere run
die geen chapters kon vinden — dan knipt `ydm` daaruit in plaats van opnieuw te
downloaden. Dat gaat met `-c copy`, dus zonder tweede encodeerslag en met behoud van de
album art:

```
Bron: The Sayings of Kings and Commanders.mp3 (al aanwezig, niet opnieuw gedownload)
```

Zo kun je eerst binnenhalen en later pas splitsen, en uitproberen welke indeling je
bevalt.

## Album art

De thumbnail wordt opgehaald, naar JPG omgezet en als album art in het bestand gezet
(ID3v2.3 `APIC` voor mp3, `covr` voor m4a). Dat is standaard aan.

- `-c` snijdt er een vierkant uit het midden van — YouTube-thumbnails zijn 16:9, en de
  meeste spelers verwachten een vierkante cover.
- `-a` slaat de art helemaal over.

Bij `-s` krijgt elke track dezelfde art: het is één album.

## Tags

| Tag | Komt uit |
|---|---|
| `title` | het nummer (`track` uit YouTube Music, anders de opgeschoonde titel of de chaptertitel) |
| `artist` | `artist` uit YouTube Music → de artiest uit `"Artiest - Nummer"` → het kanaal |
| `album_artist` | de artiest van de hele video/playlist |
| `album` | `-Album` → de playlisttitel → de videotitel (bij `-s`) → `album` uit YouTube Music |
| `track` | volgnummer/totaal, bijvoorbeeld `3/12` |
| `date` | `release_year`, anders het jaar uit de uploaddatum |
| `genre` | alleen met een preset: `Audiobook` of `Podcast` |
| `comment` | de video-URL, zodat je altijd terug kunt vinden waar het vandaan komt |

Noemen de chapters zelf een artiest (`Miles Davis - So What`), dan krijgt elke track zijn
eigen `artist` en blijft `album_artist` het kanaal. Noemt alleen de videotitel een artiest
(`Pink Floyd - The Wall`), dan wordt dát de artiest en is `The Wall` het album.

`-Artist` en `-Album` overrulen alles.

## Titels opschonen

Standaard gaat de ruis uit de titel:

| Titel op YouTube | Bestand |
|---|---|
| `Daft Punk - Around the World (Official Music Video)` | `Daft Punk - Around the World.mp3` |
| `Song [HD]` / `Song \| Official Video` | `Song.mp3` |
| `Pink Floyd - The Wall (Full Album)` (met `-s`) | album `The Wall` |

Bij een playlist wordt bovendien de tekst gestript die in **élke** titel terugkomt, precies
zoals [`ypl`](ypl.md#herhaalde-tekst-strippen) dat doet — inclusief een nummer vooraan dat
de playlist-index herhaalt.

Haakjes die geen ruis zijn blijven staan (`Song (Live at Paradiso)`), en `AC/DC` overleeft
het ook. Klopt er toch iets niet: `-k` houdt de originele titels, `-p` laat vooraf zien wat
het wordt.

## Output structuur

```
$HOME\music\Daft_Punk\Daft Punk - Around the World.mp3          # losse track
$HOME\music\Pink_Floyd\The_Wall\01 In the Flesh.mp3             # -s
$HOME\music\Lofi_Girl\Beats_To_Study_To\01 Sunrise.mp3          # playlist
$HOME\music\Lofi_Girl\Beats_To_Study_To\album.json
$HOME\Audiobooks\Ancient_Recitations\The_Prince\01 Chapter 1.mp3  # -ab
$HOME\Podcasts\De_Show\2026-09-18 Aflevering 12.mp3             # -pc
```

- Mapnamen krijgen underscores (zoals in `split.ps1` en `ypl.ps1`), bestandsnamen houden
  hun spaties.
- `album.json` bewaart de URL, de gestripte kop/staart en alle entries — handig om
  achteraf te zien waar een bestandsnaam vandaan komt.
- Met `-o` kies je zelf een map; er wordt dan geen `<artiest>\<album>` aangemaakt.
- Het downloaden gebeurt in `%TEMP%\ydm\<video-id>`; die map wordt daarna opgeruimd.

## Hervatten

Bestaat een bestand al, dan wordt het overgeslagen — ook per chapter. Een afgebroken run
pak je dus op door hetzelfde commando opnieuw te draaien:

```
[4/10] 04 Total Station Setup.mp3 - bestaat al, overgeslagen
```

Staat bij `-s` álles er al, dan wordt er niets gedownload:

```
Alles bestaat al in C:\Users\User\music\Pink_Floyd\The_Wall - niets te doen
```

## Batch (meerdere URL's)

Een lijst met één URL per regel; lege regels en `#`-regels worden overgeslagen.

```
# lijst.txt
https://www.youtube.com/watch?v=...
https://www.youtube.com/playlist?list=PL...
```

```powershell
ydm -f "lijst.txt" -q 320
```

Per regel wordt opnieuw bepaald of het een losse video of een playlist is, dus `-s` werkt
gewoon voor de video's in de lijst. Een URL die mislukt stopt de rest niet; aan het eind
volgt een telling.

### Secties

Een kopregel zet de modus voor alles eronder, zodat muziek, podcasts en luisterboeken in
één bestand kunnen:

```
# Podcasts
https://www.youtube.com/@DeShow/videos
https://www.youtube.com/watch?v=...

# Music
https://www.youtube.com/playlist?list=PL...
https://www.youtube.com/watch?v=...

# Audiobooks
https://www.youtube.com/watch?v=...
```

Herkend worden `# Music` (ook `Muziek`, `Songs`, `Albums`), `# Podcasts` (`Shows`,
`Afleveringen`) en `# Audiobooks` (`Luisterboeken`, `Hoorboeken`, `Boeken`) — enkelvoud of
meervoud, hoofdletters maken niet uit. Een `#`-regel die géén sectienaam is blijft gewoon
commentaar, dus bestaande lijsten blijven werken zoals ze waren. Zonder sectie is het
muziek, of wat je op de commandline meegaf.

### Opties per regel

Achter een URL mag je dezelfde opties zetten als op de commandline. Die gelden alleen voor
die regel en gaan vóór de sectie:

```
# Podcasts
https://www.youtube.com/watch?v=...                 # gewone aflevering
https://www.youtube.com/watch?v=... -s              # deze wél in hoofdstukken

# Music
https://www.youtube.com/watch?v=... -s -q 320       # album opknippen, hoge bitrate
https://www.youtube.com/watch?v=... -c -x m4a       # vierkante art, als m4a
https://www.youtube.com/watch?v=... -ab             # tóch een luisterboek
https://www.youtube.com/watch?v=... -Artist "Nina Simone" -Album "Live"
https://www.youtube.com/playlist?list=PL... -i "1-10" -o "D:\ergens anders"
```

| Optie | Betekenis |
|---|---|
| `-s` / `-split` | splitsen op chapters |
| `-ab` / `-audiobook` | luisterboek (ook binnen een andere sectie) |
| `-pc` / `-podcast` | podcast |
| `-m` / `-music` | terug naar muziek, ongeacht de sectie |
| `-q <waarde>`, `-x <mp3\|m4a>`, `-i <selectie>` | zoals op de commandline |
| `-c`, `-a`, `-n`, `-k`, `-r`, `-keepfull` | de schakelaars |
| `-b <map>`, `-o <map>` | eigen map; `-b` gaat vóór de preset-map |
| `-Artist "..."`, `-Album "..."` | tags forceren (quotes voor spaties) |

Quotes mogen enkel of dubbel: `-s` en `'-s'` en `"-s"` zijn hetzelfde.

Alles na een spatie en een `#` is commentaar — een `#` in de URL zelf heeft geen spatie
ervoor en blijft dus staan. Een optie die niet klopt wordt met regelnummer gemeld en
overgeslagen, de rest draait gewoon door:

```
[WARN] regel 19: onbekende optie '-zzz' genegeerd
[WARN] regel 19: 'flac' is geen geldig formaat, genegeerd
```

Elke URL krijgt zijn eigen map, dus de globale `-o` geldt niet voor een hele lijst; zet er
per regel een `-o` achter als je dat wil.

## Kwaliteit

| Flag | Alias | Bitrate |
|---|---|---|
| `++` | `320` | 320 kbit/s |
| — | `256` | 256 kbit/s |
| `+` | `192` | 192 kbit/s (default) |
| `-` | `128` | 128 kbit/s |
| `--` | `96` | 96 kbit/s |

> **PowerShell leest `-q "-"` en `-q "--"` als parameternaam**, ook tussen quotes. Gebruik
> daarom `-q 128` / `-q 96`, of schrijf het met een dubbele punt: `-q:"--"`.

YouTube levert Opus of AAC; dat wordt één keer naar mp3 (of m4a) omgezet. Boven de
192 kbit/s wint je daar weinig mee — de bron is al lossy — maar `-q 320` kan als je het
bestand later nog wil bewerken.

## Veelgemaakte fouten

- **`-s` doet niets** — de video heeft geen chapters en ook geen tracklist met minstens
  twee tijden in de beschrijving. Check met `-p`.
- **Verkeerde artiest** — bij een upload zonder YouTube Music-metadata raadt `ydm` de
  artiest uit de titel of het kanaal. `-Artist "..."` zet hem goed.
- **Album art staat verkeerd om in de speler** — gebruik `-c`; sommige spelers rekken een
  16:9 cover uit.
- **`-s` bij een playlist** — dat wordt genegeerd. Zet de video's in een batch-bestand.
- **Geen JS runtime** — yt-dlp heeft een JavaScript runtime nodig voor YouTube-extractie.
  `ydm` detecteert `deno`, `node` of `bun` en geeft die door via `--js-runtimes`. Zie de
  [EJS wiki](https://github.com/yt-dlp/yt-dlp/wiki/EJS).
