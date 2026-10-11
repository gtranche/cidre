#!/usr/bin/env python3
"""Amorce ou complete les fiches profils/<appid>.toml depuis les bases publiques.

    importer_profils.py [options] [appid ...]

Sans appid : toute la bibliotheque Steam du compte (`cidre library --json`).
Outil de la machine de dev uniquement (Python 3.11+, aucune dependance) : rien
ici ne tourne cote runtime.

Sources, par ordre d'autorite decroissante (cf. profils/README.md) :
  cidre-test > utilisateur > winehq > protondb / applegamingwiki / pcgamingwiki
  > crossover.
Une valeur dont la source est cidre-test ou utilisateur n'est JAMAIS ecrasee :
si l'import dit autre chose, c'est une contradiction, listee dans le rapport.
Chaque valeur importee porte sa source et sa date : par cle dans [jeu.sources]
(`moteur = "pcgamingwiki 2026-10-11"`), par section pour les blocs d'import
[compat.protondb], [compat.applegamingwiki], [compat.pcgamingwiki] (`source`,
`date`). Une valeur SANS provenance a ete ecrite a la main : protegee aussi.
Sous-ensemble TOML du README : ni tableau, ni table en ligne (hors
[reglages_jeu]), ni date TOML -- les listes sont des chaines separees par " ; ".

Les reponses sont mises en cache (dossier ignore par git, --cache) : une
seconde execution ne retelecharge rien, --refresh force. Les textes des wikis
(CC BY-NC-SA) ne sont jamais recopies : on n'en tire que des donnees
structurees (modeles), et la fiche cite l'URL de la page.
"""
import argparse
import collections
import datetime as dt
import json
import os
import re
import subprocess
import sys
import tarfile
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE = os.path.abspath(os.path.join(ICI, "..", ".."))
PROFILS_DEFAUT = os.path.join(RACINE, "profils")
CACHE_DEFAUT = os.path.join(RACINE, "build", "cache-profils")
UA = "cidre-importer/0.1 (+https://github.com/gtranche/cidre ; donnees publiques, cache local)"
PAUSE = 0.35  # secondes entre deux requetes vers un meme hote

PROTONDB_SUMMARY = "https://www.protondb.com/api/v1/reports/summaries/{appid}.json"
PROTONDB_PAGE = "https://www.protondb.com/app/{appid}"
PROTONDB_EXPORT_DEPOT = "https://api.github.com/repos/bdefore/protondb-data/contents/reports"
PROTONDB_EXPORT_BRUT = "https://github.com/bdefore/protondb-data/raw/master/reports/{nom}"
PCGW_API = "https://www.pcgamingwiki.com/w/api.php"
PCGW_PAGE = "https://www.pcgamingwiki.com/wiki/{titre}"
AGW_API = "https://www.applegamingwiki.com/w/api.php"
AGW_PAGE = "https://www.applegamingwiki.com/wiki/{titre}"

SOURCES_PROTEGEES = ("cidre-test", "utilisateur")
MOTEURS_FICHE = ("unity", "unreal", "hashlink", "stingray", "godot", "source")
ANTICHEAT_FICHE = ("none", "eac", "battleye", "denuvo", "vac")

# Vocabulaire ferme de la fiche (cf. README) <- libelles des sources.
ANTICHEAT = {
    "easy anti-cheat": "eac", "easy anticheat": "eac", "eac": "eac",
    "battleye": "battleye", "battleeye": "battleye",
    "denuvo anti-cheat": "denuvo", "denuvo anticheat": "denuvo",
    "vanguard": "vanguard", "riot vanguard": "vanguard",
    "nprotect gameguard": "gameguard", "gameguard": "gameguard",
    "xigncode3": "xigncode", "xigncode": "xigncode",
    "punkbuster": "punkbuster", "vac": "vac", "valve anti-cheat": "vac",
    "fairfight": "fairfight", "equ8": "equ8", "anticheat expert": "ace",
    "none": "none", "no": "none",
}
MOTEURS = [
    ("unreal engine 5", "unreal5"), ("unreal engine 4", "unreal4"),
    ("unreal engine 3", "unreal3"), ("unreal", "unreal"),
    ("unity", "unity"), ("godot", "godot"), ("stingray", "stingray"),
    ("bitsquid", "stingray"), ("hashlink", "hashlink"), ("heaps", "hashlink"),
    ("source 2", "source2"), ("source", "source"), ("gamemaker", "gamemaker"),
    ("game maker", "gamemaker"), ("construct", "construct"), ("renpy", "renpy"),
    ("ren'py", "renpy"), ("rpg maker", "rpgmaker"), ("cryengine", "cryengine"),
    ("frostbite", "frostbite"), ("id tech", "idtech"), ("re engine", "reengine"),
    ("mt framework", "mtframework"), ("creation engine", "creation"),
    ("gamebryo", "gamebryo"), ("anvil", "anvil"), ("snowdrop", "snowdrop"),
    ("decima", "decima"), ("clausewitz", "clausewitz"), ("monogame", "monogame"),
    ("xna", "xna"), ("fna", "fna"), ("love", "love"), ("defold", "defold"),
    ("cocos", "cocos"), ("phyre", "phyre"), ("adobe air", "air"), ("flash", "flash"),
    ("electron", "electron"), ("nw.js", "nwjs"), ("libgdx", "libgdx"),
    ("java", "java"), ("scummvm", "scummvm"), ("dosbox", "dosbox"),
    ("gzdoom", "gzdoom"), ("openmw", "openmw"), ("wolf rpg", "wolfrpg"),
    ("kirikiri", "kirikiri"), ("torque", "torque"), ("ogre", "ogre"),
    ("irrlicht", "irrlicht"), ("bgfx", "bgfx"), ("sdl", "sdl"),
]
COMPAT_AGW = {"perfect": "parfait", "playable": "jouable", "runs": "demarre",
              "unplayable": "ko", "unknown": None, "na": None, "n/a": None, "": None}
TIERS_PROTONDB = ("platinum", "gold", "silver", "bronze", "borked", "pending")
METHODES_MAC = [
    ("game porting toolkit", "gptk"), ("gptk", "gptk"), ("whisky", "whisky"),
    ("kegworks", "kegworks"), ("porting kit", "portingkit"), ("crossover", "crossover"),
    ("heroic", "heroic"), ("wine", "wine"), ("parallels", "parallels"),
]


# ----------------------------------------------------------------- utilitaires
def aujourdhui():
    return dt.date.today().isoformat()


def dire(*a):
    print(*a, file=sys.stderr, flush=True)


