#!/bin/sh
# Teste les emplacements des jeux Cidre (`cidre emplacements`, `cidre move`,
# `cidre dl --vers`, jeux hors ligne) sur de faux disques : des images disque
# APFS, exFAT et FAT32 creees et montees par hdiutil dans un dossier
# temporaire, que CIDRE_VOLUMES fait passer pour /Volumes. De faux jeux, un
# faux SteamCMD, un faux lanceur ; ni vrai jeu, ni vrai disque, ni Wine, ni
# reseau.
#   1. emplacements : principal seul ; un disque ajoute par sa racine (dossier
#      « Jeux Cidre », marque), deux fois, un dossier dans un autre, FAT32
#      refuse, un dossier du Mac ; --json ;
#   2. cidre move vers exFAT puis APFS, et retour : copie verifiee (noms
#      accentues, liens, gros fichier), original efface, sauvegardes et
#      prefixe intacts, pas de ._xxx ; lance depuis son nouvel endroit ;
#   3. meme volume : un renommage ;
#   4. refus : jeu en cours (temoin, processus), place, jeu du client Steam,
#      emplacement inconnu ou debranche, liens symboliques impossibles ;
#   5. interruption (SIGTERM) puis reprise ; --annuler ; disque debranche
#      pendant la copie, puis reprise ;
#   6. hors ligne : disque debranche -> jeux hors ligne, ni desinstalles ni
#      perdus (list, info, emplacements) ; play, dl, rm, move refuses (code 8) ;
#      rebranche -> de retour ; volume renomme (autre point de montage) ->
#      retrouve par sa marque ;
#   7. detection : jeu copie a la main sous un autre nom ; doublon, puis un
#      move qui finit le travail ;
#   8. cidre dl --vers, emplacement par defaut (branche, puis debranche) ;
#   9. retirer puis rajouter un emplacement : ses jeux reviennent ; detecte ;
#  10. syntaxe, aide.
# Rien n'est lu ni ecrit hors d'un dossier temporaire (HOME, CIDRE_DIR,
# volumes a part).
#   sh tests/tester_emplacements.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
C="$R/cidre"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-empl.XXXXXX")
T=$(cd "$T" && pwd -P)
F="$T/faux"; V="$T/volumes"
demonter() { # (un disque debranche : de force, comme un cable arrache)
   hdiutil detach "$1" -force >"$T/demonter.log" 2>&1 || diskutil unmount force "$1" >>"$T/demonter.log" 2>&1
   [ ! -d "$1" ] || { echo "  (impossible de demonter $1 : $(tr '\n' ' ' <"$T/demonter.log"))" >&2; return 1; }
}
nettoyer() {
   for m in "$V"/*; do [ -d "$m" ] && demonter "$m"; done
   rm -rf "${T:?}"
}
trap nettoyer EXIT
nb=0; ko=0
ok()   { nb=$((nb + 1)); echo "  ok   $1"; }
echec() { nb=$((nb + 1)); ko=$((ko + 1)); echo "  KO   $1" >&2; }
verif() { # <libelle> <attendu> <obtenu>
   if [ "$2" = "$3" ]; then ok "$1"; else echec "$1 : attendu « $2 », obtenu « $3 »"; fi
}
contient() { # <libelle> <motif fixe> <texte>
   case $3 in *"$2"*) ok "$1" ;; *) echec "$1 : « $2 » absent de « $3 »" ;; esac
}
sans() { # <libelle> <motif fixe> <texte>
   case $3 in *"$2"*) echec "$1 : « $2 » present dans « $3 »" ;; *) ok "$1" ;; esac
}
valide() { printf '%s' "$2" | plutil -convert json -o /dev/null - 2>/dev/null && ok "$1" || echec "$1 : JSON invalide : $2"; }
# une valeur d'un JSON (chemin a points : emplacements.1.id), « null » si absente ou nulle
pj() { pj_v=$(printf '%s' "$1" | plutil -extract "$2" raw - 2>/dev/null) || pj_v=null; printf '%s' "$pj_v"; }
# l'objet JSON d'un emplacement, par son id, dans `cidre emplacements --json`
empl() { # <id>
   sh "$C" emplacements --json | awk -v i="\"id\":\"$1\"" 'index($0, i) { sub(/^ *,? */, ""); sub(/,$/, ""); print; exit }'
}

if [ ! -x "$R/build/cidre-outil" ] || [ "$R/tests/cidre_outil.c" -nt "$R/build/cidre-outil" ]; then sh "$R/tests/construire_cidre_outil.sh" >/dev/null 2>&1; fi

