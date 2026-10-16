# Les depots de langue d'un jeu qui manquent a son installation (pour `cidre`).
#
#    awk -v appid=<appid> -v langue=<nom Steam> [-v os=windows] -f depots_langue.awk <appmanifest.acf> <appinfo.txt>
#
# appinfo.txt est la sortie de `steamcmd +app_info_print <appid>`. Un depot de
# langue y porte "config" { "language" "french" } ; Steam ne l'installe que pour
# cette langue. Ecrit les depots de la langue voulue, pour cet os (ou sans os),
# que l'appmanifest ne compte pas dans "InstalledDepots" -- rien quand le jeu est
# entier (ou n'a pas de depot de langue : Sherlock Holmes Chapter One met toutes
# ses langues dans un seul depot). On laisse de cote les depots de DLC
# (dlcappid : le compte ne les a pas forcement) et ceux d'une autre application
# (depotfromapp : redistribuables), et ceux sans manifeste public (rien a
# telecharger : la mise a jour serait retentee a chaque lancement).

function cle(s) { sub(/^[ \t]*"/, "", s); sub(/".*$/, "", s); return s }
function valeur(s) { sub(/"[ \t]*$/, "", s); sub(/^.*"/, "", s); return s }
{ sub(/\r$/, "") }

# l'appmanifest : AppState > InstalledDepots > <depot>
FNR == NR {
   if ($0 ~ /^[ \t]*"[^"]*"[ \t]*$/) { attente = cle($0); next }
   if ($0 ~ /^[ \t]*[{][ \t]*$/) { pile[++n] = attente; if (n == 3 && pile[2] == "InstalledDepots") installe[attente] = 1; next }
   if ($0 ~ /^[ \t]*[}][ \t]*$/) { n--; next }
   next
}

# appinfo : de "AppID : <appid>" a la fiche suivante
/^AppID : [0-9]+/ { dedans = (substr($0, 9) + 0 == appid + 0); m = 0; next }
!dedans { next }
/^[ \t]*"[^"]*"[ \t]*$/ { attente = cle($0); next }
/^[ \t]*[{][ \t]*$/ { chemin[++m] = attente; next }
/^[ \t]*[}][ \t]*$/ { if (m > 0) m--; next }
/^[ \t]*"[^"]*"[ \t]+"[^"]*"[ \t]*$/ {
   # <appid> > depots > <depot> > ...
   if (m >= 3 && chemin[2] == "depots" && chemin[3] ~ /^[0-9]+$/) {
      d = chemin[3]; vu[d] = 1
      k = cle($0); v = valeur($0)
      if (m == 3 && (k == "dlcappid" || k == "depotfromapp")) exclu[d] = 1
      if (m == 4 && chemin[4] == "config" && k == "language") lang[d] = v
      if (m == 4 && chemin[4] == "config" && k == "oslist") oslist[d] = v
      if (m == 5 && chemin[4] == "manifests" && chemin[5] == "public" && k == "gid") publie[d] = 1
   }
   next
}
END {
   if (os == "") os = "windows"
   for (d in vu) {
      if (exclu[d] || !publie[d] || lang[d] == "" || lang[d] != langue) continue
      if (oslist[d] != "" && index("," oslist[d] ",", "," os ",") == 0) continue
      if (!(d in installe)) print d
   }
}
