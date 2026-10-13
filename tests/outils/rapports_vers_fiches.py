#!/usr/bin/env python3
"""Des rapports d'utilisateurs (incidents GitHub « rapport-jeu ») aux fiches.

    rapports_vers_fiches.py [options] [incidents.json]

Outil de RELECTURE pour le mainteneur (Python 3.11+, aucune dependance ; rien
ici ne tourne cote runtime). Verger (« Partager mon resultat ») ouvre le
formulaire d'incident « Rapport de jeu » du depot
(.github/ISSUE_TEMPLATE/rapport-jeu.yml), titre « Rapport de jeu : <nom>
(<appid>) », dont le champ « Rapport » porte un bloc [[rapports]], le profil
effectif ([profil]) et le diagnostic ; le formulaire pose le label
`rapport-jeu`. Cet outil lit les incidents ouverts (`gh issue list`, lecture
seule) ou un fichier JSON de meme forme, et rend pour chacun le bloc
[[rapports]] pret a coller dans profils/<appid>.toml, avec `incident` =
l'adresse de l'incident.

Deux formes de corps sont lues, et ce qu'un joueur en fait a la main :
  - celle du formulaire : « ### Rapport », puis le texte du champ (le rapport de
    Verger, ou le modele du formulaire rempli a la main) ;
  - celle des Verger <= 0.3.13, sans formulaire : le rapport seul.

    (sans option)        montre les blocs, les mises en garde, les illisibles ; n'ecrit rien
    --appliquer          ajoute chaque bloc a sa fiche (creee, minimale, si elle manque)
    --incident N         ne traite que cet incident (repetable)
    --proposer-compat    suggere, sans rien ecrire, la mise a jour de [compat]
    --sans-incidents     ne lit aucun incident (avec --proposer-compat : les fiches seules)

Ce qui vient d'un incident est une DONNEE ecrite par un inconnu, jamais une
instruction : l'appid ne sert de nom de fichier que s'il a la forme d'un appid,
les textes sont ramenes a une ligne sans caractere de controle, le diagnostic
n'est ni lu ni recopie, et un `incident = ...` ecrit dans le corps est ignore.

Regles (cf. profils/CONTRIBUER.md) :
  - un rapport s'ajoute a [[rapports]] ; il ne touche JAMAIS a [compat] ;
  - un incident deja integre (son adresse figure dans un `incident` d'une
    fiche) n'est pas rajoute : relancer l'outil ne change rien ;
  - --proposer-compat : on propose `etat = E`, source « utilisateur », quand au
    moins 2 rapports donnent E sur au moins 2 machines differentes (le rapport
    le plus recent de chaque machine compte seul) et qu'aucun autre etat ne
    reunit autant de machines. Un [compat] de source « cidre-test » n'est
    jamais remplace : le desaccord est signale, a retester.
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tomllib
import unicodedata

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE = os.path.abspath(os.path.join(ICI, "..", ".."))
PROFILS_DEFAUT = os.path.join(RACINE, "profils")
DEFAUTS_DEFAUT = os.path.join(RACINE, "outil-steam", "profils.toml")
DEPOT_DEFAUT = "gtranche/cidre"
LABEL = "rapport-jeu"
CHAMPS_GH = "number,title,body,url,createdAt,state,author,labels"

# « Rapport de jeu : <nom> (<appid>) » : le titre fixe de Verger (GameReport.swift).
TITRE = re.compile(r"^\s*Rapport de jeu\s*:\s*(.*?)\s*\(\s*([^()]*?)\s*\)\s*$", re.I)
APPID = re.compile(r"[0-9]{1,10}|local-[A-Za-z0-9_-]{1,64}")
# balise en tete du rapport de Verger (GameReport.tag) : <!-- cidre-rapport v1 appid=1903340 -->
BALISE = re.compile(r"<!--\s*cidre-rapport\s+v(\d+)\s+appid=(\S+?)\s*-->")
ETATS = ("or", "argent", "bronze", "ko")
SYNONYMES = {
    "or": "or", "gold": "or", "parfait": "or", "perfect": "or",
    "argent": "argent", "silver": "argent", "jouable": "argent", "playable": "argent",
    "bronze": "bronze",
    "ko": "ko", "borked": "ko", "broken": "ko", "ne marche pas": "ko",
}
CLES_RAPPORT = ("date", "machine", "cidre_version", "etat", "fps_menu", "fps_jeu", "notes")
# options du profil effectif qui ne disent rien de la compatibilite : pas dans les notes
OPTIONS_TUES = ("langue", "hud", "journal_detaille")
MAX_NOTES = 500
MAX_MACHINE = 80
MAX_NOM = 120


def dire(*a):
    print(*a, file=sys.stderr)


# ------------------------------------------------------------------ incidents
def lire_incidents(args):
    """Les incidents, en dicts de la forme de `gh issue list --json`."""
    if args.sans_incidents:
        return []
    if args.fichier:
        with open(args.fichier, encoding="utf-8") as f:
            d = json.load(f)
        return [i for i in ([d] if isinstance(d, dict) else d) if isinstance(i, dict)]
    # Trois requetes : le label, le titre, la balise du corps. Le label est pose
    # par le formulaire d'incident, quel que soit l'auteur ; le titre et la
    # balise sont les filets pour un incident ouvert hors du formulaire (un
    # Verger <= 0.3.13 passait par `labels=` dans l'adresse, que GitHub refuse a
    # qui n'a pas le droit de poser un label ; un incident libre n'en a pas).
    base = ["gh", "issue", "list", "--repo", args.depot, "--state", args.etat,
            "--limit", "500", "--json", CHAMPS_GH]
    vus = {}
    for filtre in (["--label", LABEL], ["--search", 'in:title "Rapport de jeu"'],
                   ["--search", 'in:body "cidre-rapport v1"']):
        try:
            r = subprocess.run(base + filtre, capture_output=True, text=True, check=False)
        except FileNotFoundError:
            raise SystemExit("gh introuvable : installer GitHub CLI, ou passer un fichier JSON d'incidents")
        if r.returncode != 0:
            raise SystemExit(f"gh issue list a echoue ({r.returncode}) : {r.stderr.strip()[:300]}")
        for i in json.loads(r.stdout or "[]"):
            vus.setdefault(i.get("number"), i)
    return [vus[n] for n in sorted(vus, key=lambda n: (n is None, n))]


# -------------------------------------------------------------------- lecture
def propre(s, maxi):
    """Une ligne de texte sure pour une chaine de fiche : pas de saut de ligne,
    pas de caractere de controle ni de format (marques d'ordre bidirectionnel)."""
    s = unicodedata.normalize("NFC", str(s))
    s = re.sub(r"\s*(\r\n|\r|\n)\s*", " / ", s.strip())
    s = "".join(" " if c == "\t" else c for c in s if unicodedata.category(c) not in ("Cc", "Cf", "Co", "Cs") or c == "\t")
    s = re.sub(r" {2,}", " ", s).strip()
    if len(s) > maxi:
        s = s[:maxi - 1].rstrip() + "…"
    return s


def segments(corps):
    """Le corps en morceaux [(dans_un_bloc_de_code, info, lignes)], dans l'ordre."""
    res, courant, cloture, info = [], [], None, ""
    for l in corps.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        m = re.match(r"^\s{0,3}(`{3,}|~{3,})\s*([^`]*)$", l)
        if cloture is None and m:
            res.append((False, "", courant))
            courant, cloture, info = [], m.group(1)[0] * 3, m.group(2).strip().lower()
        elif cloture is not None and l.strip().startswith(cloture) and not l.strip().strip(cloture[0]):
            res.append((True, info, courant))
            courant, cloture, info = [], None, ""
        else:
            courant.append(l)
    res.append((cloture is not None, info, courant))
    return [s for s in res if s[2]]


_ENTETE_RAPPORT = re.compile(r"^\s*\[\[\s*rapports?\s*\]\]\s*$", re.I)
_ENTETE = re.compile(r"^\s*\[+[^\]]*\]+\s*$")
_CLE = re.compile(r"^\s*[-*]?\s*`?([A-Za-z_][A-Za-z0-9_]*)`?\s*[=:]\s*(.*?)\s*$")


def _a_un_etat(bloc):
    """Vrai si le bloc donne un `etat` non vide : le modele du formulaire, laisse
    tel quel au-dessus d'un rapport colle, n'en donne pas."""
    for l in bloc:
        m = _CLE.match(l)
        if m and m.group(1).lower() == "etat":
            return bool(str(valeur(m.group(2))[0]).strip())
    return False


def lignes_du_rapport(corps):
    """Les lignes `cle = valeur` du rapport, ou None. Verger les met dans un
    bloc de code toml sous [[rapports]] ; on tolere un bloc sans en-tete, ou
    pas de bloc du tout. De plusieurs blocs [[rapports]], le premier qui donne
    un etat est pris. Le diagnostic (bloc `text`, ou ce qui suit son intitule,
    en gras ou en titre) n'est jamais lu."""
    segs = segments(corps)
    for i, (code, info, lignes) in enumerate(segs):  # tout ce qui suit l'intitule du diagnostic est du journal
        n = next((k for k, l in enumerate(lignes) if re.match(r"^\s*[#*\s]*diagnos", l, re.I)), None)
        if not code and n is not None:
            segs = segs[:i] + [(False, "", lignes[:n])]
            break
    segs = [s for s in segs if not (s[0] and s[1] in ("text", "log", "txt"))]

    def apres_entetes(lignes):
        blocs = []
        for i, l in enumerate(lignes):
            if _ENTETE_RAPPORT.match(l):
                bloc = []
                for l2 in lignes[i + 1:]:
                    if _ENTETE.match(l2):
                        break
                    bloc.append(l2)
                blocs.append(bloc)
        return blocs

    blocs = [b for _, _, lignes in segs for b in apres_entetes(lignes)]   # 1. [[rapports]], dans un bloc de code ou non
    if blocs:
        return next((b for b in blocs if _a_un_etat(b)), blocs[0])
    for code, _, lignes in segs:                    # 2. pas d'en-tete : des lignes avec un `etat`
        bloc = []
        for l in lignes:
            if _ENTETE.match(l):
                if bloc:
                    break
                continue
            bloc.append(l)
        if any((m := _CLE.match(l)) and m.group(1).lower() == "etat" for l in bloc):
            return bloc
    return None


def lire_profil(corps):
    """Le profil effectif ([profil], une option par ligne), ou {}."""
    for code, info, lignes in segments(corps):
        if not code or info in ("text", "log", "txt"):
            continue
        for i, l in enumerate(lignes):
            if re.match(r"^\s*\[\s*profil\s*\]\s*$", l, re.I):
                d = {}
                for l2 in lignes[i + 1:]:
                    if _ENTETE.match(l2):
                        break
                    m = _CLE.match(l2)
                    if m:
                        d[m.group(1)] = valeur(m.group(2))[0]
                return d
    return {}


def valeur(brut):
    """Une valeur telle que Verger l'ecrit (chaine TOML, entier, booleen), ou
    telle qu'un utilisateur l'a retouchee. Rend (valeur, lue_proprement)."""
    brut = brut.strip()
    try:
        return tomllib.loads("v = " + brut)["v"], True
    except (tomllib.TOMLDecodeError, ValueError, RecursionError):
        pass
    m = re.fullmatch(r"""(["'“”«])\s*(.*?)\s*(["'“”»])""", brut, re.S)
    return (m.group(2) if m else brut), False


def lire_rapport(incident, depot):
    """Un incident -> {numero, url, titre, auteur, appid, nom, champs, profil,
    avertissements, erreurs}. `erreurs` non vide : rapport illisible, rien a integrer."""
    r = {"numero": incident.get("number"), "titre": str(incident.get("title") or ""),
         "auteur": ((incident.get("author") or {}).get("login") or ""),
         "appid": None, "nom": "", "champs": {}, "profil": {}, "avertissements": [], "erreurs": []}
    av, err = r["avertissements"], r["erreurs"]
    corps = str(incident.get("body") or "")
    # le label, pose par le formulaire : son absence dit par ou l'incident est arrive
    labels = incident.get("labels")
    if isinstance(labels, list) and LABEL not in [str((l or {}).get("name", "")) if isinstance(l, dict) else str(l) for l in labels]:
        av.append(f"sans le label {LABEL} : ouvert hors du formulaire « Rapport de jeu » (ou par un Verger <= 0.3.13)")

    # l'adresse de l'incident : celle de GitHub, sur ce depot, rien d'autre
    url = str(incident.get("url") or "")
    attendu = re.compile(r"https://github\.com/" + re.escape(depot) + r"/issues/([0-9]+)", re.I)
    m = attendu.fullmatch(url)
    if not m and isinstance(r["numero"], int):
        if url:
            av.append(f"adresse inattendue ({propre(url, 100)}) : celle du depot {depot} est prise")
        url = f"https://github.com/{depot}/issues/{r['numero']}"
    elif not m:
        err.append("ni numero ni adresse d'incident sur le depot")
    r["url"] = url

    # le jeu : la balise du corps si elle existe, sinon le titre
    m = TITRE.match(r["titre"])
    if m:
        r["nom"] = propre(m.group(1), MAX_NOM)
    balise = BALISE.search("\n".join(l for code, _, ls in segments(corps) if not code for l in ls))
    candidat = balise.group(2) if balise else (m.group(2) if m else "")
    if balise and m and m.group(2) != balise.group(2):
        av.append(f"le titre dit ({propre(m.group(2), 40)}), la balise du corps appid={propre(balise.group(2), 40)} : la balise est prise")
    if APPID.fullmatch(candidat):
        r["appid"] = candidat
    elif candidat:
        err.append(f"identifiant de jeu refuse : « {propre(candidat, 40)} » (attendu : un appid Steam ou local-...)")
    else:
        err.append("titre sans « Rapport de jeu : <nom> (<appid>) » : jeu inconnu")

    # le bloc [[rapports]]
    bloc = lignes_du_rapport(corps)
    if bloc is None:
        err.append("aucun bloc [[rapports]] ni ligne « etat = ... » dans le corps")
        return r
    lus = {}
    for l in bloc:
        m = _CLE.match(l)
        if not m:
            continue
        cle = m.group(1).lower()
        if cle == "incident":
            av.append("`incident` ecrit dans le corps : ignore (c'est l'adresse de l'incident lui-meme)")
        elif cle not in CLES_RAPPORT:
            av.append(f"cle inconnue ignoree : {propre(cle, 30)}")
        elif cle in lus:
            av.append(f"`{cle}` donne deux fois : la premiere valeur est gardee")
        else:
            v, net = valeur(m.group(2))
            if not net and v and cle == "notes":
                av.append(f"`{cle}` : chaine mal formee, lue telle quelle")
            lus[cle] = v
    champs = r["champs"]

    cree = str(incident.get("createdAt") or "")[:10]
    date = str(lus.get("date", "")).strip()
    try:
        dt.date.fromisoformat(date)
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
            raise ValueError
    except ValueError:
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", cree):
            av.append(("date absente" if not date else f"date illisible (« {propre(date, 30)} »)") + f" : celle de l'incident ({cree}) est prise")
            date = cree
        else:
            err.append("date absente ou illisible, et l'incident n'en donne pas")
            date = ""
    if date:
        champs["date"] = date

    machine = propre(lus.get("machine", ""), MAX_MACHINE)
    if machine:
        champs["machine"] = machine
    else:
        av.append("machine absente : ce rapport ne comptera pas pour --proposer-compat")

    version = str(lus.get("cidre_version", "")).strip()
    if version:
        if re.fullmatch(r"[0-9A-Za-z][0-9A-Za-z.+-]{0,29}", version):   # « 1.5.7 », « dev »
            champs["cidre_version"] = re.sub(r"^v(?=[0-9])", "", version)
        else:
            av.append(f"cidre_version illisible (« {propre(version, 30)} ») : omise")

    etat_brut = propre(lus.get("etat", ""), 40)
    etat = SYNONYMES.get(etat_brut.casefold())
    if etat is None:
        err.append("etat absent" if not etat_brut else f"etat inconnu : « {etat_brut} » (attendu : {', '.join(ETATS)})")
    else:
        champs["etat"] = etat
        if etat_brut != etat:
            av.append(f"etat « {etat_brut} » lu « {etat} »")

    for cle in ("fps_menu", "fps_jeu"):
        if cle not in lus:
            continue
        v = lus[cle]
        texte = str(v).strip()
        m = re.search(r"[0-9]+", texte)
        if isinstance(v, bool) or not m:
            av.append(f"{cle} illisible (« {propre(texte, 30)} ») : omis")
            continue
        n = int(m.group(0))
        if not 0 < n <= 1000:
            if n:
                av.append(f"{cle} = {n} : hors de toute mesure plausible, omis")
            continue
        if not isinstance(v, int) and not texte.isdigit():
            av.append(f"{cle} « {propre(texte, 30)} » lu {n}")
        champs[cle] = n

    notes = propre(lus.get("notes", ""), MAX_NOTES)
    if len(str(lus.get("notes", ""))) > MAX_NOTES:
        av.append(f"notes coupees a {MAX_NOTES} caracteres")
    if re.search(r"https?://|www\.", notes, re.I):
        av.append("un lien dans les notes : a relire avant d'integrer")
    if notes:
        champs["notes"] = notes
    r["profil"] = lire_profil(corps)
    return r


# --------------------------------------------------------------------- fiches
def chaine(s):
    """Une chaine du sous-ensemble TOML des fiches : seuls \\" et \\\\ sont echappes."""
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def bloc_toml(champs, url):
    lignes = ["[[rapports]]"]
    for cle in CLES_RAPPORT:
        if cle in champs:
            v = champs[cle]
            lignes.append(f"{cle} = {v}" if isinstance(v, int) else f"{cle} = {chaine(v)}")
    lignes.append(f"incident = {chaine(url)}")
    return lignes


def chemin_fiche(profils, appid):
    assert APPID.fullmatch(appid), appid  # jamais un chemin venu d'un titre
    return os.path.join(profils, appid + ".toml")


def lire_fiche(chemin):
    with open(chemin, "rb") as f:
        return tomllib.load(f)


def incidents_integres(profils):
    """{adresse d'incident: appid} pour tous les [[rapports]] de la base."""
    res = {}
    motif = re.compile(r'^\s*incident\s*=\s*"([^"]*)"', re.M)
    for nom in sorted(os.listdir(profils)) if os.path.isdir(profils) else []:
        if not nom.endswith(".toml") or nom == "index.toml":
            continue
        with open(os.path.join(profils, nom), encoding="utf-8", errors="replace") as f:
            for url in motif.findall(f.read()):
                res.setdefault(url.lower(), nom[:-5])
    return res


def options_du_joueur(profil, fiche, defauts):
    """Les options avec lesquelles le joueur a lance et qui different de la
    reference (reglages livres par defaut, puis [cidre] de la fiche)."""
    ref = dict(defauts)
    ref.update((fiche or {}).get("cidre", {}))
    ecarts = []
    for cle, v in profil.items():
        if cle in ref and cle not in OPTIONS_TUES and v != ref[cle] and re.fullmatch(r"[a-z0-9_]{1,30}", cle):
            v = ("true" if v else "false") if isinstance(v, bool) else propre(v, 30)
            ecarts.append(f"{cle}={v}")
    return ecarts


def avec_options(champs, ecarts, a_une_fiche):
    """Les notes du joueur suivies, en une phrase, des options qui different."""
    if not ecarts:
        return champs
    phrase = "Lance avec " + ", ".join(ecarts) + (" (differe de la fiche)." if a_une_fiche else " (differe des reglages par defaut).")
    notes = champs.get("notes", "")
    if notes and notes[-1] not in ".!?…":
        notes += "."
    res = dict(champs)
    res["notes"] = (notes + " " + phrase).strip()
    return res


_EN_TETE_LIGNE = re.compile(r"^\s*(\[\[?)\s*([^\]]+?)\s*\]\]?\s*(#.*)?$")


def _sections(lignes):
    """[(nom, est_tableau, debut, fin)] des en-tetes de section d'une fiche."""
    res = []
    for i, l in enumerate(lignes):
        m = _EN_TETE_LIGNE.match(l)
        if m:
            res.append([m.group(2).replace('"', "").strip(), m.group(1) == "[[", i, len(lignes)])
    for k in range(len(res) - 1):
        res[k][3] = res[k + 1][2]
    return res


def _fin_utile(lignes, debut, fin):
    """Indice apres la derniere ligne `cle = valeur` du bloc : les commentaires
    qui suivent appartiennent a la section d'apres."""
    j = fin
    while j > debut + 1 and (not lignes[j - 1].strip() or lignes[j - 1].lstrip().startswith("#")):
        j -= 1
    return j


def inserer_rapport(texte, bloc):
    """Le texte de la fiche avec le bloc en plus, sans toucher au reste : apres
    le dernier [[rapports]], sinon apres [compat], sinon a la fin."""
    lignes = texte.rstrip("\n").split("\n") if texte.strip() else []
    secs = _sections(lignes)
    cible = [s for s in secs if s[0] == "rapports" and s[1]] or [s for s in secs if s[0] == "compat" and not s[1]]
    pos = _fin_utile(lignes, cible[-1][2], cible[-1][3]) if cible else len(lignes)
    lignes[pos:pos] = ([""] if pos else []) + bloc + ([""] if pos < len(lignes) and lignes[pos].strip() else [])
    return "\n".join(lignes).rstrip("\n") + "\n"


def fiche_minimale(appid, nom, date, outil="tests/outils/rapports_vers_fiches.py"):
    return "\n".join([
        f"# {nom or appid} -- fiche amorcee par {outil} ({date}) depuis un rapport",
        "# d'utilisateur. Rien n'y est teste par nous : [compat] attend une relecture",
        "# (voir profils/CONTRIBUER.md).",
        "",
        "[jeu]",
        f"appid = {appid}" if appid.isdigit() else f"appid = {chaine(appid)}",
        f"nom = {chaine(nom or appid)}",
        "",
        "[compat]",
        'etat = "non-teste"',
        f"date = {chaine(date)}",
        "",
    ])


def ecrire(chemin, texte):
    tmp = chemin + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(texte)
    os.replace(tmp, chemin)


def appliquer(chemin, appid, nom, bloc, date):
    """Ajoute le bloc a la fiche (creee si elle manque). Le fichier est relu
    avant d'etre ecrit : tout ce qui n'est pas [[rapports]] doit etre intact."""
    neuve = not os.path.exists(chemin)
    if neuve:
        avant_texte = fiche_minimale(appid, nom, date)
    else:
        with open(chemin, encoding="utf-8") as f:
            avant_texte = f.read()
    avant = tomllib.loads(avant_texte)
    apres_texte = inserer_rapport(avant_texte, bloc)
    apres = tomllib.loads(apres_texte)
    ajoute = tomllib.loads("\n".join(bloc))["rapports"]
    attendu = dict(avant)
    attendu["rapports"] = list(avant.get("rapports", [])) + ajoute
    if apres != attendu:
        raise RuntimeError(f"{chemin} : la fiche relue n'est pas l'ancienne plus le rapport ; rien n'est ecrit")
    ecrire(chemin, apres_texte)
    return neuve


def generer_index(profils):
    outil = os.path.join(RACINE, "tests", "fiche_profil.sh")
    if not os.path.exists(outil) or os.path.abspath(profils) != PROFILS_DEFAUT:
        return False
    sortie = subprocess.run(["sh", outil, "generer-index"], capture_output=True, text=True, check=False)
    if sortie.returncode != 0:
        dire("generer-index a echoue :", sortie.stderr.strip()[:300])
        return False
    ecrire(os.path.join(profils, "index.toml"), sortie.stdout)
    return True


# --------------------------------------------------------------------- compat
def _machine(m):
    return re.sub(r"\s+", " ", str(m)).strip().casefold()


def proposer_compat(fiche, rapports):
    """La regle de l'en-tete. Rend (a_montrer, constat, proposition) :
    `proposition` est le dict des cles de [compat] a poser, ou None ; `a_montrer`
    dit si le constat merite l'oeil du mainteneur meme sans proposition."""
    compat = {k: v for k, v in (fiche or {}).get("compat", {}).items() if not isinstance(v, dict)}
    # le rapport le plus recent de chaque machine (a date egale, le dernier arrive)
    par_machine = {}
    for r in rapports:
        if r.get("etat") in ETATS and _machine(r.get("machine", "")):
            m = _machine(r["machine"])
            if m not in par_machine or str(r.get("date", "")) >= str(par_machine[m].get("date", "")):
                par_machine[m] = r
    voix = {}
    for r in par_machine.values():
        voix.setdefault(r["etat"], []).append(r)
    if not voix:
        return False, "aucun rapport avec etat et machine", None
    rang = sorted(voix.items(), key=lambda kv: -len(kv[1]))
    etat, accord = rang[0]
    decompte = ", ".join(f"{e} x{len(v)}" for e, v in rang)
    if len(accord) < 2:
        return False, f"pas encore deux machines d'accord ({decompte})", None
    if len(rang) > 1 and len(rang[1][1]) == len(accord):
        return True, f"desaccord entre rapports ({decompte}) : pas de proposition, a tester", None
    machines = " ; ".join(r["machine"] for r in accord)
    constat = f"{len(accord)} machines donnent « {etat} » ({machines})" + (f" ; en tout : {decompte}" if len(rang) > 1 else "") + "."
    actuel, source = compat.get("etat", "non-teste"), compat.get("source", "")
    if actuel == etat:
        return False, constat + f" [compat] dit deja « {etat} ».", None
    if source == "cidre-test" or (not source and actuel != "non-teste"):
        origine = "de source cidre-test, nos tests priment" if source else "ecrit a la main"
        return True, constat + f" [compat] dit « {actuel} » ({origine}) : pas de proposition, a retester.", None
    ref = max(accord, key=lambda r: str(r.get("date", "")))
    numeros = [re.sub(r".*/", "#", str(r["incident"])) for r in accord if r.get("incident")]
    prop = {"etat": etat, "source": "utilisateur"}
    for cle in ("date", "machine", "cidre_version", "fps_menu", "fps_jeu"):
        if cle in ref:
            prop[cle] = ref[cle]
    prop["notes"] = (f"{len(accord)} rapports d'utilisateurs concordants ({machines})"
                     + (f", incidents {' '.join(numeros)}" if numeros else "") + ". Mesures : le plus recent.")
    return True, constat, prop


# ----------------------------------------------------------------------- main
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("fichier", nargs="?", help="incidents en JSON (forme de `gh issue list --json`) au lieu d'interroger GitHub")
    ap.add_argument("--appliquer", action="store_true", help="ajouter les blocs aux fiches")
    ap.add_argument("--proposer-compat", action="store_true", help="suggerer la mise a jour de [compat] (n'ecrit rien)")
    ap.add_argument("--incident", type=int, action="append", default=[], metavar="N", help="ne traiter que cet incident (repetable)")
    ap.add_argument("--sans-incidents", action="store_true", help="ne lire aucun incident")
    ap.add_argument("--depot", default=DEPOT_DEFAUT, help=f"depot GitHub (defaut : {DEPOT_DEFAUT})")
    ap.add_argument("--etat", default="open", choices=("open", "closed", "all"), help="incidents a lire (defaut : open)")
    ap.add_argument("--profils", default=PROFILS_DEFAUT, help="dossier des fiches")
    ap.add_argument("--defauts", default=DEFAUTS_DEFAUT, help="reglages livres par defaut (outil-steam/profils.toml)")
    ap.add_argument("--date", default=dt.date.today().isoformat(), help="date du jour (pour les tests)")
    args = ap.parse_args(argv)

    try:
        defauts = lire_fiche(args.defauts).get("defaut", {})
    except (OSError, tomllib.TOMLDecodeError):
        defauts = {}
    incidents = lire_incidents(args)
    if args.incident:
        incidents = [i for i in incidents if i.get("number") in args.incident]
        absents = sorted(set(args.incident) - {i.get("number") for i in incidents})
        if absents:
            dire("incident(s) introuvable(s) :", " ".join(f"#{n}" for n in absents))
    integres = incidents_integres(args.profils)

    compte = {"a_integrer": 0, "integres": 0, "deja": 0, "illisibles": 0, "creees": 0}
    en_attente = {}   # appid -> [champs + incident] des rapports lus et pas encore dans la fiche
    auteurs = {}      # (appid, auteur) -> numero, pour signaler un doublon
    for incident in incidents:
        r = lire_rapport(incident, args.depot)
        print(f"== #{r['numero']} {propre(r['titre'], 150)}")
        print(f"   {r['url']}")
        for a in r["avertissements"]:
            print(f"   attention : {a}")
        if r["erreurs"]:
            compte["illisibles"] += 1
            for e in r["erreurs"]:
                print(f"   ILLISIBLE : {e}")
            print()
            continue
        appid = r["appid"]
        chemin = chemin_fiche(args.profils, appid)
        relatif = os.path.relpath(chemin, RACINE) if os.path.abspath(chemin).startswith(RACINE + os.sep) else chemin
        deja = integres.get(r["url"].lower())
        if deja:
            compte["deja"] += 1
            print(f"   deja integre (profils/{deja}.toml) : rien a faire\n")
            continue
        fiche = None
        if os.path.exists(chemin):
            try:
                fiche = lire_fiche(chemin)
            except tomllib.TOMLDecodeError as e:
                compte["illisibles"] += 1
                print(f"   ILLISIBLE : la fiche {relatif} ne se lit pas ({e})\n")
                continue
            compat = fiche.get("compat", {})
            print(f"   fiche : {relatif} ([compat] {compat.get('etat', 'non-teste')}"
                  + (f", source {compat['source']}" if compat.get("source") else "")
                  + f" ; {len(fiche.get('rapports', []))} rapport(s))")
            nom_fiche = str(fiche.get("jeu", {}).get("nom", ""))
            alnum = lambda s: re.sub(r"[\W_]+", "", s.casefold())
            if r["nom"] and nom_fiche and alnum(r["nom"]) != alnum(nom_fiche):
                print(f"   attention : l'incident nomme « {r['nom']} », la fiche « {propre(nom_fiche, MAX_NOM)} » : verifier l'appid")
        else:
            print(f"   fiche : {relatif} n'existe pas" + (" (jeu hors Steam : pas de fiche creee d'office)" if appid.startswith("local-") else " (creee, minimale, par --appliquer)"))
        cle = (appid, r["auteur"])
        if r["auteur"] and cle in auteurs:
            print(f"   attention : meme auteur et meme jeu que #{auteurs[cle]} : un doublon ?")
        auteurs.setdefault(cle, r["numero"])

        champs = avec_options(r["champs"], options_du_joueur(r["profil"], fiche, defauts), fiche is not None)
        bloc = bloc_toml(champs, r["url"])
        print("\n".join(bloc))
        if args.appliquer and fiche is None and appid.startswith("local-"):
            compte["a_integrer"] += 1
            print("   non applique : creer la fiche a la main si ce jeu hors Steam en merite une")
        elif args.appliquer:
            if appliquer(chemin, appid, r["nom"], bloc, args.date):
                compte["creees"] += 1
                print(f"   fiche creee : {relatif}")
            else:
                print(f"   ajoute a {relatif}")
            compte["integres"] += 1
            integres[r["url"].lower()] = appid
        else:
            compte["a_integrer"] += 1
            en_attente.setdefault(appid, []).append(dict(champs, incident=r["url"]))
        print()

    if args.appliquer and compte["creees"]:
        if generer_index(args.profils):
            print("profils/index.toml regenere")
        else:
            print("index non regenere (dossier de fiches hors depot) : sh tests/fiche_profil.sh generer-index > profils/index.toml")
    if incidents or not args.sans_incidents:
        print(f"{len(incidents)} incident(s) : {compte['integres']} integre(s), {compte['a_integrer']} a integrer, "
              f"{compte['deja']} deja integre(s), {compte['illisibles']} illisible(s)")
        if compte["a_integrer"] and not args.appliquer:
            print("Relire, puis : --appliquer [--incident N], relire `git diff profils/`, commiter, fermer les incidents integres.")

    if args.proposer_compat:
        print("\n== [compat] : propositions (rien n'est ecrit ; regle : 2 machines d'accord, aucun autre etat a egalite)")
        appids = set(en_attente)
        for nom in os.listdir(args.profils) if os.path.isdir(args.profils) else []:
            if nom.endswith(".toml") and nom != "index.toml":
                with open(os.path.join(args.profils, nom), encoding="utf-8", errors="replace") as f:
                    if "[[rapports]]" in f.read():
                        appids.add(nom[:-5])
        rien = True
        for appid in sorted(appids, key=lambda a: (not a.isdigit(), int(a) if a.isdigit() else 0, a)):
            chemin = chemin_fiche(args.profils, appid)
            try:
                fiche = lire_fiche(chemin) if os.path.exists(chemin) else {}
            except tomllib.TOMLDecodeError:
                continue
            attente = en_attente.get(appid, [])
            a_montrer, constat, prop = proposer_compat(fiche, list(fiche.get("rapports", [])) + attente)
            if not a_montrer:
                continue
            rien = False
            print(f"-- {appid} {propre(fiche.get('jeu', {}).get('nom', ''), MAX_NOM)}"
                  + (f" (dont {len(attente)} rapport(s) pas encore integre(s))" if attente else ""))
            print(f"   {constat}")
            if prop:
                print("[compat]")
                for k, v in prop.items():
                    print(f"{k} = {v}" if isinstance(v, int) else f"{k} = {chaine(v)}")
            print()
        if rien:
            print("   aucune : pas de jeu ou deux machines s'accordent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
