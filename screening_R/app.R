# =====================================================================
#  SCREENING TITLU & ABSTRACT pentru review de literatură
#  - 2 recenzori independenți (în orb unul față de celălalt)
#  - 1 arbitru care rezolvă diferențele (conflictele)
#
#  Pornire:  în R / RStudio ->  shiny::runApp("cale/catre/screening_R")
#  Singurul pachet necesar: shiny   ->  install.packages("shiny")
# =====================================================================

library(shiny)

# ---------------------------------------------------------------------
# 1. FIȘIERE ȘI CONSTANTE
# ---------------------------------------------------------------------
# Folderul de bază (poate fi un folder sincronizat Google Drive / Dropbox /
# Nextcloud, setat prin variabila SCREENING_DIR). Fiecare screening are în el
# un subfolder cu numele lui, în care se salvează articolele și deciziile.
DIR_BAZA <- Sys.getenv("SCREENING_DIR", "date_screening")
dir.create(DIR_BAZA, showWarnings = FALSE, recursive = TRUE)
DIR_BAZA <- normalizePath(DIR_BAZA)

MARCAJ <- "proiect_screening.txt"   # fișier care marchează un folder ca fiind un screening
FISIERE_DATE <- c("articole.csv", "setari.rds", "decizii_R1.csv", "decizii_R2.csv", "decizii_ARB.csv")
NUME_VECHI <- "(screening fără nume, creat înainte)"

F_ART <- function(dir) file.path(dir, "articole.csv")
F_SET <- function(dir) file.path(dir, "setari.rds")
F_DEC <- function(dir, rol) file.path(dir, paste0("decizii_", rol, ".csv"))

ROLURI   <- c("Recenzor 1" = "R1", "Recenzor 2" = "R2", "Arbitru (al 3-lea recenzor)" = "ARB")
ETICHETE <- c(include = "INCLUS", exclude = "EXCLUS", maybe = "NESIGUR")
COL_ART  <- c("id", "titlu", "autori", "an", "jurnal", "doi", "pmid", "abstract", "sursa")
COL_DEC  <- c("id", "decizie", "motiv", "nota", "nume", "data")

SET_IMPLICIT <- list(
  motive = c("Populație nepotrivită",
             "Intervenție / expunere nepotrivită",
             "Comparator nepotrivit",
             "Rezultat (outcome) nepotrivit",
             "Tip de studiu nepotrivit (ex. review, editorial)",
             "Nu este pe subiect",
             "Limbă",
             "Studiu pe animale / in vitro",
             "Altul (vezi nota)"),
  protocol = "",      # textul protocolului (criterii de includere / excludere)
  kw_inc = "",
  kw_exc = "",
  identificate = 0,
  duplicate = 0,
  pe_baze = list(),   # înregistrări identificate în fiecare bază de date (pentru PRISMA)
  istoric = NULL      # istoricul importurilor (data, fișier, bază, înregistrări, noi, duplicate)
)

BAZE <- c("PubMed", "Scopus", "Web of Science", "Embase", "Cochrane Library",
          "CINAHL", "PsycINFO", "Google Scholar", "Altă sursă")

# Transformă codurile (include/exclude/maybe) în etichete în română
et <- function(x) {
  y <- unname(ETICHETE[x])
  y[is.na(y)] <- ""
  y
}

# ---------------------------------------------------------------------
# 2. CITIRE / SCRIERE FIȘIERE
# ---------------------------------------------------------------------
tabel_gol <- function(coloane) {
  as.data.frame(setNames(rep(list(character(0)), length(coloane)), coloane),
                stringsAsFactors = FALSE)
}

citeste_csv <- function(f, coloane) {
  if (!file.exists(f)) return(tabel_gol(coloane))
  d <- read.csv(f, stringsAsFactors = FALSE, colClasses = "character",
                fileEncoding = "UTF-8-BOM", na.strings = character(0),
                check.names = FALSE)
  for (c in setdiff(coloane, names(d))) d[[c]] <- rep("", nrow(d))
  d[, coloane, drop = FALSE]
}

# Scrie CSV în UTF-8 cu BOM (se deschide corect și în Excel / LibreOffice).
# Scrie întâi într-un fișier temporar, ca să nu se strice datele la o eroare.
scrie_csv <- function(d, f) {
  tmp <- paste0(f, ".tmp")
  con <- file(tmp, "wb")
  writeBin(as.raw(c(0xef, 0xbb, 0xbf)), con)
  close(con)
  con <- file(tmp, "a", encoding = "UTF-8")
  write.table(d, con, sep = ",", row.names = FALSE, qmethod = "double")
  close(con)
  file.rename(tmp, f)
}

citeste_setari <- function(dir) {
  s <- SET_IMPLICIT
  if (!is.null(dir) && file.exists(F_SET(dir))) {
    x <- tryCatch(readRDS(F_SET(dir)), error = function(e) list())
    s[names(x)] <- x
  }
  s
}

salveaza_decizie <- function(dir, rol, id, decizie, motiv, nota, nume) {
  d <- citeste_csv(F_DEC(dir, rol), COL_DEC)
  d <- d[d$id != id, , drop = FALSE]
  d <- rbind(d, data.frame(id = id, decizie = decizie, motiv = motiv,
                           nota = nota, nume = nume,
                           data = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
                           stringsAsFactors = FALSE))
  scrie_csv(d, F_DEC(dir, rol))
}

# ---------------------------------------------------------------------
# 2b. MAI MULTE SCREENING-URI (fiecare în folderul lui)
# ---------------------------------------------------------------------
ultima_modificare <- function(dir) {
  t <- suppressWarnings(max(file.mtime(file.path(dir, FISIERE_DATE)), na.rm = TRUE))
  if (!is.finite(t)) t <- file.mtime(dir)
  t
}

# Lista screening-urilor: nume -> folder (cel mai recent modificat primul)
lista_proiecte <- function() {
  d <- list.dirs(DIR_BAZA, recursive = FALSE, full.names = TRUE)
  d <- d[file.exists(file.path(d, MARCAJ))]
  p <- setNames(d, basename(d))
  if (any(file.exists(file.path(DIR_BAZA, FISIERE_DATE))))     # date salvate înainte de această versiune
    p <- c(p, setNames(DIR_BAZA, NUME_VECHI))
  if (length(p) > 1) p <- p[order(-as.numeric(sapply(p, ultima_modificare)))]
  p
}

curata_nume <- function(x) {
  x <- gsub("[/\\\\:*?\"<>|]", "", x)          # caractere interzise în numele de foldere
  x <- trimws(gsub("\\s+", " ", x))
  substr(x, 1, 60)
}

creeaza_proiect <- function(nume) {
  nume <- curata_nume(nume)
  if (!nzchar(nume)) stop("Scrie un nume pentru screening.")
  if (tolower(nume) %in% c("screening_r", "date_screening")) stop("Alege alt nume.")
  dir <- file.path(DIR_BAZA, nume)
  if (dir.exists(dir)) stop("Există deja un folder cu acest nume.")
  dir.create(dir, recursive = TRUE)
  writeLines(c(paste("Screening:", nume), paste("Creat:", format(Sys.time(), "%Y-%m-%d %H:%M"))),
             file.path(dir, MARCAJ), useBytes = TRUE)
  dir
}

sterge_proiect <- function(dir) {
  dir <- normalizePath(dir)
  if (dir == DIR_BAZA) {                     # screening-ul vechi: șterg doar fișierele lui
    unlink(file.path(dir, FISIERE_DATE))
  } else if (dirname(dir) == DIR_BAZA && file.exists(file.path(dir, MARCAJ))) {
    unlink(dir, recursive = TRUE)
  } else stop("Folderul nu pare să fie un screening; nu îl șterg.")
}

rezumat_proiect <- function(dir) {
  a  <- citeste_csv(F_ART(dir), COL_ART)
  D  <- list(art = a, R1 = citeste_csv(F_DEC(dir, "R1"), COL_DEC),
             R2 = citeste_csv(F_DEC(dir, "R2"), COL_DEC), ARB = citeste_csv(F_DEC(dir, "ARB"), COL_DEC))
  t <- combina(D)
  c(Articole = nrow(a),
    "Recenzor 1" = sum(nzchar(t$R1)), "Recenzor 2" = sum(nzchar(t$R2)),
    "Conflicte nerezolvate" = sum(t$stare == "conflict" & !nzchar(t$ARB)),
    Incluse = sum(t$final == "include"))
}

# Pe Linux: datele sunt într-un folder „Drive” care NU e montat? (ar rămâne doar pe laptop)
drive_nemontat <- function(cale) {
  if (Sys.info()[["sysname"]] != "Linux" || !nzchar(Sys.which("mountpoint"))) return(FALSE)
  cale <- normalizePath(cale, mustWork = FALSE)
  if (!grepl("drive", cale, ignore.case = TRUE)) return(FALSE)
  acasa <- normalizePath("~")
  while (nchar(cale) > nchar(acasa)) {
    if (suppressWarnings(system2("mountpoint", c("-q", shQuote(cale)))) == 0) return(FALSE)
    cale <- dirname(cale)
  }
  TRUE
}

