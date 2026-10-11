# Screening titlu & abstract (R / Shiny)

Aplicație simplă, în browser, pentru screening-ul de **titlu și abstract** într-un review de literatură:

- **Recenzor 1** și **Recenzor 2** evaluează independent fiecare articol (INCLUS / EXCLUS / NESIGUR), fără să vadă deciziile celuilalt.
- **Arbitrul** (al 3-lea) vede doar articolele cu **decizii diferite** (sau unde cineva a ales NESIGUR) și dă decizia finală.
- La final: acordul dintre recenzori, **kappa Cohen**, cifrele pentru **diagrama PRISMA** și exportul articolelor incluse (CSV + RIS pentru Zotero).

## 1. Instalare (o singură dată) – Fedora

```bash
sudo dnf install R
```

Apoi deschide R (scrie `R` în terminal) și rulează:

```r
install.packages("shiny")
```

(Opțional, mai comod: instalează **RStudio Desktop** și deschide `app.R` → butonul **Run App**.)

## 2. Pornire

Din folderul care conține `screening_R`:

```bash
Rscript -e 'shiny::runApp("screening_R", launch.browser = TRUE)'
```

Se deschide în browser. Oprire: `Ctrl + C` în terminal.

## 3. Pașii de lucru

0. **Tab 0 – Screening-uri**: creezi un screening nou și îi dai un nume (ex. „BCI post-AVC”). Datele lui se salvează într-un folder cu acest nume. Poți avea oricâte screening-uri; cel la care lucrezi se alege din bara de sus. Tot aici poți **șterge** un screening (îți cere confirmare).

1. **Tab 1 – Import & setări**: alege exporturile **pe rând**: apeși «Browse...», alegi un fișier, apoi din nou «Browse...» pentru următorul — fiecare se adaugă într-un tabel. Aplicația recunoaște automat baza de date a fiecărui fișier (PubMed, Scopus, Web of Science, Embase, Cochrane); verifică în tabel și corectează dacă e nevoie, apoi apasă **Importă**. Poți adăuga și mai târziu alte exporturi.
   - Duplicatele dintre baze (același DOI sau titlu) sunt eliminate automat; articolul păstrează toate bazele în care a apărut (ex. „PubMed; Scopus”), iar abstractul/DOI-ul lipsă se completează din celălalt export.
   - Vezi un tabel cu câte articole a adus fiecare bază și istoricul importurilor; cifrele pe baze apar și la PRISMA.
   - Poți încerca cu `exemplu_articole.csv` (articole fictive).
   - **PubMed**: *Save → Format: PubMed* (fișier .txt) – conține abstractele. Exportul CSV din PubMed **nu** are abstract!
   - **Scopus**: export CSV sau RIS (bifează „Abstract”).
   - **Web of Science**: *Export → Tab delimited file* sau RIS.
   - **Excel**: salvează ca CSV, cu coloanele `Title`, `Abstract`, `Authors`, `Year`, `DOI`.
   - Tot aici lipiți **protocolul review-ului** (criteriile de eligibilitate) și cuvintele-cheie evidențiate cu verde/roșu în abstract. Protocolul se scrie ca text simplu:
     ```
     In functie de populatie
     Inclusion: Pacienți adulți
     Exclusion: Studii pe animale

     In functie de designul studiului
     Inclusion: Studii randomizate controlate
     Exclusion: Case reports

     Clarificare: adult = 18 ani sau mai mult
     ```
     - un rând simplu = titlul unei categorii;
     - `Inclusion:` / `Includere:` = criteriu de includere; `Exclusion:` / `Excludere:` = criteriu de excludere;
     - `Clarificare:` / `Notă:` / `Definiție:` = precizări.

     Sub căsuță vezi imediat cum a înțeles aplicația protocolul. După salvare, protocolul apare lângă fiecare articol (la screening și la conflicte), are un tab propriu, iar **criteriile de excludere devin automat lista de motive de excludere** (și apar așa în rezultate și în exportul final).
2. **Tab 2 – Screening**: fiecare recenzor își alege rolul și își scrie numele în bara de sus. Scurtături: **I** = inclus, **E** = exclus, **N** = nesigur, **← →** = navigare. Decizia se poate schimba oricând.
3. **Tab 3 – Conflicte**: arbitrul vede opiniile ambilor recenzori (cu motive și note) și decide.
4. **Tab 4 – Rezultate**: statistică, cifre PRISMA, descărcare.

