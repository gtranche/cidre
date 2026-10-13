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

Source `steam` : le nom et les plateformes viennent de la bibliotheque du
compte ; la configuration Steam Cloud du jeu ([compat.steam_cloud] : methode,
racines par systeme, motifs, et qui synchronise sous Cidre) vient de ses
metadonnees publiques, lues par SteamCMD sans compte (`app_info_print`,
section `ufs`) -- voir steam_cloud_valeurs et « Sauvegardes » du README.

Les reponses sont mises en cache (dossier ignore par git, --cache) : une
seconde execution ne retelecharge rien, --refresh force. Les textes des wikis
(CC BY-NC-SA) ne sont jamais recopies : on n'en tire que des donnees
structurees (modeles), et la fiche cite l'URL de la page.

Source `crossover` : les recettes CrossTie de CodeWeavers. Constat (2026-10-13) :
  - Ou : une seule archive publique, sans compte ni cle, remise a jour chaque
    jour, que CrossOver telecharge lui-meme :
      https://media.codeweavers.com/pub/crossover/tie/crossover.tie.gz
    (3 Mo, 24 Mo de XML, 4 489 recettes ; miroir ftp.codeweavers.com, meme
    chemin). Racine <c4p>, puis <applications><app appid="com.codeweavers.c4.N">,
    une entree par version minimale de CrossOver (<cxversion>) : la plus haute
    est la recette en vigueur. 1 574 Steam ID (<appprofile><steamid>). Les
    .tie unitaires se prennent sur le site, page par page, derriere un
    controle anti-robot (robots.txt : 100 s entre deux requetes) : on n'y va pas.
    Page d'une recette, citee dans la fiche, jamais telechargee :
      https://www.codeweavers.com/compatibility/browse/name/?app_id=N
  - Licence : aucune n'accompagne l'archive. Le site porte « Copyright (c)
    1999-2026 All Rights Reserved », sans conditions d'utilisation publiees ;
    la licence de CrossOver (codeweavers.com/crossover/eula) ne vise que « the
    software accompanying this License » et ne dit rien des recettes ni de la
    base. Aucune autorisation de reprise, donc : l'archive n'est ni
    redistribuee ni versee au depot (cache local, hors depot), et aucun texte
    n'en sort -- ni <description>, ni <installnotes>, ni <comment>, ni
    medailles, ni contributeurs.
  - Ce qu'on reprend : des valeurs techniques, qui sont des faits de
    configuration de Wine et pas une oeuvre -- gabarit de bouteille (version de
    Windows), DLL forcees (HKCU/Software/Wine/DllOverrides), autres cles sous
    Software/Wine, variables d'environnement de la bouteille, identifiants des
    dependances (traduits en verbes facon winetricks par NOTRE table) -- et
    seulement pour les jeux qui ont une fiche (une part non substantielle de la
    base). Les recettes n'ont pas d'options de lancement. Chaque fiche cite la
    recette (identifiant, URL, date) dans [compat.crossover].
  - Rang : le dernier. Une valeur CrossOver n'ecrase jamais celle d'une autre
    source ; elle ne remplace qu'une valeur CrossOver. Fondue dans [cidre]
    (dll_overrides, dependances, windows_version) avec
    sa provenance par cle dans [cidre.sources], sous garde-fous (voir
    crossover_valeurs et importer_crossover).
Ce constat n'est pas un avis juridique : si CodeWeavers publie des conditions
qui l'interdisent, `--sources` sans crossover et le retrait des blocs
[compat.crossover] suffisent a revenir en arriere.
"""
import argparse
import collections
import datetime as dt
import gzip
import json
import os
import re
import subprocess
import sys
import tarfile
import time
import tomllib
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

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

CROSSOVER_ARCHIVE = "https://media.codeweavers.com/pub/crossover/tie/crossover.tie.gz"
CROSSOVER_PAGE = "https://www.codeweavers.com/compatibility/browse/name/?app_id={n}"
CROSSOVER_TAILLE_MAX = 200 * 1024 * 1024  # XML decompresse : 24 Mo aujourd'hui

SOURCES = ("steam", "protondb", "pcgamingwiki", "applegamingwiki", "crossover")
SOURCES_PROTEGEES = ("cidre-test", "utilisateur")
# Rang d'autorite (cf. README) : une source n'ecrase que son rang ou plus bas.
RANG = {"cidre-test": 0, "utilisateur": 1, "winehq": 2, "steam": 3, "protondb": 3,
        "applegamingwiki": 3, "pcgamingwiki": 3, "crossover": 4}
RANG_DEFAUT = 3
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
    """Indice apres la derniere cle du bloc [debut, fin) : les lignes vides et
    les commentaires qui le terminent annoncent la section suivante."""
    j = fin
    while j > debut + 1 and (not lignes[j - 1].strip() or lignes[j - 1].lstrip().startswith("#")):
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
        motif = re.compile(r"^\s*(" + re.escape(cle) + r"|" + re.escape(json.dumps(cle, ensure_ascii=False)) + r")\s*=")
        if valeur is None:  # retrait d'une cle (Fiche.retirer)
            if bloc:
                debut, fin = bloc[-1][2], bloc[-1][3]
                for i in range(debut + 1, fin):
                    if motif.match(lignes[i]):
                        del lignes[i]
                        fin -= 1
                        break
                if not any(l.strip() for l in lignes[debut + 1:fin]):
                    del lignes[debut:fin]  # section videe : son en-tete part avec elle
            continue
        if not bloc:
            parent = section.rsplit(".", 1)[0] if "." in section else None
            apres = [x for x in secs if parent and (x[0] == parent or x[0].startswith(parent + ".")) and not x[1]]
            jeu = [x for x in secs if (x[0] == "jeu" or x[0].startswith("jeu.")) and not x[1]]
            if section.endswith(".sources") and apres:
                pos = _fin_utile(lignes, apres[-1][2], apres[-1][3])
            elif section == "cidre" and jeu:
                # [cidre] a sa place dans l'ordre du README : apres [jeu], pas en fin de fiche
                pos = _fin_utile(lignes, jeu[-1][2], jeu[-1][3])
            else:
                pos = len(lignes)
            lignes[pos:pos] = ["", f"[{section}]"]
            secs = _sections_texte(lignes)
            bloc = [x for x in secs if x[0] == section and not x[1]]
        nom, _, debut, fin = bloc[-1]
        ligne = f"{_toml_cle(cle)} = {_toml_valeur(valeur)}"
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
        r = {k: _sans_vides(v) for k, v in d.items()}
        return {k: v for k, v in r.items() if not (isinstance(v, dict) and not v)}
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
        if cle in sec:
            # une source de rang plus haut a deja parle : on ne l'ecrase pas
            en_place = self.source_de(section, cle)[0]
            if RANG.get(en_place, RANG_DEFAUT) < RANG.get(source, RANG_DEFAUT):
                if _differe(sec[cle], valeur):
                    self.contradictions.append({
                        "appid": appid, "champ": f"{section}.{cle}", "fiche": sec[cle], "source_fiche": en_place,
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

    def retirer(self, section, cle, source):
        """Retire une cle que `source` avait posee et qu'elle ne donne plus
        (recette changee) ; une cle d'une autre source, ou a la main, reste."""
        sec = self.doc
        for p in section.split("."):  # sans creer la section au passage
            sec = sec.get(p) if isinstance(sec, dict) else None
        if not isinstance(sec, dict) or cle not in sec or self.source_de(section, cle)[0] != source:
            return False
        del sec[cle]
        self.ops.append((section, cle, None))
        if isinstance(sec.get("sources"), dict) and cle in sec["sources"]:
            del sec["sources"][cle]
            self.ops.append((f"{section}.sources", cle, None))
        self.modifiee = True
        return True

    def poser_provenance(self, section, cle, source, date):
        sec = self.section(section)
        if section in ("jeu", "cidre"):
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