class Toile:
    """HTTP avec cache sur disque, pause par hote, et mode sans reseau."""

    def __init__(self, cache, refresh=False, sans_reseau=False):
        self.cache = cache
        self.refresh = refresh
        self.sans_reseau = sans_reseau
        self.dernier = {}
        self.requetes = 0

    def chemin(self, cle):
        return os.path.join(self.cache, cle)

    def lire_cache(self, cle):
        p = self.chemin(cle)
        if os.path.exists(p) and not self.refresh:
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        return None

    def ecrire_cache(self, cle, obj):
        p = self.chemin(cle)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tmp = f"{p}.{os.getpid()}.tmp"  # unique : plusieurs importeurs peuvent partager le cache
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=1)
        os.replace(tmp, p)

    def get(self, url, cle, binaire=False):
        """Rend {'date', 'statut', 'corps'} ; corps = JSON decode ou texte."""
        if not binaire:
            vu = self.lire_cache(cle)
            if vu is not None:
                return vu
        if self.sans_reseau:
            return {"date": aujourdhui(), "statut": 0, "corps": None, "hors_ligne": True}
        hote = urllib.parse.urlsplit(url).netloc
        attente = PAUSE - (time.monotonic() - self.dernier.get(hote, 0))
        if attente > 0:
            time.sleep(attente)
        statut, corps = 0, None
        for essai in range(4):
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json, text/plain, */*"})
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    statut = r.status
                    brut = r.read()
                break
            except urllib.error.HTTPError as e:
                statut, brut = e.code, b""
                if statut in (429, 500, 502, 503, 504) and essai < 3:
                    time.sleep(2 * (essai + 1) + (5 if statut == 429 else 0))
                    continue
                break
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                statut, brut = -1, str(e).encode()
                if essai < 3:
                    time.sleep(2 * (essai + 1))
                    continue
        self.dernier[hote] = time.monotonic()
        self.requetes += 1
        if binaire:
            return {"date": aujourdhui(), "statut": statut, "corps": brut}
        if statut == 200:
            texte = brut.decode("utf-8", "replace")
            try:
                corps = json.loads(texte)
            except ValueError:
                corps = texte
        res = {"date": aujourdhui(), "statut": statut, "corps": corps}
        if statut in (200, 404):
            self.ecrire_cache(cle, res)
        return res


# ---------------------------------------------------------------------- TOML
def lire_toml(chemin):
    with open(chemin, "rb") as f:
        return tomllib.load(f)


def _toml_valeur(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, (dt.date, dt.datetime)):
        return v.isoformat()
    raise TypeError(f"valeur hors du sous-ensemble TOML des fiches : {v!r}")


def _toml_cle(k):
    return k if re.fullmatch(r"[A-Za-z0-9_-]+", k) else json.dumps(k, ensure_ascii=False)


def ecrire_toml(chemin, doc, entete=""):
    """Serialise un document (dict) : tables, sous-tables et tableaux de tables.
    Les dicts imbriques dans une liste sont des [[tableaux de tables]] ; un dict
    sous une cle dont le nom est `sources` ou qui ne contient que des scalaires
    de provenance reste une table nommee ([section.sources])."""
    lignes = []
    if entete:
        lignes.append(entete.rstrip("\n"))
        lignes.append("")

    def ecrire_table(nom, table):
        scalaires = {k: v for k, v in table.items() if not isinstance(v, dict)
                     and not (isinstance(v, list) and v and all(isinstance(x, dict) for x in v))}
        sous = {k: v for k, v in table.items() if isinstance(v, dict)}
        tableaux = {k: v for k, v in table.items() if isinstance(v, list) and v and all(isinstance(x, dict) for x in v)}
        if nom and (scalaires or not sous and not tableaux):
            lignes.append(f"[{nom}]")
        for k, v in scalaires.items():
            lignes.append(f"{_toml_cle(k)} = {_toml_valeur(v)}")
        if nom and (scalaires or not sous and not tableaux):
            lignes.append("")
        for k, v in sous.items():
            ecrire_table(f"{nom}.{_toml_cle(k)}" if nom else _toml_cle(k), v)
        for k, v in tableaux.items():
            chemin_tab = f"{nom}.{_toml_cle(k)}" if nom else _toml_cle(k)
            for elt in v:
                lignes.append(f"[[{chemin_tab}]]")
                for kk, vv in elt.items():
                    if not isinstance(vv, dict):
                        lignes.append(f"{_toml_cle(kk)} = {_toml_valeur(vv)}")
                for kk, vv in elt.items():
                    if isinstance(vv, dict):  # [reglages_jeu.valeurs] : sous-table du dernier element
                        lignes.append(f"[{chemin_tab}.{_toml_cle(kk)}]")
                        for k3, v3 in vv.items():
                            lignes.append(f"{_toml_cle(k3)} = {_toml_valeur(v3)}")
                lignes.append("")

    ecrire_table("", doc)
    texte = "\n".join(lignes).rstrip("\n") + "\n"
    tomllib.loads(texte)  # on ne livre jamais un fichier qu'on ne sait pas relire
    tmp = chemin + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(texte)
    os.replace(tmp, chemin)


_HEADER = re.compile(r"^\s*(\[\[)?\[?\s*([^\]]+?)\s*\]\]?\s*(#.*)?$")


def _sections_texte(lignes):
    """[(nom, est_tableau, debut, fin)] : les en-tetes de section d'un texte TOML."""
    res = []
    for i, l in enumerate(lignes):
        t = l.strip()
        if not t.startswith("["):
            continue
        m = _HEADER.match(l)
        if not m:
            continue
        nom = m.group(2).replace('"', "").strip()
        res.append([nom, bool(m.group(1)) or t.startswith("[["), i, None])
    for k, sec in enumerate(res):
        sec[3] = res[k + 1][2] if k + 1 < len(res) else len(lignes)
    return [tuple(x) for x in res]


def _fin_utile(lignes, debut, fin):
    """Indice apres la derniere ligne non vide du bloc [debut, fin)."""
    j = fin
    while j > debut + 1 and not lignes[j - 1].strip():
        j -= 1
    return j


def retoucher_toml(texte, ops, doc_attendu):
    """Applique des (section, cle, valeur) a un texte TOML sans toucher au reste
    (commentaires, ordre, formes). Une section absente est creee : [jeu.sources]
    juste apres le bloc [jeu], les autres a la fin. Le resultat est relu et
    compare au document attendu : on n'ecrit jamais un fichier faux."""
    lignes = texte.rstrip("\n").split("\n") if texte.strip() else []
    for section, cle, valeur in ops:
        secs = _sections_texte(lignes)
        bloc = [x for x in secs if x[0] == section and not x[1]]
        if not bloc:
            parent = section.rsplit(".", 1)[0] if "." in section else None
            apres = [x for x in secs if parent and (x[0] == parent or x[0].startswith(parent + ".")) and not x[1]]
            if section.endswith(".sources") and apres:
                pos = _fin_utile(lignes, apres[-1][2], apres[-1][3])
            else:
                pos = len(lignes)
            lignes[pos:pos] = ["", f"[{section}]"]
            secs = _sections_texte(lignes)
            bloc = [x for x in secs if x[0] == section and not x[1]]
        nom, _, debut, fin = bloc[-1]
        ligne = f"{_toml_cle(cle)} = {_toml_valeur(valeur)}"
        motif = re.compile(r"^\s*(" + re.escape(cle) + r"|" + re.escape(json.dumps(cle, ensure_ascii=False)) + r")\s*=")
        for i in range(debut + 1, fin):
            if motif.match(lignes[i]):
                lignes[i] = ligne
                break
        else:
            pos = _fin_utile(lignes, debut, fin)
            lignes.insert(pos, ligne)
    resultat = "\n".join(lignes).rstrip("\n") + "\n"
    relu = tomllib.loads(resultat)
    if _sans_vides(relu) != _sans_vides(doc_attendu):
        raise RuntimeError("retouche TOML : le fichier relu ne correspond pas au document attendu")
    return resultat


def _sans_vides(d):
    if isinstance(d, dict):
        return {k: _sans_vides(v) for k, v in d.items() if not (isinstance(v, dict) and not v)}
    if isinstance(d, list):
        return [_sans_vides(x) for x in d]
    return d


# ------------------------------------------------------------------- fusion
class Fiche:
    """Une fiche et sa provenance : [section.sources] porte, par cle,
    { source = "...", date = "AAAA-MM-JJ" }."""

    def __init__(self, doc):
        self.doc = doc
        self.contradictions = []
        self.modifiee = False
        self.ops = []  # (section, cle, valeur) ecrites, dans l'ordre : pour la retouche textuelle

    def ecrire(self, section, cle, valeur):
        """Ecrit sans regle de protection (appid, [compat] etat/date d'une fiche neuve)."""
        self.section(section)[cle] = valeur
        self.ops.append((section, cle, valeur))
        self.modifiee = True

    def section(self, chemin):
        t = self.doc
        for p in chemin.split("."):
            t = t.setdefault(p, {})
        return t

    def source_de(self, section, cle):
        """(source, date) d'une cle : [section.sources] cle = "source date",
        sinon la `source`/`date` de la section entiere, sinon (None, None) :
        ecrite a la main, donc protegee."""
        sec = self.section(section)
        s = sec.get("sources", {}).get(cle) if isinstance(sec.get("sources"), dict) else None
        if isinstance(s, str) and s:
            parts = s.split()
            return parts[0], (parts[1] if len(parts) > 1 else None)
        if isinstance(sec.get("source"), str):
            return sec["source"], sec.get("date")
        return None, None

    def protegee(self, section, cle):
        if cle not in self.section(section):
            return False
        src, _ = self.source_de(section, cle)
        return src is None or src in SOURCES_PROTEGEES

    def poser(self, section, cle, valeur, source, date, appid=None):
        """Ecrit valeur sauf si la cle existante vient d'une source protegee ;
        dans ce cas, si les valeurs different, c'est une contradiction."""
        if valeur is None or valeur == [] or valeur == "":
            return False
        if isinstance(valeur, list):
            valeur = " ; ".join(str(x) for x in valeur)
        sec = self.section(section)
        if self.protegee(section, cle):
            if _differe(sec[cle], valeur):
                self.contradictions.append({
                    "appid": appid, "champ": f"{section}.{cle}",
                    "fiche": sec[cle], "source_fiche": self.source_de(section, cle)[0] or "fiche (a la main)",
                    "import": valeur, "source_import": source,
                })
            return False
        if cle in sec and not _differe(sec[cle], valeur):
            return False  # rien de neuf : la date d'origine reste
        sec[cle] = valeur
        self.ops.append((section, cle, valeur))
        self.poser_provenance(section, cle, source, date)
        self.modifiee = True
        return True

    def poser_provenance(self, section, cle, source, date):
        sec = self.section(section)
        if section == "jeu":
            sec.setdefault("sources", {})[cle] = f"{source} {date}"
            self.ops.append((f"{section}.sources", cle, f"{source} {date}"))
        else:
            # blocs d'import : une source et une date pour toute la section
            if sec.get("source") != source or sec.get("date") != date:
                sec["source"], sec["date"] = source, date
                self.ops.append((section, "source", source))
                self.ops.append((section, "date", date))


def _differe(a, b):
    if isinstance(a, list) and isinstance(b, list):
        return sorted(map(str, a)) != sorted(map(str, b))
    return a != b


# ---------------------------------------------------------------- wikitexte
def modeles(texte, nom):
    """Rend les corps des modeles {{nom ...}} (accolades equilibrees)."""
    res = []
    motif = re.compile(r"\{\{\s*" + re.escape(nom) + r"\s*(?=[|\n}])", re.I)
    for m in motif.finditer(texte):
        i, prof = m.end(), 1
        j = i
        while j < len(texte) and prof:
            if texte.startswith("{{", j):
                prof += 1
                j += 2
            elif texte.startswith("}}", j):
                prof -= 1
                j += 2
            else:
                j += 1
        res.append(texte[i:j - 2])
    return res


def champs(corps):
    """|cle = valeur (multi-ligne) -> dict, sans entrer dans les modeles imbriques."""
    d, prof, i, cour = {}, 0, 0, []
    morceaux = []
    while i < len(corps):
        if corps.startswith("{{", i) or corps.startswith("[[", i):
            prof += 1
            cour.append(corps[i:i + 2])
            i += 2
        elif corps.startswith("}}", i) or corps.startswith("]]", i):
            prof -= 1
            cour.append(corps[i:i + 2])
            i += 2
        elif corps[i] == "|" and prof == 0:
            morceaux.append("".join(cour))
            cour = []
            i += 1
        else:
            cour.append(corps[i])
            i += 1
    morceaux.append("".join(cour))
    for m in morceaux[1:]:
        if "=" in m:
            k, v = m.split("=", 1)
            d[k.strip().lower()] = v.strip()
    return d


def positionnels(corps):
    """Les parametres sans nom d'un modele ({{Game data/config|Windows|a|b}})."""
    res, prof, i, cour = [], 0, 0, []
    while i < len(corps):
        if corps.startswith("{{", i):
            prof += 1
            cour.append("{{")
            i += 2
        elif corps.startswith("}}", i):
            prof -= 1
            cour.append("}}")
            i += 2
        elif corps[i] == "|" and prof == 0:
            res.append("".join(cour).strip())
            cour = []
            i += 1
        else:
            cour.append(corps[i])
            i += 1
    res.append("".join(cour).strip())
    return res[1:]  # res[0] est le vide avant le premier |


def sans_balisage(s):
    s = re.sub(r"<ref[^>]*>.*?</ref>", "", s, flags=re.S)
    s = re.sub(r"<ref[^>]*/>", "", s)
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", s)
    s = re.sub(r"'{2,}", "", s)
    return s.strip()


