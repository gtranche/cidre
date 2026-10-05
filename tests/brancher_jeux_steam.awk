# Pose ou retire l'option de lancement Cidre dans le localconfig.vdf de Steam
# (pour brancher_jeux_steam.sh). Le fichier est lu en entier, modifie en
# memoire, et ecrit dans SORTIE seulement si ses accolades restent equilibrees.
# Dit sur la sortie ce qui a ete fait, jeu par jeu.
#
#    LC_ALL=C CMD=<option> APPIDS="<appid> ..." NATIFS="<appid> ..." [RETIRER=1] \
#       SORTIE=<fichier> [SANS_FIN=1] awk -f brancher_jeux_steam.awk localconfig.vdf
#
# APPIDS : les jeux ou poser l'option (ou la retirer, avec RETIRER). NATIFS :
# ceux qui ont une version macOS, ou on retire la notre si elle y est. On ne
# touche jamais a une option que l'utilisateur a ecrite lui-meme. SANS_FIN : le
# fichier ne finit pas par un saut de ligne, la sortie non plus.

function nu(s) { gsub(/^[ \t\r]+|[ \t\r]+$/, "", s); return s }
function accolades(s,    o) { o = gsub(/[{]/, "{", s); return o - gsub(/[}]/, "}", s) }
# la ligne qui ferme le bloc ouvert apres la ligne deb
function fin_bloc(deb,    k, prof) {
   prof = 0
   for (k = deb + 1; k <= n; k++) { prof += accolades(l[k]); if (prof == 0) return k }
   return n
}
function inserer(pos, s,    k) { for (k = n; k >= pos; k--) l[k + 1] = l[k]; l[pos] = s; n++ }
function supprimer(pos,    k) { for (k = pos; k < n; k++) l[k] = l[k + 1]; delete l[n]; n-- }
# la ligne du bloc d'un jeu dans "apps" (qui se ferme en fin), 0 s'il n'en a pas
function bloc_du_jeu(appid, fin,    k) {
   for (k = apps; k < fin; k++) if (nu(l[k]) == "\"" appid "\"" && nu(l[k + 1]) == "{") return k
   return 0
}
# la ligne de l'option de lancement d'un jeu, 0 s'il n'en a pas
function option(ligne,    k, f2) {
   f2 = fin_bloc(ligne)
   for (k = ligne + 1; k < f2; k++) if (index(l[k], "\"LaunchOptions\"")) return k
   return 0
}
function est_la_notre(k) { return index(l[k], "lancer_depuis_steam.sh") > 0 }
function fait(appid, quoi) { fa[++nf] = appid; fq[nf] = quoi }

{ l[++n] = $0 }
END {
   cmd = ENVIRON["CMD"]; retirer = ENVIRON["RETIRER"]; sortie = ENVIRON["SORTIE"]
   for (k = 1; k < n; k++) if (nu(l[k]) == "\"apps\"" && nu(l[k + 1]) == "{") { apps = k; break }
   if (!apps) { print "section \"apps\" introuvable, rien ecrit" > "/dev/stderr"; exit 1 }
   match(l[apps], /^\t*/)
   tab = substr(l[apps], 1, RLENGTH) "\t"
   fin = fin_bloc(apps)

   na = split(ENVIRON["APPIDS"], a, " ")
   for (i = 1; i <= na; i++) {
      ligne = bloc_du_jeu(a[i], fin)
      if (!ligne) {
         if (retirer) continue
         inserer(apps + 2, tab "\"" a[i] "\"")
         inserer(apps + 3, tab "{")
         inserer(apps + 4, tab "\t\"LaunchOptions\"\t\t\"" cmd "\"")
         inserer(apps + 5, tab "}")
         fin += 4; fait(a[i], "creee")
         continue
      }
      k = option(ligne)
      if (retirer) {
         if (k && est_la_notre(k)) { supprimer(k); fin--; fait(a[i], "retiree") }
      } else if (!k) {
         inserer(ligne + 2, tab "\t\"LaunchOptions\"\t\t\"" cmd "\""); fin++; fait(a[i], "posee")
      } else if (est_la_notre(k))
         fait(a[i], "deja en place")
      else
         fait(a[i], "LAISSEE INTACTE (option personnelle deja presente)")
   }
   na = split(ENVIRON["NATIFS"], a, " ")
   for (i = 1; i <= na; i++) {
      ligne = bloc_du_jeu(a[i], fin_bloc(apps))
      if (!ligne) continue
      k = option(ligne)
      if (k && est_la_notre(k)) { supprimer(k); fait(a[i], "retiree (version macOS native)") }
   }

   prof = 0
   for (k = 1; k <= n; k++) prof += accolades(l[k])
   if (prof != 0) { print "accolades desequilibrees, rien ecrit" > "/dev/stderr"; exit 1 }
   for (k = 1; k <= n; k++) printf "%s%s", l[k], (k < n || !ENVIRON["SANS_FIN"] ? "\n" : "") > sortie
   close(sortie)
   for (i = 1; i <= nf; i++) printf "  %-9s %s\n", fa[i], fq[i]
}
