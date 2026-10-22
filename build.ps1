# build.ps1 - assembla i giochi con vasm6502 e pubblica i .bin su GitHub
#
#   .\build.ps1                 tutti i file .asm della cartella
#   .\build.ps1 tank.asm        solo i file indicati
#   .\build.ps1 -NoPublish      crea i .bin senza commit e push
#
# Il percorso di vasm6502_oldstyle.exe si legge dalla variabile VASM
# oppure dalla prima riga del file vasm.path (escluso da git).
# Se esiste il file copy.path (escluso da git), i .asm e i .bin
# assemblati vengono copiati anche nella cartella indicata.
# Con Node.js installato, ogni gioco assemblato viene fatto girare
# nell'emulatore (tools\screenshots.js) e gli screenshot finiscono
# in screenshots\ e su GitHub insieme ai .bin.

param([string[]]$Files, [switch]$NoPublish)

Set-Location $PSScriptRoot

$vasm = $env:VASM
if (-not $vasm -and (Test-Path vasm.path)) { $vasm = (Get-Content vasm.path -TotalCount 1).Trim() }
if (-not $vasm -or -not (Test-Path $vasm)) {
  Write-Host "vasm6502_oldstyle non trovato: scrivi il suo percorso nel file vasm.path" -ForegroundColor Red
  exit 1
}

if (-not $Files) { $Files = (Get-ChildItem *.asm).Name }
New-Item -ItemType Directory -Force bin | Out-Null

# ---------------- assemblaggio ----------------
$built  = @()
$failed = @()
foreach ($f in $Files) {
  $name = [IO.Path]::GetFileNameWithoutExtension($f)
  $out  = "bin\$name.bin"
  Write-Host "== $f -> $out" -ForegroundColor Cyan
  & $vasm -Fbin -dotdir -c02 -quiet -o $out $f
  if ($LASTEXITCODE -ne 0) { $failed += $f } else { $built += $f, $out }
}
if ($failed) {
  Write-Host "ERRORI in: $($failed -join ', ') - niente pubblicato" -ForegroundColor Red
  exit 1
}

# ---------------- copia nella cartella locale ----------------
if (Test-Path copy.path) {
  $dest = (Get-Content copy.path -TotalCount 1).Trim()
  if (Test-Path $dest) {
    Copy-Item -Path $built -Destination $dest -Force
    Write-Host "Copiati in $dest" -ForegroundColor Green
  } else {
    Write-Host "Cartella di copia non trovata: $dest" -ForegroundColor Red
  }
}

# ---------------- screenshot nell'emulatore ----------------
if (Get-Command node -ErrorAction SilentlyContinue) {
  $games = $Files | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }
  node tools\screenshots.js $games
  if ($LASTEXITCODE -eq 0) {
    $built += $games | ForEach-Object { Get-ChildItem "screenshots\$($_)_*.png" } | ForEach-Object { "screenshots\$($_.Name)" }
  } else {
    Write-Host "Screenshot non riusciti (la build prosegue)" -ForegroundColor Yellow
  }
} else {
  Write-Host "Node.js non trovato: niente screenshot" -ForegroundColor Yellow
}
if ($NoPublish) { exit 0 }

# ---------------- pubblicazione su GitHub ----------------
git add -- $built
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
  Write-Host "Nessuna modifica da pubblicare" -ForegroundColor Yellow
  exit 0
}
$names = ($Files | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ', '
git commit -m "Build: $names"
git push
if ($LASTEXITCODE -ne 0) { Write-Host "Push non riuscito" -ForegroundColor Red; exit 1 }
Write-Host "Pubblicato su GitHub" -ForegroundColor Green
