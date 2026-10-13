#!/bin/sh
# Teste tests/expliquer_sortie.sh sur des journaux fabriques : chaque cas connu
# doit donner sa cause et son « a faire », et un cas inconnu doit citer les
# dernieres erreurs du journal. Rien n'est lance.
#   sh tests/tester_sortie.sh
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
S="$R/tests/expliquer_sortie.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/tester-sortie.XXXXXX")
trap 'rm -rf "$T"' EXIT
nb=0; ko=0
ok()   { nb=$((nb + 1)); echo "  ok   $1"; }
echec() { nb=$((nb + 1)); ko=$((ko + 1)); echo "  KO   $1" >&2; }
verif() { # <libelle> <attendu> <obtenu>
   if [ "$2" = "$3" ]; then ok "$1"; else echec "$1 : attendu « $2 », obtenu « $3 »"; fi
}
contient() { # <libelle> <motif> <texte>
   case $3 in *"$2"*) ok "$1" ;; *) echec "$1 : « $2 » absent de « $3 »" ;; esac
}
absent() { # <libelle> <motif> <texte>
   case $3 in *"$2"*) echec "$1 : « $2 » present dans « $3 »" ;; *) ok "$1" ;; esac
}
# un journal avec deux lancements : seul le dernier compte
journal() { # <corps du dernier lancement>
   J="$T/steam-1.log"
   printf '=== 2026-10-11 10:00:00  appid=1  jeu=x\n0024:err:module:import_dll Library vieux.dll (which is needed by L"x.exe") not found\n    le jeu s'"'"'est termine sur le code 1\n=== 2026-10-12 10:00:00  appid=1  jeu=x\n%s\n' "$1" >"$J"
   echo "$J"
}
expliquer() { # <code> <journal>
   SteamAppId=${APPID-1} CIDRE_CLIENT_STEAM_ETAT=${ETAT-connecte} sh "$S" "$1" "$2" 2>&1
}