def booleen_wiki(v):
    v = sans_balisage(v or "").lower()
    if v in ("true", "yes"):
        return True
    if v in ("false", "no"):
        return False
    return None


# Chemins PCGW {{p|...}} -> convention Cidre (relatif a drive_c/users/<user>/,
# `jeu:` pour le dossier du jeu, `steam:` pour celui de Steam, sinon absolu).
CHEMINS_P = {
    "appdata": "AppData/Roaming", "localappdata": "AppData/Local",
    "locallow": "AppData/LocalLow", "userprofile": "", "documents": "Documents",
    "savedgames": "Saved Games", "public": "C:/Users/Public",
    "programdata": "C:/ProgramData", "programfiles": "C:/Program Files",
    "programfiles(x86)": "C:/Program Files (x86)", "windir": "C:/Windows",
    "game": "jeu:", "steam": "steam:", "uid": "<uid>", "uplay": "ubisoft:",
    "hkcu": "registre:HKEY_CURRENT_USER", "hklm": "registre:HKEY_LOCAL_MACHINE",
    "wow64": "WOW6432Node",
}


def chemin_cidre(brut):
    s = sans_balisage(brut)
    s = re.sub(r"\{\{\s*p\s*\|\s*([^}|]+)\s*\}\}", lambda m: CHEMINS_P.get(m.group(1).strip().lower(), "{" + m.group(1).strip() + "}"), s, flags=re.I)
    s = re.sub(r"\{\{\s*code\s*\|([^}]*)\}\}", r"\1", s, flags=re.I)
    s = s.replace("\\", "/")
    s = re.sub(r"\{\{[^}]*\}\}", "", s)  # tout modele restant est du balisage
    s = re.sub(r"/{2,}", "/", s).strip().lstrip("/")
    if s.startswith("jeu:/"):
        s = "jeu:" + s[5:]
    if s.startswith("steam:/"):
        s = "steam:" + s[7:]
    if s.startswith("C:/Users/<uid>/"):
        s = s[len("C:/Users/<uid>/"):]
    if not s or "{" in s or len(s) > 200:
        return None
    return s


