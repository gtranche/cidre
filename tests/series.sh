# Serie de correctifs, par arbre amont.
#
# Ce fichier est lu par etape1_appliquer_correctifs.sh et par
# verifier_reconstruction.sh. Il n'existe que pour ca : une liste recopiee dans
# deux scripts finit par deriver, et une verification qui ne verifie plus rien
# est pire que pas de verification du tout.
#
# Attend que $R designe la racine du projet.

serie_mesa() {
   for f in "$R"/00[0-9][0-9]-kosmickrisp-*.patch; do
      case "$(basename "$f")" in 0000-*) continue;; esac
      echo "$f"
   done
}

serie_wine() {
   ls "$R"/0028-*.patch "$R"/0035-*.patch "$R"/0036-*.patch \
      "$R"/0038-*.patch "$R"/0040-*.patch "$R"/0041-*.patch \
      "$R"/0062-*.patch "$R"/0064-*.patch "$R"/0065-*.patch \
      "$R"/0066-*.patch "$R"/0067-*.patch 2>/dev/null
}

serie_wine11() {
   ls "$R"/0048-*.patch "$R"/0049-*.patch "$R"/0068-*.patch 2>/dev/null
}

serie_vkd3d_proton() {
   ls "$R"/0004-*.patch "$R"/0007-*.patch "$R"/0008-*.patch \
      "$R"/0014-*.patch "$R"/0016-*.patch "$R"/0044-*.patch 2>/dev/null
}

serie_dxvk() {
   ls "$R"/0039-*.patch "$R"/0042-*.patch "$R"/0043-*.patch \
      "$R"/0061-*.patch "$R"/0071-*.patch 2>/dev/null
}
