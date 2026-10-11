# =====================================================================
#  PORNEȘTE APLICAȚIA DE SCREENING
#
#  În RStudio: deschide acest fișier și apasă butonul «Source» (sus, dreapta).
#  Din terminal: Rscript porneste.R
#
#  Datele (articole, decizii) se salvează în folderul în care se află
#  folderul «screening_R». Dacă «screening_R» stă într-un folder partajat
#  pe Google Drive, toată echipa lucrează automat pe aceleași date.
# =====================================================================

cat("porneste.R a pornit (", R.version.string, ")\n", sep = "")

# Folderul în care se află acest fișier (adică folderul «screening_R»)
aici <- local({
  f <- tryCatch(sys.frame(1)$ofile, error = function(e) NULL)
  if (is.null(f)) {
    a <- grep("^--file=", commandArgs(FALSE), value = TRUE)
    if (length(a)) f <- gsub("~+~", " ", sub("^--file=", "", a[1]), fixed = TRUE)  # Rscript codifică spațiile ca ~+~
  }
  if (is.null(f) && requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable())
    f <- rstudioapi::getSourceEditorContext()$path
  if (is.null(f) || !nzchar(f)) getwd() else dirname(normalizePath(f))
})

if (!file.exists(file.path(aici, "app.R")))
  stop("Nu găsesc app.R lângă porneste.R. Ține cele două fișiere în același folder «screening_R».")

# Instalează pachetul shiny la prima pornire
# (în biblioteca personală a utilizatorului, ca să nu fie nevoie de drepturi de administrator)
if (!requireNamespace("shiny", quietly = TRUE)) {
  message("Instalez pachetul «shiny» (doar prima dată, durează câteva minute)...")
  lib <- strsplit(Sys.getenv("R_LIBS_USER"), .Platform$path.sep)[[1]][1]
  dir.create(lib, recursive = TRUE, showWarnings = FALSE)
  .libPaths(c(lib, .libPaths()))
  install.packages("shiny", lib = lib, repos = "https://cloud.r-project.org")
}

# ---------------------------------------------------------------------
# Unde se salvează datele
#  1. variabila SCREENING_DIR, dacă e setată (ex. de iconița de pe Linux)
#  2. folderul ales anterior (ținut minte în fișierul de configurare)
#  3. pe Windows: la prima pornire se deschide o fereastră în care alegi
#     folderul «Screening» de pe Google Drive
#  4. altfel: folderul de deasupra lui «screening_R»
# Pornit cu argumentul «alege-folder», fereastra de alegere apare din nou.
# ---------------------------------------------------------------------
fisier_config <- file.path(tools::R_user_dir("screening", "config"), "folder_date.txt")
realege <- "alege-folder" %in% commandArgs(trailingOnly = TRUE)

folder_valid <- function(d) length(d) == 1 && !is.na(d) && nzchar(d) && dir.exists(d) && file.access(d, 2) == 0

if (!nzchar(Sys.getenv("SCREENING_DIR"))) {
  ales <- if (!realege && file.exists(fisier_config)) readLines(fisier_config, warn = FALSE, encoding = "UTF-8")[1] else NA
  if (!folder_valid(ales) && .Platform$OS.type == "windows") {
    message("\n>>> Alege în fereastra care s-a deschis folderul «Screening» de pe Google Drive")
    message(">>> (de obicei: Google Drive (G:) -> My Drive -> Screening).")
    message(">>> Dacă nu vezi fereastra, caut-o în spatele celorlalte ferestre.\n")
    ales <- utils::choose.dir(caption = "Alege folderul «Screening» de pe Google Drive")
    if (folder_valid(ales)) {
      dir.create(dirname(fisier_config), recursive = TRUE, showWarnings = FALSE)
      writeLines(ales, fisier_config, useBytes = TRUE)
    }
  }
  if (!folder_valid(ales)) {
    ales <- dirname(aici)
    if (.Platform$OS.type == "windows")
      message("ATENȚIE: nu ai ales niciun folder; datele se salvează local, NU pe Google Drive.")
  }
  Sys.setenv(SCREENING_DIR = ales)
}
message("Datele se salvează în: ", Sys.getenv("SCREENING_DIR"))

# Deschide browserul (pe Linux prin xdg-open, care merge sigur și din terminal)
deschide_browser <- function(url) {
  message("\n>>> Aplicația rulează la adresa: ", url)
  message(">>> Dacă browserul nu se deschide singur, copiază adresa în browser.")
  message(">>> Pentru a opri aplicația, închide această fereastră (sau Ctrl + C).\n")
  if (Sys.info()[["sysname"]] == "Linux" && nzchar(Sys.which("xdg-open"))) {
    system2("xdg-open", url, wait = FALSE, stdout = FALSE, stderr = FALSE)
  } else {
    utils::browseURL(url)
  }
}

message("Pornesc aplicația...")
shiny::runApp(aici, launch.browser = deschide_browser)
