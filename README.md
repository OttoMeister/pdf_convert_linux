### Beschreibung des Bash-Skripts

Dieses Bash-Skript dient der automatisierten Verarbeitung von PDF-Dateien, die typischerweise mit Apps wie CamScanner erstellt wurden. Es optimiert gescannte PDFs, indem es Wasserzeichen entfernt, Bilder extrahiert und verarbeitet, die Auflösung anpasst, Rauschen reduziert, PDFs komprimiert und schließlich OCR (Optical Character Recognition) anwendet, um suchbare PDFs zu erzeugen. Das Skript ist für die Stapelverarbeitung mehrerer PDFs ausgelegt und verwendet eine Reihe von Kommandozeilen-Tools aus dem Linux-Umfeld (z. B. unter Ubuntu/Debian).

#### Voraussetzungen und benötigte Pakete
Das Skript listet die erforderlichen Pakete auf, die mit `sudo apt install` installiert werden müssen:
- **poppler-utils**: Für PDF-Manipulationen (z. B. `pdfimages`).
- **imagemagick**: Für Bildverarbeitung (z. B. `convert`).
- **parallel**: Für parallele Ausführung von Befehlen.
- **unpaper**: Zur Rauschreduzierung und Nachbearbeitung von gescannten Bildern.
- **img2pdf**: Zum Erstellen von PDFs aus Bildern.
- **pdftk**: Zum Komprimieren und Manipulieren von PDFs.
- **tesseract-ocr** und Sprachpakete (z. B. `tesseract-ocr-deu`, `tesseract-ocr-eng`, `tesseract-ocr-spa`): Für OCR. Weitere Sprachen können über `apt list tesseract-ocr-*` gefunden werden.
- **ocrmypdf**: Zum Hinzufügen von OCR-Schichten zu PDFs.

Das Skript läuft unter Bash und setzt ein Linux-System voraus. Es hat keine Internetabhängigkeit, aber die Tools müssen vorab installiert sein.


