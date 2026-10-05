# Compare les jeux installes a la derniere version publiee (pour `cidre updates`).
#
#    awk -v paires="<appid>=<build installe> ..." [-v texte=1] -f majs_steam.awk <appinfo.txt>
#
# appinfo.txt est la sortie de `steamcmd +app_info_print <appid>` : pour chaque
# application, sa fiche, dont le numero de build de la branche publique. Un jeu
# est a jour quand son build installe est celui-la. Sort du JSON, ou (texte=1)
# une ligne par jeu.

# le build de la branche publique d'une fiche, ou rien
function build_public(fiche,    s, i, k) {
   if (!match(fiche, /"branches"[ \t\r\n]*[{][ \t\r\n]*"public"[ \t\r\n]*[{][^{}]*"buildid"[ \t\r\n]*"[0-9]+"/))
      return ""
   s = substr(fiche, RSTART, RLENGTH)
   # le bloc "public" s'ouvre a la derniere accolade ; on veut son premier buildid
   i = 0
   while ((k = index(substr(s, i + 1), "{")) > 0) i += k
   s = substr(s, i + 1)
   match(s, /"buildid"[ \t\r\n]*"[0-9]+"/)
   s = substr(s, RSTART, RLENGTH - 1)
   match(s, /[0-9]+$/)
   return substr(s, RSTART)
}
function clore(    b) {
   if (appid != "" && (b = build_public(fiche)) != "") publie[appid] = b + 0
   appid = ""; fiche = ""
}
/^AppID : [0-9]+/ {
   clore()
   match($0, /^AppID : [0-9]+/)
   appid = substr($0, 9, RLENGTH - 8) + 0
   fiche = substr($0, RLENGTH + 1) "\n"
   next
}
appid != "" { fiche = fiche $0 "\n" }
END {
   clore()
   n = split(paires, p, " ")
   sep = ""
   if (!texte) printf "["
   for (i = 1; i <= n; i++) {
      # pas de build connu d'un cote ou de l'autre : on ne dit rien
      if (p[i] !~ /^[0-9]+=[0-9]+$/) continue
      split(p[i], q, "=")
      a = q[1] + 0; installe = q[2] + 0
      if (!(a in publie)) continue
      a_jour = (installe == publie[a])
      if (texte)
         printf "%-9d %s\n", a, (a_jour ? "a jour" : sprintf("MISE A JOUR : build %d -> %d", installe, publie[a]))
      else
         printf "%s{\"appid\": %d, \"build_installe\": %d, \"build_disponible\": %d, \"a_jour\": %s}", sep, a, installe, publie[a], (a_jour ? "true" : "false")
      sep = ", "
   }
   if (!texte) print "]"
}
