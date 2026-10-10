#!/bin/bash
# =====================================================================
#  Creează pe Desktop (și în meniul de aplicații) două pictograme:
#   1. «Montează Drive Screening»  – montează folderul de pe Google Drive
#   2. «Pornește Screening»        – montează (dacă e nevoie) și pornește aplicația
#
#  Se rulează O SINGURĂ DATĂ:   bash instaleaza_scurtaturi.sh
#  Presupune că rclone e deja configurat cu conexiunea «gdrive».
# =====================================================================

BIN="$HOME/.local/bin"
APPS="$HOME/.local/share/applications"
DESKTOP="$(xdg-user-dir DESKTOP 2>/dev/null || echo "$HOME/Desktop")"
mkdir -p "$BIN" "$APPS" "$DESKTOP"

# ---------- scriptul de montare ----------
cat > "$BIN/monteaza-drive-screening.sh" <<'SCRIPT'
#!/bin/bash
D="$HOME/DriveScreening"
mkdir -p "$D"
if mountpoint -q "$D"; then
  notify-send -i folder-cloud "Drive Screening" "Folderul este deja montat."
else
  rclone mount gdrive: "$D" --vfs-cache-mode full --poll-interval 15s --daemon
  sleep 2
  if mountpoint -q "$D"; then
    notify-send -i folder-cloud "Drive Screening" "Folderul de pe Google Drive a fost montat ✔"
  else
    notify-send -u critical -i dialog-error "Drive Screening" \
      "Montarea a eșuat. Verifică internetul sau rulează în terminal: rclone mount gdrive: ~/DriveScreening"
    exit 1
  fi
fi
[ "$1" = "--fara-dolphin" ] || xdg-open "$D"
SCRIPT

# ---------- scriptul care pornește aplicația ----------
cat > "$BIN/porneste-screening.sh" <<'SCRIPT'
#!/bin/bash
"$HOME/.local/bin/monteaza-drive-screening.sh" --fara-dolphin || { read -p "Apasă Enter pentru a închide..."; exit 1; }
APP="$HOME/DriveScreening/screening_R/porneste.R"
if [ ! -f "$APP" ]; then
  echo "Nu găsesc $APP"
  echo "Copiază folderul screening_R în folderul de pe Google Drive."
  read -p "Apasă Enter pentru a închide..."; exit 1
fi
echo "Aplicația pornește în browser. Pentru a o opri, închide această fereastră."
Rscript "$APP"
read -p "Aplicația s-a oprit. Apasă Enter pentru a închide..."
SCRIPT

chmod +x "$BIN/monteaza-drive-screening.sh" "$BIN/porneste-screening.sh"

# ---------- pictogramele ----------
cat > "$APPS/monteaza-drive-screening.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Montează Drive Screening
Comment=Montează folderul de screening de pe Google Drive în ~/DriveScreening
Exec=$BIN/monteaza-drive-screening.sh
Icon=folder-cloud
Terminal=false
Categories=Utility;
DESK

cat > "$APPS/porneste-screening.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Pornește Screening
Comment=Montează Google Drive și pornește aplicația de screening
Exec=$BIN/porneste-screening.sh
Icon=view-list-details
Terminal=true
Categories=Education;
DESK

for f in monteaza-drive-screening porneste-screening; do
  cp "$APPS/$f.desktop" "$DESKTOP/$f.desktop"
  chmod +x "$APPS/$f.desktop" "$DESKTOP/$f.desktop"
  gio set "$DESKTOP/$f.desktop" metadata::trusted true 2>/dev/null
done

echo "Gata! Pe Desktop au apărut «Montează Drive Screening» și «Pornește Screening»."
echo "Le găsești și în meniul de aplicații (caută «Screening»)."
