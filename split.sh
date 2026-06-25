#!/usr/bin/env bash
# ============================================
# split.sh - Download en split YouTube video's op basis van chapters
# Linux/macOS port van split.ps1
# Vereist: yt-dlp, ffmpeg, ffprobe, jq (+ een JS runtime: deno/node/bun)
# ============================================

set -euo pipefail

# ============================================
# Defaults
# ============================================
URL=""
BATCH_FILE=""
BASE_DIR="${HOME}/videos"
OUTPUT_DIR=""
SELECT_CHAPTERS=0
THUMBNAILS=0
ACCURATE_CUT=0
KEEP_DOWNLOADS=0
LOG_FILE=""
PRINT_CHAPTERS=0
DOWNLOAD_ONLY=0
QUALITY="+"

# ============================================
# Kleuren (alleen bij een terminal)
# ============================================
if [ -t 1 ]; then
    C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
    C_RED=$'\033[31m'; C_GRAY=$'\033[90m'; C_MAGENTA=$'\033[35m'; C_RESET=$'\033[0m'
else
    C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_GRAY=""; C_MAGENTA=""; C_RESET=""
fi

usage() {
cat <<'EOF'
split.sh - Download en split YouTube video's op basis van chapters

GEBRUIK:
    ./split.sh -u <URL> [OPTIES]
    ./split.sh -f <bestand.txt> [OPTIES]

PARAMETERS:
    -u, --url <URL>         URL van de YouTube video (of gebruik -f)
    -f, --batch-file <FILE> Tekstbestand met 1 URL per regel (lege regels en regels die met # beginnen worden genegeerd)
    -b, --base-dir <DIR>    Basis directory (default: $HOME/videos)
    -o, --output-dir <DIR>  Eigen output directory (genegeerd in batch-modus)
    -s, --select            Toon chapters, selecteer interactief (V/n)
    -t, --thumbnails        Genereer JPG thumbnails per chapter
    -a, --accurate          Frame-accurate cuts (re-encode, langzamer)
    -k, --keep              Bewaar downloads directory na splitsen
    -l, --log <FILE>        Pad voor logbestand
    -p, --print-chapters    Toon chapter lijst en stop
    -d, --download-only     Alleen downloaden (niet splitsen)
    -q, --quality <Q>       Kwaliteit: ++ (4K), + (1080p), - (720p), -- (480p)
    -h, --help              Dit help bericht

VOORBEELDEN:
    ./split.sh -u "https://youtube.com/watch?v=..."
    ./split.sh -u "..." -s -t
    ./split.sh -u "..." -d -q "++"
    ./split.sh -u "..." -p
    ./split.sh -f "urls.txt" -t
EOF
}

# ============================================
# Argument parsing
# ============================================
while [ $# -gt 0 ]; do
    case "$1" in
        -u|--url)            URL="${2:-}"; shift 2 ;;
        -f|--batch-file)     BATCH_FILE="${2:-}"; shift 2 ;;
        -b|--base-dir)       BASE_DIR="${2:-}"; shift 2 ;;
        -o|--output-dir)     OUTPUT_DIR="${2:-}"; shift 2 ;;
        -s|--select)         SELECT_CHAPTERS=1; shift ;;
        -t|--thumbnails)     THUMBNAILS=1; shift ;;
        -a|--accurate)       ACCURATE_CUT=1; shift ;;
        -k|--keep)           KEEP_DOWNLOADS=1; shift ;;
        -l|--log)            LOG_FILE="${2:-}"; shift 2 ;;
        -p|--print-chapters) PRINT_CHAPTERS=1; shift ;;
        -d|--download-only)  DOWNLOAD_ONLY=1; shift ;;
        -q|--quality)        QUALITY="${2:-}"; shift 2 ;;
        -h|--help)           usage; exit 0 ;;
        *) echo "${C_RED}[ERROR] Onbekende optie: $1${C_RESET}" >&2; usage; exit 1 ;;
    esac
done

# ============================================
# Logging (tee stdout+stderr naar logbestand)
# ============================================
if [ -n "$LOG_FILE" ]; then
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

# ============================================
# Vereisten check
# ============================================
missing=()
for cmd in yt-dlp ffmpeg ffprobe jq; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "${C_RED}[ERROR] Ontbrekende programma's: ${missing[*]}${C_RESET}" >&2
    echo "${C_YELLOW}Installeer ze voordat je dit script runt.${C_RESET}" >&2
    exit 1
fi

