---
name: pdf-tools
description: Read PDF files (text, metadata, and pages rendered as images for tables, figures or scanned pages) with poppler's pdfinfo, pdftotext and pdftoppm. Use whenever you need to read, summarize, search or extract content from a .pdf file, since the read tool cannot open PDFs.
---

# PDF tools

The `read` tool does not open PDFs. Use poppler through `bash` instead, and
`read` on the PNG files it produces to see pages as images.

Requires poppler (`pdfinfo`, `pdftotext`, `pdftoppm`). If it is missing,
offer `brew install poppler`.

## Workflow

1. Inspect the document first:
   `scripts/pdf.sh info file.pdf` (page count, title, author, size).
2. Extract text for a page range, keeping the layout:
   `scripts/pdf.sh text file.pdf FIRST LAST > /tmp/out.txt`.
   Read the output with `read` (offset/limit) or `rg`, not all at once.
3. Find pages whose content is mostly images (tables, figures, scans):
   `scripts/pdf.sh image-pages file.pdf [FIRST LAST]`. It lists pages with
   embedded images and their extracted word count. Pages with images and
   few words, or text that refers to a "Tabla"/"Figura" with no content,
   need to be viewed.
4. Render those pages and look at them:
   `scripts/pdf.sh render file.pdf FIRST LAST /tmp/pdf-pages [DPI]`
   (default 100 DPI), then `read` each PNG. Use 150 DPI for small print.
   To render only an image instead of the whole page, use
   `pdfimages -png -f N -l N file.pdf /tmp/prefix`.

## Large documents

- Extract to a file once and split it (for example by chapter headings)
  instead of re-running `pdftotext` per question.
- For more than about 100 pages, delegate chapters to subagents or parallel
  `pi -p` runs, each writing its findings to a file, and merge the results.
- Rendering many pages is expensive: render only the pages you need.
- Delegated runs over many images skip pages silently. Ask them to cite
  the page of each table or figure, then check every rendered page is
  cited (or explicitly ruled out) and re-run the missing ones.

## Notes

- Scanned PDFs have no text layer: `text` returns nothing, so render the
  pages and read them as images.
- Text extracted with `-layout` keeps columns; drop it (`--raw` mode) if
  words from different columns get mixed.
- Paths with spaces must be quoted.