def moteur_cidre(brut):
    """(moteur du vocabulaire de la fiche, nom brut du moteur)."""
    s = sans_balisage(brut).lower().strip()
    if not s:
        return None, None
    for aiguille, nom in MOTEURS:
        if aiguille in s:
            nom = "unreal" if nom.startswith("unreal") else nom
            return (nom if nom in MOTEURS_FICHE else "autre"), sans_balisage(brut).strip()
    return "autre", sans_balisage(brut).strip()


def anticheat_cidre(brut):
    """(anticheat du vocabulaire de la fiche, nom brut)."""
    s = sans_balisage(brut).lower().strip()
    if not s:
        return None, None
    for aiguille, nom in sorted(ANTICHEAT.items(), key=lambda kv: -len(kv[0])):
        if aiguille in s:
            return (nom if nom in ANTICHEAT_FICHE else "autre"), sans_balisage(brut).strip()
    return "autre", sans_balisage(brut).strip()


# --------------------------------------------------------------- bibliotheque
def bibliotheque_steam(fichier=None):
    if fichier:
        with open(fichier, "r", encoding="utf-8") as f:
            return json.load(f)
    cidre = os.path.join(RACINE, "cidre")
    sortie = subprocess.run([cidre, "library", "--json"], capture_output=True, text=True, check=False)
    if sortie.returncode != 0 or not sortie.stdout.strip():
        dire("cidre library --json a echoue :", sortie.stderr.strip()[:300])
        return []
    return json.loads(sortie.stdout)


# ------------------------------------------------------------------ ProtonDB
def protondb_resume(toile, appid):
    r = toile.get(PROTONDB_SUMMARY.format(appid=appid), f"protondb/resumes/{appid}.json")
    if r["statut"] != 200 or not isinstance(r["corps"], dict):
        return None, r["date"]
    return r["corps"], r["date"]


def protondb_export_indexer(toile, appids):
    """L'export public des rapports (bdefore/protondb-data, tar.gz mensuel de
    ~70 Mo) est telecharge une fois, puis reduit a un index par appid :
    lanceur, options de lancement, anti-triche signale, verdicts recents.
    L'index est complete pour les appids qui n'y sont pas encore (l'archive en
    cache suffit, meme hors reseau). Rend (dossier de l'index, date de l'export)."""
    dossier = os.path.join(toile.cache, "protondb", "export")
    os.makedirs(dossier, exist_ok=True)
    marque = os.path.join(dossier, "index-fait.json")
    index_dir = os.path.join(dossier, "index")
    etat = json.load(open(marque)) if os.path.exists(marque) else None
    if etat and not isinstance(etat.get("appids"), list):
        etat["appids"] = []  # ancien marqueur (compteur) : on recompte
    voulus = set(map(str, appids))
    if etat and not toile.refresh and voulus <= set(etat.get("appids", [])):
        return index_dir, etat["date"]
    mois = {m: i for i, m in enumerate(("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"), 1)}

    def cle(n):
        m = re.match(r"reports_([a-z]{3})(\d+)_(\d{4})\.tar\.gz", n)
        return (int(m.group(3)), mois.get(m.group(1), 0), int(m.group(2))) if m else (0, 0, 0)
    locaux = [n for n in os.listdir(dossier) if cle(n) != (0, 0, 0)]
    nom = max(locaux, key=cle) if locaux else None
    if (not nom or toile.refresh) and not toile.sans_reseau:
        liste = toile.get(PROTONDB_EXPORT_DEPOT, "protondb/export/liste.json")
        if liste["statut"] == 200 and isinstance(liste["corps"], list):
            noms = [x["name"] for x in liste["corps"] if cle(x["name"]) != (0, 0, 0)]
            if noms and (not nom or cle(max(noms, key=cle)) > cle(nom)):
                candidat = max(noms, key=cle)
                dire(f"ProtonDB : telechargement de {candidat} (~70 Mo)...")
                r = toile.get(PROTONDB_EXPORT_BRUT.format(nom=candidat), "", binaire=True)
                if r["statut"] == 200:
                    with open(os.path.join(dossier, candidat + ".tmp"), "wb") as f:
                        f.write(r["corps"])
                    os.replace(os.path.join(dossier, candidat + ".tmp"), os.path.join(dossier, candidat))
                    nom = candidat
                else:
                    dire("ProtonDB : export indisponible (", r["statut"], ")")
        else:
            dire("ProtonDB : liste des exports indisponible")
    if not nom:
        dire("ProtonDB : pas d'export en cache, on continue sans")
        return (index_dir if os.path.isdir(index_dir) else None), (etat or {}).get("date")
    deja = set(etat.get("appids", [])) if etat and etat.get("export") == nom and not toile.refresh else set()
    manquants = voulus - deja
    dire(f"ProtonDB : indexation de l'export {nom} pour {len(manquants)} appid(s) (quelques dizaines de secondes)...")
    with tarfile.open(os.path.join(dossier, nom), "r:gz") as t:
        membre = next(m for m in t.getmembers() if m.name.endswith(".json"))
        rapports = json.load(t.extractfile(membre))
    par_app = collections.defaultdict(list)
    for x in rapports:
        try:
            a = str(x["app"]["steam"]["appId"])
        except (KeyError, TypeError):
            continue
        if a in manquants:
            par_app[a].append(x)
    del rapports
    os.makedirs(index_dir, exist_ok=True)
    for a in manquants:
        with open(os.path.join(index_dir, f"{a}.json"), "w", encoding="utf-8") as f:
            json.dump(_indexer_rapports(par_app.get(a, [])), f, ensure_ascii=False, indent=1)
    date = dt.date(*cle(nom)).isoformat()
    with open(marque + ".tmp", "w") as f:
        json.dump({"date": date, "export": nom, "appids": sorted(deja | voulus)}, f)
    os.replace(marque + ".tmp", marque)
    return index_dir, date