## 4. Lucru în echipă prin Google Drive (recomandat)

**Coordonatorul (o singură dată):**
1. Pune folderul `screening_R` (cu `app.R` și `porneste.R` în el) în folderul partajat de pe Google Drive.
2. Partajează folderul cu colegii, cu drept de **Editor**.
3. Pornește aplicația, lipește protocolul, salvează setările și importă articolele. Doar el face importul.

**Fiecare colaborator pe Windows:**
1. Instalează **R** de pe https://cran.r-project.org/bin/windows/base/ (Next, Next, Finish).
2. Instalează **Google Drive for Desktop**; în browser, pe folderul partajat: click dreapta → *Organize → Add shortcut to Drive*.
3. Copiază folderul `screening_R` **pe Desktop** (NU îl rula direct din Google Drive).
4. În `screening_R\windows` dă dublu-click pe **`Creeaza_iconita_pe_Desktop.bat`** (o singură dată).
5. Pornește din iconița **„Porneste Screening”**. Aplicația găsește singură folderul **Screening** de pe Google Drive (`G:\My Drive\Screening`) și salvează datele acolo. Dacă nu-l găsește, se deschide o fereastră în care îl alegi (o singură dată).
6. Pentru a alege alt folder: dublu-click pe `windows\Schimba_folderul_Drive.bat`.

> Dacă Windows afișează „Windows protected your PC”, apasă *More info → Run anyway* (fișierele .bat nu sunt semnate digital).

**Pe Mac:** instalează R și RStudio, deschide `screening_R/porneste.R` din folderul Google Drive cu RStudio și apasă **Source**.

Datele se salvează automat în folderul partajat, lângă `screening_R`. Fiecare rol scrie în fișierul lui, deci nu vă încurcați.

**Pe Linux (Fedora)**, după ce folderul de Drive e montat cu rclone:
```bash
Rscript "$HOME/DriveScreening/NumeleFolderului/screening_R/porneste.R"
```

**Pictograme cu dublu-click pe Linux (KDE):** după ce rclone e configurat, rulează o singură dată
```bash
bash linux/instaleaza_scurtaturi.sh
```
(din folderul `screening_R`). Pe Desktop apar «Montează Drive Screening» și «Pornește Screening».

**Actualizarea aplicației:** coordonatorul descarcă noul ZIP de pe GitHub și înlocuiește doar folderul `screening_R` de pe Drive. Datele nu se pierd (stau în afara lui).

## 4b. Alte variante de lucru în echipă

- **A. Aceeași rețea Wi-Fi (cel mai simplu)**: o persoană pornește aplicația așa:
  ```bash
  Rscript -e 'shiny::runApp("screening_R", host = "0.0.0.0", port = 8080)'
  ```
  iar ceilalți deschid în browser `http://IP-ul-calculatorului:8080` (IP-ul îl afli cu `hostname -I`). Pe Fedora poate fi nevoie să deschizi portul: `sudo firewall-cmd --add-port=8080/tcp`.
- **B. Folder sincronizat** (Google Drive, Dropbox, Nextcloud): fiecare rulează aplicația pe laptopul lui, dar toți folosesc același folder de date:
  ```bash
  SCREENING_DIR="/cale/catre/folderul/sincronizat" Rscript -e 'shiny::runApp("screening_R", launch.browser = TRUE)'
  ```
  Fiecare rol scrie într-un fișier separat, deci nu apar conflicte de sincronizare.
- **C. Un singur calculator**: pe rând, fiecare își alege rolul.

## 5. Unde sunt datele

În folderul `date_screening/` (creat automat):

| Fișier | Conținut |
|---|---|
| `articole.csv` | articolele unice importate |
| `decizii_R1.csv`, `decizii_R2.csv` | deciziile recenzorilor (decizie, motiv, notă, nume, dată/oră) |
| `decizii_ARB.csv` | deciziile arbitrului |
| `setari.rds` | motive de excludere, cuvinte-cheie, numărători PRISMA |

Fă periodic o copie de siguranță a acestui folder. Pentru a începe un proiect nou, mută/șterge folderul.

> Notă: „orbirea” recenzorilor se bazează pe încredere – aplicația doar nu le arată deciziile celuilalt, nu are parole.
