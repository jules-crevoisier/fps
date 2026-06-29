@echo off
REM ============================================================
REM  Setup Git pour le projet FPS (a lancer depuis ce dossier)
REM  Double-clique dessus, ou : cmd > cd vers le dossier > setup_git.bat
REM ============================================================

echo Nettoyage d'un eventuel depot Git casse...
if exist ".git" rmdir /s /q ".git"

echo Initialisation du depot...
git init -b main
git config user.name "jules"
git config user.email "srko.dj@gmail.com"
git config core.autocrlf false

echo Premier commit...
git add -A
git commit -m "feat: setup projet FPS Godot + mouvement facon Apex (slide, slide-jump, slide-hop, air control)"

echo.
echo ============================================================
echo  Depot local pret (branche main).
echo  Pour pousser sur GitHub :
echo    1) Cree un repo VIDE nomme "fps" sur github.com
echo    2) git remote add origin https://github.com/TON_USER/fps.git
echo    3) git push -u origin main
echo ============================================================
pause