echo "== DXMT refuse au demarrage (DXGI_ERROR_UNSUPPORTED)"
r=$(expliquer 1 "$(journal '    d3d11 : dxmt pose depuis /x/dxmt
Failed to initialize DirectX driver (DXError 887A0004 line 112)')")
contient "cause sans repli" "n'a pas pu initialiser DirectX" "$r"
contient "a faire sans repli" "d3d11 = dxvk" "$r"
r=$(expliquer 0 "$(journal '    d3d11 : dxmt pose depuis /x/dxmt
Failed to initialize DirectX driver (DXError 887A0004 line 112)
    d3d11 : repli automatique vers dxvk pour 1 (DXMT refuse par le jeu au demarrage)')")
contient "cause avec repli" "refuse de demarrer avec DXMT" "$r"
contient "a faire avec repli" "relance-le" "$r"

echo "== repli_dxmt.sh : enregistre dxvk dans le profil utilisateur"
export CIDRE_PROFILS="$T/perso.toml"
j=$(journal '    d3d11 : dxmt pose depuis /x/dxmt
Failed to initialize DirectX driver (DXError 887A0004 line 112)')
r=$(sh "$R/tests/repli_dxmt.sh" 1903340 "$j"); rc=$?
contient "repli : message" "repli automatique vers dxvk pour 1903340" "$r"
verif "repli : code 0" "0" "$rc"
verif "repli : d3d11 = dxvk ecrit" "dxvk" "$(sh "$R/tests/profil_cidre.sh" 1903340 get d3d11 2>/dev/null | sed -n 's/^d3d11=//p')"
r=$(sh "$R/tests/repli_dxmt.sh" 1903340 "$(journal '    d3d11 : dxmt pose depuis /x/dxmt
err:   DXGI: CreateSwapChainForHwnd: Failed to create swap chain, hr -2147467259')"); rc=$?
verif "repli : swap chain seul n est pas un refus (code 1)" "1" "$rc"
r=$(sh "$R/tests/repli_dxmt.sh" 1903340 "$(journal 'Failed to initialize DirectX driver (DXError 887A0004 line 112)')"); rc=$?
verif "repli : pas lance en dxmt -> rien (code 1)" "1" "$rc"
r=$(sh "$R/tests/repli_dxmt.sh" 1903340 "$(journal '    d3d11 : dxmt pose depuis /x/dxmt
Failed to initialize DirectX driver (DXError 887A0004 line 112)
    d3d11 : repli automatique vers dxvk pour 1903340 (DXMT refuse)')"); rc=$?
verif "repli : deja replie dans ce journal -> rien (code 1)" "1" "$rc"
unset CIDRE_PROFILS

echo "== pas de session a l'ecran"
r=$(expliquer 3 "$(journal 'Application tried to create a window, but no driver could be loaded.')")
contient "cause" "aucun affichage" "$r"
contient "a faire" "session connectee a l'ecran" "$r"

echo "== DLL manquante (journal)"
r=$(expliquer 3221225781 "$(journal '0024:err:module:import_dll Library vcruntime140_1.dll (which is needed by L"C:\\jeu\\x.exe") not found')")
contient "nomme la DLL" "vcruntime140_1.dll" "$r"
contient "et qui la demande" 'requise par L"C:\jeu\x.exe"' "$r"
contient "a faire" "cidre setup" "$r"

echo "== DLL manquante (code seul)"
r=$(expliquer 3221225781 "$(journal 'rien de special')")
contient "cause" "STATUS_DLL_NOT_FOUND" "$r"

echo "== prefixe abime"
r=$(expliquer 1 "$(journal 'wine: could not load kernel32.dll, status c0000135')")
contient "cause" "prefixe Wine" "$r"
contient "a faire" "cidre setup" "$r"

echo "== FreeType"
r=$(expliquer 1 "$(journal 'Wine cannot find the FreeType font library.')")
contient "cause" "FreeType" "$r"
contient "a faire" "brew install freetype" "$r"

echo "== Vulkan"
r=$(expliquer 1 "$(journal 'err:   DxvkInstance: Failed to create Vulkan instance')")
contient "cause" "pilote Vulkan" "$r"

echo "== DXMT"
r=$(expliquer 1 "$(journal 'err:   Failed to create metal view')")
contient "cause" "DXMT" "$r"
contient "a faire" "d3d11 = dxvk" "$r"

echo "== anti-triche"
r=$(expliquer 1 "$(journal 'EasyAntiCheat: launcher error')")
contient "cause" "anti-triche" "$r"
r=$(expliquer 1 "$(journal '    profil  : langue=auto tso=false moteur=unreal anticheat=none etat=argent source=cidre')")
absent "anticheat=none n'est pas un anti-triche" "anti-triche" "$r"
r=$(expliquer 1 "$(journal '    profil  : moteur=unreal anticheat=eac etat=bronze')")
contient "anticheat=eac en est un" "anti-triche" "$r"

echo "== arret demande par cidre stop"
mkdir -p "$R/build/logs"; touch "$R/build/logs/arret-demande-1"
r=$(expliquer 1 "$(journal 'EasyAntiCheat: launcher error')")
contient "cause" "arrete a la demande" "$r"
absent "pas d'autre diagnostic" "anti-triche" "$r"
[ -f "$R/build/logs/arret-demande-1" ] && echec "marqueur d'arret non consomme" || ok "marqueur d'arret consomme"

echo "== GPU"
r=$(expliquer 1 "$(journal 'err:   Device error at frame 5379: Error Domain=MTLCommandBufferErrorDomain Code=2 "Caused GPU Timeout Error (00000002:kIOGPUCommandBufferCallbackErrorTimeout)"')")
contient "cause" "depassement de temps GPU" "$r"

echo "== plantage memoire"
r=$(expliquer 3221225477 "$(journal 'wine: Unhandled page fault on read access to 00006FFFB8B0A231 at address 00006FFFFF96BD9E (thread 01d4), starting debugger...')")
contient "cause" "acces memoire invalide" "$r"
contient "cite l'adresse" "00006FFFFF96BD9E" "$r"
absent "sans le prefixe de fil" "01d4:" "$(printf '%s' "$r" | head -1)"

echo "== code 53, client Steam ferme"
r=$(ETAT=ferme expliquer 53 "$(journal 'rien')")
contient "cause" "client Steam de macOS ne tournait pas" "$r"
contient "a faire" "ouvrir Steam" "$r"
echo "== code 53, client ouvert mais pas connecte"
r=$(ETAT=ouvert expliquer 53 "$(journal 'rien')")
contient "cause" "pas connecte" "$r"
echo "== code 53, client connecte"
r=$(ETAT=connecte expliquer 53 "$(journal 'rien')")
contient "cause" "alors que le client tourne" "$r"
echo "== code 53, jeu hors Steam"
r=$(APPID= expliquer 53 "$(journal 'rien')")
absent "ne parle pas du client" "client Steam" "$r"

echo "== tue, arrete"
contient "137" "memoire insuffisante" "$(expliquer 137 "$(journal 'rien')")"
contient "143" "arrete de l'exterieur" "$(expliquer 143 "$(journal 'rien')")"

echo "== inconnu : cite les dernieres erreurs du dernier lancement seulement"
r=$(expliquer 7 "$(journal '0030:err:ole:CoCreateInstance no class object
0030:err:winediag:truc une erreur parlante
0030:fixme:rien:rien pas une erreur')")
contient "cause" "code 7 sans signature connue" "$r"
contient "cite l'erreur" "une erreur parlante" "$r"
absent "pas le lancement precedent" "vieux.dll" "$r"
contient "a faire" "cidre doctor" "$r"

echo "== journal absent : ne plante pas"
r=$(expliquer 7 "$T/nexiste.pas")
contient "cause" "code 7" "$r"

echo
echo "$nb verifications, $ko en echec"
[ $ko -eq 0 ]