# ============================================
# JavaScript runtime detectie
# YouTube extractie vereist nu een JS runtime (deno/node/bun).
# ============================================
JS_RUNTIME=""
for rt in deno node bun; do
    if command -v "$rt" >/dev/null 2>&1; then JS_RUNTIME="$rt"; break; fi
done
JS_ARGS=()
if [ -n "$JS_RUNTIME" ]; then
    JS_ARGS=(--js-runtimes "$JS_RUNTIME")
else
    echo "${C_YELLOW}[WARN] Geen JavaScript runtime (deno/node/bun) gevonden.${C_RESET}" >&2
    echo "${C_YELLOW}       YouTube kan formats missen. Installeer node of deno:${C_RESET}" >&2
    echo "${C_YELLOW}       https://github.com/yt-dlp/yt-dlp/wiki/EJS${C_RESET}" >&2
fi

# ============================================
# Quality mapping
# ============================================
case "$QUALITY" in
    '++') QFMT="bestvideo[height<=2160]+bestaudio/best[height<=2160]" ;;
    '+')  QFMT="bestvideo[height<=1080]+bestaudio/best[height<=1080]" ;;
    '-')  QFMT="bestvideo[height<=720]+bestaudio/best[height<=720]" ;;
    '--') QFMT="bestvideo[height<=480]+bestaudio/best[height<=480]" ;;
    *) echo "${C_RED}[ERROR] Ongeldige -q waarde: '$QUALITY' (gebruik ++, +, - of --)${C_RESET}" >&2; exit 1 ;;
esac

# ============================================
# Helper functies
# ============================================
# Maak een veilige bestandsnaam (mirror van Get-SafeFileName)
safe_filename() {
    local n="$1"
    n="${n// - / }"                                   # ' - ' -> ' '
    n="$(printf '%s' "$n" | tr ' \t\n\r\\/:*?"<>|' '_')"  # ongewenste tekens -> _
    n="$(printf '%s' "$n" | tr -s '_')"               # squeeze herhaalde _
    n="$(printf '%s' "$n" | sed -E 's#^_+##; s#_+$##')" # strip rand-_
    printf '%s' "$n"
}

# Sanitize titel/kanaal (zonder de ' - ' collapse)
sanitize() {
    local n="$1"
    n="$(printf '%s' "$n" | tr ' \t\n\r\\/:*?"<>|' '_')"
    n="$(printf '%s' "$n" | tr -s '_')"
    n="$(printf '%s' "$n" | sed -E 's#^_+##; s#_+$##')"
    printf '%s' "$n"
}

# float arithmetic helpers
fsub() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.3f", a-b}'; }
favg() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.3f", (a+b)/2}'; }
fgt0() { awk -v d="$1" 'BEGIN{exit !(d>0)}'; }  # exit 0 als d>0

