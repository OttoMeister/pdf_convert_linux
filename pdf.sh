#!/bin/bash
# Funktion zur Verarbeitung einer einzelnen PDF
# benötigte Pakete:
# sudo apt install -y poppler-utils imagemagick parallel unpaper img2pdf pdftk tesseract-ocr tesseract-ocr-deu tesseract-ocr-eng ocrmypdf tesseract-ocr-spa
# weitere Sprachen: "apt list tesseract-ocr-*"

# Funktion zum Entfernen leerer Seiten aus PDF
remove_empty_pages() {
    local INPUT_PDF="$1"
    local OUTPUT_PDF="$2"
    
    echo "Analysiere PDF auf leere Seiten..."
    
    # Erstelle Liste mit nicht-leeren Seiten
    PAGES_TO_KEEP=""
    TOTAL_PAGES=$(pdfinfo "$INPUT_PDF" | grep "^Pages:" | awk '{print $2}')
    EMPTY_COUNT=0
    KEEP_COUNT=0
    
    echo "Gesamt-Seitenzahl: $TOTAL_PAGES"
    
    for PAGE in $(seq 1 $TOTAL_PAGES); do
        # Extrahiere Text von dieser Seite
        TEXT=$(pdftotext -f $PAGE -l $PAGE "$INPUT_PDF" - 2>/dev/null | tr -d '[:space:]')
        TEXT_LENGTH=${#TEXT}
        
        # Seite behalten wenn mehr als 20 Zeichen Text vorhanden
        if [ $TEXT_LENGTH -gt 20 ]; then
            if [ -z "$PAGES_TO_KEEP" ]; then
                PAGES_TO_KEEP="$PAGE"
            else
                PAGES_TO_KEEP="$PAGES_TO_KEEP $PAGE"
            fi
            KEEP_COUNT=$((KEEP_COUNT + 1))
            echo "  Seite $PAGE: Text gefunden ($TEXT_LENGTH Zeichen) - BEHALTEN"
        else
            EMPTY_COUNT=$((EMPTY_COUNT + 1))
            echo "  Seite $PAGE: Leer ($TEXT_LENGTH Zeichen) - ENTFERNEN"
        fi
    done
    
    echo "Zusammenfassung: $KEEP_COUNT Seiten behalten, $EMPTY_COUNT Seiten entfernt"
    
    if [ -z "$PAGES_TO_KEEP" ]; then
        echo "WARNUNG: Alle Seiten wären leer - behalte Original"
        cp "$INPUT_PDF" "$OUTPUT_PDF"
        return 1
    else
        echo "Erstelle PDF nur mit nicht-leeren Seiten..."
        pdftk "$INPUT_PDF" cat $PAGES_TO_KEEP output "$OUTPUT_PDF"
        if [ $? -eq 0 ]; then
            echo "Erfolgreich: $KEEP_COUNT von $TOTAL_PAGES Seiten gespeichert"
            return 0
        else
            echo "FEHLER beim Erstellen des gefilterten PDFs"
            return 1
        fi
    fi
}

process_pdf() {
    local FULLFILENAME="$1"

    echo "========================================"
    echo "Starte Verarbeitung: $FULLFILENAME"
    echo "========================================"

    # Konvertiere zu absolutem Pfad BEVOR wir das Verzeichnis wechseln
    FULLFILENAME=$(realpath "$FULLFILENAME")
    echo "Absoluter Pfad: $FULLFILENAME"

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

    ls -la "$WORK_DIR"

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

    # Automatische Rotationserkennung und -korrektur (90°-Schritte)
    echo "Erkenne und korrigiere Seitenausrichtung (90°-Schritte)..."
    cat list | parallel -eta '
        TESSERACT_OUTPUT=$(tesseract {} - --psm 0 2>/dev/null)
        ROTATE_ANGLE=$(echo "$TESSERACT_OUTPUT" | grep "Rotate:" | awk "{print \$2}")
        
        if [ ! -z "$ROTATE_ANGLE" ] && [ "$ROTATE_ANGLE" != "0" ]; then
            echo "  $(basename {}): Drehe um $ROTATE_ANGLE Grad"
            convert {} -rotate $((-$ROTATE_ANGLE)) {}
        else
            echo "  $(basename {}): Korrekte Ausrichtung (0°)"
        fi
    '

    # Feinausrichtung (Deskewing) für schiefe Scans
    echo "Feinausrichtung: Begradige schiefe Bilder..."
    cat list | parallel -eta convert {} -deskew 40% -verbose {} 2>&1
  

    # Grafikgröße vorbereiten auf DPI150(1240x1754)
    echo "Konvertiere Bilder zu PNG (1240x1754)..."
    cat list | parallel -eta convert {} -compress jpeg -resize 1240x1754 -gravity center -extent 1240x1754 {.}_NEU.png
    PNG_COUNT=$(find "$WORK_DIR" -type f -name '*_NEU.png' | wc -l)
    echo "Anzahl erstellter PNG-Dateien: $PNG_COUNT"
    echo "Konvertiere Bilder zu PGM (1240x1754)..."
    cat list | parallel -eta convert {} -compress jpeg -resize 1240x1754 -gravity center -extent 1240x1754 {.}_NEU.pgm
    PGM_COUNT=$(find "$WORK_DIR" -type f -name '*_NEU.pgm' | wc -l)
    echo "Anzahl erstellter PGM-Dateien: $PGM_COUNT"

    # Verarbeite alle PGM-Dateien parallel mit unpaper
    echo "Führe unpaper-Nachbearbeitung aus..."
    find "$WORK_DIR" -type f -name '*_NEU.pgm' | sort | \
         parallel -eta \
        '/usr/bin/unpaper --no-multi-pages {} {}_unpaper.pgm 2>/dev/null || \
         /usr/bin/unpaper --no-multi-pages {} {}_unpaper.pgm'
     PGM2_COUNT=$(find "$WORK_DIR" -type f -name '*_unpaper.pgm' | wc -l)
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
    /usr/bin/img2pdf -S 1240x1754 `find "$WORK_DIR" -type f -name '*_unpaper.pgm' | sort -V` -o output2.pdf
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
    /usr/bin/ocrmypdf -l deu output4.pdf "${FULLFILENAMENOEXT}_NEU2_temp.pdf"
    if [ -f "${FULLFILENAMENOEXT}_NEU2_temp.pdf" ]; then
        echo "Entferne leere Seiten aus NEU2.pdf..."
        remove_empty_pages "${FULLFILENAMENOEXT}_NEU2_temp.pdf" "${FULLFILENAMENOEXT}_NEU2.pdf"
        rm "${FULLFILENAMENOEXT}_NEU2_temp.pdf"
        
        if [ -f "${FULLFILENAMENOEXT}_NEU2.pdf" ]; then
            FINAL2_SIZE=$(du -h "${FULLFILENAMENOEXT}_NEU2.pdf" | cut -f1)
            echo "FERTIG: ${FULLFILENAMENOEXT}_NEU2.pdf erstellt (Größe: $FINAL2_SIZE)"
        else
            echo "FEHLER: ${FULLFILENAMENOEXT}_NEU2.pdf konnte nicht erstellt werden!"
        fi
    else
        echo "FEHLER: OCR für NEU2.pdf fehlgeschlagen!"
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
echo "mit Rotation und Feinausrichtung"
echo "Anzahl zu verarbeitender Dateien: $#"
echo "========================================"
echo ""

# Verarbeite alle übergebenen PDF-Dateien
SUCCESS_COUNT=0
FAIL_COUNT=0

for PDF_FILE in "$@"; do
    if process_pdf "$PDF_FILE"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo "========================================"
echo "ZUSAMMENFASSUNG"
echo "========================================"
echo "Erfolgreich verarbeitet: $SUCCESS_COUNT"
echo "Fehlgeschlagen: $FAIL_COUNT"
echo "Gesamt: $#"
echo "========================================"
