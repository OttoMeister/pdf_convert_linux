
#!/bin/bash
printf '%s: Diese PDF aus der Android App CamScanner umwandeln \n' "$1"
#Erzeuge Temporäres Verzeichniss
WORK_DIR=`/bin/mktemp -d`
#printf 'Erzeuge Temporäres Verzeichniss: %s\n' "$WORK_DIR"
cd $WORK_DIR
#Analisiere Argument
FULLFILENAME=$1
FULLFILENAMENOEXT="${FULLFILENAME%.*}"
FILENAME=$(basename "$FULLFILENAME")
FNAME="${FILENAME%.*}"
EXT="${FILENAME##*.}"
#Nur aufrufen wen die Datei existiert
if test -f "$FULLFILENAME";
 then
 # Extrahiren JPG
 /usr/bin/pdfimages -all "$FULLFILENAME" pdfimages
 # Lösche Wasserzeichen
 /usr/bin/find $WORK_DIR -type f -size -35k -iname 'pdfimages*' -delete
 # alle dateien aus dem pdf die größer als 35k sind kmmen in die Liste
 find $WORK_DIR -type f -name 'pdfimages*' | sort >list
 # Grafikgrösse vorbereiten auf 300dpi(2480x3508) oder DPI150(1240x1754)
 cat list | parallel -eta convert {} -compress jpeg -resize 1240x1754 -gravity center -extent 1240x1754 {.}_NEU.png
 cat list | parallel -eta convert {} -compress jpeg -resize 1240x1754 -gravity center -extent 1240x1754 {.}_NEU.pgm
 #unpaper ist ein mächtiges Kommandozeilenprogramm zur Nachbearbeitung von fotokopierten/gescannten Bild- und Textvorlagen
 find $WORK_DIR -type f -name '*_NEU.pgm' | sort | parallel -eta /usr/bin/unpaper {} {.}NEU2.pgm
 #PDF aus JPG erzeugen mit DPI300(2480x3508) oder DPI150(1240x1754)
 /usr/bin/img2pdf -S 1240x1754 `find $WORK_DIR -type f -name '**_NEU.png' | sort -V` -o output1.pdf
 /usr/bin/img2pdf -S 1240x1754 `find $WORK_DIR -type f -name '**_NEUNEU2.pgm' | sort -V` -o output2.pdf
 #Compress (bringt nicht viel)
 /usr/bin/pdftk output1.pdf output output3.pdf compress
 /usr/bin/pdftk output2.pdf output output4.pdf compress
 #OCR um suchbare Files zu erzeugen  - l deu spa eng
 /usr/bin/ocrmypdf --quiet -l deu output3.pdf "$FULLFILENAMENOEXT"_NEU1.pdf
 /usr/bin/ocrmypdf --quiet -l deu output4.pdf "$FULLFILENAMENOEXT"_NEU2.pdf
else
 # Fehlermeldung
 printf '%s: No such file\n' "$FULLFILENAME"
fi
#Verzeichniss löschen
rm -rf "$WORK_DIR"
