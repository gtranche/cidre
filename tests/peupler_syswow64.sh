#!/bin/sh
# Peuple « syswow64 » d'un prefixe avec les DLL factices i386.
#
# Pourquoi ce script existe : « wineboot --init » lance bien la passe 32 bits de
# wine.inf -- la trace le dit, « start_rundll32 machine 14c starting
# C:\windows\syswow64\rundll32.exe » -- mais elle ne cree rien. Le repli sur les
# modules integres ne joue que pendant l'amorcage (is_prefix_bootstrap), et il ne
# suffit pas ici : un processus 32 bits ne peut charger kernel32 que si le
# fichier factice existe deja. La boucle est fermee, et Wine s'en sort sur
# x86_64 sans qu'on sache encore pourquoi pas ici.
#
# En attendant, on copie les factices d'un prefixe qui en a. Elles ne
# contiennent pas de code : leur seul role est de faire trouver le module
# integre au chargeur.
#
#   peupler_syswow64.sh <prefixe-cible> [prefixe-source]
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
cible=${1:?usage: peupler_syswow64.sh <prefixe-cible> [prefixe-source]}
source=${2:-$R/wine/pfx-i386}

[ -d "$cible/drive_c/windows/syswow64" ] || { echo "pas de syswow64 dans $cible" >&2; exit 1; }
[ -n "$(ls -A "$source/drive_c/windows/syswow64")" ] || { echo "$source n'a rien a copier" >&2; exit 1; }

cp -a "$source/drive_c/windows/syswow64/." "$cible/drive_c/windows/syswow64/"
echo "$(ls "$cible/drive_c/windows/syswow64" | wc -l) entrees dans $cible/drive_c/windows/syswow64"
