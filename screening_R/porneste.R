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
if (!requireNamespace("shiny", quietly = TRUE)) {
  message("Instalez pachetul «shiny» (doar prima dată, durează câteva minute)...")
  install.packages("shiny", repos = "https://cloud.r-project.org")
}

# Unde se salvează datele: folderul de deasupra lui «screening_R»
# (dacă variabila SCREENING_DIR e deja setată, se folosește aceea)
if (!nzchar(Sys.getenv("SCREENING_DIR"))) Sys.setenv(SCREENING_DIR = dirname(aici))
message("Datele se salvează în: ", Sys.getenv("SCREENING_DIR"))

shiny::runApp(aici, launch.browser = TRUE)