# ---------------------------------------------------------------------
# 3. IMPORT ARTICOLE (CSV, RIS, PubMed/MEDLINE .nbib/.txt, WoS tab-delimited)
# ---------------------------------------------------------------------
an_din <- function(x) {
  y <- regmatches(x, regexpr("(1[89]|20)[0-9]{2}", x))
  out <- rep("", length(x))
  out[grepl("(1[89]|20)[0-9]{2}", x)] <- y
  out
}

gaseste_col <- function(nume, tipare) {
  for (p in tipare) {
    i <- grep(p, nume, ignore.case = TRUE)
    if (length(i)) return(i[1])
  }
  NA
}

# Fișier tabelar: CSV (PubMed, Scopus, Rayyan, Zotero, Excel salvat ca CSV)
# sau tab-delimited (Web of Science)
citeste_tabel <- function(f) {
  l1 <- readLines(f, n = 1, warn = FALSE, encoding = "UTF-8")
  nr <- sapply(c(",", ";", "\t"), function(s) lengths(regmatches(l1, gregexpr(s, l1, fixed = TRUE))))
  sep <- names(nr)[which.max(nr)]
  d <- read.delim(f, sep = sep, quote = if (sep == "\t") "" else "\"",
                  colClasses = "character", fileEncoding = "UTF-8-BOM",
                  check.names = FALSE, na.strings = character(0),
                  comment.char = "", fill = TRUE)
  col <- function(tipare) {
    i <- gaseste_col(names(d), tipare)
    if (is.na(i)) rep("", nrow(d)) else as.character(d[[i]])
  }
  titlu <- col(c("^title$", "^article title$", "^titlu$", "^TI$", "^document title$", "^title"))
  if (all(titlu == "")) stop("Nu am găsit coloana cu titlul (trebuie să se numească «Title»).")
  data.frame(
    titlu    = titlu,
    autori   = col(c("^authors?$", "^author full names$", "^autori$", "^AU$", "author")),
    an       = an_din(col(c("^year$", "^publication year$", "^an$", "^PY$", "year", "date"))),
    jurnal   = col(c("^journal$", "^source title$", "^journal/book$", "^jurnal$", "^SO$", "journal", "source")),
    doi      = col(c("^doi$", "^DI$", "doi")),
    pmid     = col(c("^pmid$", "^pubmed id$", "^PM$", "pmid")),
    abstract = col(c("^abstract$", "^AB$", "^rezumat$", "abstract")),
    stringsAsFactors = FALSE
  )
}

# Format cu etichete: RIS (Scopus, Embase, Zotero, Mendeley, Cochrane)
# și MEDLINE/PubMed (.nbib sau .txt). Ex.: "TI  - Titlu", "AB  - Abstract"
citeste_etichetat <- function(f) {
  linii <- readLines(f, warn = FALSE, encoding = "UTF-8")
  linii <- sub("^﻿", "", linii)
  pat <- "^([A-Z][A-Z0-9]{1,3}) *- ?(.*)$"
  are_tag <- grepl(pat, linii)
  tags <- ifelse(are_tag, sub(pat, "\\1", linii), NA)
  vals <- ifelse(are_tag, trimws(sub(pat, "\\2", linii)), NA)

  recs <- list(); cur <- list(); ultim <- NULL
  inchide <- function() {
    if (length(cur)) recs[[length(recs) + 1]] <<- cur
    cur <<- list(); ultim <<- NULL
  }
  for (k in seq_along(linii)) {
    if (are_tag[k]) {
      tg <- tags[k]
      if (tg == "ER") { inchide(); next }
      if (tg %in% c("TY", "PMID") && length(cur)) inchide()
      cur[[tg]] <- c(cur[[tg]], vals[k]); ultim <- tg
    } else if (!is.null(ultim) && grepl("^\\s+\\S", linii[k])) {
      n <- length(cur[[ultim]])
      cur[[ultim]][n] <- paste(cur[[ultim]][n], trimws(linii[k]))
    }
  }
  inchide()
  if (!length(recs)) stop("Fișierul nu pare să fie în format RIS sau PubMed (MEDLINE).")

  camp <- function(r, tg, sep = "; ") {
    for (t in tg) if (!is.null(r[[t]])) return(paste(r[[t]], collapse = sep))
    ""
  }
  doi_din <- function(r) {
    if (!is.null(r$DO)) return(r$DO[1])
    x <- c(r$LID, r$AID)
    x <- x[grepl("\\[doi\\]", x)]
    if (length(x)) trimws(sub("\\[doi\\]", "", x[1])) else ""
  }
  data.frame(
    titlu    = sapply(recs, camp, tg = c("TI", "T1", "CT"), sep = " "),
    autori   = sapply(recs, camp, tg = c("AU", "A1", "FAU")),
    an       = an_din(sapply(recs, camp, tg = c("PY", "Y1", "DP", "DA"))),
    jurnal   = sapply(recs, camp, tg = c("JT", "T2", "JO", "JF", "TA"), sep = " "),
    doi      = sapply(recs, doi_din),
    pmid     = sapply(recs, camp, tg = c("PMID")),
    abstract = sapply(recs, camp, tg = c("AB", "N2"), sep = " "),
    stringsAsFactors = FALSE
  )
}

citeste_fisier <- function(cale, nume) {
  ext <- tolower(tools::file_ext(nume))
  if (ext %in% c("xls", "xlsx"))
    stop("Salvează fișierul Excel ca CSV (Fișier → Salvare ca → CSV) și importă-l din nou.")
  if (ext == "csv" || ext == "tsv") return(citeste_tabel(cale))
  l1 <- readLines(cale, n = 1, warn = FALSE)
  if (ext == "txt" && length(l1) && grepl("\t", l1)) return(citeste_tabel(cale))
  citeste_etichetat(cale)
}

# Recunoaște automat din ce bază de date provine un export
detecteaza_baza <- function(cale, nume) {
  l <- tryCatch(readLines(cale, n = 300, warn = FALSE, encoding = "UTF-8"),
                error = function(e) character(0))
  l <- sub("^\ufeff", "", l)
  db <- sub("^DB  - ", "", grep("^DB  - ", l, value = TRUE))
  if (length(db)) {
    db <- db[1]
    for (b in c("Embase", "Scopus", "Cochrane", "CINAHL", "PsycINFO", "Web of Science"))
      if (grepl(b, db, ignore.case = TRUE)) return(if (b == "Cochrane") "Cochrane Library" else b)
    if (grepl("medline|pubmed", db, ignore.case = TRUE)) return("PubMed")
  }
  if (any(grepl("^PMID- ", l))) return("PubMed")
  if (length(l) && grepl("^\"?PMID\"?,\"?Title\"?|^\"?Title\"?,\"?Authors\"?,\"?Citation", l[1])) return("PubMed")
  if (any(grepl("scopus\\.com", l, ignore.case = TRUE))) return("Scopus")
  if (length(l) && (grepl("^(PT|FN)\t", l[1]) || grepl("^FN (Clarivate|Thomson)", l[1]))) return("Web of Science")
  if (any(grepl("webofscience|isiknowledge", l, ignore.case = TRUE))) return("Web of Science")
  if (any(grepl("cochranelibrary\\.com", l, ignore.case = TRUE))) return("Cochrane Library")
  if (any(grepl("embase\\.com", l, ignore.case = TRUE))) return("Embase")
  "Altă sursă"
}

# Adaugă articole noi, eliminând duplicatele (același DOI sau același titlu).
# Un duplicat nu se pierde: baza lui de date se adaugă la articolul deja existent
# (ex. „PubMed; Scopus”), iar câmpurile goale (abstract, DOI...) se completează din el.
cheie_titlu <- function(t) gsub("[^a-z0-9]", "", tolower(iconv(t, to = "ASCII//TRANSLIT", sub = "")))