def _indexer_rapports(rapports):
    """Reduit les rapports d'un jeu a ce qui nous sert : pas de prose."""
    lanceurs = collections.Counter()
    options = collections.Counter()
    anticheat = collections.Counter()
    verdicts = collections.Counter()
    secondaire = collections.Counter()
    seuil = time.time() - 2 * 365 * 86400
    recents = 0
    for x in rapports:
        r = x.get("responses") or {}
        if x.get("timestamp", 0) >= seuil:
            recents += 1
            verdicts[str(r.get("verdict"))] += 1
            lo = (r.get("launchOptions") or "").strip()
            if lo and len(lo) <= 200:
                options[lo] += 1
        la = r.get("launcher")
        if la:
            lanceurs[la] += 1
        if r.get("secondaryLauncher") in ("yes", "no"):
            secondaire["oui" if r["secondaryLauncher"] == "yes" else "non"] += 1
        fu = (r.get("followUp") or {}).get("isImpactedByAntiCheat") or {}
        for k in fu:
            anticheat[k] += 1
        notes = r.get("notes") or {}
        txt = " ".join(str(v) for v in notes.values()).lower() if isinstance(notes, dict) else ""
        if r.get("isImpactedByAntiCheat") == "yes" and not fu:
            if "battleye" in txt or "battle eye" in txt:
                anticheat["battlEye"] += 1
            elif "eac" in txt or "easy anti" in txt:
                anticheat["easyAntiCheat"] += 1
            else:
                anticheat["autre"] += 1
    return {
        "total": len(rapports), "recents": recents,
        "verdicts_recents": dict(verdicts),
        "lanceurs": dict(lanceurs.most_common(5)),
        "options_lancement": [{"options": o, "n": n} for o, n in options.most_common(8)],
        "anticheat": dict(anticheat),
        "lanceur_secondaire": dict(secondaire),
    }


def protondb_index(index_dir, appid):
    if not index_dir:
        return None
    p = os.path.join(index_dir, f"{appid}.json")
    if not os.path.exists(p):
        return None
    with open(p, "r", encoding="utf-8") as f:
        return json.load(f)


# ------------------------------------------------------------ PCGamingWiki
def wiki_page(toile, api, prefixe, titre):
    """Wikitexte d'une page (API MediaWiki, pas index.php : Cloudflare)."""
    cle = f"{prefixe}/pages/{urllib.parse.quote(titre, safe='')}.json"
    url = api + "?" + urllib.parse.urlencode({
        "action": "query", "prop": "revisions", "rvprop": "content|timestamp",
        "rvslots": "main", "titles": titre, "redirects": 1,
        "format": "json", "formatversion": 2})
    r = toile.get(url, cle)
    if r["statut"] != 200 or not isinstance(r["corps"], dict):
        return None, None, r["date"]
    pages = r["corps"].get("query", {}).get("pages", [])
    if not pages or pages[0].get("missing"):
        return None, None, r["date"]
    p = pages[0]
    rev = p.get("revisions", [{}])[0]
    return p.get("title"), rev.get("slots", {}).get("main", {}).get("content", ""), r["date"]


def wiki_chercher_appid(toile, api, prefixe, appid):
    """Titres candidats pour un appid (recherche plein texte, puis on verifie
    dans l'infobox que c'est bien lui)."""
    cle = f"{prefixe}/recherche/{appid}.json"
    url = api + "?" + urllib.parse.urlencode({
        "action": "query", "list": "search", "srsearch": f'"{appid}"',
        "srwhat": "text", "srlimit": 5, "format": "json"})
    r = toile.get(url, cle)
    if r["statut"] != 200 or not isinstance(r["corps"], dict):
        return []
    return [x["title"] for x in r["corps"].get("query", {}).get("search", [])]


def infobox_appids(texte):
    ib = modeles(texte, "Infobox game")
    if not ib:
        return set(), set()
    c = champs(ib[0])
    principal = set(re.findall(r"\d+", c.get("steam appid", "")))
    cotes = set(re.findall(r"\d+", c.get("steam appid side", "")))
    return principal, cotes


def trouver_page(toile, api, prefixe, appid, nom_steam):
    """Page du jeu : par appid dans l'infobox, sinon par titre Steam."""
    candidats = wiki_chercher_appid(toile, api, prefixe, appid)
    if nom_steam:
        candidats = candidats + [nom_steam, re.sub(r"[®™©]", "", nom_steam).strip()]
    vus = set()
    repli = None
    for t in candidats:
        if t in vus:
            continue
        vus.add(t)
        titre, texte, date = wiki_page(toile, api, prefixe, t)
        if not texte:
            continue
        principal, cotes = infobox_appids(texte)
        if str(appid) in principal:
            return titre, texte, date, "appid"
        if str(appid) in cotes:
            repli = (titre, texte, date, "appid-side")
        elif not principal and not cotes and nom_steam and titre and titre.lower() == re.sub(r"[®™©]", "", nom_steam).strip().lower():
            repli = repli or (titre, texte, date, "titre")
    return repli or (None, None, None, None)