mkdir -p "$F/bin" "$V" "$T/home"
export HOME="$T/home" CIDRE_DIR="$T/cidre" CIDRE_PROFILS="$T/perso.toml" CIDRE_PROFILS_BASE="$T/profils-base"
export CIDRE_VOLUMES="$V" CIDRE_LANCEUR="$F/lanceur.sh" CIDRE_STEAMCMD="$F/steamcmd.sh" CIDRE_STEAM_USER=essai
export CIDRE_SANS_STEAM=1 CIDRE_MAJ_AVANT_LANCEMENT=0 CIDRE_DEPL_MARGE_KO=1024 CIDRE_MAJ_LIBRE_MIN=1
export CIDRE_PROTONDB_URL="file://$T/nulle-part/"
unset CIDRE_ESSAI_LIBRE_KO 2>/dev/null
# `open` (le client Steam) : un faux ; rsync : le vrai, ralenti quand $F/lent existe
printf '#!/bin/sh\necho "$*" >>"%s/ouvertures"\n' "$F" >"$F/bin/open"
printf '#!/bin/sh\nif [ -f "%s/lent" ]; then exec /usr/bin/rsync --bwlimit="$(cat "%s/lent")" "$@"; fi\nexec /usr/bin/rsync "$@"\n' "$F" "$F" >"$F/bin/rsync"
chmod +x "$F/bin/open" "$F/bin/rsync"
export PATH="$F/bin:$PATH"
G="$CIDRE_DIR/games"; D="$CIDRE_DIR/deplacements"
mkdir -p "$G"

# Le faux lanceur : note l'executable qu'on lui confie.
cat >"$F/lanceur.sh" <<'LANCEUR'
#!/bin/sh
echo "$1" >>"$(dirname "$0")/lances"
LANCEUR
# Le faux SteamCMD : +app_update pose un petit jeu dans +force_install_dir.
cat >"$F/steamcmd.sh" <<'STEAMCMD'
#!/bin/sh
F=$(dirname "$0"); echo "$*" >>"$F/appels"
dest=; app=; avant=
for a in "$@"; do
   case $avant in +force_install_dir) dest=$a ;; +app_update) app=$a ;; esac
   avant=$a
done
echo "Logging in user 'essai' to Steam Public...OK"
[ -n "$app" ] || exit 0
mkdir -p "$dest/steamapps"; printf 'MZ telecharge\n' >"$dest/Jeu.exe"
printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"Telecharge %s"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Jeu"\n\t"SizeOnDisk"\t\t"14"\n\t"buildid"\t\t"9"\n}\n' "$app" "$app" >"$dest/steamapps/appmanifest_$app.acf"
echo "Success! App '$app' fully installed."
STEAMCMD
chmod +x "$F/lanceur.sh" "$F/steamcmd.sh"

# Un faux jeu tel que `cidre dl` le laisse : exe, manifeste, un nom accentue, un
# lien relatif, un lien absolu vers son propre dossier, un lien vers un dossier
# de sauvegardes macOS (Steam Cloud), et des morceaux de 1 Mo au besoin (une
# copie interrompue garde les fichiers finis : la reprise se voit).
jeu() { # <dossier> <appid> [Mo]
   mkdir -p "$1/steamapps" "$1/Data/Sous dossier" "$HOME/Saves/$2"
   printf 'MZ jeu %s\n' "$2" >"$1/Jeu.exe"
   printf 'accents\n' >"$1/Data/Éditeur à accents.txt"
   printf 'profond\n' >"$1/Data/Sous dossier/niveau.dat"
   ln -s "Data/Éditeur à accents.txt" "$1/lien-relatif"
   ln -s "$1/Data" "$1/lien-absolu"
   ln -s "$HOME/Saves/$2" "$1/Saves"
   echo "sauvegarde $2" >"$HOME/Saves/$2/partie.sav"
   j_i=1; while [ $j_i -le "${3:-0}" ]; do dd if=/dev/urandom of="$1/Data/morceau-$j_i.bin" bs=1048576 count=1 2>/dev/null; j_i=$((j_i + 1)); done
   t=$(du -sk "$1" | cut -f1)
   printf '"AppState"\n{\n\t"appid"\t\t"%s"\n\t"name"\t\t"Jeu %s"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"Jeu"\n\t"SizeOnDisk"\t\t"%s"\n\t"buildid"\t\t"7"\n\t"LastPlayed"\t\t"1790000000"\n}\n' "$2" "$2" "$((t * 1024))" >"$1/steamapps/appmanifest_$2.acf"
}
# ce que contient un jeu, pour comparer avant/apres (sans les ._xxx, noms en NFC)
empreinte() {
   (cd "$1" && find . ! -name '._*' \( -type f -exec shasum {} + -o -type l -exec stat -f 'lien %N' {} + \)) 2>/dev/null |
      /usr/bin/iconv -f UTF-8-MAC -t UTF-8 | LC_ALL=C sort
}
point_souligne() { find "$1" -name '._*' 2>/dev/null | wc -l | tr -d ' '; }

