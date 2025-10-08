#!/bin/bash
# Funktion zur Verarbeitung einer einzelnen PDF
# benötigte Pakete:
# sudo apt install -y poppler-utils imagemagick parallel unpaper img2pdf pdftk tesseract-ocr tesseract-ocr-deu tesseract-ocr-eng ocrmypdf tesseract-ocr-spa
# weitere Sprachen: "apt list tesseract-ocr-*"

process_pdf() {
    local FULLFILENAME="$1"

    echo "========================================"
    echo "Starte Verarbeitung: $FULLFILENAME"
    echo "========================================"

    # Prüfe ob Datei existiert
    if [ ! -f "$FULLFILENAME" ]; then
        echo "FEHLER: Datei existiert nicht: $FULLFILENAME"
        return 1
    fi

    # Erzeuge Temporäres Verzeichnis
    WORK_DIR=`/bin/mktemp -d`
    echo "Temporäres Verzeichnis erstellt: $WORK_DIR"
    cd "$WORK_DIR"

    # Analysiere Argument
    FULLFILENAMENOEXT="${FULLFILENAME%.*}"
    FILENAME=$(basename "$FULLFILENAME")
    FNAME="${FILENAME%.*}"
    EXT="${FILENAME##*.}"

    echo "Dateiname ohne Pfad: $FILENAME"
    echo "Dateiname ohne Extension: $FNAME"
    echo "Extension: $EXT"

    # Extrahiere Bilder aus PDF
    echo "Extrahiere Bilder aus PDF..."
    /usr/bin/pdfimages -all "$FULLFILENAME" pdfimages

    # Zähle extrahierte Dateien
    EXTRACTED_COUNT=$(find "$WORK_DIR" -type f -name 'pdfimages*' | wc -l)
    echo "Anzahl extrahierter Dateien: $EXTRACTED_COUNT"

    if [ "$EXTRACTED_COUNT" -eq 0 ]; then
        echo "FEHLER: Keine Bilder aus PDF extrahiert!"
        rm -rf "$WORK_DIR"
        return 1
    fi

    # Lösche Wasserzeichen
    echo "Lösche kleine Dateien (Wasserzeichen) unter 35k..."
    BEFORE_DELETE=$(find "$WORK_DIR" -type f -name 'pdfimages*' | wc -l)
    /usr/bin/find "$WORK_DIR" -type f -size -35k -iname 'pdfimages*' -delete
    AFTER_DELETE=$(find "$WORK_DIR" -type f -name 'pdfimages*' | wc -l)
    echo "Dateien vor dem Löschen: $BEFORE_DELETE, danach: $AFTER_DELETE"

    # Alle Dateien aus dem PDF die größer als 35k sind kommen in die Liste
    find "$WORK_DIR" -type f -name 'pdfimages*' | sort >list
    IMAGE_COUNT=$(wc -l < list)
    echo "Anzahl zu verarbeitender Bilder: $IMAGE_COUNT"

    if [ "$IMAGE_COUNT" -eq 0 ]; then
        echo "FEHLER: Keine Bilder zum Verarbeiten vorhanden!"
        rm -rf "$WORK_DIR"
        return 1
    fi

    # Grafikgrösse vorbereiten auf DPI150(1240x1754)
    echo "Konvertiere Bilder zu PNG (1240x1754)..."
    cat list | parallel -eta convert {} -compress jpeg -resize 1240x1754 -gravity center -extent 1240x1754 {.}_NEU.png
    PNG_COUNT=$(find "$WORK_DIR" -type f -name '*_NEU.png' | wc -l)
    echo "Anzahl erstellter PNG-Dateien: $PNG_COUNT"

    echo "Konvertiere Bilder zu PGM (1240x1754)..."
    cat list | parallel -eta convert {} -compress jpeg -resize 1240x1754 -gravity center -extent 1240x1754 {.}_NEU.pgm
    PGM_COUNT=$(find "$WORK_DIR" -type f -name '*_NEU.pgm' | wc -l)
    echo "Anzahl erstellter PGM-Dateien: $PGM_COUNT"

    # Unpaper zur Nachbearbeitung
    echo "Führe unpaper-Nachbearbeitung aus..."
    find "$WORK_DIR" -type f -name '*_NEU.pgm' | sort | parallel -eta '/usr/bin/unpaper --no-multi-pages {} {.}_NEU2.pgm 2>/dev/null || /usr/bin/unpaper --no-multi-pages {} {.}_NEU2.pgm'
    PGM2_COUNT=$(find "$WORK_DIR" -type f -name '*_NEU_NEU2.pgm' | wc -l)
    echo "Anzahl nachbearbeiteter PGM-Dateien: $PGM2_COUNT"

    # PDF aus Bildern erzeugen
    echo "Erstelle PDF aus PNG-Dateien (output1.pdf)..."
    /usr/bin/img2pdf -S 1240x1754 `find "$WORK_DIR" -type f -name '*_NEU.png' | sort -V` -o output1.pdf
    if [ -f output1.pdf ]; then
        PDF1_SIZE=$(du -h output1.pdf | cut -f1)
        echo "output1.pdf erstellt (Größe: $PDF1_SIZE)"
    else
        echo "FEHLER: output1.pdf konnte nicht erstellt werden!"
    fi

    echo "Erstelle PDF aus PGM-Dateien (output2.pdf)..."
    /usr/bin/img2pdf -S 1240x1754 `find "$WORK_DIR" -type f -name '*_NEU_NEU2.pgm' | sort -V` -o output2.pdf
    if [ -f output2.pdf ]; then
        PDF2_SIZE=$(du -h output2.pdf | cut -f1)
        echo "output2.pdf erstellt (Größe: $PDF2_SIZE)"
    else
        echo "FEHLER: output2.pdf konnte nicht erstellt werden!"
    fi

    # Komprimiere PDFs
    echo "Komprimiere output1.pdf zu output3.pdf..."
    /usr/bin/pdftk output1.pdf output output3.pdf compress
    if [ -f output3.pdf ]; then
        PDF3_SIZE=$(du -h output3.pdf | cut -f1)
        echo "output3.pdf erstellt (Größe: $PDF3_SIZE)"
    fi

    echo "Komprimiere output2.pdf zu output4.pdf..."
    /usr/bin/pdftk output2.pdf output output4.pdf compress
    if [ -f output4.pdf ]; then
        PDF4_SIZE=$(du -h output4.pdf | cut -f1)
        echo "output4.pdf erstellt (Größe: $PDF4_SIZE)"
    fi

    # OCR um suchbare Files zu erzeugen
    # see tesseract --list-langs for all language packs installed in your system
    echo "Führe OCR aus (Deutsch) für NEU1.pdf..."
    /usr/bin/ocrmypdf -l deu output3.pdf "${FULLFILENAMENOEXT}_NEU1.pdf"
    if [ -f "${FULLFILENAMENOEXT}_NEU1.pdf" ]; then
        FINAL1_SIZE=$(du -h "${FULLFILENAMENOEXT}_NEU1.pdf" | cut -f1)
        echo "FERTIG: ${FULLFILENAMENOEXT}_NEU1.pdf erstellt (Größe: $FINAL1_SIZE)"
    else
        echo "FEHLER: ${FULLFILENAMENOEXT}_NEU1.pdf konnte nicht erstellt werden!"
    fi

    echo "Führe OCR aus (Deutsch) für NEU2.pdf..."
    /usr/bin/ocrmypdf -l deu output4.pdf "${FULLFILENAMENOEXT}_NEU2.pdf"
    if [ -f "${FULLFILENAMENOEXT}_NEU2.pdf" ]; then
        FINAL2_SIZE=$(du -h "${FULLFILENAMENOEXT}_NEU2.pdf" | cut -f1)
        echo "FERTIG: ${FULLFILENAMENOEXT}_NEU2.pdf erstellt (Größe: $FINAL2_SIZE)"
    else
        echo "FEHLER: ${FULLFILENAMENOEXT}_NEU2.pdf konnte nicht erstellt werden!"
    fi

    # Verzeichnis löschen
    echo "Lösche temporäres Verzeichnis: $WORK_DIR"
    rm -rf "$WORK_DIR"

    echo "Verarbeitung von $FILENAME abgeschlossen!"
    echo ""
}

# Hauptprogramm
if [ $# -eq 0 ]; then
    echo "Fehler: Keine PDF-Dateien angegeben!"
    echo "Verwendung: $0 <PDF-Datei1> [PDF-Datei2] [PDF-Datei3] ..."
    exit 1
fi

echo "========================================"
echo "PDF Converter für CamScanner PDFs"
echo "Anzahl zu verarbeitender Dateien: $#"
echo "========================================"
echo ""

# Verarbeite alle übergebenen PDF-Dateien
SUCCESS_COUNT=0
FAIL_COUNT=0

for PDF_FILE in "$@"; do
    if process_pdf "$PDF_FILE"; then
        ((SUCCESS_COUNT++))
    else
        ((FAIL_COUNT++))
    fi
done

echo "========================================"
echo "ZUSAMMENFASSUNG"
echo "========================================"
echo "Erfolgreich verarbeitet: $SUCCESS_COUNT"
echo "Fehlgeschlagen: $FAIL_COUNT"
echo "Gesamt: $#"
echo "========================================"