def pcgw_extraire(texte):
    """Donnees structurees d'une page PCGW : jamais de prose."""
    out = {}
    ib = modeles(texte, "Infobox game")
    if ib:
        c = champs(ib[0])
        moteurs = [moteur_cidre(positionnels(m)[0] if positionnels(m) else "")
                   for m in modeles(c.get("engines", ""), "Infobox game/row/engine")]
        moteurs = [m for m in moteurs if m[0]]
        if moteurs:
            # plusieurs moteurs (ex. remaster) : on prend le premier, on garde les noms
            out["moteur"] = moteurs[0][0]
            out["moteur_nom"] = " ; ".join(dict.fromkeys(m[1] for m in moteurs))
    api = modeles(texte, "API")
    if api:
        c = champs(api[0])
        apis = []
        for v in re.findall(r"\d+(?:\.\d+)?", sans_balisage(c.get("direct3d versions", ""))):
            apis.append("d3d" + v.split(".")[0])
        if re.search(r"\d", sans_balisage(c.get("directdraw versions", ""))):
            apis.append("ddraw")
        if re.search(r"\d", sans_balisage(c.get("opengl versions", ""))) or booleen_wiki(c.get("opengl versions")) is True:
            apis.append("opengl")
        vk = sans_balisage(c.get("vulkan versions", "") or c.get("vulkan support", ""))
        if re.search(r"\d", vk) or vk.lower() in ("true", "yes"):
            apis.append("vulkan")
        if booleen_wiki(c.get("metal support")) is True:
            apis.append("metal")
        if booleen_wiki(c.get("glide versions")) is True or re.search(r"\d", sans_balisage(c.get("glide versions", ""))):
            apis.append("glide")
        apis = list(dict.fromkeys(apis))
        if apis:
            out["api_disponibles"] = " ".join(apis)
            if len(apis) == 1:
                out["api"] = apis[0]  # une seule API : c'est celle que le jeu demande
        b32 = booleen_wiki(c.get("windows 32-bit exe"))
        b64 = booleen_wiki(c.get("windows 64-bit exe"))
        if b64:
            out["bits"] = 64  # un jeu 32+64 bits se lance en 64 sous Cidre
        elif b32:
            out["bits"] = 32
        if b64 and b32:
            out["bits_32_aussi"] = True
    mw = modeles(texte, "Middleware")
    if mw:
        c = champs(mw[0])
        ac, nom = anticheat_cidre(c.get("anticheat", ""))
        if ac:
            out["anticheat"] = ac
            if ac == "autre":
                out["anticheat_nom"] = nom
    # Fichiers de reglages et sauvegardes (Windows seulement)
    fichiers, saves = [], []
    for corps in modeles(texte, "Game data/config"):
        p = positionnels(corps)
        if p and p[0].strip().lower() == "windows":
            fichiers += [c for c in (chemin_cidre(x) for x in p[1:]) if c]
    for corps in modeles(texte, "Game data/saves"):
        p = positionnels(corps)
        if p and p[0].strip().lower() == "windows":
            saves += [c for c in (chemin_cidre(x) for x in p[1:]) if c]
    if fichiers:
        out["fichiers_reglages"] = list(dict.fromkeys(fichiers))
    if saves:
        out["sauvegardes"] = list(dict.fromkeys(saves))
    # DRM sur la boutique Steam
    for corps in modeles(texte, "Availability/row"):
        p = positionnels(corps)
        if len(p) >= 3 and p[0].strip().lower() == "steam":
            drm = sans_balisage(p[2]).strip().lower()
            if drm:
                out["drm"] = " ; ".join(sorted({d.strip() for d in re.split(r"[,;]", drm) if d.strip()}))
            break
    # Lanceur : PCGW note « launcher » dans Availability ou Infobox ? Non
    # (pas de champ dedie) : on n'invente pas.
    return out


# ------------------------------------------------------- AppleGamingWiki
def agw_extraire(texte):
    out = {}
    comp = modeles(texte, "Compatibility/macOS")
    if not comp:
        return out
    c = champs(comp[0])
    for cle, nom in (("native", "natif"), ("rosetta 2", "rosetta"), ("crossover", "crossover"),
                     ("wine", "wine"), ("parallels", "parallels")):
        v = sans_balisage(c.get(cle, "")).lower().strip()
        verdict = COMPAT_AGW.get(v, None)
        if verdict:
            out[nom] = verdict
    # Les notes ne sont pas recopiees : on n'en tire que la methode (GPTK,
    # Whisky...) et la date la plus recente des temoignages.
    methodes, dates = set(), []
    for cle in ("wine notes", "crossover notes"):
        n = (c.get(cle, "") or "").lower()
        for aiguille, nom in METHODES_MAC:
            if aiguille in n:
                methodes.add(nom)
        dates += re.findall(r"\|\s*date\s*=\s*(\d{4}-\d{2}-\d{2})", n)
    if methodes:
        out["methodes"] = " ".join(sorted(methodes))
    if dates:
        out["dernier_temoignage"] = max(dates)
    return out


# ------------------------------------------------------------------- import
def _compteur(d, n=5):
    """{'steam': 97, 'bottles': 2} -> "steam:97 bottles:2" (le README interdit les tables en ligne)."""
    return " ".join(f"{k}:{v}" for k, v in sorted(d.items(), key=lambda kv: -kv[1])[:n])


