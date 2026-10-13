#!/bin/sh
# Version de Windows vue par le jeu qu'on lance (option windows_version de son
# profil : win7, winxp... ; win10 sans l'option). Appele par
# lancer_depuis_steam.sh avant de demarrer Wine, et par `cidre set` pour valider.
#
#   version_windows.sh liste              les valeurs admises, une par ligne
#   version_windows.sh valider <valeur>   la valeur sous sa forme canonique ; code 1 et un message si elle est inconnue
#   version_windows.sh poser [<valeur>]   regle le prefixe ($WINEPREFIX) pour le lancement qui suit ; sans valeur : le defaut
#
# Tous les jeux partagent un prefixe : la version ne peut pas etre un reglage
# qu'on y pose une fois. Elle est donc reglee a CHAQUE lancement, pour le jeu
# qu'on lance, par la valeur HKEY_CURRENT_USER\Software\Wine\Version :
#   - ntdll la lit au demarrage de chaque processus, apres la cle par application
#     (AppDefaults\<exe>\Version) et AVANT la version du prefixe (HKLM, celle de
#     `winecfg -v`) : tous les processus du jeu la voient, quel que soit leur nom
#     (lanceur, executable final, outils qu'il demarre) -- c'est la portee d'une
#     bouteille CrossOver, d'ou viennent ces valeurs. La cle par application ne
#     suit que le nom d'un executable : il faudrait enumerer ceux du jeu, et
#     deux jeux qui ont un `Launcher.exe` se la disputeraient ;
#   - c'est une seule ligne de user.reg, ecrite sans demarrer Wine (le prefixe
#     ne doit etre tenu par aucun wineserver, cf. reglages_jeu.sh) ; un jeu sans
#     l'option la RETIRE : rien ne passe d'un jeu au suivant.
# La version du prefixe (HKLM) reste celle de Wine, Windows 10. Si elle a ete
# changee pour tous les jeux (`winecfg -v`, que les lanceurs d'avant devaient
# appeler ; winecfg ou winetricks a la main), elle est remise : on la reconnait
# a la signature de winecfg -- ProductName « Microsoft Windows ... » la ou
# wine.inf ecrit « Windows 10 Pro », avec un autre numero de build que 19045 ;
# ou plus aucune valeur NT et un VersionNumber de Windows 9x.
# Limite, celle de la cle par application de Wine : un programme qui lit la
# version dans HKLM au lieu de la demander a Windows y trouve Windows 10.
#
# Codes de retour de `poser` : 0 = regle (ou rien a faire) ; 3 = le prefixe est
# tenu par un wineserver, ou n'existe pas encore : rien n'est ecrit ; 1 = erreur.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
PFX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
DEFAUT=win10
# Les noms que ntdll connait (dlls/ntdll/version.c), de Windows 2000 a 11 ; ni
# les Windows 9x ni les editions serveur.
ADMISES="win11 win10 win81 win8 win7 vista winxp64 winxp win2k"

canonique() { # <valeur> : la forme que Wine attend (il compare a la lettre), vide si elle est inconnue
   v=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
   case $v in winvista) v=vista ;; win2000) v=win2k ;; win8.1) v=win81 ;; esac
   case $v in ''|*[!a-z0-9]*) return 0 ;; esac
   case " $ADMISES " in *" $v "*) echo "$v" ;; esac
}
liste() { echo $ADMISES | sed 's/ /, /g'; }

# La donnee d'une valeur dans une ruche, sans ses guillemets ; vide si la cle ou
# la valeur manque. <ruche> <cle, barres doublees comme dans la ruche> <nom>
valeur() {
   [ -f "$PFX/$1" ] || return 0
   CLE=$2 NOM=$3 LC_ALL=C awk '
      BEGIN { cle = "[" tolower(ENVIRON["CLE"]) "]"; nom = "\"" tolower(ENVIRON["NOM"]) "\"=" }
      /^\[/ { if (dedans) exit; k = tolower($0); sub(/\][^\]]*$/, "]", k); dedans = (k == cle); next }
      dedans && index(tolower($0), nom) == 1 { v = substr($0, length(nom) + 1); gsub(/^"|"$/, "", v); print v; exit }' "$PFX/$1"
}
# Ecrit sous <cle> de <ruche> les lignes `nom TAB donnee` de l'entree (donnee
# vide : la valeur est retiree), par l'ecriture de registre de reglages_jeu.sh.
ecrire() { WINEPREFIX=$PFX sh "$R/tests/reglages_jeu.sh" - ruche "$1" "$2" >/dev/null; }
existe() { LC_ALL=C grep -q -i -F "[$2]" "$PFX/$1" 2>/dev/null; }   # <ruche> <cle, barres doublees>

