#!/bin/sh
# Un jeu s'est termine sur un code d'erreur : dire en une phrase ce qui s'est
# probablement passe, et quoi faire. Le code de sortie seul (« code 53 »,
# « code 3221225477 ») n'aide personne ; le journal, lui, porte presque toujours
# la raison, mais noyee dans des milliers de lignes. Ce script lit le journal du
# lancement (depuis sa derniere en-tete « === »), reconnait les signatures
# connues et ecrit, dans le style du journal :
#
#     cause probable : <ce qui s'est passe>
#     a faire : <ce que le joueur peut faire>
#
# Le lanceur l'appelle a la sortie en erreur et recopie ces lignes au journal et
# sur sa sortie (que Verger affiche). Rien n'est modifie. Sans signature connue,
# on donne les dernieres lignes d'erreur du journal et on renvoie vers
# `cidre doctor`.
#
#   expliquer_sortie.sh <code> <journal> [<premiere ligne a lire>]
#
# Pour les essais : CIDRE_CLIENT_STEAM_ETAT (l'etat du client Steam, au lieu de
# l'interroger : connecte, ouvert, ferme, absent) ; SteamAppId vide = jeu hors
# Steam, on ne parle pas du client.
set -u
RC=${1:?usage: expliquer_sortie.sh <code> <journal> [<ligne>]}
JOURNAL=${2:?usage: expliquer_sortie.sh <code> <journal> [<ligne>]}
R=$(cd "$(dirname "$0")/.." && pwd)

# Le journal de CE lancement : depuis la derniere en-tete, ou la ligne donnee.
segment() {
   [ -f "$JOURNAL" ] || return 0
   if [ -n "${3:-}" ]; then tail -n +"$3" "$JOURNAL"; return 0; fi
   debut=$(grep -n '^=== ' "$JOURNAL" | tail -1 | cut -d: -f1)
   tail -n +"${debut:-1}" "$JOURNAL"
}
S=$(segment "$@" | tail -n 4000)
a() { case $S in *"$1"*) return 0 ;; esac; return 1; }   # le journal contient-il ce texte ?
# une ligne du journal qui contient le motif (la premiere), sans son prefixe de fil
ligne() { printf '%s\n' "$S" | grep -m1 -F -- "$1" | sed 's/^[0-9a-f]*://' | cut -c1-160; }

etat_steam() {
   [ -n "${CIDRE_CLIENT_STEAM_ETAT:-}" ] && { echo "$CIDRE_CLIENT_STEAM_ETAT"; return; }
   sh "$R/tests/client_steam_natif.sh" 2>/dev/null || echo inconnu
}

dire() { echo "    cause probable : $1"; [ -n "${2:-}" ] && echo "    a faire : $2"; return 0; }

# --- signatures du journal, de la plus precise a la plus generale ---------------

if a "887A0004" || a "DXGI_ERROR_UNSUPPORTED" || a "Failed to initialize DirectX"; then
   if a "repli automatique vers dxvk"; then
      dire "ce jeu refuse de demarrer avec DXMT (DirectX non pris en charge, DXGI_ERROR_UNSUPPORTED)" \
           "Cidre l'a remis en DXVK pour ce jeu : relance-le (cidre set <id> d3d11 dxmt pour reessayer DXMT)"
   else
      dire "le jeu n'a pas pu initialiser DirectX (DXGI_ERROR_UNSUPPORTED)" \
           "passer ce jeu en DXVK (option d3d11 = dxvk dans Verger), puis relancer"
   fi
   exit 0
fi

if a "no driver could be loaded"; then
   dire "le jeu a demande une fenetre mais aucun affichage n'est disponible : il a ete lance hors d'une session a l'ecran (par SSH, un service, un terminal distant)" \
        "lancer le jeu depuis Verger ou un terminal ouvert dans la session connectee a l'ecran"
   exit 0
fi

if a "import_dll" && a " not found"; then
   dll=$(ligne "import_dll" | sed -n 's/.*Library \([^ ]*\) (which is needed by \(.*\)) not found.*/\1 (requise par \2)/p')
   dire "une DLL manque : ${dll:-voir le journal}" \
        "relancer \`cidre setup\` (il repose les DLL livrees) ; si elle appartient au jeu, verifier ses fichiers dans Steam"
   exit 0
fi

if a "Could not load wine-gecko" || a "could not load kernel32.dll" || a "wine: failed to initialize" || { a "wineboot" && a "failed"; }; then
   dire "le prefixe Wine (le faux Windows du jeu) est incomplet ou abime" \
        "relancer \`cidre setup\` ; si cela ne suffit pas, \`cidre doctor\`"
   exit 0
fi

if a "FreeType"; then
   dire "la bibliotheque FreeType manque : Wine ne peut pas dessiner de texte" \
        "installer FreeType (brew install freetype), puis relancer"
   exit 0
fi

if a "Failed to create Vulkan instance" || a "vkCreateInstance" || a "libvulkan_kosmickrisp" || a "libSPIRV-Tools" || { a "ICD" && a "vulkan"; }; then
   dire "le pilote Vulkan (KosmicKrisp) ne se charge pas : installation incomplete ou dependance absente" \
        "relancer \`cidre setup\`, puis \`cidre doctor\` si le probleme reste"
   exit 0
fi