# ============================================
# Eén video verwerken (download + split + thumbnails)
#   $1 = URL,  $2 = output-dir override (leeg = standaard pad)
# ============================================
process_video() {
    local url="$1"
    local out_override="${2:-}"

    echo ""
    echo "${C_CYAN}=== Metadata ophalen ===${C_RESET}"

    local META
    META="$(yt-dlp ${JS_ARGS[@]+"${JS_ARGS[@]}"} --dump-json "$url" || true)"
    if [ -z "$META" ]; then
        echo "${C_RED}[ERROR] Kon metadata niet ophalen${C_RESET}" >&2
        return 1
    fi

    local TITLE CHANNEL VIDEO_TITLE CHANNEL_NAME CH_COUNT OUT_DIR
    TITLE="$(printf '%s' "$META" | jq -r '.title // empty')"
    CHANNEL="$(printf '%s' "$META" | jq -r '.channel // empty')"
    VIDEO_TITLE="$(sanitize "$TITLE")"
    CHANNEL_NAME="$(sanitize "$CHANNEL")"

    echo "${C_GREEN}[x] Metadata opgehaald${C_RESET}"
    echo ""
    echo "$TITLE"
    echo ""
    echo "$CHANNEL"
    echo ""

    CH_COUNT="$(printf '%s' "$META" | jq -r 'if .chapters then (.chapters | length) else 0 end')"

    # --- Print Chapters ---
    if [ "$PRINT_CHAPTERS" -eq 1 ]; then
        if [ "$CH_COUNT" -eq 0 ]; then
            echo "${C_YELLOW}Geen chapters gevonden${C_RESET}"
        else
            echo "${C_GREEN}=== Chapters ===${C_RESET}"
            printf '%s\t%s\t%s\n' "start_time" "end_time" "title"
            printf '%s' "$META" | jq -r '.chapters[] | "\(.start_time)\t\(.end_time)\t\(.title)"'
        fi
        return 0
    fi

    # --- Output directory ---
    if [ -n "$out_override" ]; then
        OUT_DIR="$out_override"
    else
        OUT_DIR="$BASE_DIR/$CHANNEL_NAME/$VIDEO_TITLE"
    fi
    mkdir -p "$OUT_DIR"

    printf '%s' "$META" | jq '.' > "$OUT_DIR/meta.json"
    echo "${C_GREEN}[x] Metadata opgeslagen${C_RESET}"
    echo ""

    # Chapters in bash-arrays (alleen wanneer aanwezig)
    local -a CH_START=() CH_END=() CH_TITLE=()
    if [ "$CH_COUNT" -gt 0 ]; then
        mapfile -t CH_START < <(printf '%s' "$META" | jq -r '.chapters[].start_time')
        mapfile -t CH_END   < <(printf '%s' "$META" | jq -r '.chapters[].end_time')
        mapfile -t CH_TITLE < <(printf '%s' "$META" | jq -r '.chapters[].title')
    fi

    local i j start end title dur safe file out mid thumb
    local WORK_DIR VIDEO_FILE SQF hpat
    local -a SEL_IDX DL_PATH DL_J DL_IDX

    # ============================================
    # Select Chapters flow — download-sections per chapter
    # ============================================
    if [ "$SELECT_CHAPTERS" -eq 1 ]; then
        if [ "$CH_COUNT" -eq 0 ]; then
            echo "${C_YELLOW}Geen chapters gevonden${C_RESET}"
            return 0
        fi

        echo "${C_GREEN}=== Chapters ===${C_RESET}"
        echo ""
        for ((j=0; j<CH_COUNT; j++)); do
            printf '%s\t%s\t%s\n' "${CH_START[$j]}" "${CH_END[$j]}" "${CH_TITLE[$j]}"
        done

        echo ""
        echo "${C_CYAN}=== Chapters selecteren ===${C_RESET}"
        echo "${C_YELLOW}  Typ 'V' voor elke chapter die je wilt downloaden${C_RESET}"

        SEL_IDX=()
        for ((j=0; j<CH_COUNT; j++)); do
            read -r -p "[$((j+1))] ${CH_TITLE[$j]} [V/]: " resp || resp=""
            if [ "$resp" = "V" ] || [ "$resp" = "v" ]; then
                SEL_IDX+=("$j")
            fi
        done

        if [ ${#SEL_IDX[@]} -eq 0 ]; then
            echo "${C_YELLOW}  Geen chapters geselecteerd${C_RESET}"
            return 0
        fi
        echo "${C_GREEN}  -> ${#SEL_IDX[@]} chapter(s) geselecteerd${C_RESET}"

        echo ""
        echo "${C_CYAN}=== Chapters downloaden ===${C_RESET}"

        # Section-quality (progressive) afgeleid van QFMT
        hpat='\[height<=([0-9]+)\]'
        if [[ "$QFMT" =~ $hpat ]]; then
            SQF="best[height<=${BASH_REMATCH[1]}]"
        else
            SQF="$QFMT"
        fi

        DL_PATH=(); DL_J=(); DL_IDX=()
        i=1
        local total=${#SEL_IDX[@]}
        for j in "${SEL_IDX[@]}"; do
            start="${CH_START[$j]}"; end="${CH_END[$j]}"; title="${CH_TITLE[$j]}"
            dur="$(fsub "$end" "$start")"
            fgt0 "$dur" || continue

            safe="$(safe_filename "$title")"
            file="$(printf '%02d_%s.mp4' "$i" "$safe")"
            out="$OUT_DIR/$file"

            echo "${C_YELLOW}[$i/$total] $file${C_RESET}"

            if yt-dlp \
                --download-sections "*${start}-${end}" \
                --force-keyframes-at-cuts \
                -f "$SQF" \
                --force-ipv4 \
                --retries infinite \
                --fragment-retries infinite \
                --socket-timeout 30 \
                ${JS_ARGS[@]+"${JS_ARGS[@]}"} \
                --no-part \
                -o "$out" \
                "$url"; then
                DL_PATH+=("$out"); DL_J+=("$j"); DL_IDX+=("$i")
                i=$((i+1))
            else
                echo "${C_RED}  [ERROR] Download gefaald voor: $file${C_RESET}" >&2
            fi
        done

        # Thumbnails (select flow)
        if [ "$THUMBNAILS" -eq 1 ] && [ ${#DL_PATH[@]} -gt 0 ]; then
            echo ""
            echo "${C_CYAN}=== Thumbnails genereren ===${C_RESET}"
            local n path idx
            for ((n=0; n<${#DL_PATH[@]}; n++)); do
                j="${DL_J[$n]}"; idx="${DL_IDX[$n]}"; path="${DL_PATH[$n]}"
                start="${CH_START[$j]}"; end="${CH_END[$j]}"; title="${CH_TITLE[$j]}"
                dur="$(fsub "$end" "$start")"
                fgt0 "$dur" || continue
                mid="$(awk -v d="$dur" 'BEGIN{printf "%.3f", d/2}')"
                safe="$(safe_filename "$title")"
                thumb="$(printf '%02d_%s.jpg' "$idx" "$safe")"
                echo "${C_GRAY}  -> $thumb${C_RESET}"
                ffmpeg -y -ss "$mid" -i "$path" -vframes 1 -q:v 2 "$OUT_DIR/$thumb" -hide_banner -loglevel error -nostats || true
            done
        fi

        echo ""
        echo "${C_GREEN}=== Gereed! ===${C_RESET}"
        echo "Output: $OUT_DIR"
        return 0
    fi

    # ============================================
    # Non-select flow: download hele video
    # ============================================
    WORK_DIR="$BASE_DIR/downloads/$CHANNEL_NAME/$VIDEO_TITLE"
    mkdir -p "$WORK_DIR"

    if [ "$DOWNLOAD_ONLY" -eq 1 ]; then
        VIDEO_FILE="$OUT_DIR/$VIDEO_TITLE.mp4"
    else
        VIDEO_FILE="$WORK_DIR/video.mp4"
    fi

    if [ -f "$VIDEO_FILE" ]; then
        echo "${C_YELLOW}Video bestaat al, download wordt overgeslagen${C_RESET}"
    else
        echo ""
        echo "${C_CYAN}=== Video downloaden ===${C_RESET}"
        if ! yt-dlp \
            -f "$QFMT" \
            --merge-output-format mp4 \
            --force-ipv4 \
            --retries infinite \
            --fragment-retries infinite \
            --socket-timeout 30 \
            ${JS_ARGS[@]+"${JS_ARGS[@]}"} \
            --no-part \
            -o "$VIDEO_FILE" \
            "$url"; then
            echo "${C_RED}[ERROR] yt-dlp download gefaald${C_RESET}" >&2
            return 1
        fi
        echo "${C_GREEN}[x] Video gedownload${C_RESET}"
    fi

    # --- Download Only: klaar ---
    if [ "$DOWNLOAD_ONLY" -eq 1 ]; then
        echo ""
        echo "${C_GREEN}=== Gereed! ===${C_RESET}"
        echo "Output: $VIDEO_FILE"
        return 0
    fi

    # ============================================
    # Chapters verwerken
    # ============================================
    echo ""
    echo "${C_CYAN}=== Chapters verwerken ===${C_RESET}"

    if [ "$CH_COUNT" -eq 0 ]; then
        echo "${C_YELLOW}Geen chapters gevonden${C_RESET}"
        return 0
    fi

    echo ""
    echo "${C_GREEN}=== Chapter Index ===${C_RESET}"
    for ((j=0; j<CH_COUNT; j++)); do
        printf '%s\t%s\t%s\n' "${CH_START[$j]}" "${CH_END[$j]}" "${CH_TITLE[$j]}"
    done

    # --- Split ---
    echo ""
    echo "${C_CYAN}=== Video splitsen ===${C_RESET}"
    i=1
    for ((j=0; j<CH_COUNT; j++)); do
        start="${CH_START[$j]}"; end="${CH_END[$j]}"; title="${CH_TITLE[$j]}"
        dur="$(fsub "$end" "$start")"
        fgt0 "$dur" || continue

        safe="$(safe_filename "$title")"
        file="$(printf '%02d_%s.mp4' "$i" "$safe")"
        out="$OUT_DIR/$file"

        echo "${C_YELLOW}[$i/$CH_COUNT] $file${C_RESET}"

        if [ "$ACCURATE_CUT" -eq 1 ]; then
            ffmpeg -y -i "$VIDEO_FILE" -ss "$start" -t "$dur" \
                -c:v libx264 -preset fast -crf 22 -c:a aac -b:a 192k \
                "$out" -hide_banner -loglevel error -nostats \
                || echo "${C_RED}  [ERROR] ffmpeg gefaald voor: $file${C_RESET}" >&2
        else
            ffmpeg -y -ss "$start" -i "$VIDEO_FILE" -t "$dur" \
                -c copy "$out" -hide_banner -loglevel error -nostats \
                || echo "${C_RED}  [ERROR] ffmpeg gefaald voor: $file${C_RESET}" >&2
        fi

        i=$((i+1))
    done

    # --- Thumbnails ---
    if [ "$THUMBNAILS" -eq 1 ]; then
        echo ""
        echo "${C_CYAN}=== Thumbnails genereren ===${C_RESET}"
        i=1
        for ((j=0; j<CH_COUNT; j++)); do
            start="${CH_START[$j]}"; end="${CH_END[$j]}"; title="${CH_TITLE[$j]}"
            dur="$(fsub "$end" "$start")"
            fgt0 "$dur" || continue

            mid="$(favg "$start" "$end")"
            safe="$(safe_filename "$title")"
            thumb="$(printf '%02d_%s.jpg' "$i" "$safe")"
            echo "${C_GRAY}  -> $thumb${C_RESET}"
            ffmpeg -y -ss "$mid" -i "$VIDEO_FILE" -vframes 1 -q:v 2 "$OUT_DIR/$thumb" -hide_banner -loglevel error -nostats || true
            i=$((i+1))
        done
    fi

    # --- Cleanup ---
    if [ "$KEEP_DOWNLOADS" -eq 0 ]; then
        echo ""
        echo "${C_CYAN}=== Opruimen ===${C_RESET}"
        if [ -n "$CHANNEL_NAME" ] && [ -n "$VIDEO_TITLE" ] && [ -d "$WORK_DIR" ]; then
            rm -rf "$WORK_DIR"
            echo "${C_GREEN}[x] Downloads verwijderd${C_RESET}"
        fi
    fi

    echo ""
    echo "${C_GREEN}=== Gereed! ===${C_RESET}"
    echo "Output: $OUT_DIR"
    return 0
}

# ============================================
# URL-lijst opbouwen (enkele URL en/of batch-bestand)
# ============================================
URLS=()
if [ -n "$URL" ]; then URLS+=("$URL"); fi
if [ -n "$BATCH_FILE" ]; then
    if [ ! -f "$BATCH_FILE" ]; then
        echo "${C_RED}[ERROR] Batch-bestand niet gevonden: $BATCH_FILE${C_RESET}" >&2
        exit 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"                                   # strip CR (CRLF-bestanden)
        line="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
        [ -z "$line" ] && continue
        case "$line" in \#*) continue ;; esac
        URLS+=("$line")
    done < "$BATCH_FILE"
fi

if [ ${#URLS[@]} -eq 0 ]; then
    echo "${C_RED}[ERROR] Geen URL opgegeven. Gebruik -u <URL> of -f <bestand>.${C_RESET}" >&2
    usage
    exit 1
fi

if [ -n "$BATCH_FILE" ] && [ -n "$OUTPUT_DIR" ]; then
    echo "${C_YELLOW}[WARN] -o/--output-dir wordt genegeerd in batch-modus; elke video krijgt een eigen map onder -b.${C_RESET}" >&2
fi

# ============================================
# Main loop
# ============================================
FAILED=()
total_urls=${#URLS[@]}
idx=0

for url in "${URLS[@]}"; do
    idx=$((idx+1))

    if [ "$total_urls" -gt 1 ]; then
        echo ""
        echo "${C_MAGENTA}############################################${C_RESET}"
        echo "${C_MAGENTA}# [$idx/$total_urls] $url${C_RESET}"
        echo "${C_MAGENTA}############################################${C_RESET}"
    fi

    if [[ ! "$url" =~ ^https?:// ]]; then
        echo "${C_RED}[ERROR] Ongeldige URL overgeslagen: $url${C_RESET}" >&2
        FAILED+=("$url")
        continue
    fi

    # In batch-modus negeren we -o zodat video's elkaar niet overschrijven
    if [ "$total_urls" -gt 1 ]; then override=""; else override="$OUTPUT_DIR"; fi

    set +e
    process_video "$url" "$override"
    status=$?
    set -e
    if [ "$status" -ne 0 ]; then
        echo "${C_RED}[ERROR] Verwerken mislukt: $url${C_RESET}" >&2
        FAILED+=("$url")
    fi
done

if [ "$total_urls" -gt 1 ]; then
    echo ""
    ok=$((total_urls - ${#FAILED[@]}))
    echo "${C_GREEN}=== Batch klaar: $ok/$total_urls gelukt ===${C_RESET}"
    if [ ${#FAILED[@]} -gt 0 ]; then
        echo "${C_RED}Mislukt:${C_RESET}"
        for u in "${FAILED[@]}"; do echo "${C_RED}  - $u${C_RESET}"; done
    fi
fi

[ ${#FAILED[@]} -eq 0 ]