# La version du prefixe, si winecfg l'a changee : « <produit> (build <n>) », vide sinon.
collee() {
   [ -f "$PFX/system.reg" ] || return 0
   NT='[software\\microsoft\\windows nt\\currentversion]' NT32='[software\\wow6432node\\microsoft\\windows nt\\currentversion]' \
   W9='[software\\microsoft\\windows\\currentversion]' LC_ALL=C awk '
      function donnee(l) { l = substr(l, index(l, "=") + 1); gsub(/^"|"$/, "", l); return l }
      /^\[/ {
         k = tolower($0); sub(/\][^\]]*$/, "]", k)
         ou = (k == ENVIRON["NT"] || k == ENVIRON["NT32"]) ? "nt" : (k == ENVIRON["W9"]) ? "9x" : ""
         if (ou == "nt") vu = 1
         next
      }
      ou == "nt" && /^"CurrentBuild"=/ { a_build = 1; if (donnee($0) != "19045") build = donnee($0) }
      ou == "nt" && /^"ProductName"="Microsoft Windows/ { produit = donnee($0) }
      ou == "9x" && /^"VersionNumber"=/ { v9 = donnee($0) }
      ou == "9x" && /^"ProductName"=/ { p9 = donnee($0) }
      END {
         if (build != "" && produit != "") print produit " (build " build ")"
         else if (vu && !a_build && v9 != "") print (p9 != "" ? p9 : "Windows 9x") " (" v9 ")"
      }' "$PFX/system.reg"
}
# Remet la version du prefixe a celle que wine.inf y pose (Wine 11 : Windows 10,
# build 19045), valeur par valeur ce que `winecfg -v` ecrit, dans les deux vues
# du registre (64 et 32 bits). Rend le code de la premiere ecriture qui echoue.
decoller() {
   for vue in 'Software' 'Software\Wow6432Node'; do
      printf '%s\t%s\n' CurrentVersion '"6.3"' CurrentMajorVersionNumber dword:0000000a CurrentMinorVersionNumber dword:00000000 \
         CurrentBuild '"19045"' CurrentBuildNumber '"19045"' ProductName '"Windows 10 Pro"' UBR dword:000016a4 CSDVersion '' |
         ecrire system.reg "$vue\\Microsoft\\Windows NT\\CurrentVersion" || return $?
      printf '%s\t\n' VersionNumber SubVersionNumber ProductName |
         ecrire system.reg "$vue\\Microsoft\\Windows\\CurrentVersion" || return $?
   done
   # (CurrentControlSet est un lien vers ControlSet001 : la ruche ne connait que lui)
   C='System\ControlSet001\Control'
   if existe system.reg 'System\\ControlSet001\\Control\\ProductOptions'; then
      printf 'ProductType\t"WinNT"\n' | ecrire system.reg "$C\\ProductOptions" || return $?
   fi
   if existe system.reg 'System\\ControlSet001\\Control\\Windows'; then
      printf 'CSDVersion\tdword:00000000\n' | ecrire system.reg "$C\\Windows" || return $?
   fi
   if existe system.reg 'System\\ControlSet001\\Control\\Session Manager\\Environment'; then
      printf 'OS\t"Windows_NT"\n' | ecrire system.reg "$C\\Session Manager\\Environment" || return $?
   fi
   return 0
}
occupe() { # <code d'ecriture> <la version qui reste en place>
   [ "$1" -eq 3 ] || { echo "    version de Windows : echec de l'ecriture du registre du prefixe ; elle reste $2"; exit 1; }
   echo "    version de Windows : le prefixe est en cours d'usage (un autre jeu tourne), registre laisse ; elle reste $2 pour ce lancement"
   exit 3
}

case ${1:-} in
   liste) printf '%s\n' $ADMISES ;;
   valider)
      v=$(canonique "${2:-}")
      [ -n "$v" ] || { echo "windows_version attend une de ces valeurs : $(liste)" >&2; exit 1; }
      echo "$v" ;;
   poser)
      voulue=$DEFAUT
      if [ -n "${2:-}" ]; then
         voulue=$(canonique "$2")
         if [ -z "$voulue" ]; then
            echo "    version de Windows : windows_version = « $2 » n'est pas une valeur connue ($(liste)) : le jeu est lance en $DEFAUT"
            voulue=$DEFAUT
         fi
      fi
      if [ ! -f "$PFX/user.reg" ]; then
         [ "$voulue" = "$DEFAUT" ] || echo "    version de Windows : le prefixe n'existe pas encore, $voulue sera pose au prochain lancement"
         exit 3
      fi
      avant=$(valeur user.reg 'Software\\Wine' Version)
      c=$(collee)
      if [ -n "$c" ]; then
         decoller || occupe $? "celle du prefixe, $c"
         echo "    version de Windows : le prefixe etait regle sur $c pour tous les jeux (winecfg -v) : remis a Windows 10 ; elle se regle par jeu (cidre set <id> windows_version <version>)"
      fi
      if [ "$voulue" = "$DEFAUT" ]; then
         [ -n "$avant" ] || exit 0
         printf 'Version\t\n' | ecrire user.reg 'Software\Wine' || occupe $? "$avant"
         [ "$avant" = "$DEFAUT" ] || echo "    version de Windows : $avant etait reste dans le prefixe (un autre jeu) : retire, ce jeu tourne en $DEFAUT"
      else
         if [ "$avant" != "$voulue" ]; then
            printf 'Version\t"%s"\n' "$voulue" | ecrire user.reg 'Software\Wine' || occupe $? "${avant:-$DEFAUT}"
         fi
         echo "    version de Windows : $voulue pour ce jeu (option windows_version) ; les autres restent en $DEFAUT"
      fi ;;
   *) echo "usage : version_windows.sh liste | valider <valeur> | poser [<valeur>]" >&2; exit 2 ;;
esac