# --------------------------------------------------- Steam Cloud (app info)
# Ce que Steam publie de chaque jeu (« app info », section `ufs`) dit comment
# ses sauvegardes vont dans Steam Cloud. SteamCMD le lit sans compte
# (`+login anonymous +app_info_print`), dans son propre dossier, comme
# `cidre updates` : rien n'est demande au client Steam ni au compte.
STEAM_LOT = 60  # appids par lancement de SteamCMD
STEAM_ENTETE = re.compile(r"^AppID : (\d+), change number : (\d+)")
# Racine Steam -> dossier, dans la convention Cidre : sous drive_c/users/<utilisateur>/
# pour Windows (`jeu:` = dossier du jeu), sous le dossier personnel pour macOS.
RACINES_WINDOWS = {"winmydocuments": "Documents", "winappdatalocal": "AppData/Local",
                   "winappdatalocallow": "AppData/LocalLow", "winappdataroaming": "AppData/Roaming",
                   "winsavedgames": "Saved Games", "windowshome": "", "gameinstall": "jeu:"}
RACINES_MACOS = {"machome": "", "macappsupport": "Library/Application Support", "macdocuments": "Documents",
                 "gameinstall": "jeu:"}
OS_STEAM = {"windows": "windows", "macos": "macos", "macosx": "macos", "mac": "macos", "linux": "linux"}
CLES_STEAM_CLOUD = ("methode", "synchro", "racine_windows", "motifs", "dossier_windows", "racine_macos",
                    "motifs_macos", "partage", "liens", "sans_lien")


def vdf_lire(texte):
    """Le format texte de Valve (KeyValues) : "cle" "valeur" ou "cle" { ... }.
    Rend un dict (les cles en double : la derniere gagne)."""
    jetons = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', texte)
    pos = 0

    def bloc():
        nonlocal pos
        d = {}
        while pos < len(jetons):
            chaine, accolade = jetons[pos]
            pos += 1
            if accolade == "}":
                return d
            if accolade == "{":
                raise ValueError("accolade sans cle")
            if pos >= len(jetons):
                raise ValueError("cle sans valeur")
            v, acc = jetons[pos]
            pos += 1
            cle = re.sub(r"\\(.)", r"\1", chaine)
            if acc == "{":
                d[cle] = bloc()
            elif acc == "}":
                raise ValueError("cle sans valeur")
            else:
                d[cle] = re.sub(r"\\(.)", r"\1", v)
        return d

    return bloc()


def steamcmd_trouver(indique=None):
    for c in (indique, os.path.join(RACINE, "tools", "steamcmd", "steamcmd.sh"), os.environ.get("STEAMCMD"),
              "/opt/homebrew/bin/steamcmd"):
        if c and os.access(c, os.X_OK):
            return c
    return None


def steam_appinfo_decouper(sortie):
    """La sortie de `app_info_print` -> {appid: bloc VDF decode}."""
    lignes = sortie.replace("\r", "").split("\n")
    blocs, i = {}, 0
    while i < len(lignes):
        m = STEAM_ENTETE.match(lignes[i])
        i += 1
        if not m:
            continue
        j = i
        while j < len(lignes) and lignes[j] != "}" and not STEAM_ENTETE.match(lignes[j]):
            j += 1
        if j < len(lignes) and lignes[j] == "}":
            try:
                doc = vdf_lire("\n".join(lignes[i:j + 1]))
            except ValueError:
                doc = {}
            corps = doc.get(m.group(1))
            if isinstance(corps, dict):
                blocs[m.group(1)] = corps
            i = j + 1
    return blocs


def steam_appinfo_charger(toile, appids, steamcmd=None):
    """Met en cache (steam/appinfo/<appid>.json) ce que Steam publie des jeux
    qui n'y sont pas encore. On ne garde que ce qui sert : la section `ufs`, le
    nom, les plateformes. Un jeu que Steam ne montre pas sans compte est note
    (statut 403) et n'ecrit rien dans la fiche."""
    manquants = [a for a in appids if str(a).isdigit() and (toile.refresh or _steam_appinfo(toile, a) is None)]
    if not manquants or toile.sans_reseau:
        return 0
    scmd = steamcmd_trouver(steamcmd)
    if not scmd:
        dire("Steam Cloud : SteamCMD introuvable (tools/steamcmd/, STEAMCMD, --steamcmd) : inventaire saute")
        return 0
    cidre_dir = os.environ.get("CIDRE_DIR") or os.path.expanduser("~/Library/Application Support/Cidre")
    foyer = os.path.join(cidre_dir, "steamcmd-anonyme")  # le dossier de `cidre updates` : pas celui du client
    os.makedirs(foyer, exist_ok=True)
    env = dict(os.environ, HOME=foyer)
    lus = 0
    for debut in range(0, len(manquants), STEAM_LOT):
        lot = manquants[debut:debut + STEAM_LOT]
        restants = list(lot)
        for essai in range(3):  # un jeu pas encore en cache local est « demande » : il sort au passage suivant
            cmd = [scmd, "+login", "anonymous", "+app_info_update", "1"]
            for a in restants:
                cmd += ["+app_info_print", a]
            try:
                r = subprocess.run(cmd + ["+quit"], capture_output=True, text=True, errors="replace",
                                   stdin=subprocess.DEVNULL, env=env, timeout=600, check=False)
            except (OSError, subprocess.TimeoutExpired) as e:
                dire(f"Steam Cloud : SteamCMD a echoue ({type(e).__name__}) sur un lot de {len(restants)}")
                break
            toile.requetes += 1
            for a, corps in steam_appinfo_decouper(r.stdout).items():
                if a not in restants:
                    continue
                commun = corps.get("common") if isinstance(corps.get("common"), dict) else None
                garde = {"ufs": corps.get("ufs") if isinstance(corps.get("ufs"), dict) else None,
                         "nom": (commun or {}).get("name"), "oslist": (commun or {}).get("oslist")}
                toile.ecrire_cache(f"steam/appinfo/{a}.json",
                                   {"date": aujourdhui(), "statut": 200 if commun else 403, "corps": garde})
                restants.remove(a)
                lus += 1
            if not restants:
                break
        for a in restants:
            dire(f"Steam Cloud : pas de reponse de Steam pour {a}")
        dire(f"Steam Cloud : {min(debut + STEAM_LOT, len(manquants))}/{len(manquants)} jeux demandes a SteamCMD")
    return lus


