#!/usr/bin/env bash
# Helpers around poppler for reading PDFs. See ../SKILL.md.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  pdf.sh info FILE
  pdf.sh text FILE [FIRST [LAST]] [--raw]
  pdf.sh image-pages FILE [FIRST [LAST]]
  pdf.sh render FILE FIRST LAST OUTDIR [DPI]
USAGE
  exit 2
}

need() { command -v "$1" >/dev/null || { echo "Missing $1: brew install poppler" >&2; exit 1; }; }
pages() { pdfinfo "$1" | awk '/^Pages:/ {print $2}'; }

cmd=${1:-}; [ $# -ge 2 ] || usage
file=$2
[ -f "$file" ] || { echo "No such file: $file" >&2; exit 1; }
need pdfinfo

case $cmd in
  info)
    pdfinfo "$file"
    ;;
  text)
    need pdftotext
    first=${3:-1}; last=${4:-$(pages "$file")}
    mode=-layout; [ "${5:-}" = "--raw" ] && mode=-raw
    pdftotext "$mode" -f "$first" -l "$last" "$file" -
    ;;
  image-pages)
    need pdfimages; need pdftotext
    first=${3:-1}; last=${4:-$(pages "$file")}
    printf 'page\timages\twords\n'
    # Skip tiny images and decorations repeated on more than 3 pages (logos, banners).
    pdfimages -list -f "$first" -l "$last" "$file" \
      | awk 'NR > 2 && $3 == "image" && $4 > 50 && $5 > 50 {page[NR] = $1; obj[NR] = $11; seen[$11]++}
             END {for (r in page) if (seen[obj[r]] <= 3) n[page[r]]++; for (p in n) print p "\t" n[p]}' \
      | sort -n \
      | while IFS=$'\t' read -r page count; do
          words=$(pdftotext -f "$page" -l "$page" "$file" - | wc -w | tr -d ' ')
          printf '%s\t%s\t%s\n' "$page" "$count" "$words"
        done
    ;;
  render)
    need pdftoppm
    [ $# -ge 5 ] || usage
    first=$3; last=$4; out=$5; dpi=${6:-100}
    mkdir -p "$out"
    pdftoppm -png -r "$dpi" -f "$first" -l "$last" "$file" "$out/page"
    ls "$out"/page*.png
    ;;
  *) usage ;;
esac