echo "== 0. les faux disques"
hdiutil create -size 300m -fs APFS -volname "Faux APFS" -type SPARSE "$T/apfs" >/dev/null 2>&1 &&
hdiutil create -size 300m -fs ExFAT -volname "Faux ExFAT" -type SPARSE "$T/exfat" >/dev/null 2>&1 &&
hdiutil create -size 64m -fs MS-DOS -volname FAUXFAT -type SPARSE "$T/fat" >/dev/null 2>&1 ||
   { echo "hdiutil ne cree pas d'image disque ici : suite non jouee" >&2; exit 1; }
monter() { hdiutil attach -nobrowse -mountpoint "$V/$2" "$T/$1.sparseimage" >/dev/null 2>&1; }
monter apfs "Faux APFS" && monter exfat "Faux ExFAT" && monter fat FAUXFAT ||
   { echo "hdiutil n'attache pas d'image disque ici : suite non jouee" >&2; exit 1; }
EX="$V/Faux ExFAT"; AP="$V/Faux APFS"
verif "trois volumes montes" "3" "$(ls "$V" | wc -l | tr -d ' ')"

echo "== 1. emplacements"
jeu "$G/111" 111 8
sortie=$(sh "$C" emplacements --json)
valide "emplacements --json : JSON valide" "$sortie"
verif "principal seul, par defaut, sur ce Mac" "principal Ce Mac true true true 1" \
   "$(pj "$sortie" emplacements.0.id) $(pj "$sortie" emplacements.0.nom) $(pj "$sortie" emplacements.0.defaut) $(pj "$sortie" emplacements.0.en_ligne) $(pj "$sortie" emplacements.0.principal) $(pj "$sortie" emplacements.0.jeux)"
verif "principal : apfs, place libre lue" "apfs oui" "$(pj "$sortie" emplacements.0.systeme_fichiers) $([ "$(pj "$sortie" emplacements.0.libre)" -gt 0 ] && echo oui)"
verif "rien de detecte" "null" "$(pj "$sortie" detectes.0)"
sortie=$(sh "$C" emplacements ajouter "$EX" --json); rc=$?
verif "ajouter la racine d'un disque exFAT : code 0" "0" "$rc"
valide "ajouter --json : JSON valide" "$sortie"
IDX=$(pj "$sortie" id)
case $IDX in faux-exfat-[0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ok "id lisible : $IDX" ;; *) echec "id inattendu : $IDX" ;; esac
verif "dossier « Jeux Cidre » sur le disque, marque posee" "$EX/Jeux Cidre id=$IDX" "$(pj "$sortie" chemin) $(cat "$EX/Jeux Cidre/.cidre-emplacement" 2>/dev/null)"
verif "exFAT : volume, systeme, amovible, inscriptible, pas par defaut" "Faux ExFAT exfat true true false" \
   "$(pj "$sortie" volume) $(pj "$sortie" systeme_fichiers) $(pj "$sortie" amovible) $(pj "$sortie" inscriptible) $(pj "$sortie" defaut)"
contient "exFAT : une remarque" "exFAT" "$(pj "$sortie" remarque)"
sortie=$(sh "$C" emplacements ajouter "$EX/Jeux Cidre" 2>&1); rc=$?
verif "ajouter deux fois : rien de plus (code 0)" "0 1" "$rc $(wc -l <"$CIDRE_DIR/emplacements.conf" | tr -d ' ')"
contient "ajouter deux fois : on le dit" "deja un emplacement : $IDX" "$sortie"
sortie=$(sh "$C" emplacements ajouter "$AP"); IDA=$(sed -n 's/^id=//p' "$AP/Jeux Cidre/.cidre-emplacement")
contient "ajouter un disque APFS" "emplacement ajoute : $IDA" "$sortie"
sortie=$(sh "$C" emplacements ajouter "$V/FAUXFAT" 2>&1); rc=$?
verif "FAT32 refuse (code 1)" "1" "$rc"
contient "FAT32 : pourquoi" "FAT32 : aucun fichier de plus de 4 Go" "$sortie"
mkdir -p "$EX/Jeux Cidre/sous"
sortie=$(sh "$C" emplacements ajouter "$EX/Jeux Cidre/sous" 2>&1); rc=$?
verif "un dossier dans un emplacement : refuse" "1" "$rc"
contient "un dossier dans un emplacement : pourquoi" "est dans l'emplacement « Faux ExFAT »" "$sortie"
rmdir "$EX/Jeux Cidre/sous"
sortie=$(sh "$C" emplacements ajouter "$CIDRE_DIR" 2>&1); rc=$?
verif "un dossier qui contient le principal : refuse" "1" "$rc"
mkdir -p "$T/autre"
sortie=$(sh "$C" emplacements ajouter "$T/autre"); IDM=$(sed -n 's/^id=//p' "$T/autre/.cidre-emplacement")
contient "un dossier du Mac (meme volume que le principal)" "emplacement ajoute : autre-" "$sortie"
sortie=$(sh "$C" emplacements)
contient "liste en texte : l'exFAT" "$IDX" "$sortie"
contient "liste en texte : le defaut marque" "principal *" "$sortie"
verif "quatre emplacements" "4" "$(sh "$C" emplacements --json | grep -c '"id":')"