adauga_articole <- function(noi, existente) {
  noi[] <- lapply(noi, function(x) { x[is.na(x)] <- ""; trimws(x) })
  noi$doi <- tolower(sub("^https?://(dx\\.)?doi\\.org/", "", noi$doi))
  goale <- !(nzchar(noi$titlu) | nzchar(noi$abstract))
  noi <- noi[!goale, , drop = FALSE]
  noi$id <- ""
  V <- as.list(rbind(existente[, COL_ART], noi[, COL_ART]))
  kd <- tolower(V$doi)
  kt <- cheie_titlu(V$titlu)
  dupa_doi <- new.env(hash = TRUE)
  dupa_titlu <- new.env(hash = TRUE)
  inregistreaza <- function(i) {
    if (nzchar(kd[i])) assign(kd[i], i, envir = dupa_doi)
    if (nchar(kt[i]) > 10) assign(kt[i], i, envir = dupa_titlu)
  }
  for (i in seq_len(nrow(existente))) inregistreaza(i)

  pastreaza <- rep(TRUE, length(V$id))
  for (j in nrow(existente) + seq_len(nrow(noi))) {
    m <- NULL
    if (nzchar(kd[j])) m <- get0(kd[j], envir = dupa_doi, inherits = FALSE)
    if (is.null(m) && nchar(kt[j]) > 10) m <- get0(kt[j], envir = dupa_titlu, inherits = FALSE)
    if (is.null(m)) { inregistreaza(j); next }
    # duplicat: îl contopim în articolul m
    pastreaza[j] <- FALSE
    surse <- trimws(unlist(strsplit(V$sursa[m], ";")))
    if (!(V$sursa[j] %in% surse)) V$sursa[m] <- paste(c(surse[nzchar(surse)], V$sursa[j]), collapse = "; ")
    for (f in c("autori", "an", "jurnal", "doi", "pmid", "abstract"))
      if (!nzchar(V[[f]][m]) && nzchar(V[[f]][j])) V[[f]][m] <- V[[f]][j]
    if (!nzchar(kd[m]) && nzchar(kd[j])) { kd[m] <- kd[j]; assign(kd[m], m, envir = dupa_doi) }
  }
  tot <- as.data.frame(V, stringsAsFactors = FALSE)[pastreaza, , drop = FALSE]
  fara_id <- !nzchar(tot$id)
  start <- if (nrow(existente)) max(as.integer(sub("^A", "", existente$id))) else 0
  tot$id[fara_id] <- sprintf("A%04d", start + seq_len(sum(fara_id)))
  rownames(tot) <- NULL
  list(articole = tot,
       adaugate = sum(fara_id),
       duplicate = nrow(noi) - sum(fara_id),
       goale = sum(goale))
}

# Exportă articole în format RIS (pentru Zotero / Mendeley / EndNote)
scrie_ris <- function(d, f) {
  linii <- unlist(lapply(seq_len(nrow(d)), function(i) {
    r <- d[i, ]
    au <- trimws(unlist(strsplit(r$autori, ";")))
    au <- au[nzchar(au)]
    c("TY  - JOUR",
      paste("TI  -", r$titlu),
      if (length(au)) paste("AU  -", au),
      if (nzchar(r$an)) paste("PY  -", r$an),
      if (nzchar(r$jurnal)) paste("T2  -", r$jurnal),
      if (nzchar(r$doi)) paste("DO  -", r$doi),
      if (nzchar(r$pmid)) paste("AN  -", r$pmid),
      if (nzchar(r$abstract)) paste("AB  -", r$abstract),
      "ER  - ", "")
  }))
  con <- file(f, "w", encoding = "UTF-8")
  writeLines(linii, con)
  close(con)
}

# ---------------------------------------------------------------------
# 4. CALCULE: combinarea deciziilor, conflicte, kappa
# ---------------------------------------------------------------------
combina <- function(D) {
  a <- D$art
  for (rol in c("R1", "R2", "ARB")) {
    d <- D[[rol]]
    m <- match(a$id, d$id)
    for (c in c("decizie", "motiv", "nota", "nume")) {
      v <- d[[c]][m]; v[is.na(v)] <- ""
      a[[if (c == "decizie") rol else paste0(rol, "_", c)]] <- v
    }
  }
  ambii <- nzchar(a$R1) & nzchar(a$R2)
  acord <- ambii & a$R1 == a$R2 & a$R1 != "maybe"
  a$stare <- ifelse(!ambii, "neterminat", ifelse(acord, "acord", "conflict"))
  a$final <- ifelse(a$stare == "acord", a$R1,
                    ifelse(a$stare == "conflict", a$ARB, ""))
  a$motiv_final <- ifelse(a$final != "exclude", "",
                          ifelse(a$stare == "acord",
                                 ifelse(nzchar(a$R1_motiv), a$R1_motiv, a$R2_motiv),
                                 a$ARB_motiv))
  a
}

kappa_cohen <- function(x, y) {
  if (!length(x)) return(NA)
  niv <- union(x, y)
  t <- table(factor(x, niv), factor(y, niv))
  n <- sum(t)
  po <- sum(diag(t)) / n
  pe <- sum(rowSums(t) * colSums(t)) / n^2
  if (pe == 1) return(NA)
  (po - pe) / (1 - pe)
}

interpreteaza_kappa <- function(k) {
  if (is.na(k)) return("nu se poate calcula încă")
  if (k < 0) return("acord mai slab decât întâmplarea")
  if (k <= 0.20) return("acord slab")
  if (k <= 0.40) return("acord modest")
  if (k <= 0.60) return("acord moderat")
  if (k <= 0.80) return("acord substanțial")
  "acord aproape perfect"
}

# ---------------------------------------------------------------------
# 5. EVIDENȚIEREA CUVINTELOR-CHEIE ÎN TITLU / ABSTRACT
# ---------------------------------------------------------------------
regex_cuvinte <- function(txt) {
  kw <- trimws(unlist(strsplit(txt, "[,;\n]")))
  kw <- kw[nzchar(kw)]
  if (!length(kw)) return(NULL)
  kw <- gsub("([][{}()+?.\\\\^$|])", "\\\\\\1", kw, perl = TRUE)
  kw <- gsub("\\*", "\\\\w*", kw)               # random* -> randomized, randomised...
  paste0("(*UCP)\\b(", paste(kw, collapse = "|"), ")\\b")
}

evidentiaza <- function(text, kw_inc, kw_exc) {
  t <- htmltools::htmlEscape(text)
  p <- regex_cuvinte(kw_inc)
  if (!is.null(p)) t <- gsub(p, "\u0001\\1\u0002", t, ignore.case = TRUE, perl = TRUE)
  p <- regex_cuvinte(kw_exc)
  if (!is.null(p)) t <- gsub(p, "\u0003\\1\u0004", t, ignore.case = TRUE, perl = TRUE)
  t <- gsub("\u0001", "<mark class='inc'>", t, fixed = TRUE)
  t <- gsub("\u0003", "<mark class='exc'>", t, fixed = TRUE)
  t <- gsub("[\u0002\u0004]", "</mark>", t)
  HTML(t)
}

afiseaza_articol <- function(r, nr, total, s) {
  autori <- r$autori
  if (nchar(autori) > 300) autori <- paste0(substr(autori, 1, 300), " …")
  div(class = "articol",
      div(class = "nr", sprintf("Articolul %d din %d  ·  ID %s  ·  sursa: %s",
                                nr, total, r$id, r$sursa)),
      h3(evidentiaza(r$titlu, s$kw_inc, s$kw_exc)),
      p(class = "meta", autori),
      p(class = "meta", paste(c(r$jurnal, r$an)[nzchar(c(r$jurnal, r$an))], collapse = " · ")),
      p(class = "meta",
        if (nzchar(r$doi)) a(href = paste0("https://doi.org/", r$doi), target = "_blank",
                             paste("DOI:", r$doi)),
        if (nzchar(r$pmid)) span(" · ", a(href = paste0("https://pubmed.ncbi.nlm.nih.gov/", r$pmid),
                                          target = "_blank", paste("PMID:", r$pmid)))),
      h4("Abstract"),
      div(class = "abstract",
          if (nzchar(r$abstract)) evidentiaza(r$abstract, s$kw_inc, s$kw_exc)
          else em("(acest articol nu are abstract — decide după titlu sau marchează NESIGUR)"))
  )
}

# ---------------------------------------------------------------------
# 5b. PROTOCOLUL REVIEW-ULUI (criterii de includere / excludere)
# ---------------------------------------------------------------------
# Protocolul se scrie (sau se lipește) ca text simplu, de exemplu:
#
#   In functie de populatie
#   Inclusion: Pacienți adulți
#   Exclusion: Studii pe animale
#   Clarificare: adult = 18 ani sau mai mult
#
# - rândurile care încep cu „Inclusion / Includere / Inclus:” = criterii de includere
# - rândurile care încep cu „Exclusion / Excludere / Exclus:” = criterii de excludere
# - rândurile care încep cu „Clarificare / Notă / Definiție:” = precizări
# - orice alt rând = titlul unei categorii (ex. „Populație”, „Design”)
parseaza_protocol <- function(txt) {
  gol <- data.frame(categorie = character(0), tip = character(0), text = character(0),
                    stringsAsFactors = FALSE)
  if (is.null(txt) || !nzchar(trimws(txt))) return(gol)
  linii <- trimws(unlist(strsplit(txt, "\n")))
  linii <- sub("^[•*·]\\s*", "", linii)                # elimin buline
  linii <- linii[nzchar(linii)]
  tipare <- c(
    inc  = "^(criteri[iua]+ de )?(inclusion|includere|inclus|include)( criteria| criterii| criteriu)?\\s*[:–-]\\s*",
    exc  = "^(criteri[iua]+ de )?(exclusion|excludere|exclus|exclude)( criteria| criterii| criteriu)?\\s*[:–-]\\s*",
    nota = "^(clarific[a-zăâîșțţş]*|not[ăa]|note|precizare|precizări|definiți[ie]|definiti[ie]|observați[ie])( aspecte)?\\s*[:–-]?\\s*"
  )
  cat_curenta <- "General"
  rez <- gol
  for (l in linii) {
    tip <- NA
    for (t in names(tipare)) if (grepl(tipare[[t]], l, ignore.case = TRUE, perl = TRUE)) { tip <- t; break }
    if (is.na(tip)) {
      cat_curenta <- trimws(sub(":\\s*$", "", sub("^#+\\s*", "", l)))
      next
    }
    text <- trimws(sub(tipare[[tip]], "", l, ignore.case = TRUE, perl = TRUE))
    if (tip == "nota" && !nzchar(text)) next
    rez <- rbind(rez, data.frame(categorie = if (tip == "nota") "Clarificări" else cat_curenta,
                                 tip = tip, text = text, stringsAsFactors = FALSE))
  }
  rez
}

