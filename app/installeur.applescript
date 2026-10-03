-- cidre : installeur natif macOS (applet AppleScript).
-- Telecharge le runtime (barre de progression native), puis delegue la
-- configuration a installer_cidre.sh embarque dans Contents/Resources.

set repoURL to "https://github.com/gtranche/cidre/releases/latest/download/cidre-runtime.tar.zst"
set destDefault to (POSIX path of (path to home folder)) & "Library/Application Support/cidre"
set shPath to POSIX path of (path to resource "installer_cidre.sh")

-- 1. Accueil / confirmation
try
	display dialog "Cidre installe le runtime qui fait tourner les jeux Windows via Steam, sans Rosetta.

Telechargement d'environ 550 Mo puis configuration, quelques minutes." with title "Installer Cidre" buttons {"Annuler", "Installer"} default button "Installer" with icon note
on error number -128
	return
end try

-- 2. Prerequis (zstd requis ; FreeType requis pour le texte)
set manque to do shell script "m=''; command -v zstd >/dev/null 2>&1 || m=\"$m zstd\"; [ -f /opt/homebrew/lib/libfreetype.6.dylib ] || m=\"$m freetype\"; echo $m"
if manque is not "" then
	set cmd to "brew install" & manque
	try
		display dialog "Il manque : " & manque & "

Ouvrez le Terminal et lancez :

" & cmd & "

puis relancez cet installeur." with title "Prerequis manquants" buttons {"Copier la commande", "Quitter"} default button "Copier la commande" with icon caution
		set the clipboard to cmd
	end try
	return
end if

-- 3. Telechargement avec barre de progression determinee
set tarPath to (do shell script "mktemp -d") & "/cidre-runtime.tar.zst"
set total to 0
try
	set total to (do shell script "curl -fsIL " & quoted form of repoURL & " | awk 'BEGIN{IGNORECASE=1} /^content-length:/{v=$2} END{gsub(/\\r/,\"\",v); print v+0}'") as integer
end try

set progress total steps to 100
set progress completed steps to 0
set progress description to "Telechargement du runtime (~550 Mo)..."
set progress additional description to ""

set pid to do shell script "curl -fsSL -o " & quoted form of tarPath & " " & quoted form of repoURL & " >/dev/null 2>&1 & echo $!"

repeat
	delay 1
	set alive to (do shell script "kill -0 " & pid & " 2>/dev/null && echo 1 || echo 0")
	set got to (do shell script "stat -f%z " & quoted form of tarPath & " 2>/dev/null || echo 0") as integer
	if total > 0 then
		set pct to (got * 100) div total
		if pct > 99 then set pct to 99
		set progress completed steps to pct
		set progress additional description to ((got div 1048576) as string) & " / " & ((total div 1048576) as string) & " Mo"
	end if
	if alive is "0" then exit repeat
end repeat

-- Verifier que le telechargement a reussi
set got to (do shell script "stat -f%z " & quoted form of tarPath & " 2>/dev/null || echo 0") as integer
if got < 1000000 then
	display dialog "Echec du telechargement du runtime. Verifiez votre connexion et reessayez." with title "Erreur" buttons {"Quitter"} default button "Quitter" with icon stop
	return
end if
set progress completed steps to 100

-- 4. Configuration (prefixe, DXVK, FEX, pont Steam) via l'installeur embarque,
--    nourri par le tarball deja telecharge (il saute alors son propre download).
set progress completed steps to 0
set progress total steps to 0 -- barre indeterminee pendant la config
set progress description to "Configuration (prefixe Wine, DXVK, FEX, pont Steam)..."
set ok to true
set logOut to ""
try
	with timeout of 1800 seconds
		set logOut to do shell script "/bin/sh " & quoted form of shPath & " " & quoted form of destDefault & " " & quoted form of tarPath & " 2>&1"
	end timeout
on error errMsg
	set ok to false
	set logOut to errMsg
end try

-- 5. Bilan
if ok then
	display dialog "Installe sous :
" & destDefault & "

Lancez un jeu Windows depuis Steam (bouton Jouer). Si Steam etait ouvert, fermez-le puis rouvrez-le une fois." with title "Termine" buttons {"Terminer"} default button "Terminer" with icon note
else
	display dialog "La configuration a echoue :

" & logOut with title "Erreur" buttons {"Quitter"} default button "Quitter" with icon stop
end if