echo "== 2. deplacer vers exFAT, puis APFS"
avant=$(empreinte "$G/111")
pfx="$CIDRE_DIR/prefixe-temoin"; echo intact >"$pfx"
sortie=$(sh "$C" move 111 "Faux ExFAT" --json 2>/dev/null); rc=$?
verif "move vers exFAT : code 0" "0" "$rc"
printf '%s\n' "$sortie" | while IFS= read -r l; do printf '%s' "$l" | plutil -convert json -o /dev/null - 2>/dev/null || echo "$l"; done >"$T/invalides"
verif "move --json : un objet JSON par ligne" "" "$(cat "$T/invalides")"
contient "evenement : copie, avec le total" '"phase":"copie","avancement":0,"octets":0,"total":' "$sortie"
contient "evenement : verification" '"phase":"verification"' "$sortie"
contient "evenement : fait, vers l'emplacement" "\"etat\":\"fait\",\"emplacement\":\"$IDX\",\"chemin\":\"$EX/Jeux Cidre/111\"" "$sortie"
verif "l'original n'est plus la" "non" "$([ -e "$G/111" ] && echo oui || echo non)"
verif "le jeu est entier a destination" "$avant" "$(empreinte "$EX/Jeux Cidre/111")"
verif "aucun ._xxx d'exFAT dans le jeu" "0" "$(point_souligne "$EX/Jeux Cidre/111")"
verif "lien absolu vers son propre dossier : refait vers le nouveau" "$EX/Jeux Cidre/111/Data" "$(readlink "$EX/Jeux Cidre/111/lien-absolu")"
verif "lien vers les sauvegardes macOS : intact" "sauvegarde 111" "$(cat "$EX/Jeux Cidre/111/Saves/partie.sav" 2>/dev/null)"
verif "sauvegardes et prefixe : intacts" "sauvegarde 111 intact" "$(cat "$HOME/Saves/111/partie.sav") $(cat "$pfx")"
verif "rien ne reste du deplacement" "" "$(ls -A "$D" 2>/dev/null; ls -A "$EX/Jeux Cidre" | grep '^\.cidre-[ds]')"
info=$(sh "$C" info 111 --json)
valide "info --json : JSON valide" "$info"
verif "info : emplacement, chemin, en ligne, installe, pas de deplacement" "$IDX $EX/Jeux Cidre/111 true true null" \
   "$(pj "$info" emplacement) $(pj "$info" chemin) $(pj "$info" en_ligne) $(pj "$info" installe) $(pj "$info" deplacement)"
sh "$C" play 111 >/dev/null 2>&1
verif "play : l'executable du nouvel endroit" "$EX/Jeux Cidre/111/Jeu.exe" "$(tail -1 "$F/lances")"
verif "emplacements : le jeu compte sur l'exFAT" "1" "$(pj "$(empl "$IDX")" jeux)"
sortie=$(sh "$C" move 111 "$IDA"); rc=$?
verif "move exFAT -> APFS : code 0" "0" "$rc"
verif "APFS : entier" "$avant" "$(empreinte "$AP/Jeux Cidre/111")"
verif "exFAT : plus rien" "non" "$([ -e "$EX/Jeux Cidre/111" ] && echo oui || echo non)"
sortie=$(sh "$C" move 111 principal); rc=$?
verif "retour sur ce Mac (designe par « principal »)" "0 $avant" "$rc $(empreinte "$G/111")"
sortie=$(sh "$C" move 111 principal); rc=$?
verif "deja la : rien a faire (code 0)" "0" "$rc"
contient "deja la : on le dit" "est deja dans « Ce Mac »" "$sortie"

echo "== 3. meme volume"
ino=$(stat -f %i "$G/111/Data/morceau-1.bin")
sortie=$(sh "$C" move 111 "$T/autre"); rc=$?
verif "vers un dossier du meme volume : code 0" "0" "$rc"
contient "renomme, sans copie" "meme volume : renomme" "$sortie"
verif "les memes fichiers (meme inode)" "$ino" "$(stat -f %i "$T/autre/111/Data/morceau-1.bin" 2>/dev/null)"
sh "$C" move 111 principal >/dev/null 2>&1