# Motivele de excludere = criteriile de excludere din protocol (grupate pe categorii).
# Dacă protocolul nu are criterii de excludere, se folosește lista generală.
alegeri_motive <- function(s) {
  pr <- parseaza_protocol(s$protocol)
  ex <- pr[pr$tip == "exc", , drop = FALSE]
  if (!nrow(ex)) return(c("(fără motiv)" = "", SET_IMPLICIT$motive))
  grupe <- lapply(split(ex, factor(ex$categorie, unique(ex$categorie))), function(d) {
    v <- paste0(d$categorie, ": ", d$text)
    setNames(v, d$text)
  })
  c(list("(fără motiv)" = ""), grupe, list("Altele" = c("Altul (vezi nota)" = "Altul (vezi nota)")))
}

# Afișarea protocolului (în screening, conflicte și tab-ul „Protocol”)
protocol_ui <- function(s, deschis = TRUE) {
  pr <- parseaza_protocol(s$protocol)
  if (!nrow(pr))
    return(p(class = "scurtaturi", "Niciun protocol salvat. Îl poți adăuga în tab-ul «1. Import & setări»."))
  categorii <- unique(pr$categorie)
  blocuri <- lapply(categorii, function(c) {
    d <- pr[pr$categorie == c, , drop = FALSE]
    div(class = "crit-cat",
        div(class = "crit-titlu", c),
        lapply(seq_len(nrow(d)), function(i) {
          simbol <- switch(d$tip[i], inc = "✔", exc = "✘", nota = "ℹ")
          div(class = paste0("crit crit-", d$tip[i]), span(class = "crit-simbol", simbol), d$text[i])
        }))
  })
  tags$details(open = if (deschis) NA else NULL, class = "protocol",
               tags$summary(strong("Criterii de eligibilitate (protocol)")),
               blocuri)
}

