# Masque, dans un fichier texte du diagnostic (tests/diag_cidre.sh), ce qui
# identifie le testeur : son dossier personnel et son nom de session, son nom
# et celui de son Mac, ses comptes Steam (identifiants, noms de connexion et de
# profil), le numero de serie du Mac, les jetons, les adresses e-mail et IP.
# Le reste passe tel quel : un journal masque doit rester lisible.
#
#   awk -f masquer_diag.awk <fichier>  > <fichier masque>
#
# Environnement :
#   DIAG_LITTERAUX  fichier de lignes `categorie TAB texte TAB remplacement` :
#                   les textes propres a cette machine (dossier personnel, nom
#                   de session, comptes Steam, noms du Mac...), remplaces sans
#                   tenir compte de la casse, dans l'ordre du fichier (le plus
#                   long d'abord : /Users/marie avant marie)
#   DIAG_COMPTES    fichier ou ajouter, a la fin, `categorie TAB nombre` pour
#                   chaque categorie masquee au moins une fois
#
# Categories : chemin, compte_steam, identifiant_steam, machine, email, ip, jeton.
# awk d'origine de macOS (one true awk) : pas de \b ni de regarde-autour, d'ou
# les verifications de bord a la main.

BEGIN {
   nl = 0
   f = ENVIRON["DIAG_LITTERAUX"]
   if (f != "") {
      while ((getline ligne < f) > 0) {
         n = split(ligne, c, "\t")
         if (n < 3 || length(c[2]) < 3) continue
         nl++; lcat[nl] = c[1]; ltxt[nl] = tolower(c[2]); lrep[nl] = c[3]
      }
      close(f)
      # le plus long d'abord : « marie_jeux » avant « marie »
      for (i = 2; i <= nl; i++) for (j = i; j > 1 && length(ltxt[j]) > length(ltxt[j - 1]); j--) {
         t = lcat[j]; lcat[j] = lcat[j - 1]; lcat[j - 1] = t
         t = ltxt[j]; ltxt[j] = ltxt[j - 1]; ltxt[j - 1] = t
         t = lrep[j]; lrep[j] = lrep[j - 1]; lrep[j - 1] = t
      }
   }
}

function compter(cat, n) { if (n > 0) total[cat] += n }

# remplace chaque occurrence d'un texte, sans tenir compte de la casse
function litteral(s, bas, rep,    lo, out, i, n, k) {
   lo = tolower(s); out = ""; n = 0; k = length(bas)
   while ((i = index(lo, bas)) > 0) {
      out = out substr(s, 1, i - 1) rep
      s = substr(s, i + k); lo = substr(lo, i + k); n++
   }
   nb = n
   return out s
}

# remplace chaque correspondance d'une expression ; `garde` : nombre de
# caracteres du debut de la correspondance a garder (la cle d'un jeton) ;
# `bords` : refuser une correspondance collee a une lettre, un chiffre ou un
# point (une version 1.0.0.1, un hexadecimal plus long) ; `ci` : sans casse ;
# `filtre` : nom d'une verification de plus (ipv4)
function expr(s, re, rep, ci, bords, filtre,    lo, out, n, av, ap, m, ok, d, l) {
   out = ""; n = 0
   while (1) {
      lo = ci ? tolower(s) : s
      if (!match(lo, re)) break
      d = RSTART; l = RLENGTH
      m = substr(s, d, l)
      av = d > 1 ? substr(s, d - 1, 1) : ""
      ap = substr(s, d + l, 1)
      ok = 1
      if (bords && (av ~ /[A-Za-z0-9.:]/ || ap ~ /[A-Za-z0-9]/ || (ap == "." && substr(s, d + l + 1, 1) ~ /[0-9]/))) ok = 0
      if (ok && filtre == "ipv4") ok = ipv4_a_masquer(m)
      if (ok && filtre == "jeton") { m = jeton(m); ok = m != "" }
      if (ok) { out = out substr(s, 1, d - 1) (filtre == "jeton" ? m : rep); n++ }
      else out = out substr(s, 1, d + l - 1)
      s = substr(s, d + l)
      if (l == 0) { out = out substr(s, 1, 1); s = substr(s, 2) }
   }
   nb = n
   return out s
}

function ipv4_a_masquer(m,    o, i) {
   split(m, o, ".")
   for (i = 1; i <= 4; i++) if (o[i] + 0 > 255 || (length(o[i]) > 1 && substr(o[i], 1, 1) == "0")) return 0
   if (o[1] == 127 || m == "0.0.0.0" || o[1] == 255) return 0
   return 1
}

# `cle=valeur`, `cle: "valeur"` : on garde la cle, la valeur part. Une valeur
# courte et banale (true, 0, vide) n'est pas un secret : on la laisse.
function jeton(m,    i, cle, val) {
   if (!match(m, /[:=][ \t"']*/)) return ""
   cle = substr(m, 1, RSTART + RLENGTH - 1); val = substr(m, RSTART + RLENGTH)
   if (length(val) < 6 || val ~ /^(true|false|null|none|vide|absent)$/ || substr(val, 1, 1) == "‹") return ""
   return cle "‹jeton›"
}

{
   s = $0
   # d'abord ce qui contient des noms (une adresse e-mail, un jeton) : entiers
   s = expr(s, "eyj[a-z0-9_-]{8,}\\.[a-z0-9_-]{8,}\\.[a-z0-9_-]*", "‹jeton›", 1, 0); compter("jeton", nb)
   s = expr(s, "(access_?token|refresh_?token|token|jeton|password|passwd|mot_de_passe|secret|authorization|bearer|api[_-]?key|cookie|sessionid|webcookie|ssfn|crashreporterkey|sleepwakeuuid|deviceidentifierforvendor|deviceidentifier)[\"' \t]*[:=][ \t\"']*[^ \t\"',;&}]+", "", 1, 0, "jeton"); compter("jeton", nb)
   s = expr(s, "[a-z0-9._%+-]+@[a-z0-9-]+(\\.[a-z0-9-]+)*\\.[a-z][a-z]+", "‹e-mail›", 1, 0); compter("email", nb)
   for (i = 1; i <= nl; i++) { s = litteral(s, ltxt[i], lrep[i]); compter(lcat[i], nb) }
   # comptes Steam : SteamID64, [U:1:compte], dossier userdata/<compte>
   s = expr(s, "7656119[0-9]{10}", "7656119‹…›", 0, 1); compter("identifiant_steam", nb)
   s = expr(s, "\\[u:1:[0-9]+\\]", "[U:1:‹…›]", 1, 0); compter("identifiant_steam", nb)
   s = expr(s, "userdata[/\\\\][0-9]+", "userdata/‹…›", 1, 0); compter("identifiant_steam", nb)
   # adresses IP : IPv4 (pas 127.x ni 0.0.0.0), IPv6 et adresses materielles
   s = expr(s, "[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}", "‹ip›", 0, 1, "ipv4"); compter("ip", nb)
   s = expr(s, "([0-9a-f]{1,4}:){4,7}[0-9a-f]{1,4}", "‹ip›", 1, 1); compter("ip", nb)
   s = expr(s, "fe80::[0-9a-z:%]+", "‹ip›", 1, 0); compter("ip", nb)
   print s
}

END {
   f = ENVIRON["DIAG_COMPTES"]
   if (f != "") for (k in total) printf "%s\t%d\n", k, total[k] >> f
}
