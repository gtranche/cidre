#!/usr/bin/env python3
"""rapport.py <dossier-de-la-nuit> [jeux.tsv] : rapport A/B du banc nocturne.

Lit <nuit>/resultats.tsv (lignes de manche_jeu.sh et de temoins.sh), <nuit>/A.banc-arbre, <nuit>/B.banc-arbre et
<nuit>/refus.txt ; ecrit <nuit>/rapport.md (tableaux A/B, ecarts signales) et <nuit>/synthese.txt (une ligne).
"""
import os
import sys

nuit = sys.argv[1]
jeux_tsv = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "jeux.tsv")


def lire(chemin):
    try:
        with open(chemin, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def etiquette(t):
    d = {}
    for l in lire(os.path.join(nuit, t + ".banc-arbre")).splitlines():
        if "=" in l:
            k, v = l.split("=", 1)
            d[k] = v
    return d


def nombre(x):
    try:
        return float(x)
    except ValueError:
        return None


seuils = {}
for l in lire(jeux_tsv).splitlines():
    c = l.split("\t")
    if l.startswith("#") or len(c) < 5:
        continue
    seuils[c[0]] = nombre(c[4]) or 15.0

jeux, temoins, ordre_j, ordre_t = {}, {}, [], []
for l in lire(os.path.join(nuit, "resultats.tsv")).splitlines():
    c = l.split("\t")
    if c[0] == "jeu" and len(c) >= 13:
        nom, t = c[1], c[2]
        jeux.setdefault(nom, {})[t] = dict(zip(
            ["statut", "demarrage", "vivant", "arret", "plateau", "mediane", "releves", "exc", "err", "rem"], c[3:13]))
        if nom not in ordre_j:
            ordre_j.append(nom)
    elif c[0] == "temoin" and len(c) >= 7:
        nom, t = c[1], c[2]
        temoins.setdefault(nom, {})[t] = dict(zip(["statut", "duree", "resume", "mesures"], c[3:7]))
        if nom not in ordre_t:
            ordre_t.append(nom)

A, B = etiquette("A"), etiquette("B")
refus = lire(os.path.join(nuit, "refus.txt")).strip()
date = os.path.basename(nuit.rstrip("/"))
ecarts = []  # (gravite, texte) ; gravite : 2 regression, 1 a voir, 0 information


def vide():
    return {"statut": "-", "plateau": "-", "mediane": "-", "exc": "-", "err": "-", "arret": "-", "vivant": "-",
            "demarrage": "-", "releves": "-", "rem": "", "duree": "-", "resume": "", "mesures": "-"}


lignes_j = []
for nom in ordre_j:
    a, b = jeux[nom].get("A", vide()), jeux[nom].get("B", vide())
    pa, pb = nombre(a["plateau"]), nombre(b["plateau"])
    ec = ""
    if pa and pb:
        e = (pb - pa) / pa * 100
        ec = "%+.0f %%" % e
        s = seuils.get(nom, 15.0)
        if abs(e) > s:
            ecarts.append((2 if e < 0 else 0, "%s : %s images/s (%.1f -> %.1f, seuil %.0f %%)" % (nom, ec, pa, pb, s)))
        for p in (60, 120):
            if abs(pa - p) < 1.5 and abs(pb - p) < 1.5:
                ecarts.append((1, "%s : A et B a %d images/s, plafond vsync probable (mesure sans valeur)" % (nom, p)))
    if "-" in (a["statut"], b["statut"]):
        pass  # manche non passee (refus ou fin de serie)
    elif a["statut"] != b["statut"]:
        if b["statut"] == "ok":
            # A hors service : pas de comparaison possible pour ce jeu cette nuit
            ecarts.append((1, ("%s : %s en A, ok en B : comparaison impossible %s" % (nom, a["statut"], a["rem"])).strip()))
        else:
            ecarts.append((2, ("%s : %s en B (A : %s) %s" % (nom, b["statut"], a["statut"], b["rem"])).strip()))
    elif b["statut"] not in ("ok", "-"):
        ecarts.append((1, ("%s : %s en A et en B %s" % (nom, b["statut"], b["rem"])).strip()))
    xa, xb = nombre(a["exc"]), nombre(b["exc"])
    if xa is not None and xb is not None and xb > xa:
        ecarts.append((1, "%s : %d exception(s) au journal en B contre %d en A" % (nom, xb, xa)))
    lignes_j.append("| %s | %s | %s | %s | %s | %s | %s | %s/%s | %s/%s | %s/%s |" % (
        nom, a["statut"], a["plateau"], b["statut"], b["plateau"], ec or "-", "%s/%s" % (a["mediane"], b["mediane"]),
        a["demarrage"], b["demarrage"], a["arret"], b["arret"], a["exc"], b["exc"]))

lignes_t = []
for nom in ordre_t:
    a, b = temoins[nom].get("A", vide()), temoins[nom].get("B", vide())
    if nom == "*" or "-" in (a["statut"], b["statut"]):
        pass  # passage interrompu (refus) : rien a comparer, le refus est dit en tete
    elif a["statut"] != b["statut"]:
        if b["statut"] == "ok":
            ecarts.append((0, "temoin %s : %s en A, ok en B" % (nom, a["statut"])))
        else:
            ecarts.append((2, "temoin %s : %s en B (A : %s) -- %s" % (nom, b["statut"], a["statut"], b["resume"])))
    elif b["statut"] not in ("ok", "-"):
        ecarts.append((1, "temoin %s : %s en A et en B -- %s" % (nom, b["statut"], b["resume"])))
    mes = ""
    if a["mesures"] != "-" or b["mesures"] != "-":
        mes = "%s / %s" % (a["mesures"].strip() or "-", b["mesures"].strip() or "-")
    res = b["resume"] if b["resume"] == a["resume"] else "A : %s ; B : %s" % (a["resume"], b["resume"])
    lignes_t.append("| %s | %s | %s | %s/%s | %s | %s |" % (
        nom, a["statut"], b["statut"], a["duree"], b["duree"], mes or "-", res.replace("|", "/")))

ecarts.sort(key=lambda x: -x[0])
marque = {2: "**REGRESSION**", 1: "a voir", 0: "info"}
nj_ok = sum(1 for n in ordre_j if jeux[n].get("B", {}).get("statut") == "ok")
nt_ok = sum(1 for n in ordre_t if temoins[n].get("B", {}).get("statut") == "ok")
nreg = sum(1 for g, _ in ecarts if g == 2)
nvoir = sum(1 for g, _ in ecarts if g == 1)

candidat = B.get("liste", "?")
if candidat.startswith("aucune"):
    nom_b = "A, contre-epreuve A/A"
else:
    d = os.path.dirname(candidat.split(" (")[0])
    nom_b = os.path.basename(os.path.dirname(d)) if os.path.basename(d) == "livraison" else os.path.basename(d)
sec = " (a sec)" if os.path.exists(os.path.join(nuit, "a-sec")) else ""
if refus:
    synthese = "%s banc nocturne%s : REFUS -- %s" % (date, sec, refus.splitlines()[0])
else:
    tete = "%s banc A/B%s (B = %s) : jeux B %d/%d ok, temoins B %d/%d ok" % (
        date, sec, nom_b, nj_ok, len(ordre_j), nt_ok, len(ordre_t))
    if nreg or nvoir:
        premier = next(t for g, t in ecarts if g >= 1)
        synthese = "%s ; %d regression(s), %d a voir -- %s" % (tete, nreg, nvoir, premier)
    else:
        synthese = tete + " ; RAS"

out = ["# Banc nocturne Cidre -- %s" % date, "", "**%s**" % synthese, ""]
if refus:
    out += ["## Refus", "", "```", refus, "```", ""]
out += ["## Arbres", "", "| | A (installe) | B (candidat) |", "|---|---|---|"]
for k in ("liste", "ntdll.so", "ntdll.dll", "xtajit64", "xtajit", "kk", "cidre", "monte"):
    va, vb = A.get(k, "-"), B.get(k, "-")
    out.append("| %s | %s | %s%s |" % (k, va, vb, "" if va == vb or k in ("liste", "monte") else " (*)"))
out += ["", "(*) differe de A.", ""]
if ordre_j:
    out += ["## Jeux (au menu)", "",
            "| Jeu | A | A img/s | B | B img/s | ecart | mediane A/B | demarrage s A/B | arret A/B | exceptions A/B |",
            "|---|---|---|---|---|---|---|---|---|---|"] + lignes_j + [
            "", "img/s : moyenne des 15 derniers releves de 2 s ; mediane : releves apres les 30 premieres s.", ""]
if ordre_t:
    out += ["## Temoins hors jeu", "", "| Temoin | A | B | duree s A/B | mesures A / B | resume |",
            "|---|---|---|---|---|---|"] + lignes_t + [""]
out += ["## Ecarts signales", ""]
out += ["- %s : %s" % (marque[g], t) for g, t in ecarts] or ["Aucun."]
out += ["", "Journaux : `%s/` (play-, stop-, journal-, images-<jeu>-<A|B> ; temoins-<A|B>/)." % nuit, ""]

with open(os.path.join(nuit, "rapport.md"), "w", encoding="utf-8") as f:
    f.write("\n".join(out))
with open(os.path.join(nuit, "synthese.txt"), "w", encoding="utf-8") as f:
    f.write(synthese + "\n")
print(synthese)