def _steam_appinfo(toile, appid):
    """L'entree du cache, meme sous --refresh (le lot vient d'etre redemande)."""
    try:
        with open(toile.chemin(f"steam/appinfo/{appid}.json"), "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _vdf_liste(d):
    """Un bloc VDF numerote ("0" {...} "1" {...}) -> ses valeurs, dans l'ordre."""
    if not isinstance(d, dict):
        return []
    return [d[k] for k in sorted(d, key=lambda k: (not k.isdigit(), int(k) if k.isdigit() else 0, k))]


def _steam_os(d):
    """Le bloc `platforms` d'une regle -> {"windows", "macos", ...} ; vide = toutes."""
    noms = _vdf_liste(d) if isinstance(d, dict) else ([d] if isinstance(d, str) else [])
    plats = {OS_STEAM.get(str(n).strip().lower(), str(n).strip().lower()) for n in noms if str(n).strip()}
    return set() if "all" in plats else plats


def _steam_regle(regle, surcharges, os_):
    """Ou une regle `savefiles` range ses fichiers sur un systeme : (racine,
    chemin) apres `rootoverrides`, ou None si la regle ne vaut pas la."""
    plats = _steam_os(regle.get("platforms"))
    if plats and os_ not in plats:
        return None
    racine, chemin = str(regle.get("root", "")), str(regle.get("path", "")).replace("\\", "/")
    for s in surcharges:
        if str(s.get("root", "")).lower() != racine.lower():
            continue
        cible = OS_STEAM.get(str(s.get("os", "")).strip().lower())
        comparaison = str(s.get("oscompare", "=")).strip()
        if not ((comparaison == "=" and cible == os_) or (comparaison in ("!=", "<>") and cible != os_)):
            continue
        racine = str(s.get("useinstead") or racine)
        for t in _vdf_liste(s.get("pathtransforms")):
            cherche, remplace = str(t.get("find", "")).replace("\\", "/"), str(t.get("replace", "")).replace("\\", "/")
            if cherche:
                chemin = chemin.replace(cherche, remplace, 1)
            elif remplace:
                chemin = remplace.rstrip("/") + "/" + chemin
        if s.get("addpath"):
            chemin = str(s["addpath"]).replace("\\", "/").rstrip("/") + "/" + chemin
        break
    chemin = "/".join(p for p in chemin.split("/") if p not in ("", "."))
    table = RACINES_WINDOWS if os_ == "windows" else RACINES_MACOS
    if racine.lower() not in table or ".." in chemin.split("/"):
        return None  # racine d'un autre systeme : Steam ne sait pas la resoudre ici
    return racine, chemin


def _dossier(table, racine, chemin):
    base = table[racine.lower()]
    if base.endswith(":"):
        return base + chemin
    return "/".join(p for p in (base, chemin) if p)


def steam_cloud_valeurs(ufs):
    """La section `ufs` d'un jeu -> les valeurs de [compat.steam_cloud].

    methode : `aucune` (pas de Steam Cloud), `api` (le jeu ecrit par
    ISteamRemoteStorage : aucun dossier declare), `auto` (Auto-Cloud : Steam
    ramasse des fichiers dans des dossiers declares par systeme).
    synchro, qui synchronise sous Cidre : `steam-api` (le client macOS, par le
    pont), `steam-lien` (le client macOS, une fois le dossier du prefixe lie au
    dossier macOS declare), `copie` (Cidre : Steam ne sait pas resoudre une
    racine Windows sur macOS), `aucune`.
    `steam-api` dit que le jeu PEUT ecrire par l'API, pas que tout y passe : un
    dossier de sauvegardes locales designe par saves.conf reste copie par Cidre.
    Un lien n'est propose que si la meme regle vaut sur les deux systemes
    (`partage = "multiplateforme"`), ou si une regle Windows et une regle macOS
    de meme motif se repondent (`par-plateforme` : Steam garde alors des
    fichiers distincts par systeme, la synchro ne se fait qu'entre Mac). Des
    motifs differents sont des formats differents : pas de lien."""
    ufs = ufs if isinstance(ufs, dict) else {}
    regles = [r for r in _vdf_liste(ufs.get("savefiles")) if isinstance(r, dict)]
    surcharges = [s for s in _vdf_liste(ufs.get("rootoverrides")) if isinstance(s, dict)]
    try:
        quota = int(ufs.get("quota", 0) or 0)
    except ValueError:
        quota = 0
    if not regles:
        if quota <= 0:
            return {"methode": "aucune", "synchro": "aucune"}
        return {"methode": "api", "synchro": "steam-api"}

    def motif(r):
        return str(r.get("pattern", "*")) + (" (recursif)" if str(r.get("recursive", "0")) == "1" else "")

    win, mac = [], []  # (indice de la regle, racine, chemin, motif)
    for i, r in enumerate(regles):
        for os_, liste in (("windows", win), ("macos", mac)):
            ou = _steam_regle(r, surcharges, os_)
            if ou:
                liste.append((i, ou[0], ou[1], motif(r)))
    v = {"methode": "auto"}
    if win:
        v["racine_windows"] = " ; ".join(dict.fromkeys(f"{r}/{c}".rstrip("/") for _, r, c, _ in win))
        v["motifs"] = " ; ".join(dict.fromkeys(m for *_, m in win))
        # les memes dossiers dans la convention Cidre, pour la copie : coupes avant
        # une variable ({64BitSteamID}), et jamais une racine entiere
        dossiers = []
        for _, r, c, _ in win:
            fixe = []
            for part in c.split("/"):
                if "{" in part:
                    break
                fixe.append(part)
            if fixe and fixe != [""]:
                dossiers.append(_dossier(RACINES_WINDOWS, r, "/".join(fixe)))
        if dossiers:
            v["dossier_windows"] = " ; ".join(dict.fromkeys(dossiers))
    if mac:
        v["racine_macos"] = " ; ".join(dict.fromkeys(f"{r}/{c}".rstrip("/") for _, r, c, _ in mac))
        motifs_macos = " ; ".join(dict.fromkeys(m for *_, m in mac))
        if motifs_macos != v.get("motifs"):
            v["motifs_macos"] = motifs_macos
    if not win or not mac:
        v["synchro"] = "copie"
        return v

    # apparier chaque regle Windows a la regle macOS qui lui repond
    communs = {i for i, *_ in win} & {i for i, *_ in mac}
    paires, raisons = [], []
    for w in win:
        if w[0] in communs:
            paires.append((w, next(m for m in mac if m[0] == w[0])))
    win_seuls = [w for w in win if w[0] not in communs]
    mac_seuls = [m for m in mac if m[0] not in communs]
    v["partage"] = "multiplateforme" if not win_seuls else "par-plateforme"
    if win_seuls:
        if len(win_seuls) == len(mac_seuls) and all(w[3].lower() == m[3].lower() for w, m in zip(win_seuls, mac_seuls)):
            paires += list(zip(win_seuls, mac_seuls))
        else:
            for w in win_seuls:
                memes = [m for m in mac_seuls if m[3].lower() == w[3].lower()]
                if len(memes) == 1:
                    paires.append((w, memes[0]))
                elif not mac_seuls:
                    raisons.append("regle Windows sans equivalent macOS")
                else:
                    raisons.append("motifs differents" if not memes else "regles non appariables")
    liens = {}
    for w, m in paires:
        dw, dm = _dossier(RACINES_WINDOWS, w[1], w[2]), _dossier(RACINES_MACOS, m[1], m[2])
        if dm.startswith("jeu:") or dw.startswith("jeu:"):
            # cote macOS, le client les cherche dans SA bibliotheque, ou le jeu Windows n'est
            # pas ; cote Windows, on ne deplace jamais un dossier du jeu (ses binaires y sont)
            raisons.append("fichiers dans le dossier du jeu")
        elif not w[2] or not m[2]:
            raisons.append("racine entiere")  # on ne lie jamais Documents ou AppData entiers
        elif liens.get(dw, dm) != dm:
            raisons.append("un dossier Windows pour plusieurs dossiers macOS")
        else:
            liens[dw] = dm
    # un dossier deja couvert par le lien de son parent n'a pas besoin du sien
    for dw in sorted(liens, key=len):
        parent = next((p for p in liens if p != dw and dw.startswith(p + "/")), None)
        if parent:
            if liens[dw] != liens[parent] + dw[len(parent):]:
                raisons.append("dossiers imbriques")
            del liens[dw]
    if liens and not raisons:
        v["liens"] = " ; ".join(f"{a} => {b}" for a, b in liens.items())
        v["synchro"] = "steam-lien"
    else:
        v["sans_lien"] = " ; ".join(dict.fromkeys(raisons)) or "aucune regle a lier"
        v["synchro"] = "copie"
    return v


def importer_steam_cloud(fiche, appid, toile):
    vu = _steam_appinfo(toile, appid)
    if not vu or vu.get("statut") != 200 or not isinstance(vu.get("corps"), dict):
        return None
    v = steam_cloud_valeurs(vu["corps"].get("ufs"))
    for k in CLES_STEAM_CLOUD:
        if k in v:
            fiche.poser("compat.steam_cloud", k, v[k], "steam", vu["date"], appid)
        else:
            fiche.retirer("compat.steam_cloud", k, "steam")
    # dans une fiche retouchee, `source` et `date` ferment le bloc, comme dans une fiche neuve
    fin = [o for o in fiche.ops if o[0] == "compat.steam_cloud" and o[1] in ("source", "date")]
    fiche.ops = [o for o in fiche.ops if o not in fin] + fin
    return v


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


# ---------------------------------------------------------------- CrossOver
# Gabarit de bouteille CrossOver -> nom de version de winecfg (`winecfg -v`).
GABARITS = {"win11": "win11", "win10": "win10", "win8": "win8", "win7": "win7", "winvista": "vista",
            "winxp": "winxp", "win2000": "win2k", "win98": "win98"}
# Les versions que le lanceur sait poser (tests/version_windows.sh liste, que
# test_importer_profils.py compare a celle-ci) et qui ne sont pas un defaut :
# win10 est le notre, win11 l'autre defaut des recettes pour CrossOver 26. Un
# gabarit win98 n'en donne donc pas.
VERSIONS_WINDOWS_REPRISES = ("win81", "win8", "win7", "vista", "winxp64", "winxp", "win2k")
# A partir de CrossOver 23, win10_64 (puis win11_64) est le gabarit de 86 % des
# recettes de jeu (archive du 2026-10-12 ; win7_64 ou winxp dominent avant la
# 21) : un autre gabarit y est un choix. Avant, c'est le defaut de l'epoque.
CROSSOVER_GABARIT_CHOISI = 23
# Les DLL du chemin graphique sont celles de Cidre (DXVK, DXMT, vkd3d) : une
# recette ne les force pas.
DLL_GRAPHIQUES = re.compile(r"^(dxgi|d3d(8|9|10|10_1|10core|11|12|12core)|winemetal|nvapi(64)?)$")
DLL_NOM = re.compile(r"^\*?[A-Za-z0-9_.+-]{1,64}$")
DLL_MODES = {"native": "n", "builtin": "b", "disable": "", "disabled": ""}
CLE_DLL = re.compile(r"^(?:HKEY_CURRENT_USER|HKCU)\\Software\\Wine\\DllOverrides$", re.I)
CLE_DLL_EXE = re.compile(r"^(?:HKEY_CURRENT_USER|HKCU)\\Software\\Wine\\AppDefaults\\([^\\]{1,64})\\DllOverrides$", re.I)
CLE_WINE = re.compile(r"^(?:HKEY_CURRENT_USER|HKCU)\\Software\\Wine\\(.{1,80})$", re.I)
VALEUR_SURE = re.compile(r"^[A-Za-z0-9 _.:+*/-]{0,60}$")
# Nom (anglais) d'un composant CrossOver -> verbe facon winetricks. La table est
# la notre ; un composant qui n'y est pas reste cite par son identifiant.
VERBES = [
    (r"^core fonts$", "corefonts"),
    (r"^directx for modern games$", "directx_jun2010"),      # directx_Jun2010_redist.exe
    (r"^directx for pre-windows xp games$", "directx_feb2010"),
    (r"visual c\+\+ redistributable \(latest\)", "vcrun2022"),
    (r"visual c\+\+ (20\d\d)\b", r"vcrun\1"),
    (r"visual c\+\+ 6\.0", "vcrun6"),
    (r"\.net framework (\d)\.(\d)(?:\.(\d))?(?: service pack (\d))?$", None),  # voir _verbe
    (r"xml parser \(msxml\) (\d)", r"msxml\1"),
    (r"^windows gdi\+", "gdiplus"),
    (r"visual basic 6 runtime", "vb6run"),
    (r"\(mdac\) 2\.8", "mdac28"),
    (r"^microsoft jet 4\.0", "jet40"),
    (r"^internet explorer ([678])$", r"ie\1"),
    (r"^direct music$", "directmusic"),
    (r"^nvidia physx$", "physx"),
    (r"^xna framework (\d)\.(\d)$", r"xna\1\2"),
    (r"^xact engine", "xact"),
    (r"^d3dcompiler_(4[37])\b", r"d3dcompiler_\1"),
    (r"^openal$", "openal"),
    (r"^microsoft rich edit 2\.0$", "riched20"),
    (r"^microsoft rich edit 4\.1", "msftedit"),
    (r"^windows script 5\.7$", "wsh57"),
    (r"^truetype font: (arial|courier|georgia|impact|times|trebuchet|verdana|webdings)\b", r"\1"),
    (r"^adobe source han sans", "sourcehansans"),
    (r"^msls31$", "msls31"),
    (r"^microsoft media player sound engine 9$", "wmp9"),
    (r"^windows media player (9|10)$", r"wmp\1"),
]


def _tie_lire(chemin):
    """Racine XML d'un .tie ou .tie.gz. Donnee telechargee : taille bornee, et
    ni DOCTYPE ni entite (un .tie n'en a pas ; on ne laisse rien se deployer)."""
    with open(chemin, "rb") as f:
        if f.read(2) == b"\x1f\x8b":
            f.seek(0)
            with gzip.GzipFile(fileobj=f) as g:
                brut = g.read(CROSSOVER_TAILLE_MAX + 1)
        else:
            f.seek(0)
            brut = f.read(CROSSOVER_TAILLE_MAX + 1)
    if len(brut) > CROSSOVER_TAILLE_MAX:
        raise ValueError(f"{chemin} : plus de {CROSSOVER_TAILLE_MAX} octets une fois decompresse")
    if b"<!DOCTYPE" in brut or b"<!ENTITY" in brut:
        raise ValueError(f"{chemin} : DOCTYPE ou entite dans un .tie, refuse")
    return ET.fromstring(brut)


def titre_norme(s):
    """Titre compare « exactement » : casse, marques deposees, apostrophes et
    tirets typographiques, espaces. Rien d'autre (ni sous-titre, ni edition)."""
    s = re.sub(r"[®™©]", "", s or "")  # avant NFKC, qui ferait de « ™ » les lettres TM
    s = unicodedata.normalize("NFKC", s)
    for a, b in (("’", "'"), ("‘", "'"), ("–", "-"), ("—", "-")):
        s = s.replace(a, b)
    return re.sub(r"\s+", " ", s).strip().casefold()


def _version(s):
    return tuple(int(x) for x in re.findall(r"\d+", s or "")) or (0,)


def _condition(e, faits):
    """Un <useif> : True, False, ou None quand un fait nous est inconnu (langue
    de la bouteille, fichier d'installation...). Un motif <match> n'est jamais
    compile (donnee telechargee) : seuls `.*_64` et `.*_64$` sont reconnus."""
    if e.tag in ("useif", "and", "or"):
        vals = [_condition(c, faits) for c in e]
        if e.tag == "or":
            return True if True in vals else (None if None in vals else False)
        return False if False in vals else (None if None in vals else True)
    if e.tag == "not":
        vals = [_condition(c, faits) for c in e]
        return None if len(vals) != 1 or vals[0] is None else not vals[0]
    fait = faits.get((e.get("name") or "").strip().lower())
    texte = (e.text or "").strip()
    if fait is None:
        return None
    if e.tag == "equal":
        return fait.lower() == texte.lower()
    if e.tag == "match" and texte in (".*_64", ".*_64$"):
        return fait.endswith("_64")
    return None


def crossover_recette(ident, entrees):
    """Reduit les entrees <app> d'une recette a ses valeurs techniques : aucun
    texte (description, notes, commentaire) n'est lu."""
    def pour(a):  # version minimale de CrossOver visee par l'entree
        return max([_version(v.text) for v in a.findall("cxversion")] or [(0,)])
    entrees = [a for a in entrees if pour(a)[0] < 100]  # 200 : entree desactivee
    if not entrees:
        return None
    app = max(entrees, key=lambda a: (pour(a), a.get("timestamp") or ""))
    profil = app.find("appprofile")
    if profil is None:
        return None
    titres = list(dict.fromkeys((n.text or "").strip() for a in entrees for n in a.findall("name")
                                if n.get("lang") in (None, "en") and (n.text or "").strip()))
    gabarits = [(b.text or "").strip() for b in profil.findall("bottletemplate") if b.get("purpose") in (None, "use")]
    r = {
        "id": ident, "titres": titres, "titres_normes": {titre_norme(t) for t in titres},
        "steamids": sorted({(s.text or "").strip() for a in entrees for s in a.findall("appprofile/steamid")} - {""}),
        "jeu": (profil.findtext("category") or "").startswith("Games") and "application" in [f.text for f in profil.findall("flag")],
        "version": ".".join(map(str, pour(app))),
        "date": (app.get("timestamp") or "")[:10],
        "gabarit": gabarits[0] if gabarits else None,
        "dependances": [], "dll": [], "dll_exe": [], "registre": [], "environnement": [],
    }
    faits = {"platform": "Mac", "sourcetype": "steam", "bottletemplate": r["gabarit"], "vulkan.present": "yes"}
    for ip in app.findall("installprofile"):
        if ip.get("appid"):
            continue  # reglages poses pour une AUTRE application de la bouteille
        cond = ip.find("useif")
        if cond is not None and _condition(cond, faits) is not True:
            continue
        for tag in ("predependency", "postdependency"):
            r["dependances"] += [(d.text or "").strip() for d in ip.findall(tag) if (d.text or "").strip()]
        for tag in ("preinstallregistry", "postinstallregistry"):
            for reg in ip.findall(tag):
                cle = (reg.findtext("key") or "").strip()
                for v in reg.findall("value"):
                    nom, donnee = (v.findtext("name") or "").strip(), (v.findtext("data") or "").strip()
                    exe = CLE_DLL_EXE.match(cle)
                    wine = CLE_WINE.match(cle)
                    if CLE_DLL.match(cle):
                        r["dll"].append((nom, donnee))
                    elif exe:
                        r["dll_exe"].append((exe.group(1), nom, donnee))
                    elif wine:
                        r["registre"].append((wine.group(1).replace("\\", "/"), nom, donnee))
        # variables de la bouteille (durables) ; <installerenvironment> ne vaut que pour l'installeur
        for env in ip.findall("preinstallenvironment"):
            r["environnement"].append(((env.findtext("name") or "").strip(), (env.findtext("value") or "").strip()))
    for k in ("dependances", "dll", "dll_exe", "registre", "environnement"):
        r[k] = list(dict.fromkeys(r[k]))
    return r


def crossover_indexer(racines):
    """{recettes par identifiant, par Steam ID, par titre norme (jeux seulement)}."""
    par_id = collections.defaultdict(list)
    for racine in racines:
        for app in racine.iter("app"):
            if app.get("appid"):
                par_id[app.get("appid")].append(app)
    recettes, par_steam, par_titre = {}, collections.defaultdict(list), collections.defaultdict(list)
    for ident, entrees in par_id.items():
        r = crossover_recette(ident, entrees)
        if not r:
            continue
        recettes[ident] = r
        for s in r["steamids"]:
            par_steam[s].append(r)
        if r["jeu"]:
            for t in r["titres_normes"]:
                par_titre[t].append(r)
    return {"recettes": recettes, "par_steam": par_steam, "par_titre": par_titre}


def crossover_charger(toile, aujourd):
    """Telecharge (une fois) l'archive des recettes dans <cache>/crossover/ et
    indexe tous les .tie et .tie.gz du dossier. Rend (index, date) ou (None, None)."""
    dossier = os.path.join(toile.cache, "crossover")
    archive = os.path.join(dossier, os.path.basename(CROSSOVER_ARCHIVE))
    marque = os.path.join(dossier, "archive.json")
    if (not os.path.exists(archive) or toile.refresh) and not toile.sans_reseau:
        dire("CrossOver : telechargement de l'archive des recettes (~3 Mo)...")
        r = toile.get(CROSSOVER_ARCHIVE, "", binaire=True)
        if r["statut"] == 200 and r["corps"][:2] == b"\x1f\x8b":
            os.makedirs(dossier, exist_ok=True)
            with open(archive + ".tmp", "wb") as f:
                f.write(r["corps"])
            os.replace(archive + ".tmp", archive)
            with open(marque + ".tmp", "w", encoding="utf-8") as f:
                json.dump({"date": r["date"], "url": CROSSOVER_ARCHIVE, "octets": len(r["corps"])}, f)
            os.replace(marque + ".tmp", marque)
        else:
            dire("CrossOver : archive indisponible (", r["statut"], ")")
    fichiers = sorted(os.path.join(dossier, n) for n in (os.listdir(dossier) if os.path.isdir(dossier) else [])
                      if n.endswith((".tie", ".tie.gz")))
    if not fichiers:
        dire("CrossOver : pas de recette en cache, on continue sans")
        return None, None
    racines = []
    for p in fichiers:
        try:
            racines.append(_tie_lire(p))
        except (ValueError, OSError, EOFError, ET.ParseError) as e:
            dire(f"CrossOver : {os.path.basename(p)} illisible ({e}), ignore")
    date = aujourd
    if os.path.exists(marque):
        with open(marque, "r", encoding="utf-8") as f:
            date = json.load(f).get("date") or aujourd
    return crossover_indexer(racines), date


def crossover_trouver(index, appid, nom):
    """(recette, correspondance, confiance) : par Steam ID quand la recette en
    porte un (confiance haute), sinon par titre exact d'un jeu (moyenne). Deux
    recettes pour un meme jeu sans titre pour les departager : (None, "ambigu",
    identifiants). Rien trouve : (None, None, None)."""
    titre = titre_norme(nom)
    candidats = index["par_steam"].get(str(appid), [])
    if candidats:
        exacts = [r for r in candidats if titre and titre in r["titres_normes"]]
        if len(exacts) == 1:
            return exacts[0], "steamid+titre", "haute"
        if len(candidats) == 1:
            return candidats[0], "steamid", "haute"
        return None, "ambigu", " ".join(sorted(r["id"] for r in candidats))
    # une recette qui porte un AUTRE Steam ID est un autre jeu (autre edition, remaster)
    candidats = [r for r in index["par_titre"].get(titre, []) if not r["steamids"]] if titre else []
    if len(candidats) == 1:
        return candidats[0], "titre", "moyenne"
    if candidats:
        return None, "ambigu", " ".join(sorted(r["id"] for r in candidats))
    return None, None, None


def _verbe(nom):
    n = (nom or "").strip().lower()
    for motif, verbe in VERBES:
        m = re.search(motif, n)
        if not m:
            continue
        if verbe is None:  # .NET : 4.6.2 -> dotnet462, 3.5 Service Pack 1 -> dotnet35sp1
            return "dotnet" + m.group(1) + m.group(2) + (m.group(3) or "") + (f"sp{m.group(4)}" if m.group(4) else "")
        return m.expand(verbe)
    return None


def crossover_valeurs(r, index, bits=None):
    """Les valeurs d'une recette, en deux parts : `bloc` pour [compat.crossover]
    (la recette telle qu'elle est, sans prose) et `cidre` pour [cidre] (ce que
    le lanceur applique). Garde-fous de la seconde :
      - windows_version : seulement si le gabarit est un choix (recette pour
        CrossOver >= 23, voir CROSSOVER_GABARIT_CHOISI), plus ancien que
        win10 et connu du lanceur (VERSIONS_WINDOWS_REPRISES), et pas un
        gabarit 32 bits pour un jeu dont la fiche dit 64 bits (recette d'avant
        l'executable 64 bits). importer_crossover le pose, sauf
        --sans-crossover-windows-version ;
      - dll_overrides : `native` seul devient `n,b` -- la recette installe la
        DLL native par une dependance, nous pas encore : sans elle, `n` seul
        empecherait le jeu de demarrer, `n,b` retombe sur celle de Wine ; les
        DLL du chemin graphique (dxgi, d3d11...) restent celles de Cidre ;
      - dependances : les composants que notre table sait nommer."""
    bloc, cidre = {}, {}
    bloc["recette"] = r["id"]
    bloc["recette_date"] = r["date"]
    bloc["crossover_version"] = r["version"]
    gabarit = r["gabarit"] if r["gabarit"] and re.fullmatch(r"win[a-z0-9]+(_64)?", r["gabarit"]) else None
    if gabarit:
        bloc["bouteille"] = gabarit
        version = "winxp64" if gabarit == "winxp_64" else GABARITS.get(gabarit.removesuffix("_64"))
        choisi = _version(r["version"])[0] >= CROSSOVER_GABARIT_CHOISI
        trop_vieux = bits == 64 and not gabarit.endswith("_64")
        if version in VERSIONS_WINDOWS_REPRISES and choisi and not trop_vieux:
            cidre["windows_version"] = version
    # DLL forcees
    brutes, par_mode = [], collections.OrderedDict()
    for nom, donnee in r["dll"]:
        modes = [DLL_MODES.get(x.strip().lower()) for x in donnee.split(",")] if donnee else [""]
        if not DLL_NOM.match(nom) or None in modes or len(modes) > 2:
            continue
        brutes.append(f"{nom}={','.join(modes)}")
        if DLL_GRAPHIQUES.match(nom.lower().removesuffix(".dll")):
            continue
        if modes == ["n"]:
            modes = ["n", "b"]
        par_mode.setdefault(",".join(modes), []).append(nom)
    if brutes:
        bloc["dll_overrides"] = " ; ".join(brutes)
    if par_mode:
        cidre["dll_overrides"] = ";".join(f"{','.join(noms)}={mode}" for mode, noms in par_mode.items())
    par_exe = [f"{exe}:{nom}={','.join(DLL_MODES[x.strip().lower()] for x in donnee.split(','))}"
               for exe, nom, donnee in r["dll_exe"]
               if DLL_NOM.match(exe) and DLL_NOM.match(nom) and all(x.strip().lower() in DLL_MODES for x in donnee.split(","))]
    if par_exe:
        bloc["dll_overrides_par_exe"] = " ; ".join(par_exe)
    # dependances : nos verbes, et les identifiants de ce qu'on ne sait pas nommer
    verbes, inconnues, graphismes = [], [], None
    for ident in r["dependances"]:
        dep = index["recettes"].get(ident)
        nom = dep["titres"][0] if dep and dep["titres"] else ""
        if nom.lower().startswith("dxvk"):
            graphismes = "dxvk"
            continue
        if nom.lower() == "steam":
            continue  # le client Steam n'est pas un redistribuable
        v = _verbe(nom)
        if v:
            verbes.append(v)
        elif re.fullmatch(r"com\.codeweavers\.c4\.[A-Za-z0-9]+", ident):
            inconnues.append(ident)
    verbes = list(dict.fromkeys(verbes))
    if verbes:
        bloc["dependances"] = " ".join(verbes)
        cidre["dependances"] = " ".join(verbes)
    if inconnues:
        bloc["dependances_non_traduites"] = " ".join(dict.fromkeys(inconnues))
    # environnement de la bouteille, autres cles Wine : des donnees, pas appliquees
    env = [(n, v) for n, v in r["environnement"] if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]{0,40}", n) and VALEUR_SURE.match(v)]
    for n, v in env:
        if n.upper() in ("WINED3DMETAL", "D3DMETAL") and v == "1":
            graphismes = "d3dmetal"
        elif n == "CX_GRAPHICS_BACKEND" and v in ("dxvk", "dxmt", "d3dmetal", "wined3d") and graphismes != "d3dmetal":
            graphismes = v
    if env:
        bloc["environnement"] = " ; ".join(f"{n}={v}" for n, v in env)
    if graphismes:
        bloc["graphismes"] = graphismes
    reg = [f"{cle}:{nom}={donnee}" for cle, nom, donnee in r["registre"]
           if VALEUR_SURE.match(cle) and VALEUR_SURE.match(nom) and VALEUR_SURE.match(donnee)]
    if reg:
        bloc["registre"] = " ; ".join(reg)
    return bloc, cidre


CLES_CROSSOVER = ("recette", "correspondance", "confiance", "recette_date", "crossover_version", "bouteille",
                  "dll_overrides", "dll_overrides_par_exe", "dependances", "dependances_non_traduites",
                  "graphismes", "environnement", "registre", "url")
CLES_CIDRE_CROSSOVER = ("windows_version", "dll_overrides", "dependances")


def bilan_crossover_vide():
    return {"recettes": 0, "ambigus": [], "titres_differents": [], "windows_version_retenues": [], "cidre": {}}


def importer_crossover(fiche, appid, nom, crossover, bilan):
    """Fond la recette CrossOver du jeu dans la fiche. `bilan` (dict du rapport)
    compte ce qui a ete trouve et pose ; les desaccords vont, comme pour les
    autres sources, dans fiche.contradictions.
    Dans [cidre], rien n'est pose depuis une recette rapprochee par le titre
    seul (confiance moyenne : meme jeu, mais autre boutique ou edition CD).
    windows_version y est pose comme les autres cles : le lanceur le regle a
    chaque lancement, pour le jeu qu'il lance, et le retire pour un jeu qui
    ne le demande pas (tests/version_windows.sh) -- le prefixe partage n'en
    garde rien. Sans crossover["poser_windows_version"]
    (--sans-crossover-windows-version), ce que la recette aurait donne sort
    dans bilan["windows_version_retenues"] et la cle n'est pas posee."""
    index, date = crossover["index"], crossover["date"]
    r, comment, confiance = crossover_trouver(index, appid, nom)
    if r is None:
        if comment == "ambigu":
            bilan["ambigus"].append({"appid": appid, "nom": nom, "recettes": confiance})
        return
    bilan["recettes"] += 1
    bilan["par_" + comment.replace("+", "_")] = bilan.get("par_" + comment.replace("+", "_"), 0) + 1
    if titre_norme(nom) not in r["titres_normes"]:
        bilan["titres_differents"].append({"appid": appid, "nom": nom, "recette": r["id"], "titre_recette": r["titres"][0] if r["titres"] else ""})
    bits = fiche.section("jeu").get("bits")
    bloc, cidre = crossover_valeurs(r, index, bits)
    bloc["correspondance"], bloc["confiance"] = comment, confiance
    bloc["url"] = CROSSOVER_PAGE.format(n=urllib.parse.quote(r["id"].rsplit(".", 1)[-1]))
    S = "compat.crossover"
    for k in CLES_CROSSOVER:
        if k in bloc:
            fiche.poser(S, k, bloc[k], "crossover", date, appid)
        else:
            fiche.retirer(S, k, "crossover")
    if confiance != "haute":
        cidre = {}
    if "windows_version" in cidre and not crossover.get("poser_windows_version"):
        bilan["windows_version_retenues"].append({"appid": appid, "nom": nom, "windows_version": cidre.pop("windows_version"),
                                                  "recette": r["id"]})
    for k in CLES_CIDRE_CROSSOVER:
        if k in cidre:
            if fiche.poser("cidre", k, cidre[k], "crossover", date, appid) or fiche.source_de("cidre", k)[0] == "crossover":
                bilan["cidre"][k] = bilan["cidre"].get(k, 0) + 1
        else:
            fiche.retirer("cidre", k, "crossover")
    gabarit = bloc.get("bouteille")
    if gabarit and bits == 64 and not gabarit.endswith("_64"):
        fiche.contradictions.append({
            "appid": appid, "champ": "jeu.bits", "fiche": bits, "source_fiche": fiche.source_de("jeu", "bits")[0] or "fiche (a la main)",
            "import": f"bouteille {gabarit} (32 bits)", "source_import": "crossover"})


# ------------------------------------------------------------------- import
def _compteur(d, n=5):
    """{'steam': 97, 'bottles': 2} -> "steam:97 bottles:2" (le README interdit les tables en ligne)."""
    return " ".join(f"{k}:{v}" for k, v in sorted(d.items(), key=lambda kv: -kv[1])[:n])


def importer(appid, nom_steam, plateformes, toile, index_dir, date_export, profils, aujourd,
             sources=SOURCES, crossover=None, bilan_crossover=None, bilan_steam=None):
    chemin = os.path.join(profils, f"{appid}.toml")
    doc = lire_toml(chemin) if os.path.exists(chemin) else {}
    fiche = Fiche(doc)
    jeu = fiche.section("jeu")
    nom_connu = nom_steam or jeu.get("nom")  # sans bibliotheque : le nom deja dans la fiche
    if "appid" not in jeu:
        fiche.ecrire("jeu", "appid", int(appid) if str(appid).isdigit() else str(appid))
    if nom_steam and "steam" in sources:
        fiche.poser("jeu", "nom", nom_steam, "steam", aujourd, appid)
    if plateformes and "steam" in sources:
        fiche.poser("jeu", "plateformes_steam", " ".join(sorted(plateformes)), "steam", aujourd, appid)
    if "steam" in sources:
        cloud = importer_steam_cloud(fiche, appid, toile)
        if cloud and bilan_steam is not None:
            bilan_steam[cloud["synchro"]] = bilan_steam.get(cloud["synchro"], 0) + 1
    signaux = {}

    # --- ProtonDB : resume public (palier) + export des rapports (index local)
    resume, date_r = protondb_resume(toile, appid) if "protondb" in sources else (None, None)
    if resume:
        for k_src, k in (("tier", "palier"), ("trendingTier", "tendance"), ("bestReportedTier", "meilleur_palier"),
                         ("confidence", "confiance"), ("total", "rapports")):
            if k_src in resume and resume[k_src] not in (None, ""):
                fiche.poser("compat.protondb", k, resume[k_src], "protondb", date_r, appid)
        if isinstance(resume.get("score"), (int, float)):
            fiche.poser("compat.protondb", "score", int(round(float(resume["score"]) * 100)), "protondb", date_r, appid)
        fiche.poser("compat.protondb", "url", PROTONDB_PAGE.format(appid=appid), "protondb", date_r, appid)
        signaux["protondb_palier"] = resume.get("tier")
    idx = protondb_index(index_dir, appid) if "protondb" in sources else None
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
    titre, texte, date_p, comment = (trouver_page(toile, PCGW_API, "pcgw", appid, nom_steam)
                                     if "pcgamingwiki" in sources else (None, None, None, None))
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
    for t in dict.fromkeys(titres) if "applegamingwiki" in sources else ():
        titre_a, texte_a, date_a = wiki_page(toile, AGW_API, "agw", t)
        if texte_a:
            principal, _ = infobox_appids(texte_a)
            if str(appid) in principal or not principal:
                break
        titre_a, texte_a = None, None
    if not texte_a and "applegamingwiki" in sources:
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

    # --- CrossOver : la recette CrossTie du jeu, dernier rang
    if "crossover" in sources and crossover and crossover.get("index"):
        importer_crossover(fiche, appid, nom_connu, crossover, bilan_crossover if bilan_crossover is not None
                           else bilan_crossover_vide())

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
        nouveau = {k: ranger_table(t[k], bloc_import=(k in ("protondb", "pcgamingwiki", "applegamingwiki", "crossover", "steam_cloud"))) for k in cles}
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
    ap.add_argument("--sources", default=",".join(SOURCES),
                    help="sources a interroger, separees par des virgules (defaut : toutes) : " + ", ".join(SOURCES))
    ap.add_argument("--sans-crossover-windows-version", action="store_true",
                    help="ne pas poser [cidre] windows_version depuis les recettes CrossOver (pose par defaut : le "
                         "lanceur regle la version a chaque lancement, par jeu) ; les fiches concernees sortent "
                         "dans le rapport")
    ap.add_argument("--crossover-windows-version", action="store_true", help=argparse.SUPPRESS)  # l'ancien nom du defaut
    ap.add_argument("--steamcmd", help="le SteamCMD qui lit la configuration Steam Cloud des jeux (defaut : tools/steamcmd/, STEAMCMD)")
    ap.add_argument("--fiches-existantes", action="store_true",
                    help="sans appid : les fiches deja dans --profils, au lieu de la bibliotheque Steam")
    ap.add_argument("--rapport", help="ecrire le rapport (JSON) des contradictions ici")
    ap.add_argument("--date", help="date a inscrire (defaut : aujourd'hui ; pour les tests)")
    ap.add_argument("--index", action="store_true", help="regenerer profils/index.toml a la fin (tests/fiche_profil.sh generer-index)")
    a = ap.parse_args(argv)

    aujourd = a.date or aujourdhui()
    sources = tuple(x.strip() for x in a.sources.split(",") if x.strip())
    inconnues = [x for x in sources if x not in SOURCES]
    if inconnues:
        ap.error(f"source(s) inconnue(s) : {' '.join(inconnues)} (connues : {' '.join(SOURCES)})")
    toile = Toile(a.cache, refresh=a.refresh, sans_reseau=a.sans_reseau)
    existantes = a.fiches_existantes and not a.appids
    biblio = bibliotheque_steam(a.bibliotheque) if ((not a.appids and not existantes) or a.bibliotheque) else []
    par_appid = {str(g["appid"]): g for g in biblio if g.get("appid")}
    appids = [str(x) for x in a.appids] if a.appids else list(par_appid)
    if existantes:
        appids = sorted((n[:-5] for n in os.listdir(a.profils) if n.endswith(".toml") and n != "index.toml"),
                        key=lambda x: (not x.isdigit(), int(x) if x.isdigit() else 0, x))
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
    if not a.sans_export and "protondb" in sources:
        index_dir, date_export = protondb_export_indexer(toile, appids)
    index_crossover, date_crossover = crossover_charger(toile, aujourd) if "crossover" in sources else (None, None)
    crossover = {"index": index_crossover, "date": date_crossover, "poser_windows_version": not a.sans_crossover_windows_version}
    bilan_crossover = bilan_crossover_vide()
    bilan_steam = {}
    if "steam" in sources:
        steam_appinfo_charger(toile, appids, a.steamcmd)

    ecrites, contradictions, erreurs = 0, [], []
    for i, appid in enumerate(appids, 1):
        g = par_appid.get(appid, {})
        try:
            mod, contra = importer(appid, g.get("nom"), g.get("plateformes"), toile, index_dir, date_export,
                                   a.profils, aujourd, sources, crossover, bilan_crossover, bilan_steam)
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
    if crossover["index"]:
        b = bilan_crossover
        b["date_archive"] = crossover["date"]
        rapport["crossover"] = b
        dire(f"CrossOver : {b['recettes']} recette(s) trouvee(s), {len(b['ambigus'])} ambigue(s) ; [cidre] : "
             + (", ".join(f"{k} sur {n} fiche(s)" for k, n in sorted(b["cidre"].items())) or "rien")
             + (f" ; windows_version retenue sur {len(b['windows_version_retenues'])} fiche(s) (--sans-crossover-windows-version)"
                if b["windows_version_retenues"] else ""))
    if bilan_steam:
        rapport["steam_cloud"] = dict(sorted(bilan_steam.items()))
        dire("Steam Cloud : " + ", ".join(f"{k} {n}" for k, n in sorted(bilan_steam.items())))
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