def importer(appid, nom_steam, plateformes, toile, index_dir, date_export, profils, aujourd):
    chemin = os.path.join(profils, f"{appid}.toml")
    doc = lire_toml(chemin) if os.path.exists(chemin) else {}
    fiche = Fiche(doc)
    jeu = fiche.section("jeu")
    if "appid" not in jeu:
        fiche.ecrire("jeu", "appid", int(appid) if str(appid).isdigit() else str(appid))
    if nom_steam:
        fiche.poser("jeu", "nom", nom_steam, "steam", aujourd, appid)
    if plateformes:
        fiche.poser("jeu", "plateformes_steam", " ".join(sorted(plateformes)), "steam", aujourd, appid)
    signaux = {}

    # --- ProtonDB : resume public (palier) + export des rapports (index local)
    resume, date_r = protondb_resume(toile, appid)
    if resume:
        for k_src, k in (("tier", "palier"), ("trendingTier", "tendance"), ("bestReportedTier", "meilleur_palier"),
                         ("confidence", "confiance"), ("total", "rapports")):
            if k_src in resume and resume[k_src] not in (None, ""):
                fiche.poser("compat.protondb", k, resume[k_src], "protondb", date_r, appid)
        if isinstance(resume.get("score"), (int, float)):
            fiche.poser("compat.protondb", "score", int(round(float(resume["score"]) * 100)), "protondb", date_r, appid)
        fiche.poser("compat.protondb", "url", PROTONDB_PAGE.format(appid=appid), "protondb", date_r, appid)
        signaux["protondb_palier"] = resume.get("tier")
    idx = protondb_index(index_dir, appid)
    if idx and idx.get("total"):
        d = date_export or aujourd
        if idx.get("lanceurs"):
            fiche.poser("compat.protondb", "lanceurs_signales", _compteur(idx["lanceurs"]), "protondb", d, appid)
        for n, o in enumerate(idx.get("options_lancement", [])[:3], 1):
            fiche.poser("compat.protondb", f"options_lancement_{n}", f'{o["options"]} (x{o["n"]})', "protondb", d, appid)
        if idx.get("lanceur_secondaire"):
            fiche.poser("compat.protondb", "lanceur_secondaire", _compteur(idx["lanceur_secondaire"]), "protondb", d, appid)
        if idx.get("anticheat"):
            fiche.poser("compat.protondb", "anticheat_signale", _compteur(idx["anticheat"]), "protondb", d, appid)
            ac = set()
            for k in idx["anticheat"]:
                kl = k.lower()
                if "easy" in kl or kl == "eac":
                    ac.add("eac")
                elif "battl" in kl:
                    ac.add("battleye")
            signaux["protondb_anticheat"] = ac
        if idx.get("verdicts_recents"):
            fiche.poser("compat.protondb", "verdicts_recents", _compteur(idx["verdicts_recents"]), "protondb", d, appid)
        fiche.poser("compat.protondb", "rapports_export", idx["total"], "protondb", d, appid)

    # --- PCGamingWiki : infobox, modele API, Middleware, Game data, Availability
    titre, texte, date_p, comment = trouver_page(toile, PCGW_API, "pcgw", appid, nom_steam)
    ex = {}
    if texte:
        ex = pcgw_extraire(texte)
        for k in ("moteur", "moteur_nom", "api", "api_disponibles", "bits", "bits_32_aussi",
                  "anticheat", "anticheat_nom", "drm"):
            if k in ex:
                fiche.poser("jeu", k, ex[k], "pcgamingwiki", date_p, appid)
        if "fichiers_reglages" in ex:
            fiche.poser("compat.pcgamingwiki", "fichiers_reglages", ex["fichiers_reglages"], "pcgamingwiki", date_p, appid)
        if "sauvegardes" in ex:
            fiche.poser("compat.pcgamingwiki", "sauvegardes", ex["sauvegardes"], "pcgamingwiki", date_p, appid)
        fiche.poser("compat.pcgamingwiki", "url", PCGW_PAGE.format(titre=urllib.parse.quote(titre.replace(" ", "_"))), "pcgamingwiki", date_p, appid)
        fiche.poser("compat.pcgamingwiki", "correspondance", comment, "pcgamingwiki", date_p, appid)
        signaux["pcgw_anticheat"] = ex.get("anticheat")

    # --- AppleGamingWiki : meme titre que PCGW en general
    titres = [t for t in (titre, nom_steam, re.sub(r"[®™©]", "", nom_steam or "").strip()) if t]
    titre_a, texte_a, date_a = None, None, None
    for t in dict.fromkeys(titres):
        titre_a, texte_a, date_a = wiki_page(toile, AGW_API, "agw", t)
        if texte_a:
            principal, _ = infobox_appids(texte_a)
            if str(appid) in principal or not principal:
                break
        titre_a, texte_a = None, None
    if not texte_a:
        for t in wiki_chercher_appid(toile, AGW_API, "agw", appid)[:2]:
            titre_a, texte_a, date_a = wiki_page(toile, AGW_API, "agw", t)
            if texte_a and str(appid) in infobox_appids(texte_a)[0]:
                break
            titre_a, texte_a = None, None
    if texte_a:
        ex_a = agw_extraire(texte_a)
        for k in ("natif", "rosetta", "crossover", "wine", "parallels", "methodes", "dernier_temoignage"):
            if k in ex_a:
                fiche.poser("compat.applegamingwiki", k, ex_a[k], "applegamingwiki", date_a, appid)
        fiche.poser("compat.applegamingwiki", "url", AGW_PAGE.format(titre=urllib.parse.quote(titre_a.replace(" ", "_"))), "applegamingwiki", date_a, appid)
        signaux["agw_wine"] = ex_a.get("wine")
        signaux["agw_crossover"] = ex_a.get("crossover")

    # --- anticheat : si PCGW est muet mais que les rapports ProtonDB en nomment un seul
    if not signaux.get("pcgw_anticheat") and signaux.get("protondb_anticheat"):
        acs = signaux["protondb_anticheat"]
        if len(acs) == 1:
            fiche.poser("jeu", "anticheat", next(iter(acs)), "protondb", date_export or aujourd, appid)

    # --- [compat] : jamais touche s'il existe ; sinon « non teste » date du jour
    if "etat" not in fiche.section("compat"):
        fiche.ecrire("compat", "etat", "non-teste")
        fiche.ecrire("compat", "date", aujourd)

    # --- contradictions entre sources externes (pas seulement avec la fiche)
    contradictions = list(fiche.contradictions)
    pa, da = signaux.get("pcgw_anticheat"), signaux.get("protondb_anticheat") or set()
    if pa and pa != "none" and da and pa not in da:
        contradictions.append({"appid": appid, "champ": "jeu.anticheat", "fiche": pa, "source_fiche": "pcgamingwiki",
                               "import": " ".join(sorted(da)), "source_import": "protondb (rapports)"})
    if jeu.get("anticheat") not in ("none", None) and fiche.protegee("jeu", "anticheat") and texte and not pa and not da:
        contradictions.append({"appid": appid, "champ": "jeu.anticheat", "fiche": jeu["anticheat"],
                               "source_fiche": fiche.source_de("jeu", "anticheat")[0] or "fiche (a la main)",
                               "import": "(aucun anti-triche signale)", "source_import": "pcgamingwiki+protondb"})
    pal = signaux.get("protondb_palier")
    for cle in ("agw_wine", "agw_crossover"):
        v = signaux.get(cle)
        if v == "ko" and pal in ("platinum", "gold"):
            contradictions.append({"appid": appid, "champ": "compat", "fiche": f"{cle[4:]}={v}", "source_fiche": "applegamingwiki",
                                   "import": f"palier={pal}", "source_import": "protondb"})
        if v == "parfait" and pal == "borked":
            contradictions.append({"appid": appid, "champ": "compat", "fiche": f"{cle[4:]}={v}", "source_fiche": "applegamingwiki",
                                   "import": f"palier={pal}", "source_import": "protondb"})

    if fiche.modifiee:
        os.makedirs(profils, exist_ok=True)
        if os.path.exists(chemin):
            # fiche existante (souvent ecrite a la main) : on retouche le texte, rien d'autre ne bouge
            with open(chemin, "r", encoding="utf-8") as f:
                texte = f.read()
            nouveau = retoucher_toml(texte, fiche.ops, doc)
            tmp = f"{chemin}.{os.getpid()}.tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                f.write(nouveau)
            os.replace(tmp, chemin)
        else:
            _ranger(doc)
            entete = (f"# {nom_steam or appid} -- fiche amorcee par tests/outils/importer_profils.py ({aujourd}).\n"
                      "# Chaque valeur importee porte sa source et sa date ([jeu.sources], ou `source`/`date`\n"
                      "# des blocs [compat.*]) ; une valeur sans provenance, cidre-test ou utilisateur n'est\n"
                      "# jamais ecrasee par l'import. Voir profils/README.md.")
            ecrire_toml(chemin, doc, entete)
    return fiche.modifiee, contradictions