if a "Failed to create metal view" || { a "winemetal" && a "err:"; }; then
   dire "DXMT (D3D11 vers Metal) n'a pas pu creer sa surface de rendu" \
        "relancer ; si cela se repete, repasser ce jeu en DXVK (option d3d11 = dxvk dans Verger) et partager le resultat"
   exit 0
fi

# Un arret demande par `cidre stop` (Verger) : rien a expliquer.
JEU_ID=${CIDRE_JEU:-${SteamAppId:-}}
if [ -f "$R/build/logs/arret-demande-$JEU_ID" ] || [ -f "$R/build/logs/arret-demande-tous" ]; then
   rm -f "$R/build/logs/arret-demande-$JEU_ID" "$R/build/logs/arret-demande-tous"
   dire "le jeu a ete arrete a la demande (cidre stop)" "rien a faire"
   exit 0
fi

# « anticheat=none » de la ligne de profil n'est pas un anti-triche : on ne
# retient que les modules eux-memes, ou un anticheat declare autre que none.
if a "EasyAntiCheat" || a "BattlEye" || printf '%s\n' "$S" | grep -qE 'anticheat=(eac|battleye|easy|be)'; then
   dire "le jeu demande un anti-triche (EasyAntiCheat ou BattlEye) qui ne tourne pas sous Cidre" \
        "chercher un mode sans anti-triche (serveurs moddes, hors ligne) ; sinon ce jeu n'est pas jouable ici"
   exit 0
fi

if a "GPU Timeout" || a "kIOGPUCommandBufferCallbackErrorTimeout" || a "victim of GPU error"; then
   dire "la carte graphique a abandonne une image (depassement de temps GPU) et le jeu ne s'en est pas remis" \
        "relancer ; si cela se repete, baisser les reglages graphiques du jeu ou la resolution"
   exit 0
fi

if a "Unhandled page fault" || a "Unhandled exception" || a "c0000005" || [ "$RC" = 3221225477 ]; then
   ou=$(ligne "Unhandled")
   dire "le jeu a plante (acces memoire invalide)${ou:+ : $ou}" \
        "relancer ; si cela se repete au meme endroit, \`cidre doctor\` puis « Partager mon resultat » dans Verger"
   exit 0
fi

if a "stack overflow" || [ "$RC" = 3221225725 ]; then
   dire "le jeu a plante par debordement de pile" \
        "relancer ; si cela se repete, partager le resultat dans Verger"
   exit 0
fi

# --- le code de sortie seul ------------------------------------------------------

case $RC in
   53)
      if [ -n "${SteamAppId:-}" ]; then
         case $(etat_steam) in
            ferme|absent) dire "le client Steam de macOS ne tournait pas : un jeu protege par Steam se ferme aussitot sans lui" \
                               "ouvrir Steam et s'y connecter, puis relancer (Cidre essaie de l'ouvrir lui-meme : voir plus haut dans le journal)" ;;
            ouvert)       dire "le client Steam de macOS tourne mais n'est pas connecte (fenetre de connexion, ou mise a jour en cours)" \
                               "se connecter dans Steam, puis relancer" ;;
            *)            dire "le jeu a refuse de demarrer sous la protection de Steam (code 53) alors que le client tourne" \
                               "verifier dans Steam que le jeu est bien dans la bibliotheque de ce compte, puis relancer" ;;
         esac
      else
         dire "le jeu s'est arrete aussitot (code 53)" "voir les dernieres lignes du journal, puis \`cidre doctor\`"
      fi ;;
   3221225781) dire "une DLL manque (STATUS_DLL_NOT_FOUND)" "relancer \`cidre setup\` ; si elle appartient au jeu, verifier ses fichiers dans Steam" ;;
   3221225595) dire "un executable ou une DLL n'est pas de la bonne architecture (STATUS_INVALID_IMAGE_FORMAT)" "verifier que le jeu installe est la version Windows 64 bits ; \`cidre doctor\`" ;;
   3221225794) dire "une DLL a echoue a s'initialiser (STATUS_DLL_INIT_FAILED)" "relancer \`cidre setup\`, puis partager le resultat si cela se repete" ;;
   3221226505) dire "le jeu s'est arrete lui-meme sur une erreur interne (STATUS_STACK_BUFFER_OVERRUN / fail fast)" "relancer ; partager le resultat si cela se repete" ;;
   137)        dire "le jeu a ete tue (memoire insuffisante, ou arret force)" "fermer d'autres applications, baisser les reglages ; relancer" ;;
   143|130)    dire "le jeu a ete arrete de l'exterieur (demande d'arret)" "rien a faire si c'est voulu" ;;
   134|139)    dire "Wine lui-meme s'est arrete sur un signal ($RC)" "\`cidre doctor\`, puis partager le resultat" ;;
   *)
      err=$(printf '%s\n' "$S" | grep -E '^[0-9a-f]*:?err:|^wine: |^err:' | grep -v 'installer_trampolines_steam' | tail -3 | sed 's/^[0-9a-f]*://' | cut -c1-140)
      dire "le jeu s'est termine sur le code $RC sans signature connue${err:+ ; dernieres erreurs du journal :
$(printf '%s\n' "$err" | sed 's/^/        /')}" \
           "\`cidre doctor\` pour l'etat de l'installation, puis « Partager mon resultat » dans Verger avec ce journal" ;;
esac
exit 0