echo "== 4. refus"
mkdir -p "$CIDRE_DIR/en-cours"; sleep 30 & echo $! >"$CIDRE_DIR/en-cours/111"; p=$!
sortie=$(sh "$C" move 111 "$IDX" --json 2>/dev/null); rc=$?
verif "jeu en cours (temoin de cidre play) : code 4" "4" "$rc"
contient "jeu en cours : evenement refuse" '"etat":"refuse","raison":"en_jeu"' "$sortie"
kill $p 2>/dev/null; wait $p 2>/dev/null; rm -f "$CIDRE_DIR/en-cours/111"
sh -c 'sleep 30; :' "$G/111/Jeu.exe" & p=$!
sleep 0.3
sortie=$(sh "$C" move 111 "$IDX" 2>&1); rc=$?
verif "un processus tient le dossier du jeu : code 4" "4" "$rc"
contient "processus : quoi faire" "quitte-le" "$sortie"
kill $p 2>/dev/null; wait $p 2>/dev/null
z=$(printf 'Z:%s' "$G/111/Jeu.exe" | tr / '\\')
sh -c 'sleep 30; :' "$z" & p=$!
sleep 0.3
sh "$C" move 111 "$IDX" >/dev/null 2>&1; rc=$?
verif "un processus Windows (Z:\\...) tient le jeu : code 4" "4" "$rc"
kill $p 2>/dev/null; wait $p 2>/dev/null
verif "refus : aucun etat garde" "" "$(ls -A "$D" 2>/dev/null)"
sortie=$(CIDRE_DEPL_MARGE_KO=$((400 * 1024)) sh "$C" move 111 "$IDX" 2>&1); rc=$?
verif "place insuffisante : code 5" "5" "$rc"
contient "place : combien" "Place insuffisante sur « Faux ExFAT » : il faut" "$sortie"
verif "place : l'original n'a pas bouge" "$avant" "$(empreinte "$G/111")"
sortie=$(sh "$C" move 111 nulle-part 2>&1); rc=$?
verif "emplacement inconnu : code 2" "2" "$rc"
mkdir -p "$HOME/Library/Application Support/Steam/steamapps/common/JeuSteam"
printf '"AppState"\n{\n\t"appid"\t\t"333"\n\t"name"\t\t"Jeu Steam"\n\t"StateFlags"\t\t"4"\n\t"installdir"\t\t"JeuSteam"\n}\n' >"$HOME/Library/Application Support/Steam/steamapps/appmanifest_333.acf"
sortie=$(sh "$C" move 333 "$IDX" 2>&1); rc=$?
verif "jeu du client Steam : refuse (code 1)" "1" "$rc"
contient "jeu du client Steam : se deplace depuis Steam" "depuis Steam" "$sortie"