ORDRE_SECTIONS = ("jeu", "cidre", "reglages_jeu", "compat", "rapports")


def _ranger(doc):
    """Sections dans l'ordre du README ; `sources` en fin de section."""
    def ranger_table(t, bloc_import=False):
        if not isinstance(t, dict):
            return t
        fin = ("source", "date", "url") if bloc_import else ()
        cles = [k for k in t if k != "sources" and k not in fin] + [k for k in fin if k in t] + (["sources"] if "sources" in t else [])
        nouveau = {k: ranger_table(t[k], bloc_import=(k in ("protondb", "pcgamingwiki", "applegamingwiki"))) for k in cles}
        t.clear()
        t.update(nouveau)
        return t
    cles = [s for s in ORDRE_SECTIONS if s in doc] + [k for k in doc if k not in ORDRE_SECTIONS]
    nouveau = {k: ranger_table(doc[k]) for k in cles}
    doc.clear()
    doc.update(nouveau)
    return


def generer_index(profils):
    outil = os.path.join(RACINE, "tests", "fiche_profil.sh")
    if not os.path.exists(outil) or os.path.abspath(profils) != PROFILS_DEFAUT:
        dire("index non regenere (fiche_profil.sh absent, ou dossier de fiches hors depot)")
        return
    sortie = subprocess.run(["sh", outil, "generer-index"], capture_output=True, text=True, check=False)
    if sortie.returncode != 0:
        dire("generer-index a echoue :", sortie.stderr.strip()[:300])
        return
    with open(os.path.join(profils, "index.toml"), "w", encoding="utf-8") as f:
        f.write(sortie.stdout)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("appids", nargs="*", help="appids Steam (defaut : la bibliotheque du compte)")
    ap.add_argument("--profils", default=PROFILS_DEFAUT, help="dossier des fiches (defaut : profils/)")
    ap.add_argument("--cache", default=CACHE_DEFAUT, help="cache des reponses (defaut : build/cache-profils/)")
    ap.add_argument("--bibliotheque", help="JSON de `cidre library --json` deja produit (au lieu de l'appeler)")
    ap.add_argument("--refresh", action="store_true", help="ignorer le cache, retelecharger")
    ap.add_argument("--sans-reseau", action="store_true", help="n'utiliser que le cache (tests, hors ligne)")
    ap.add_argument("--sans-export", action="store_true", help="ne pas telecharger l'export ProtonDB (resumes seulement)")
    ap.add_argument("--neuves-seulement", action="store_true", help="ne pas toucher aux fiches qui existent deja (ecrites a la main)")
    ap.add_argument("--windows-seulement", action="store_true", help="ignorer les jeux qui ont une version macOS native")
    ap.add_argument("--rapport", help="ecrire le rapport (JSON) des contradictions ici")
    ap.add_argument("--date", help="date a inscrire (defaut : aujourd'hui ; pour les tests)")
    ap.add_argument("--index", action="store_true", help="regenerer profils/index.toml a la fin (tests/fiche_profil.sh generer-index)")
    a = ap.parse_args(argv)

    aujourd = a.date or aujourdhui()
    toile = Toile(a.cache, refresh=a.refresh, sans_reseau=a.sans_reseau)
    biblio = bibliotheque_steam(a.bibliotheque) if (not a.appids or a.bibliotheque) else []
    par_appid = {str(g["appid"]): g for g in biblio if g.get("appid")}
    appids = [str(x) for x in a.appids] if a.appids else list(par_appid)
    if a.windows_seulement:  # ... sauf ceux qui ont deja une fiche (version Windows testee sous Cidre)
        appids = [x for x in appids if x not in par_appid or "macos" not in par_appid[x].get("plateformes", [])
                  or os.path.exists(os.path.join(a.profils, f"{x}.toml"))]
    if a.neuves_seulement:
        appids = [x for x in appids if not os.path.exists(os.path.join(a.profils, f"{x}.toml"))]
        if not appids:
            dire("toutes les fiches existent deja : rien a faire")
            if a.index:
                generer_index(a.profils)
            return 0
    if not appids:
        dire("aucun appid : donne-les en argument, ou verifie `cidre library --json`")
        return 2

    index_dir, date_export = (None, None)
    if not a.sans_export:
        index_dir, date_export = protondb_export_indexer(toile, appids)

    ecrites, contradictions, erreurs = 0, [], []
    for i, appid in enumerate(appids, 1):
        g = par_appid.get(appid, {})
        try:
            mod, contra = importer(appid, g.get("nom"), g.get("plateformes"), toile, index_dir, date_export,
                                   a.profils, aujourd)
        except Exception as e:  # une fiche cassee ne doit pas arreter les 1200 autres
            erreurs.append({"appid": appid, "erreur": f"{type(e).__name__}: {e}"})
            dire(f"[{i}/{len(appids)}] {appid} {g.get('nom', '')} : ERREUR {type(e).__name__}: {e}")
            continue
        ecrites += bool(mod)
        contradictions += contra
        if i % 25 == 0 or i == len(appids):
            dire(f"[{i}/{len(appids)}] fiches modifiees : {ecrites}, contradictions : {len(contradictions)}, requetes : {toile.requetes}")
    if a.index:
        generer_index(a.profils)
    rapport = {"date": aujourd, "appids": len(appids), "fiches_modifiees": ecrites,
               "contradictions": contradictions, "erreurs": erreurs, "requetes": toile.requetes}
    if a.rapport:
        with open(a.rapport, "w", encoding="utf-8") as f:
            json.dump(rapport, f, ensure_ascii=False, indent=1)
    else:
        for c in contradictions:
            print(f"{c['appid']} {c['champ']} : fiche={c['fiche']!r} ({c['source_fiche']}) vs import={c['import']!r} ({c['source_import']})")
    dire(f"{ecrites} fiche(s) ecrite(s) sur {len(appids)}, {len(contradictions)} contradiction(s), {len(erreurs)} erreur(s)")
    return 1 if erreurs else 0


if __name__ == "__main__":
    sys.exit(main())
