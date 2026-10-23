# build.ps1 - assembles the games with vasm6502 and publishes the .bin files on GitHub
#
#   .\build.ps1                 all the .asm files of the folder
#   .\build.ps1 tank.asm        only the files given
#   .\build.ps1 -NoPublish      builds the .bin files without commit and push
#
# The path of vasm6502_oldstyle.exe is read from the VASM variable
# or from the first line of the file vasm.path (not in git).
# If the file copy.path exists (not in git), the .asm and .bin files
# built are also copied to the folder it names.
# With Node.js installed, every game built is run in the emulator
# (tools\screenshots.js) and the screenshots go to screenshots\
# and to GitHub together with the .bin files.

param([switch]$NoPublish, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)

Set-Location $PSScriptRoot

$vasm = $env:VASM
if (-not $vasm -and (Test-Path vasm.path)) { $vasm = (Get-Content vasm.path -TotalCount 1).Trim() }
if (-not $vasm -or -not (Test-Path $vasm)) {
  Write-Host "vasm6502_oldstyle non trovato: scrivi il suo percorso nel file vasm.path" -ForegroundColor Red
  exit 1
}

if (-not $Files) { $Files = (Get-ChildItem *.asm).Name }
New-Item -ItemType Directory -Force bin | Out-Null

# ---------------- assembly ----------------
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

# ---------------- copy to the local folder ----------------
if (Test-Path copy.path) {
  $dest = (Get-Content copy.path -TotalCount 1).Trim()
  if (Test-Path $dest) {
    Copy-Item -Path $built -Destination $dest -Force
    Write-Host "Copiati in $dest" -ForegroundColor Green
  } else {
    Write-Host "Cartella di copia non trovata: $dest" -ForegroundColor Red
  }
}

# ---------------- screenshots in the emulator ----------------
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

# ---------------- publication on GitHub ----------------
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