echo "== 5. interruption, reprise, annulation, disque debranche"
jeu "$G/222" 222 40
avant2=$(empreinte "$G/222")
echo 4000 >"$F/lent"
sh "$C" move 222 "$IDX" --json >"$T/move.out" 2>/dev/null & p=$!
i=0; until [ "$(find "$EX/Jeux Cidre/.cidre-deplacement-222" -name 'morceau-*.bin' 2>/dev/null | wc -l)" -ge 4 ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
sleep 1.5
info=$(sh "$C" info 222 --json)
verif "pendant la copie : deplacement en cours, phase copie" "en_cours copie $IDX" "$(pj "$info" deplacement.etat) $(pj "$info" deplacement.phase) $(pj "$info" deplacement.vers)"
pct=$(pj "$info" deplacement.avancement)
case $pct in null|0|0.0) echec "pendant la copie : avancement lu ($pct)" ;; *) ok "pendant la copie : avancement lu ($pct %)" ;; esac
sortie=$(sh "$C" play 222 2>&1); rc=$?
verif "play pendant le deplacement : refuse (code 4)" "4" "$rc"
kill -TERM $p; wait $p; rc=$?
verif "interrompu (SIGTERM) : code 130" "130" "$rc"
contient "interrompu : evenement" '"etat":"interrompu"' "$(cat "$T/move.out")"
verif "interrompu : l'original est intact" "$avant2" "$(empreinte "$G/222")"
verif "interrompu : rsync arrete" "" "$(pgrep -f "rsync.*cidre-deplacement-222")"
info=$(sh "$C" info 222 --json)
verif "interrompu : l'etat le dit, le jeu reste ou il etait" "interrompu principal" "$(pj "$info" deplacement.etat) $(pj "$info" emplacement)"
deja=$(du -sk "$EX/Jeux Cidre/.cidre-deplacement-222" | cut -f1)
rm -f "$F/lent"
sortie=$(sh "$C" move 222 "$IDX"); rc=$?
verif "reprise : code 0" "0" "$rc"
contient "reprise : ce qui etait copie est garde" "(reprise : " "$sortie"
[ "$deja" -gt 1024 ] && ok "reprise : $deja Kio etaient deja copies" || echec "reprise : rien n'avait ete copie ($deja Kio)"
verif "reprise : le jeu est entier" "$avant2" "$(empreinte "$EX/Jeux Cidre/222")"
verif "reprise : l'etat est efface" "null" "$(pj "$(sh "$C" info 222 --json)" deplacement)"
# --arreter : un deplacement lance d'ailleurs s'arrete, sa copie reste
echo 4000 >"$F/lent"
sh "$C" move 222 principal >/dev/null 2>&1 & p=$!
i=0; until [ "$(find "$G/.cidre-deplacement-222" -name 'morceau-*.bin' 2>/dev/null | wc -l)" -ge 4 ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
sortie=$(sh "$C" move 222 --arreter); rc=$?
wait $p; rcp=$?
verif "--arreter : code 0, le deplacement sort en 130" "0 130" "$rc $rcp"
verif "--arreter : la copie entamee reste, l'etat dit interrompu" "oui interrompu" "$([ -d "$G/.cidre-deplacement-222" ] && echo oui || echo non) $(pj "$(sh "$C" info 222 --json)" deplacement.etat)"
sh "$C" move 222 principal >/dev/null 2>&1 & p=$!
i=0; until [ -d "$G/.cidre-deplacement-222" ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
sleep 1
sortie=$(sh "$C" move 222 --annuler); rc=$?
wait $p 2>/dev/null
verif "--annuler : code 0" "0" "$rc"
verif "--annuler : la copie entamee est effacee, l'etat aussi" "non null" "$([ -e "$G/.cidre-deplacement-222" ] && echo oui || echo non) $(pj "$(sh "$C" info 222 --json)" deplacement)"
verif "--annuler : le jeu est toujours sur l'exFAT, entier" "$avant2" "$(empreinte "$EX/Jeux Cidre/222")"
# le disque cible est debranche en pleine copie
jeu "$G/444" 444 40
avant4=$(empreinte "$G/444")
sh "$C" move 444 "$IDA" >"$T/move.out" 2>&1 & p=$!
i=0; until [ "$(find "$AP/Jeux Cidre/.cidre-deplacement-444" -name 'morceau-*.bin' 2>/dev/null | wc -l)" -ge 4 ] || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done
sleep 1
demonter "$AP"
wait $p; rc=$?
verif "disque debranche pendant la copie : code 8" "8" "$rc"
contient "debranche : quoi faire" "a ete debranche pendant la copie" "$(cat "$T/move.out")"
verif "debranche : l'original est intact" "$avant4" "$(empreinte "$G/444")"
info=$(sh "$C" info 444 --json)
verif "debranche : etat echoue (debranche), jeu sur ce Mac" "echoue debranche principal" "$(pj "$info" deplacement.etat) $(pj "$info" deplacement.raison) $(pj "$info" emplacement)"
rm -f "$F/lent"
monter apfs "Faux APFS"
sortie=$(sh "$C" move 444 "$IDA"); rc=$?
verif "rebranche : la copie reprend et aboutit" "0 $avant4" "$rc $(empreinte "$AP/Jeux Cidre/444")"
verif "rebranche : l'original est parti" "non" "$([ -e "$G/444" ] && echo oui || echo non)"
# arrete pendant l'effacement de l'original : le jeu est arrive, il reste l'etat
# et un bout de l'original (cache)
mkdir -p "$G/.cidre-supprime-444.99999/Data"; echo reste >"$G/.cidre-supprime-444.99999/Data/x"
printf 'etat=interrompu\nphase=suppression\nde=principal\nvers=%s\nsource=%s\ncible=%s\npid=99999\n' "$IDA" "$G/444" "$AP/Jeux Cidre" >"$D/444"
verif "arrete pendant l'effacement de l'original : rien a reprendre" "null $IDA" "$(pj "$(sh "$C" info 444 --json)" deplacement) $(pj "$(sh "$C" info 444 --json)" emplacement)"
sh "$C" move 444 "$IDA" >/dev/null 2>&1; rc=$?
verif "... un move vers la range l'etat et les restes de l'original" "0 non non" "$rc $([ -e "$D/444" ] && echo oui || echo non) $([ -e "$G/.cidre-supprime-444.99999" ] && echo oui || echo non)"

echo "== 6. hors ligne"
noms_avant=$(sh "$C" list --json | grep -o '"nom":"[^"]*"' | sort | tr '\n' ' ')
demonter "$EX"
liste=$(sh "$C" list --json)
valide "debranche : list --json valide" "$liste"
l222=$(printf '%s\n' "$liste" | grep '"id":"222"' | sed 's/^ *,\{0,1\}//; s/,$//')
verif "debranche : le jeu est toujours liste, installe, hors ligne" "Jeu 222 true false windows $IDX" \
   "$(pj "$l222" nom) $(pj "$l222" installe) $(pj "$l222" en_ligne) $(pj "$l222" plateforme) $(pj "$l222" emplacement)"
verif "debranche : sa taille et sa date sont gardees" "oui 1790000000" "$([ "$(pj "$l222" taille)" -gt 40000000 ] && echo oui) $(pj "$l222" dernier_lancement)"
verif "debranche : son dernier chemin connu" "$EX/Jeux Cidre/222" "$(pj "$l222" chemin)"
verif "debranche : aucun jeu perdu" "$noms_avant" "$(printf '%s' "$liste" | grep -o '"nom":"[^"]*"' | sort | tr '\n' ' ')"
e=$(empl "$IDX")
verif "emplacements : debranche, sans place lue, amovible, 1 jeu" "false null true 1" "$(pj "$e" en_ligne) $(pj "$e" libre) $(pj "$e" amovible) $(pj "$e" jeux)"
contient "emplacements : la remarque dit de rebrancher" "Debranche : branche le disque « Faux ExFAT »" "$(pj "$e" remarque)"
nl=$(wc -l <"$F/lances")
sortie=$(sh "$C" play 222 --json 2>"$T/err"); rc=$?
verif "play : refuse (code 8)" "8" "$rc"
verif "play --json : evenement erreur hors_ligne" "erreur hors_ligne $IDX" "$(pj "$sortie" evenement) $(pj "$sortie" code) $(pj "$sortie" emplacement)"
contient "play : le message" "Jeu 222 est sur « Faux ExFAT », qui n'est pas branche" "$(cat "$T/err")"
verif "play : rien n'a ete lance" "$nl" "$(wc -l <"$F/lances")"
sh "$C" dl 222 >/dev/null 2>&1; rc=$?
verif "dl : refuse (code 8), pas de second exemplaire" "8 non" "$rc $([ -e "$G/222" ] && echo oui || echo non)"
sh "$C" rm 222 >/dev/null 2>&1; rc=$?
verif "rm : refuse (code 8)" "8" "$rc"
sh "$C" move 222 principal >/dev/null 2>&1; rc=$?
verif "move depuis le disque debranche : refuse (code 8)" "8" "$rc"
sh "$C" move 111 "$IDX" >/dev/null 2>&1; rc=$?
verif "move vers le disque debranche : refuse (code 8)" "8" "$rc"
contient "info : hors ligne" "HORS LIGNE" "$(sh "$C" info 222)"
contient "emplacements (texte) : DEBRANCHE" "DEBRANCHE" "$(sh "$C" emplacements)"
monter exfat "Faux ExFAT"
l222=$(sh "$C" list --json | grep '"id":"222"' | sed 's/^ *,\{0,1\}//; s/,$//')
verif "rebranche : de retour, en ligne" "true $EX/Jeux Cidre/222" "$(pj "$l222" en_ligne) $(pj "$l222" chemin)"
sh "$C" play 222 >/dev/null 2>&1
verif "rebranche : il se lance" "$EX/Jeux Cidre/222/Jeu.exe" "$(tail -1 "$F/lances")"
# le volume change de nom : un autre point de montage
demonter "$EX"; EX2="$V/Disque Renomme"
monter exfat "Disque Renomme"
l222=$(sh "$C" list --json | grep '"id":"222"' | sed 's/^ *,\{0,1\}//; s/,$//')
verif "volume renomme : retrouve par sa marque" "true $EX2/Jeux Cidre/222" "$(pj "$l222" en_ligne) $(pj "$l222" chemin)"
verif "volume renomme : le nouveau chemin est note" "$EX2/Jeux Cidre" "$(awk -F'\t' -v i="$IDX" '$1 == i { print $2 }' "$CIDRE_DIR/emplacements.conf")"
verif "volume renomme : son nouveau nom" "Disque Renomme" "$(pj "$(empl "$IDX")" nom)"
EX=$EX2

echo "== 7. detection"
cp -Rp "$G/111" "$AP/Jeux Cidre/Copie a la main"
liste=$(sh "$C" list --json)
verif "un jeu copie a la main, sous un autre nom : reconnu" "1" "$(printf '%s' "$liste" | grep -c '"id":"111"')"
verif "doublon : le premier exemplaire (principal) reste celui du jeu" "principal" "$(pj "$(sh "$C" info 111 --json)" emplacement)"
contient "doublon : info cite l'autre exemplaire" "autres exemplaires : $AP/Jeux Cidre/Copie a la main" "$(sh "$C" info 111)"
mv "$AP/Jeux Cidre/Copie a la main" "$AP/Jeux Cidre/111"
sortie=$(sh "$C" move 111 "$IDA"); rc=$?
verif "move vers le doublon identique : code 0, sans copie" "0" "$rc"
verif "move vers le doublon : l'original part, l'exemplaire reste" "non $avant" "$([ -e "$G/111" ] && echo oui || echo non) $(empreinte "$AP/Jeux Cidre/111")"
cp -Rp "$AP/Jeux Cidre/111" "$G/111"; echo different >>"$G/111/Jeu.exe"
sortie=$(sh "$C" move 111 "$IDA" 2>&1); rc=$?
verif "un autre exemplaire different a destination : refuse (code 1)" "1" "$rc"
contient "different : on le dit" "different de celui-ci" "$sortie"
rm -rf "${G:?}/111"

echo "== 8. dl --vers, emplacement par defaut"
sh "$C" dl 555 --vers "$IDX" >/dev/null 2>&1; rc=$?
verif "dl --vers : dans l'exFAT" "0 Telecharge 555" "$rc $(sed -n 's/.*"name"[[:space:]]*"\(.*\)".*/\1/p' "$EX/Jeux Cidre/555/steamapps/appmanifest_555.acf" 2>/dev/null)"
contient "dl --vers : SteamCMD vise ce dossier" "+force_install_dir $EX/Jeux Cidre/555" "$(cat "$F/appels")"
verif "dl --vers : liste dans l'exFAT" "$IDX" "$(pj "$(sh "$C" info 555 --json)" emplacement)"
sortie=$(sh "$C" dl 555 --vers principal 2>&1); rc=$?
verif "dl d'un jeu deja ailleurs, --vers autre : refuse" "1" "$rc"
contient "dl --vers autre : cidre move" "cidre move 555" "$sortie"
sortie=$(sh "$C" emplacements defaut "$IDA" --json)
verif "defaut : choisi" "$IDA" "$(pj "$sortie" defaut)"
verif "defaut : emplacements le dit" "true" "$(pj "$(empl "$IDA")" defaut)"
sh "$C" dl 666 >/dev/null 2>&1
verif "dl sans --vers : dans l'emplacement par defaut" "oui" "$([ -f "$AP/Jeux Cidre/666/Jeu.exe" ] && echo oui || echo non)"
demonter "$AP"
sortie=$(sh "$C" dl 777 2>&1); rc=$?
verif "defaut debranche : dl refuse (code 8), rien ailleurs" "8 non" "$rc $([ -e "$G/777" ] && echo oui || echo non)"
contient "defaut debranche : quoi faire" "n'est pas branche" "$sortie"
monter apfs "Faux APFS"
sh "$C" emplacements defaut principal >/dev/null
verif "defaut : principal" "true" "$(pj "$(empl principal)" defaut)"

echo "== 9. retirer, rajouter"
nja=$(ls "$AP/Jeux Cidre" | grep -c '^[0-9]')
sortie=$(sh "$C" emplacements retirer "$IDA" --json); rc=$?
verif "retirer : code 0, ses jeux comptes" "0 $IDA $nja" "$rc $(pj "$sortie" retire) $(pj "$sortie" jeux)"
verif "retirer : ses jeux ne sont plus listes" "0" "$(sh "$C" list --json | grep -c '"id":"666"')"
verif "retirer : les fichiers restent sur le disque" "oui" "$([ -f "$AP/Jeux Cidre/666/Jeu.exe" ] && echo oui || echo non)"
sortie=$(sh "$C" emplacements --json)
verif "retire : detecte sur le disque branche" "$AP/Jeux Cidre $IDA $nja" "$(pj "$sortie" detectes.0.chemin) $(pj "$sortie" detectes.0.id) $(pj "$sortie" detectes.0.jeux)"
sh "$C" emplacements ajouter "$AP" >/dev/null
verif "rajoute : meme id, jeux de retour" "$IDA 1" "$(pj "$(sh "$C" info 666 --json)" emplacement) $(sh "$C" list --json | grep -c '"id":"666"')"
sortie=$(sh "$C" emplacements retirer principal 2>&1); rc=$?
verif "le principal ne se retire pas" "1" "$rc"

echo "== 10. syntaxe, aide"
sh -n "$C" && ok "cidre : syntaxe" || echec "cidre : syntaxe"
sh -n "$R/tests/deplacer_jeu.sh" && ok "deplacer_jeu.sh : syntaxe" || echec "deplacer_jeu.sh : syntaxe"
aide=$(sh "$C" help)
contient "aide : emplacements" "cidre emplacements ajouter" "$aide"
contient "aide : move" "cidre move <appid> <emplacement>" "$aide"
contient "aide : dl --vers" "--vers <emplacement>" "$aide"
contient "aide : move --arreter" "cidre move <appid> --arreter" "$aide"
contient "doctor : les emplacements" 'titre "Emplacements des jeux"' "$(cat "$R/tests/diagnostic_cidre.sh")"
verif "deplacer_jeu.sh : corps lu en entier (accolades, exit)" "{ exit 0 }" "$(grep -x '{' "$R/tests/deplacer_jeu.sh" | head -1) $(tail -2 "$R/tests/deplacer_jeu.sh" | tr '\n' ' ' | sed 's/ $//')"

echo
if [ $ko -eq 0 ]; then echo "$nb verifications, toutes bonnes"; else echo "$nb verifications, $ko en echec" >&2; exit 1; fi