# ---------------------------------------------------------------------
# 6. INTERFAȚA (UI)
# ---------------------------------------------------------------------
CSS <- "
  .bara-rol { background:#f4f6f9; border-bottom:1px solid #dde; padding:10px 15px 0; margin:-20px -15px 15px; }
  .articol h3 { margin-top:5px; line-height:1.35; }
  .articol .nr { color:#777; font-size:12px; }
  .meta { color:#555; margin-bottom:3px; }
  .abstract { font-size:15.5px; line-height:1.6; text-align:justify; background:#fff;
              border:1px solid #e3e3e3; border-radius:6px; padding:14px; }
  mark.inc { background:#c8f7c5; padding:0 2px; }
  mark.exc { background:#ffc9c9; padding:0 2px; }
  .butoane .btn { width:100%; margin-bottom:8px; font-weight:bold; }
  .eticheta { display:inline-block; padding:2px 8px; border-radius:4px; color:#fff; font-weight:bold; }
  .e-include { background:#28a745; } .e-exclude { background:#dc3545; } .e-maybe { background:#e0a800; }
  .opinie { border:1px solid #ddd; border-radius:6px; padding:8px; margin-bottom:8px; background:#fff; }
  .prog { padding-top:25px; }
  progress { width:100%; height:14px; }
  .scurtaturi { color:#777; font-size:12px; }
  .protocol { background:#fff; border:1px solid #ddd; border-radius:6px; padding:8px 10px; margin-top:10px;
              max-height:420px; overflow-y:auto; font-size:13px; }
  .protocol summary { cursor:pointer; }
  .crit-cat { margin-top:8px; }
  .crit-titlu { font-weight:bold; color:#333; border-bottom:1px solid #eee; margin-bottom:3px; }
  .crit { padding:1px 0 1px 20px; text-indent:-16px; }
  .crit-simbol { display:inline-block; width:16px; text-indent:0; font-weight:bold; }
  .crit-inc .crit-simbol { color:#28a745; } .crit-exc .crit-simbol { color:#dc3545; }
  .crit-nota { color:#555; font-style:italic; } .crit-nota .crit-simbol { color:#17a2b8; }
"

# Scurtături de tastatură: I = inclus, E = exclus, N = nesigur, săgeți = navigare
JS <- "
$(document).on('keydown', function(e) {
  var t = e.target.tagName;
  if (t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT' || e.target.isContentEditable) return;
  if (e.ctrlKey || e.altKey || e.metaKey) return;
  var k = e.key.toLowerCase();
  if (['i','e','n','arrowleft','arrowright'].indexOf(k) >= 0) {
    Shiny.setInputValue('tasta', {k: k, t: Date.now()});
  }
});
"

eticheta_ui <- function(dec) {
  if (!nzchar(dec)) return(span(class = "eticheta", style = "background:#999", "—"))
  span(class = paste0("eticheta e-", dec), et(dec))
}

ui <- navbarPage(
  title = "Screening titlu & abstract",
  id = "tab",
  header = tagList(
    tags$head(tags$style(HTML(CSS)), tags$script(HTML(JS))),
    uiOutput("avertisment_drive"),
    div(class = "bara-rol",
        fluidRow(
          column(3, selectInput("proiect", "Screening-ul la care lucrez", choices = NULL)),
          column(2, selectInput("rol", "Rolul meu", ROLURI)),
          column(2, textInput("nume", "Numele meu", placeholder = "ex. Ana Popescu")),
          column(5, uiOutput("progres_scurt"))
        ))
  ),

  # ---- Tab 0: Screening-uri ----
  tabPanel("0. Screening-uri", value = "proiecte",
    fluidRow(
      column(7,
        h3("Screening-urile tale"),
        p("Fiecare screening are articolele, protocolul și deciziile lui, salvate într-un folder cu numele lui, în: ",
          code(DIR_BAZA)),
        p("Screening-ul la care lucrezi se alege din bara de sus. Toți colegii trebuie să aleagă același screening."),
        tableOutput("tabel_proiecte")
      ),
      column(5,
        wellPanel(
          h4("Creează un screening nou"),
          textInput("nume_proiect_nou", NULL, placeholder = "ex. BCI post-AVC 2026", width = "100%"),
          actionButton("b_creeaza", "Creează", class = "btn-primary")
        ),
        wellPanel(
          h4("Șterge un screening"),
          p(class = "scurtaturi", "Se șterg articolele, protocolul și toate deciziile lui. ",
            "Pe Google Drive ajung în Coș (Trash), de unde se mai pot recupera 30 de zile."),
          selectInput("proiect_sters", NULL, choices = NULL, width = "100%"),
          actionButton("b_sterge", "Șterge...", class = "btn-danger")
        )
      )
    )
  ),

  # ---- Tab 1: Import & setări ----
  tabPanel("1. Import & setări", value = "import",
    fluidRow(
      column(6,
        h3("Importă articolele"),
        p("Formate acceptate: ", strong("CSV"), " (PubMed, Scopus, Rayyan, Zotero, Excel salvat ca CSV), ",
          strong("RIS"), " (Scopus, Embase, Zotero, Mendeley, Cochrane), ",
          strong("PubMed .nbib/.txt"), " (format MEDLINE — singurul export PubMed care conține abstractul), ",
          strong("Web of Science"), " (tab-delimited .txt)."),
        p(strong("Alege exporturile pe rând"), " (PubMed, Scopus, Web of Science, Embase...): ",
          "fiecare fișier ales se adaugă în tabelul de mai jos. Baza de date a fiecărui fișier este recunoscută automat; verifică și corectează în tabel. ",
          strong("Duplicatele"), " dintre baze (același DOI sau același titlu) sunt eliminate automat, ",
          "iar articolul păstrează toate bazele în care a apărut (ex. «PubMed; Scopus»)."),
        fileInput("fisiere", "Alege un fișier (apoi încă unul, și tot așa)", multiple = TRUE,
                  buttonLabel = "Browse...", placeholder = "niciun fișier ales",
                  accept = c(".csv", ".tsv", ".ris", ".nbib", ".txt")),
        uiOutput("pregatire"),
        br(), br(),
        uiOutput("info_import")
      ),
      column(6,
        h3("Setări comune"),
        p(class = "scurtaturi", "Setările sunt salvate pentru toată echipa. Stabiliți-le ÎNAINTE de screening."),
        textAreaInput("protocol_txt", "Protocolul review-ului (criterii de includere și excludere)", rows = 14,
                      width = "100%",
                      placeholder = paste("In functie de populatie",
                                          "Inclusion: ...",
                                          "Exclusion: ...",
                                          "",
                                          "In functie de designul studiului",
                                          "Inclusion: ...",
                                          "Exclusion: ...",
                                          "",
                                          "Clarificare: ...", sep = "\n")),
        tags$details(class = "scurtaturi",
          tags$summary("Cum se scrie protocolul?"),
          tags$ul(
            tags$li("Un rând simplu (ex. «In functie de populatie») = titlul unei categorii."),
            tags$li("«Inclusion:» / «Includere:» la început de rând = criteriu de includere."),
            tags$li("«Exclusion:» / «Excludere:» la început de rând = criteriu de excludere."),
            tags$li("«Clarificare:» / «Notă:» / «Definiție:» = precizări (ex. definiția fazei cronice)."),
            tags$li("Criteriile de excludere devin automat lista de «Motive de excludere» la screening.")
          )),
        h4("Așa a înțeles aplicația protocolul:"),
        uiOutput("protocol_previzualizare"),
        br(),
        textAreaInput("kw_inc_txt", "Cuvinte-cheie de evidențiat cu VERDE (criterii de includere, separate prin virgulă; * = orice terminație)",
                      rows = 2, placeholder = "ex. diabet*, metformin, randomi*"),
        textAreaInput("kw_exc_txt", "Cuvinte-cheie de evidențiat cu ROȘU (criterii de excludere)",
                      rows = 2, placeholder = "ex. mice, rat*, in vitro, review"),
        actionButton("b_setari", "Salvează setările", class = "btn-primary")
      )
    )
  ),

  # ---- Tab 2: Screening (recenzorii 1 și 2) ----
  tabPanel("2. Screening", value = "screening",
    conditionalPanel("input.rol == 'ARB'",
      div(class = "alert alert-info",
          "Ești arbitru: tu nu faci screening-ul inițial. Mergi la tab-ul «3. Conflicte» ",
          "după ce recenzorii au terminat (sau pe parcurs).")),
    conditionalPanel("input.rol != 'ARB'",
      fluidRow(
        column(8, uiOutput("articol")),
        column(4,
          wellPanel(
            uiOutput("decizia_mea"),
            div(class = "butoane",
                actionButton("b_inc", "✔  INCLUS  (tasta I)", class = "btn-success btn-lg"),
                actionButton("b_exc", "✘  EXCLUS  (tasta E)", class = "btn-danger btn-lg"),
                actionButton("b_may", "?  NESIGUR  (tasta N)", class = "btn-warning btn-lg")),
            selectInput("motiv", "Motivul excluderii (alege-l ÎNAINTE de «EXCLUS»)", choices = c("(fără motiv)" = "")),
            textAreaInput("nota", "Notă (opțional)", rows = 2),
            hr(),
            fluidRow(
              column(4, actionButton("b_prev", "◀ Înapoi", width = "100%")),
              column(4, actionButton("b_next", "Înainte ▶", width = "100%")),
              column(4, actionButton("b_neev", "Neevaluat", width = "100%",
                                     title = "Sari la primul articol neevaluat"))
            ),
            br(),
            fluidRow(
              column(7, numericInput("mergi", NULL, 1, min = 1, width = "100%")),
              column(5, actionButton("b_mergi", "Mergi la nr.", width = "100%"))
            ),
            p(class = "scurtaturi", "Scurtături: I / E / N pentru decizie, ← → pentru navigare. ",
              "Recenzorii nu văd deciziile celuilalt (screening în orb)."),
            uiOutput("protocol_screening")
          )
        )
      )
    )
  ),

  # ---- Tab 3: Conflicte (arbitrul) ----
  tabPanel("3. Conflicte", value = "conflicte",
    conditionalPanel("input.rol != 'ARB'",
      div(class = "alert alert-warning",
          "Doar arbitrul are acces aici, ca recenzorii să rămână «în orb» (să nu vadă deciziile celuilalt).")),
    conditionalPanel("input.rol == 'ARB'",
      p("Un ", strong("conflict"), " = articol la care cei doi recenzori au decis diferit, ",
        "sau cel puțin unul a ales NESIGUR. Arbitrul dă decizia finală."),
      fluidRow(
        column(9, selectInput("conflict", "Alege conflictul", choices = NULL, width = "100%")),
        column(3, checkboxInput("doar_nerez", "Doar conflictele nerezolvate", TRUE))
      ),
      fluidRow(
        column(8, uiOutput("art_conflict")),
        column(4,
          wellPanel(
            uiOutput("opinii"),
            div(class = "butoane",
                actionButton("a_inc", "✔  INCLUS  (tasta I)", class = "btn-success btn-lg"),
                actionButton("a_exc", "✘  EXCLUS  (tasta E)", class = "btn-danger btn-lg")),
            selectInput("a_motiv", "Motivul excluderii", choices = c("(fără motiv)" = "")),
            textAreaInput("a_nota", "Justificarea arbitrului (opțional)", rows = 3),
            uiOutput("protocol_conflict")
          )
        )
      )
    )
  ),

  # ---- Tab 4: Rezultate ----
  tabPanel("4. Rezultate", value = "rezultate",
    conditionalPanel("input.rol != 'ARB'",
      div(class = "alert alert-warning",
          "Rezultatele comune le vede doar arbitrul (ca recenzorii să nu fie influențați). ",
          "Progresul tău personal apare în bara de sus.")),
    conditionalPanel("input.rol == 'ARB'",
      fluidRow(
        column(6, h3("Rezumat"), uiOutput("sumar")),
        column(6,
          h3("Recenzor 1 (rânduri) vs Recenzor 2 (coloane)"),
          tableOutput("matrice"),
          h3("Motive de excludere (decizia finală)"),
          tableOutput("motive_tabel"))
      ),
      hr(),
      h3("Descarcă"),
      downloadButton("d_tot", "Toate articolele + toate deciziile (CSV)"),
      downloadButton("d_inc_csv", "Doar articolele INCLUSE (CSV)"),
      downloadButton("d_inc_ris", "Doar articolele INCLUSE (RIS → Zotero/Mendeley)"),
      br(), br()
    )
  ),

  # ---- Tab: Protocol ----
  tabPanel("Protocol", value = "protocol",
    fluidRow(column(8,
      h3("Protocolul review-ului"),
      p("Criteriile de eligibilitate stabilite de echipă. Se modifică din tab-ul «1. Import & setări»."),
      uiOutput("protocol_complet")
    ))
  ),

  # ---- Tab 5: Ajutor ----
  tabPanel("Ajutor", value = "ajutor",
    fluidRow(column(8,
      h3("Cum se lucrează"),
      tags$ol(
        tags$li("O singură persoană importă articolele (tab 1) și salvează setările comune. ",
                "Alege pe rând exporturile din toate bazele de date (se adună într-o listă), apoi «Importă»; ",
                "duplicatele dintre baze se elimină automat."),
        tags$li("Tot în tab 1 se lipește ", strong("protocolul"), " (criteriile de includere/excludere). ",
                "El apare lângă fiecare articol, iar criteriile de excludere devin motivele de excludere."),
        tags$li("Recenzorul 1 și Recenzorul 2 își aleg rolul și numele în bara de sus și evaluează fiecare articol ",
                "(tab 2), independent unul de celălalt."),
        tags$li("Arbitrul (rol «Arbitru») vede în tab 3 doar articolele unde recenzorii nu au fost de acord ",
                "sau unde cineva a ales NESIGUR, și dă decizia finală."),
        tags$li("În tab 4 arbitrul vede statistica (acord, kappa Cohen, cifrele pentru diagrama PRISMA) ",
                "și descarcă lista finală de articole pentru citirea full-text.")
      ),
      h3("Reguli pentru decizia finală"),
      tags$ul(
        tags$li("Ambii INCLUS → inclus. Ambii EXCLUS → exclus."),
        tags$li("Decizii diferite sau cel puțin un NESIGUR → conflict → decide arbitrul.")
      ),
      h3("Unde sunt datele"),
      p("Fiecare screening se salvează automat într-un folder cu numele lui, în ", code(DIR_BAZA),
        " (articole.csv, setari.rds, decizii_R1.csv, decizii_R2.csv, decizii_ARB.csv). ",
        "Fă din când în când o copie de siguranță a acestui folder.")
    ))
  )
)

# ---------------------------------------------------------------------
# 7. LOGICA (SERVER)
# ---------------------------------------------------------------------
server <- function(input, output, session) {

  # ---------- Screening-uri (proiecte) ----------
  versiune_p <- reactiveVal(0)
  proiecte_poll <- reactivePoll(4000, session,
    checkFunc = function() {
      d <- list.dirs(DIR_BAZA, recursive = FALSE)
      paste(c(d, file.exists(file.path(d, MARCAJ)), file.exists(file.path(DIR_BAZA, FISIERE_DATE))), collapse = "|")
    },
    valueFunc = function() Sys.time())
  proiecte <- reactive({ proiecte_poll(); versiune_p(); lista_proiecte() })

  observe({
    p <- proiecte()
    sel <- isolate(input$proiect)
    if (!length(p)) {
      updateSelectInput(session, "proiect", choices = c("(niciun screening — creează unul în tab-ul 0)" = ""))
      updateSelectInput(session, "proiect_sters", choices = c("(nimic de șters)" = ""))
      return()
    }
    if (is.null(sel) || !(sel %in% p)) sel <- p[[1]]
    updateSelectInput(session, "proiect", choices = p, selected = sel)
    updateSelectInput(session, "proiect_sters", choices = p, selected = isolate(input$proiect_sters))
  })

  dir_p <- reactive({
    d <- input$proiect
    if (is.null(d) || !nzchar(d) || !dir.exists(d)) NULL else d
  })
  stare <- new.env()
  observe(stare$dir <- dir_p())

  cere_proiect <- function() {
    if (is.null(dir_p())) {
      showNotification("Creează sau alege întâi un screening (tab-ul «0. Screening-uri»).", type = "error")
      return(FALSE)
    }
    TRUE
  }

  observeEvent(input$b_creeaza, {
    tryCatch({
      dir <- creeaza_proiect(input$nume_proiect_nou)
      versiune_p(versiune_p() + 1)
      updateSelectInput(session, "proiect", choices = lista_proiecte(), selected = dir)
      updateTextInput(session, "nume_proiect_nou", value = "")
      showNotification(paste("Am creat screening-ul", basename(dir)), type = "message")
      updateNavbarPage(session, "tab", selected = "import")
    }, error = function(e) showNotification(conditionMessage(e), type = "error"))
  })

  observeEvent(input$b_sterge, {
    d <- input$proiect_sters; req(nzchar(d))
    nume <- names(proiecte())[proiecte() == d][1]
    showModal(modalDialog(
      title = "Ștergi screening-ul?",
      p("Se vor șterge articolele, protocolul și toate deciziile din ", strong(nume), "."),
      textInput("confirm_sters", "Ca să confirmi, scrie STERGE:"),
      footer = tagList(modalButton("Anulează"),
                       actionButton("b_sterge_ok", "Șterge definitiv", class = "btn-danger"))))
  })
  observeEvent(input$b_sterge_ok, {
    if (!identical(toupper(trimws(input$confirm_sters)), "STERGE")) {
      showNotification("Scrie STERGE ca să confirmi.", type = "error"); return()
    }
    tryCatch({
      sterge_proiect(input$proiect_sters)
      removeModal()
      versiune_p(versiune_p() + 1)
      showNotification("Screening-ul a fost șters.", type = "message")
    }, error = function(e) showNotification(conditionMessage(e), type = "error"))
  })

  output$tabel_proiecte <- renderTable({
    p <- proiecte(); semnal()
    if (!length(p)) return(data.frame(Mesaj = "Încă nu ai niciun screening. Creează unul în dreapta."))
    r <- t(sapply(p, rezumat_proiect))
    data.frame(Screening = names(p), r, "Ultima modificare" =
                 format(as.POSIXct(sapply(p, ultima_modificare), origin = "1970-01-01"), "%Y-%m-%d %H:%M"),
               check.names = FALSE)
  }, digits = 0)

  output$avertisment_drive <- renderUI({
    invalidateLater(20000)
    if (!drive_nemontat(DIR_BAZA)) return(NULL)
    div(class = "alert alert-danger", style = "margin:0 0 10px 0",
        strong("⚠ Google Drive NU este montat. "),
        "Ce salvezi acum rămâne doar pe acest laptop și nu ajunge la colegi. ",
        "Închide aplicația și pornește-o din iconița «Pornește Screening» (care montează întâi Drive-ul).")
  })

  # Re-citește fișierele când se modifică (ex. alt recenzor salvează o decizie)
  semnal <- reactivePoll(2000, session,
                         checkFunc = function() {
                           if (is.null(stare$dir)) return("")
                           f <- file.path(stare$dir, FISIERE_DATE)
                           paste(stare$dir, file.mtime(f), file.size(f))
                         },
                         valueFunc = function() Sys.time())
  versiune <- reactiveVal(0)   # crește după fiecare salvare făcută de mine

  date <- reactive({
    semnal(); versiune()
    d <- dir_p()
    if (is.null(d))
      return(list(art = tabel_gol(COL_ART), set = SET_IMPLICIT,
                  R1 = tabel_gol(COL_DEC), R2 = tabel_gol(COL_DEC), ARB = tabel_gol(COL_DEC)))
    list(art = citeste_csv(F_ART(d), COL_ART),
         set = citeste_setari(d),
         R1  = citeste_csv(F_DEC(d, "R1"),  COL_DEC),
         R2  = citeste_csv(F_DEC(d, "R2"),  COL_DEC),
         ARB = citeste_csv(F_DEC(d, "ARB"), COL_DEC))
  })
  art    <- reactive(date()$art)
  tabel  <- reactive(combina(date()))
  deciziile_mele <- reactive({
    if (input$rol == "ARB") NULL else date()[[input$rol]]
  })

  verifica_nume <- function() {
    if (!nzchar(trimws(input$nume))) {
      showNotification("Scrie-ți întâi numele în bara de sus («Numele meu»).", type = "error")
      return(FALSE)
    }
    TRUE
  }

  # ---------- Setări ----------
  # la schimbarea screening-ului încarc setările lui
  observeEvent(dir_p(), {
    s0 <- citeste_setari(dir_p())
    updateTextAreaInput(session, "protocol_txt", value = s0$protocol)
    updateTextAreaInput(session, "kw_inc_txt", value = s0$kw_inc)
    updateTextAreaInput(session, "kw_exc_txt", value = s0$kw_exc)
    pregatite(NULL)
  }, ignoreNULL = FALSE)

  observeEvent(input$b_setari, {
    if (!cere_proiect()) return()
    s <- citeste_setari(dir_p())
    s$protocol <- input$protocol_txt
    s$kw_inc <- input$kw_inc_txt
    s$kw_exc <- input$kw_exc_txt
    saveRDS(s, F_SET(dir_p()))
    versiune(versiune() + 1)
    showNotification("Setările au fost salvate.", type = "message")
  })

  observe({
    alegeri <- alegeri_motive(date()$set)
    updateSelectInput(session, "motiv",   choices = alegeri, selected = isolate(input$motiv))
    updateSelectInput(session, "a_motiv", choices = alegeri, selected = isolate(input$a_motiv))
  })

  # ---------- Protocol ----------
  output$protocol_previzualizare <- renderUI({
    pr <- parseaza_protocol(input$protocol_txt)
    if (!nrow(pr)) return(p(class = "scurtaturi", "(încă nimic — scrie sau lipește protocolul mai sus)"))
    tagList(
      p(class = "scurtaturi", sprintf("%d categorii · %d criterii de includere · %d criterii de excludere · %d clarificări",
                                      length(unique(pr$categorie[pr$tip != "nota"])), sum(pr$tip == "inc"),
                                      sum(pr$tip == "exc"), sum(pr$tip == "nota"))),
      protocol_ui(list(protocol = input$protocol_txt)),
      p(class = "scurtaturi", "Nu uita să apeși «Salvează setările».")
    )
  })
  output$protocol_screening <- renderUI(protocol_ui(date()$set))
  output$protocol_conflict  <- renderUI(protocol_ui(date()$set))
  output$protocol_complet   <- renderUI(protocol_ui(date()$set))

  # ---------- Import ----------
  # Pas 1: fișierele alese sunt citite și li se recunoaște baza de date
  pregatite <- reactiveVal(NULL)
  nr_incarcare <- reactiveVal(0)
  observeEvent(input$fisiere, {
    # fișierele se ADAUGĂ la listă: le poți alege pe rând, câte unul
    f <- input$fisiere
    nr_incarcare(nr_incarcare() + 1)
    noi <- lapply(seq_len(nrow(f)), function(i) {
      d <- tryCatch(citeste_fisier(f$datapath[i], f$name[i]), error = function(e) conditionMessage(e))
      list(nume = f$name[i], date = d, baza = detecteaza_baza(f$datapath[i], f$name[i]),
           id = sprintf("baza_%d_%d", nr_incarcare(), i))
    })
    vechi <- pregatite()
    vechi <- Filter(function(x) !(x$nume %in% f$name), vechi)   # același fișier ales din nou -> îl înlocuiesc
    pregatite(c(vechi, noi))
  })
  observeEvent(input$b_goleste, pregatite(NULL))

  output$pregatire <- renderUI({
    p <- pregatite()
    if (is.null(p)) return(NULL)
    deja <- isolate(date()$set$istoric$Fisier)
    randuri <- lapply(p, function(x) {
      ok <- is.data.frame(x$date)
      ales <- isolate(input[[x$id]])                    # păstrez ce ai corectat deja
      if (is.null(ales) || !nzchar(ales)) ales <- x$baza
      tags$tr(
        tags$td(x$nume,
                if (x$nume %in% deja)
                  div(style = "color:#b36b00; font-size:12px",
                      "⚠ un fișier cu acest nume a mai fost importat — dacă e același export, ",
                      "nu-l importa din nou (cifrele PRISMA s-ar număra de două ori)")),
        tags$td(if (ok) nrow(x$date) else span(style = "color:#c00", "eroare")),
        tags$td(if (ok) selectizeInput(x$id, NULL, choices = unique(c(ales, x$baza, BAZE)), selected = ales,
                                       options = list(create = TRUE), width = "200px")
                else span(style = "color:#c00", x$date))
      )
    })
    nok <- sum(sapply(p, function(x) is.data.frame(x$date)))
    tagList(
      tags$table(class = "table table-condensed",
                 tags$thead(tags$tr(tags$th("Fișier"), tags$th("Înregistrări"), tags$th("Baza de date"))),
                 tags$tbody(randuri)),
      p(class = "scurtaturi", "Poți scrie și alt nume de bază de date decât cele din listă."),
      p(strong("Mai ai și alte exporturi?"), " Apasă din nou «Browse...» și alege următorul fișier — ",
        "se adaugă în tabel. Când ai toate fișierele în tabel, apasă «Importă»."),
      if (nok) actionButton("b_import", sprintf("Importă %d fișier(e)", nok), class = "btn-primary"),
      actionButton("b_goleste", "Golește lista")
    )
  })

  # Pas 2: import efectiv, fișier cu fișier (deduplicare și între fișiere)
  observeEvent(input$b_import, {
    p <- pregatite(); req(p)
    if (!cere_proiect()) return()
    dir <- dir_p()
    p <- Filter(function(x) is.data.frame(x$date), p)
    tryCatch({
      existente <- citeste_csv(F_ART(dir), COL_ART)
      s <- citeste_setari(dir)
      if (is.null(s$pe_baze)) s$pe_baze <- list()
      jurnal <- NULL
      for (x in p) {
        baza <- trimws(input[[x$id]])
        if (!length(baza) || !nzchar(baza)) baza <- x$baza
        d <- x$date
        d$sursa <- rep(baza, nrow(d))
        r <- adauga_articole(d, existente)
        existente <- r$articole
        n <- nrow(d) - r$goale
        s$identificate <- s$identificate + n
        s$duplicate <- s$duplicate + r$duplicate
        s$pe_baze[[baza]] <- (if (is.null(s$pe_baze[[baza]])) 0 else s$pe_baze[[baza]]) + n
        jurnal <- rbind(jurnal, data.frame(
          Data = format(Sys.time(), "%Y-%m-%d %H:%M"), Fisier = x$nume, Baza = baza,
          Inregistrari = n, Noi = r$adaugate, Duplicate = r$duplicate, stringsAsFactors = FALSE))
      }
      scrie_csv(existente, F_ART(dir))
      s$istoric <- rbind(s$istoric, jurnal)
      saveRDS(s, F_SET(dir))
      pregatite(NULL)
      versiune(versiune() + 1)
      showNotification(sprintf("Import terminat: %d înregistrări citite, %d articole noi, %d duplicate.",
                               sum(jurnal$Inregistrari), sum(jurnal$Noi), sum(jurnal$Duplicate)),
                       type = "message", duration = 10)
    }, error = function(e) {
      showNotification(paste("Eroare la import:", conditionMessage(e)), type = "error", duration = 15)
    })
  })

  output$info_import <- renderUI({
    a <- art(); s <- date()$set
    if (!nrow(a)) return(div(class = "alert alert-info", "Încă nu există articole importate."))
    fara_abs <- sum(!nzchar(a$abstract))
    tagList(
      div(class = "alert alert-success",
          sprintf("În proiect sunt %d articole unice (din %d înregistrări importate; %d duplicate eliminate).",
                  nrow(a), s$identificate, s$duplicate)),
      if (fara_abs > 0)
        div(class = "alert alert-warning",
            sprintf("%d articole nu au abstract. Dacă sunt multe, probabil ai exportat din PubMed în format CSV — ", fara_abs),
            "folosește în schimb «Save → Format: PubMed» (fișier .txt), care include abstractele."),
      h4("Articole unice pe baze de date"),
      tableOutput("pe_surse"),
      if (!is.null(s$istoric) && nrow(s$istoric)) tagList(h4("Istoricul importurilor"), tableOutput("istoric"))
    )
  })
  output$istoric <- renderTable(date()$set$istoric)
  output$pe_surse <- renderTable({
    a <- art(); req(nrow(a))
    surse <- lapply(strsplit(a$sursa, ";"), trimws)
    baze <- sort(unique(unlist(surse)))
    s <- date()$set
    d <- data.frame(
      Baza = baze,
      Inregistrari = sapply(baze, function(b) if (is.null(s$pe_baze[[b]])) NA else s$pe_baze[[b]]),
      Unice_gasite = sapply(baze, function(b) sum(sapply(surse, function(x) b %in% x))),
      Doar_aici = sapply(baze, function(b) sum(sapply(surse, function(x) identical(x, b)))),
      stringsAsFactors = FALSE)
    names(d) <- c("Baza de date", "Înregistrări importate", "Articole unice găsite", "Găsite DOAR aici")
    d <- rbind(d, data.frame(check.names = FALSE, "Baza de date" = "Găsite în ≥ 2 baze",
                             "Înregistrări importate" = NA,
                             "Articole unice găsite" = sum(lengths(surse) > 1),
                             "Găsite DOAR aici" = NA))
    d
  }, digits = 0, na = "")

  # ---------- Bara de progres ----------
  output$progres_scurt <- renderUI({
    a <- art(); n <- nrow(a)
    if (!n) return(div(class = "prog", "Niciun articol importat încă → tab-ul «1. Import & setări»."))
    if (input$rol == "ARB") {
      t <- tabel()
      nc <- sum(t$stare == "conflict"); nr <- sum(t$stare == "conflict" & !nzchar(t$ARB))
      return(div(class = "prog",
                 sprintf("Recenzor 1: %d/%d  ·  Recenzor 2: %d/%d  ·  Conflicte: %d (nerezolvate: %d)",
                         sum(nzchar(t$R1)), n, sum(nzchar(t$R2)), n, nc, nr)))
    }
    k <- sum(a$id %in% deciziile_mele()$id)
    div(class = "prog",
        sprintf("Progresul tău: %d / %d articole (%.0f%%)", k, n, 100 * k / n),
        tags$progress(value = k, max = n))
  })

  # ---------- Screening ----------
  idx <- reactiveVal(1)
  id_curent <- reactiveVal(NULL)
  observe({
    a <- art()
    id_curent(if (nrow(a)) a$id[min(idx(), nrow(a))] else NULL)
  })

  urmatorul_neevaluat <- function(dupa, d) {
    a <- isolate(art())
    ne <- which(!(a$id %in% d$id))
    if (!length(ne)) return(NA)
    x <- ne[ne > dupa]
    if (length(x)) x[1] else ne[1]
  }

  observeEvent(list(input$rol, dir_p()), {
    if (input$rol == "ARB") return()
    i <- urmatorul_neevaluat(0, isolate(deciziile_mele()))
    idx(if (is.na(i)) 1 else i)
  })

  output$articol <- renderUI({
    a <- art()
    if (!nrow(a)) return(div(class = "alert alert-info", "Importă întâi articolele (tab 1)."))
    i <- min(idx(), nrow(a))
    afiseaza_articol(a[i, ], i, nrow(a), date()$set)
  })

  output$decizia_mea <- renderUI({
    d <- deciziile_mele(); id <- id_curent()
    if (is.null(d) || is.null(id)) return(NULL)
    r <- d[d$id == id, ]
    if (!nrow(r)) return(p("Decizia ta: ", eticheta_ui(""), " (neevaluat)"))
    p("Decizia ta: ", eticheta_ui(r$decizie[1]),
      if (nzchar(r$motiv[1])) span(" – ", r$motiv[1]),
      br(), span(class = "scurtaturi", "salvată la ", r$data[1], " · poți s-o schimbi oricând"))
  })

  # Când trec la alt articol, completez motivul/nota salvate anterior (dacă există)
  observeEvent(list(id_curent(), input$rol), {
    d <- isolate(deciziile_mele()); id <- id_curent()
    r <- if (!is.null(d) && !is.null(id)) d[d$id == id, ] else NULL
    are <- !is.null(r) && nrow(r) > 0
    updateSelectInput(session, "motiv", selected = if (are) r$motiv[1] else "")
    updateTextAreaInput(session, "nota", value = if (are) r$nota[1] else "")
  })

  decide <- function(dec) {
    if (input$rol == "ARB" || !cere_proiect() || !verifica_nume()) return()
    a <- art(); if (!nrow(a)) return()
    i <- min(idx(), nrow(a))
    salveaza_decizie(dir_p(), input$rol, a$id[i], dec,
                     if (dec == "exclude") input$motiv else "",
                     input$nota, trimws(input$nume))
    versiune(versiune() + 1)
    d <- citeste_csv(F_DEC(dir_p(), input$rol), COL_DEC)
    nxt <- urmatorul_neevaluat(i, d)
    if (is.na(nxt)) {
      showNotification("Ai evaluat toate articolele! Mulțumim. 🎉", type = "message", duration = 10)
    } else {
      idx(nxt)
    }
  }
  observeEvent(input$b_inc, decide("include"))
  observeEvent(input$b_exc, decide("exclude"))
  observeEvent(input$b_may, decide("maybe"))

  observeEvent(input$b_prev, idx(max(1, idx() - 1)))
  observeEvent(input$b_next, idx(min(max(1, nrow(art())), idx() + 1)))
  observeEvent(input$b_mergi, {
    n <- nrow(art()); req(n, input$mergi)
    idx(max(1, min(n, as.integer(input$mergi))))
  })
  observeEvent(input$b_neev, {
    i <- urmatorul_neevaluat(idx(), deciziile_mele())
    if (is.na(i)) showNotification("Nu mai ai articole neevaluate.") else idx(i)
  })

  # ---------- Conflicte (arbitru) ----------
  observe({
    t <- tabel()
    c <- t[t$stare == "conflict", , drop = FALSE]
    if (isTRUE(input$doar_nerez)) c <- c[!nzchar(c$ARB), , drop = FALSE]
    if (!nrow(c)) {
      updateSelectInput(session, "conflict",
                        choices = c("Nu există conflicte de rezolvat în acest moment" = ""))
      return()
    }
    alegeri <- setNames(c$id, sprintf("%s · %s · R1: %s / R2: %s%s",
                                      c$id, substr(c$titlu, 1, 80), et(c$R1), et(c$R2),
                                      ifelse(nzchar(c$ARB), paste0("  → FINAL: ", et(c$ARB)), "")))
    sel <- isolate(input$conflict)
    if (is.null(sel) || !(sel %in% c$id)) sel <- c$id[1]
    updateSelectInput(session, "conflict", choices = alegeri, selected = sel)
  })

  rand_conflict <- reactive({
    req(input$conflict)
    t <- tabel()
    r <- t[t$id == input$conflict, , drop = FALSE]
    req(nrow(r))
    r
  })

  output$art_conflict <- renderUI({
    r <- rand_conflict()
    afiseaza_articol(r, match(r$id, art()$id), nrow(art()), date()$set)
  })

  output$opinii <- renderUI({
    r <- rand_conflict()
    opinie <- function(rol, titlu) {
      div(class = "opinie",
          strong(titlu), if (nzchar(r[[paste0(rol, "_nume")]])) span(" (", r[[paste0(rol, "_nume")]], ")"), ": ",
          eticheta_ui(r[[rol]]),
          if (nzchar(r[[paste0(rol, "_motiv")]])) div("Motiv: ", r[[paste0(rol, "_motiv")]]),
          if (nzchar(r[[paste0(rol, "_nota")]])) div(em("Notă: ", r[[paste0(rol, "_nota")]])))
    }
    tagList(opinie("R1", "Recenzor 1"), opinie("R2", "Recenzor 2"),
            if (nzchar(r$ARB)) opinie("ARB", "Decizia ta (arbitru)"))
  })

  observeEvent(input$conflict, {
    d <- isolate(date()$ARB)
    r <- d[d$id == input$conflict, ]
    are <- nrow(r) > 0
    updateSelectInput(session, "a_motiv", selected = if (are) r$motiv[1] else "")
    updateTextAreaInput(session, "a_nota", value = if (are) r$nota[1] else "")
  })

  decide_arbitru <- function(dec) {
    if (input$rol != "ARB" || !cere_proiect() || !verifica_nume()) return()
    id <- input$conflict
    if (is.null(id) || !nzchar(id)) return()
    salveaza_decizie(dir_p(), "ARB", id, dec, if (dec == "exclude") input$a_motiv else "",
                     input$a_nota, trimws(input$nume))
    versiune(versiune() + 1)
    showNotification(sprintf("Decizie finală salvată pentru %s: %s", id, et(dec)), type = "message")
  }
  observeEvent(input$a_inc, decide_arbitru("include"))
  observeEvent(input$a_exc, decide_arbitru("exclude"))

  # ---------- Tastatură ----------
  observeEvent(input$tasta, {
    k <- input$tasta$k
    if (input$tab == "screening" && input$rol != "ARB") {
      switch(k,
             i = decide("include"), e = decide("exclude"), n = decide("maybe"),
             arrowleft  = idx(max(1, idx() - 1)),
             arrowright = idx(min(max(1, nrow(art())), idx() + 1)))
    } else if (input$tab == "conflicte" && input$rol == "ARB") {
      switch(k, i = decide_arbitru("include"), e = decide_arbitru("exclude"))
    }
  })

  # ---------- Rezultate ----------
  output$sumar <- renderUI({
    t <- tabel(); s <- date()$set; n <- nrow(t)
    req(n)
    ambii <- t[t$stare != "neterminat", , drop = FALSE]
    k <- kappa_cohen(ambii$R1, ambii$R2)
    nconf <- sum(t$stare == "conflict")
    rand <- function(et, val) tags$tr(tags$td(et), tags$td(strong(val)))
    tagList(
      tags$table(class = "table table-condensed",
        rand("Evaluate de Recenzorul 1", sprintf("%d / %d", sum(nzchar(t$R1)), n)),
        rand("Evaluate de Recenzorul 2", sprintf("%d / %d", sum(nzchar(t$R2)), n)),
        rand("Evaluate de amândoi", nrow(ambii)),
        rand("Acord direct (ambii INCLUS sau ambii EXCLUS)",
             sprintf("%d (%.1f%%)", sum(t$stare == "acord"), 100 * mean(ambii$R1 == ambii$R2 & ambii$R1 != "maybe"))),
        rand("Acord brut (aceeași decizie, inclusiv NESIGUR)",
             if (nrow(ambii)) sprintf("%.1f%%", 100 * mean(ambii$R1 == ambii$R2)) else "–"),
        rand("Kappa Cohen", if (is.na(k)) "–" else sprintf("%.3f (%s)", k, interpreteaza_kappa(k))),
        rand("Conflicte", nconf),
        rand("   – rezolvate de arbitru", sum(t$stare == "conflict" & nzchar(t$ARB))),
        rand("   – încă nerezolvate", sum(t$stare == "conflict" & !nzchar(t$ARB))),
        rand("FINAL: INCLUSE (merg la full-text)", sum(t$final == "include")),
        rand("FINAL: EXCLUSE", sum(t$final == "exclude")),
        rand("În așteptare (neterminate / nerezolvate)", sum(!nzchar(t$final)))
      ),
      h4("Cifre pentru diagrama PRISMA 2020"),
      tags$ul(
        tags$li(sprintf("Înregistrări identificate din baze de date: %d", s$identificate),
                if (length(s$pe_baze))
                  tags$ul(lapply(names(s$pe_baze), function(b) tags$li(sprintf("%s (n = %d)", b, s$pe_baze[[b]]))))),
        tags$li(sprintf("Duplicate eliminate: %d", s$duplicate)),
        tags$li(sprintf("Înregistrări screenate (titlu & abstract): %d", n)),
        tags$li(sprintf("Înregistrări excluse: %d", sum(t$final == "exclude"))),
        tags$li(sprintf("Rapoarte căutate pentru evaluarea full-text: %d", sum(t$final == "include")))
      ),
      if (any(!nzchar(t$final)))
        div(class = "alert alert-warning", "Atenție: screening-ul nu este încă terminat — cifrele se vor mai schimba.")
    )
  })

  output$matrice <- renderTable({
    t <- tabel()
    ambii <- t[t$stare != "neterminat", , drop = FALSE]
    req(nrow(ambii))
    niv <- names(ETICHETE)
    m <- table(factor(ambii$R1, niv, ETICHETE), factor(ambii$R2, niv, ETICHETE))
    as.data.frame.matrix(m)
  }, rownames = TRUE, digits = 0)

  output$motive_tabel <- renderTable({
    t <- tabel()
    m <- t$motiv_final[t$final == "exclude"]
    req(length(m))
    m[!nzchar(m)] <- "(fără motiv)"
    x <- sort(table(m), decreasing = TRUE)
    data.frame(Motiv = names(x), Articole = as.integer(x))
  })

  export_tabel <- function(t) {
    for (c in c("R1", "R2", "ARB", "final")) t[[c]] <- et(t[[c]])
    t$final[!nzchar(t$final)] <- "ÎN AȘTEPTARE"
    t[, c("id", "titlu", "autori", "an", "jurnal", "doi", "pmid", "sursa",
          "R1", "R1_motiv", "R1_nota", "R1_nume",
          "R2", "R2_motiv", "R2_nota", "R2_nume",
          "stare", "ARB", "ARB_motiv", "ARB_nota", "ARB_nume",
          "final", "motiv_final", "abstract")]
  }
  ziua <- function() format(Sys.Date(), "%Y-%m-%d")

  output$d_tot <- downloadHandler(
    filename = function() paste0("screening_complet_", ziua(), ".csv"),
    content  = function(f) scrie_csv(export_tabel(tabel()), f))
  output$d_inc_csv <- downloadHandler(
    filename = function() paste0("articole_incluse_", ziua(), ".csv"),
    content  = function(f) { t <- tabel(); scrie_csv(export_tabel(t[t$final == "include", ]), f) })
  output$d_inc_ris <- downloadHandler(
    filename = function() paste0("articole_incluse_", ziua(), ".ris"),
    content  = function(f) { t <- tabel(); scrie_ris(t[t$final == "include", ], f) })
}

shinyApp(ui, server)
