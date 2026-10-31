# build.ps1 - assembles the games with vasm6502 and publishes the .bin files on GitHub
#
#   .\build.ps1                 all the .asm files of the folder
#   .\build.ps1 tank.asm        only the files given
#   .\build.ps1 -NoPublish      builds the .bin files without commit and push
#   .\build.ps1 -NoSd           publishes without updating the SD and the web emulator
#
# The path of vasm6502_oldstyle.exe is read from the VASM variable
# or from the first line of the file vasm.path (not in git).
# If the file copy.path exists (not in git), the .asm and .bin files
# built are also copied to the folder it names.
# With Node.js installed, every game built is run in the emulator
# (tools\screenshots.js) and the screenshots go to screenshots\
# and to GitHub together with the .bin files.
# After the push, if ..\bo6502-SDbuilder and ..\bo6502-emulator exist,
# both SD images are rebuilt from the published games (update_sd.py:
# sd.img with the games, sd_full.img also with the applications),
# sd_full.img becomes the emulator's default SD, the games are synced
# into the emulator, checked and pushed: the online emulator (GitHub
# Pages) gets the new SD in about a minute.

param([switch]$NoPublish, [switch]$NoSd, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)

Set-Location $PSScriptRoot

$vasm = $env:VASM
if (-not $vasm -and (Test-Path vasm.path)) { $vasm = (Get-Content vasm.path -TotalCount 1).Trim() }
if (-not $vasm -or -not (Test-Path $vasm)) {
  Write-Host "vasm6502_oldstyle not found: write its path in the file vasm.path" -ForegroundColor Red
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
  Write-Host "ERRORS in: $($failed -join ', ') - nothing published" -ForegroundColor Red
  exit 1
}

# ---------------- copy to the local folder ----------------
if (Test-Path copy.path) {
  $dest = (Get-Content copy.path -TotalCount 1).Trim()
  if (Test-Path $dest) {
    Copy-Item -Path $built -Destination $dest -Force
    Write-Host "Copied to $dest" -ForegroundColor Green
  } else {
    Write-Host "Copy folder not found: $dest" -ForegroundColor Red
  }
}

# ---------------- screenshots in the emulator ----------------
if (Get-Command node -ErrorAction SilentlyContinue) {
  $games = $Files | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_) }
  node tools\screenshots.js $games
  if ($LASTEXITCODE -eq 0) {
    $built += $games | ForEach-Object { Get-ChildItem "screenshots\$($_)_*.png" } | ForEach-Object { "screenshots\$($_.Name)" }
  } else {
    Write-Host "Screenshots failed (the build goes on)" -ForegroundColor Yellow
  }
} else {
  Write-Host "Node.js not found: no screenshots" -ForegroundColor Yellow
}
if ($NoPublish) { exit 0 }

# ---------------- publication on GitHub ----------------
git add -- $built
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
  Write-Host "Nothing to publish" -ForegroundColor Yellow
  exit 0
}
$names = ($Files | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ', '
git commit -m "Build: $names"
git push
if ($LASTEXITCODE -ne 0) { Write-Host "Push failed" -ForegroundColor Red; exit 1 }
Write-Host "Published on GitHub" -ForegroundColor Green

# ---------------- SD image and web emulator ----------------
$sdb = Join-Path $PSScriptRoot "..\bo6502-SDbuilder"
$emu = Join-Path $PSScriptRoot "..\bo6502-emulator"
if ($NoSd) { exit 0 }
if (-not (Test-Path "$sdb\update_sd.py") -or -not (Test-Path "$emu\scripts\sync-games.mjs")) {
  Write-Host "bo6502-SDbuilder or bo6502-emulator not found: SD not updated" -ForegroundColor Yellow
  exit 0
}

# only what is published: bin\ and README.md of HEAD (no local builds)
$src = Join-Path $env:TEMP "minivic-published"
Remove-Item -Recurse -Force $src -ErrorAction SilentlyContinue
New-Item -ItemType Directory $src | Out-Null
git archive -o "$src\published.tar" HEAD bin README.md
tar -xf "$src\published.tar" -C $src

# the emulator repo gets daily commits from its workflow: catch up first
git -C $emu pull --rebase --autostash -q
if ($LASTEXITCODE -ne 0) { Write-Host "Emulator pull failed: SD not updated" -ForegroundColor Red; exit 1 }

python "$sdb\update_sd.py" --minivic "$src\bin" --emulator $emu
if ($LASTEXITCODE -ne 0) { Write-Host "update_sd.py failed" -ForegroundColor Red; exit 1 }
# the full SD (games, applications, documents) is kept ready to burn too
python "$sdb\update_sd.py" --mode full --minivic "$src\bin"
if ($LASTEXITCODE -ne 0) { Write-Host "update_sd.py --mode full failed" -ForegroundColor Red; exit 1 }
# the full SD is the emulator's default SD (public/sd_full.img.gz)
node "$emu\scripts\pack-sd-full.mjs" --source "$sdb\sd_full.img"
if ($LASTEXITCODE -ne 0) { Write-Host "Full SD packing failed" -ForegroundColor Red; exit 1 }
node "$emu\scripts\sync-games.mjs" --source $src
if ($LASTEXITCODE -ne 0) { Write-Host "Games sync failed" -ForegroundColor Red; exit 1 }

# new game names land in minivic.txt: keep them in the SDbuilder repo
git -C $sdb add minivic.txt
git -C $sdb diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  git -C $sdb commit -q -m "Update the SD: $names" -- minivic.txt
  git -C $sdb push -q
}

# every game must reach its title screen before the emulator is published
Push-Location $emu
npx tsc --noEmit
if ($LASTEXITCODE -eq 0) { npm test --silent -- games }
if ($LASTEXITCODE -ne 0) {
  Pop-Location
  Write-Host "Emulator checks failed: nothing pushed, see ..\bo6502-emulator\tests\out" -ForegroundColor Red
  exit 1
}
$paths = "public/games", "src/machines/games.ts", "public/sd.img", "public/sd_full.img.gz", "public/songs"
git add -- $paths
git diff --cached --quiet -- $paths
if ($LASTEXITCODE -eq 0) {
  Write-Host "Emulator already up to date" -ForegroundColor Yellow
} else {
  git commit -q -m "Sync miniVIC games and the default SD: $names" -- $paths
  git push -q
  if ($LASTEXITCODE -ne 0) { Pop-Location; Write-Host "Emulator push failed" -ForegroundColor Red; exit 1 }
  Write-Host "SD updated, emulator online in about a minute: https://boogs77.github.io/BO6502-miniVIC-emulator/" -ForegroundColor Green
}
Pop-Location
