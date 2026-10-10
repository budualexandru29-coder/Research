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

1. **Tab 1 – Import & setări**: importă exportul din baza de date. Duplicatele (același DOI sau titlu) sunt eliminate automat. Poți încerca cu `exemplu_articole.csv` (articole fictive).
   - **PubMed**: *Save → Format: PubMed* (fișier .txt) – conține abstractele. Exportul CSV din PubMed **nu** are abstract!
   - **Scopus**: export CSV sau RIS (bifează „Abstract”).
   - **Web of Science**: *Export → Tab delimited file* sau RIS.
   - **Excel**: salvează ca CSV, cu coloanele `Title`, `Abstract`, `Authors`, `Year`, `DOI`.
   - Tot aici stabiliți **motivele de excludere** și cuvintele-cheie evidențiate cu verde/roșu în abstract.
2. **Tab 2 – Screening**: fiecare recenzor își alege rolul și își scrie numele în bara de sus. Scurtături: **I** = inclus, **E** = exclus, **N** = nesigur, **← →** = navigare. Decizia se poate schimba oricând.
3. **Tab 3 – Conflicte**: arbitrul vede opiniile ambilor recenzori (cu motive și note) și decide.
4. **Tab 4 – Rezultate**: statistică, cifre PRISMA, descărcare.

## 4. Cum lucrați în echipă (alegeți o variantă)

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
