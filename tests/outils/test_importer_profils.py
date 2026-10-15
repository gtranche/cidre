#!/usr/bin/env python3
"""Test de tests/outils/importer_profils.py sur un jeu fictif aux reponses figees.

    python3 tests/outils/test_importer_profils.py

Les fixtures (tests/outils/fixtures/importer_profils/cache/) ont la forme du
cache de l'outil : il tourne dessus sans reseau (--sans-reseau). On verifie :
  - qu'une valeur ecrite a la main ou de source cidre-test n'est jamais ecrasee,
    et que le desaccord est rapporte comme contradiction ;
  - que les champs importes arrivent avec leur source et leur date ;
  - qu'aucun texte editorial des wikis n'est recopie ;
  - qu'un second passage ne change rien (idempotent) ;
  - que tests/fiche_profil.sh relit la fiche produite (sous-ensemble TOML) ;
  - la source crossover, sur des recettes CrossTie fabriquees (meme forme XML
    que l'archive publique) : seules les valeurs techniques sortent, la recette
    en vigueur est la plus haute version, les profils d'une autre plateforme
    sont ecartes, [cidre] recoit dll_overrides et dependances avec leur
    provenance sans ecraser ce qui y est, crossover reste au dernier rang ;
  - l'inventaire Steam Cloud ([compat.steam_cloud], section `ufs` des
    metadonnees Steam) : methode, racines par systeme apres `rootoverrides`,
    liens proposes seulement quand la meme regle vaut sur macOS ou que les
    motifs se repondent, jamais vers le dossier du jeu ni une racine entiere ;
    et la lecture de SteamCMD, sur un faux SteamCMD ;
  - le mode catalogue (--catalogue-protondb), sur un cache fabrique : les jeux
    de l'export ProtonDB sans version macOS, nommes par le magasin Steam (ou par
    l'export s'il ne les montre plus), la page du wiki trouvee par ses liens
    vers Steam et verifiee dans l'infobox, rien d'ecrit a la main reecrit ;
    et tests/outils/verifier_catalogue.py, qui le voit si on y touche.
"""
import gzip
import importlib.util
import io
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import tomllib

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE = os.path.abspath(os.path.join(ICI, "..", ".."))
OUTIL = os.path.join(ICI, "importer_profils.py")
FIXTURES = os.path.join(ICI, "fixtures", "importer_profils")
APPID = "990000001"
DATE = "2026-01-01"


def lancer(profils, rapport, *options):
    cmd = [sys.executable, "-I", OUTIL, "--sans-reseau", "--cache", os.path.join(FIXTURES, "cache"),
           "--profils", profils, "--bibliotheque", os.path.join(FIXTURES, "bibliotheque.json"),
           "--rapport", rapport, "--date", DATE, *options, APPID]
    r = subprocess.run(cmd, capture_output=True, text=True)
    assert r.returncode == 0, f"rc={r.returncode}\n{r.stderr}"
    with open(rapport, "rb") as f:
        return json.load(f)


def unitaires_crossover(tmp):
    """Rapprochement, garde-fous et rang, sur le module charge en direct."""
    sys.dont_write_bytecode = True  # pas de __pycache__ a cote de l'outil
    spec = importlib.util.spec_from_file_location("importer_profils", OUTIL)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    tie = os.path.join(FIXTURES, "cache", "crossover", "jeux-fictifs.tie")
    index = m.crossover_indexer([m._tie_lire(tie)])

    # la meme recette en .tie.gz ; un DOCTYPE est refuse
    gz = os.path.join(tmp, "a.tie.gz")
    with open(tie, "rb") as f, gzip.open(gz, "wb") as g:
        g.write(f.read())
    assert m.crossover_indexer([m._tie_lire(gz)])["recettes"].keys() == index["recettes"].keys()
    piege = os.path.join(tmp, "piege.tie")
    with open(piege, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0"?><!DOCTYPE c4p [<!ENTITY a "aaaa">]><c4p><applications/></c4p>')
    try:
        m._tie_lire(piege)
        raise AssertionError("DOCTYPE accepte")
    except ValueError:
        pass

    # rapprochement : Steam ID, titre exact d'un jeu, ambigu, rien
    r, comment, confiance = m.crossover_trouver(index, "990000001", "Tout Autre Nom")
    assert (r["id"], comment, confiance) == ("com.codeweavers.c4.90001", "steamid", "haute")
    r, comment, confiance = m.crossover_trouver(index, "990000002", "JEU SANS IDENTIFIANT™: L'Édition")
    assert (r["id"], comment, confiance) == ("com.codeweavers.c4.90020", "titre", "moyenne")
    assert m.crossover_trouver(index, "990000002", "Jeu Sans Identifiant") == (None, None, None)
    assert m.crossover_trouver(index, "990000003", "Jeu Refait") == (None, None, None)  # la recette porte un autre Steam ID
    assert m.crossover_trouver(index, "990000004", "Tableur Homonyme") == (None, None, None)  # pas un jeu
    assert m.crossover_trouver(index, "990000030", "Jeu Double Deluxe") == (
        None, "ambigu", "com.codeweavers.c4.90030 com.codeweavers.c4.90031")
    r, comment, _ = m.crossover_trouver(index, "990000030", "Jeu Double: Complet")
    assert (r["id"], comment) == ("com.codeweavers.c4.90031", "steamid+titre")

    # une recette rapprochee par le titre est citee, mais rien n'entre dans [cidre]
    fiche, bilan = m.Fiche({"jeu": {"appid": 990000002}}), m.bilan_crossover_vide()
    crossover = {"index": index, "date": DATE, "poser_windows_version": True}
    m.importer_crossover(fiche, "990000002", "Jeu Sans Identifiant: L'Édition", crossover, bilan)
    x = fiche.doc["compat"]["crossover"]
    assert x["confiance"] == "moyenne" and x["dependances"] == "vcrun2015", x
    assert "cidre" not in fiche.doc and bilan["cidre"] == {} and bilan["par_titre"] == 1, (fiche.doc, bilan)

    # gabarit : choisi (>= 23) et plus ancien que win10 ; pas un gabarit 32 bits pour un jeu 64 bits
    xp = index["recettes"]["com.codeweavers.c4.90020"]  # winxp, CrossOver 25
    assert m.crossover_valeurs(xp, index, bits=32)[1]["windows_version"] == "winxp"
    assert "windows_version" not in m.crossover_valeurs(xp, index, bits=64)[1]
    assert "windows_version" not in m.crossover_valeurs(dict(xp, version="22.0.1"), index, bits=32)[1]
    for gabarit in ("win10_64", "win11_64"):
        assert "windows_version" not in m.crossover_valeurs(dict(xp, gabarit=gabarit), index)[1]
    assert m.crossover_valeurs(dict(xp, gabarit="winvista_64"), index)[1]["windows_version"] == "vista"
    # ... et seulement une version que le lanceur sait poser : pas de Windows 9x
    assert "windows_version" not in m.crossover_valeurs(dict(xp, gabarit="win98"), index, bits=32)[1]
    lanceur = subprocess.run(["sh", os.path.join(os.path.dirname(ICI), "version_windows.sh"), "liste"],
                             capture_output=True, text=True, check=True).stdout.split()
    assert set(m.VERSIONS_WINDOWS_REPRISES) == set(lanceur) - {"win10", "win11"}, lanceur
    fiche = m.Fiche({"jeu": {"appid": 990000002, "bits": 64, "sources": {"bits": "pcgamingwiki 2026-01-01"}}})
    m.importer_crossover(fiche, "990000002", "Jeu Sans Identifiant: L'Édition", crossover, m.bilan_crossover_vide())
    assert [(c["champ"], c["import"]) for c in fiche.contradictions] == [("jeu.bits", "bouteille winxp (32 bits)")]

    # rang : crossover n'ecrase ni winehq ni une valeur a la main, seulement crossover
    fiche = m.Fiche({"cidre": {"dll_overrides": "a=b", "dependances": "vcrun6", "tso": False,
                               "sources": {"dll_overrides": "winehq 2025-01-01", "dependances": "crossover 2025-01-01"}}})
    assert fiche.poser("cidre", "dll_overrides", "c=n,b", "crossover", DATE, 1) is False
    assert fiche.poser("cidre", "tso", True, "crossover", DATE, 1) is False
    assert fiche.poser("cidre", "dependances", "vcrun2022", "crossover", DATE, 1) is True
    assert fiche.doc["cidre"]["dll_overrides"] == "a=b" and fiche.doc["cidre"]["tso"] is False
    assert fiche.doc["cidre"]["sources"]["dependances"] == f"crossover {DATE}"
    assert [(c["champ"], c["source_fiche"]) for c in fiche.contradictions] == [
        ("cidre.dll_overrides", "winehq"), ("cidre.tso", "fiche (a la main)")], fiche.contradictions
    assert fiche.poser("cidre", "dll_overrides", "c=n,b", "winehq", DATE, 1) is True  # un rang egal ou plus haut, oui
    assert fiche.retirer("cidre", "tso", "crossover") is False and fiche.retirer("cidre", "dependances", "crossover") is True

    # la table des verbes
    for nom, verbe in (("Microsoft Visual C++ Redistributable (latest) (64-bit)", "vcrun2022"),
                       ("Microsoft Visual C++ 2008 (9.0) Redistributable", "vcrun2008"),
                       ("Microsoft Visual C++ 6.0 (4.2 & 6.0) Redistributable", "vcrun6"),
                       ("Microsoft .NET Framework 4.0", "dotnet40"), ("Microsoft .NET Framework 2.0 Service Pack 2", "dotnet20sp2"),
                       ("Microsoft XML Parser (MSXML) 6.0 SP2", "msxml6"), ("Core Fonts", "corefonts"),
                       ("d3dcompiler_47 (64-bit)", "d3dcompiler_47"), ("XNA Framework 4.0", "xna40"),
                       ("TrueType font: Arial", "arial"), ("Composant Que Notre Table Ignore", None)):
        assert m._verbe(nom) == verbe, (nom, m._verbe(nom))


def charger_outil():
    sys.dont_write_bytecode = True  # pas de __pycache__ a cote de l'outil
    spec = importlib.util.spec_from_file_location("importer_profils", OUTIL)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def unitaires_catalogue(tmp):
    """--catalogue-protondb sur un cache fabrique, sans reseau."""
    cache, profils = os.path.join(tmp, "cat-cache"), os.path.join(tmp, "cat-profils")
    os.makedirs(profils)

    def poser(cle, corps, statut=200):
        p = os.path.join(cache, cle)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as f:
            json.dump({"date": DATE, "statut": statut, "corps": corps}, f)
    WIN, MAC, RETIRE = "990000011", "990000012", "990000013"
    # l'export : trois jeux ; le titre le plus recent fait foi
    rapports = [{"app": {"steam": {"appId": WIN}, "title": "Vieux titre"}, "timestamp": 100, "responses": {"verdict": "yes"}},
                {"app": {"steam": {"appId": WIN}, "title": "Jeu Catalogue"}, "timestamp": 200, "responses": {"verdict": "yes"}},
                {"app": {"steam": {"appId": MAC}, "title": "Jeu Mac"}, "timestamp": 100, "responses": {}},
                {"app": {"steam": {"appId": RETIRE}, "title": "Jeu Retire"}, "timestamp": 100, "responses": {}}]
    os.makedirs(os.path.join(cache, "protondb", "export"))
    brut = json.dumps(rapports).encode()
    with tarfile.open(os.path.join(cache, "protondb", "export", "reports_oct1_2026.tar.gz"), "w:gz") as t:
        info = tarfile.TarInfo("reports_piiremoved.json")
        info.size = len(brut)
        t.addfile(info, io.BytesIO(brut))
    poser(f"steam/magasin/{WIN}.json", {"nom": "Jeu Catalogue", "type": 0, "plateformes": ["windows"]})
    poser(f"steam/magasin/{MAC}.json", {"nom": "Jeu Mac", "type": 0, "plateformes": ["windows", "macos"]})
    poser(f"steam/magasin/{RETIRE}.json", None, 404)
    poser(f"protondb/resumes/{WIN}.json", {"tier": "gold", "confidence": "good", "score": 0.7, "total": 12,
                                           "trendingTier": "gold", "bestReportedTier": "platinum"})
    # la carte : la page du jeu, et une liste qui le lie aussi (rejetee : pas d'infobox a son appid)
    poser("pcgw/carte-steam.json", {WIN: ["Liste de jeux", "Jeu Catalogue"]})
    poser("agw/carte-steam.json", {})

    def page(titre, texte):
        poser(f"pcgw/pages/{titre.replace(' ', '%20')}.json",
              {"query": {"pages": [{"title": titre, "revisions": [{"slots": {"main": {"content": texte}}}]}]}})
    page("Liste de jeux", "Des jeux.")
    page("Jeu Catalogue", "{{Infobox game\n|engines = \n{{Infobox game/row/engine|Unity}}\n|steam appid = " + WIN + "\n}}\n")
    # une fiche ecrite a la main : son moteur ne bouge pas
    avant = '[jeu]\nappid = 990000011\nmoteur = "unreal"\n\n[compat]\netat = "ok"\ndate = "2025-12-01"\n'
    with open(os.path.join(profils, f"{WIN}.toml"), "w", encoding="utf-8") as f:
        f.write(avant)
    depot = os.path.join(tmp, "cat-depot")
    shutil.copytree(profils, depot)
    rapport = os.path.join(tmp, "cat-rapport.json")
    r = subprocess.run([sys.executable, "-I", OUTIL, "--catalogue-protondb", "--sans-reseau", "--cache", cache,
                        "--profils", profils, "--date", DATE, "--rapport", rapport],
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stderr
    rap = json.load(open(rapport))
    assert rap["catalogue"]["windows_seulement"] == 1 and rap["catalogue"]["mac_natif"] == 1 \
        and rap["catalogue"]["hors_magasin"] == 1, rap
    assert sorted(os.listdir(profils)) == [f"{WIN}.toml", f"{RETIRE}.toml"], os.listdir(profils)
    w = tomllib.load(open(os.path.join(profils, f"{WIN}.toml"), "rb"))
    assert w["jeu"]["moteur"] == "unreal" and w["compat"]["etat"] == "ok", w
    assert any(c["champ"] == "jeu.moteur" for c in rap["contradictions"]), rap["contradictions"]
    assert w["jeu"]["nom"] == "Jeu Catalogue" and w["jeu"]["sources"]["nom"] == f"steam {DATE}", w
    assert w["jeu"]["plateformes_steam"] == "windows", w
    assert w["compat"]["protondb"]["palier"] == "gold" and w["compat"]["protondb"]["score"] == 70, w
    assert w["compat"]["pcgamingwiki"]["url"].endswith("/Jeu_Catalogue"), w
    assert w["compat"]["pcgamingwiki"]["correspondance"] == "appid", w
    assert open(os.path.join(profils, f"{WIN}.toml")).read().startswith(avant.split("\n\n")[0]), "fiche reecrite"
    x = tomllib.load(open(os.path.join(profils, f"{RETIRE}.toml"), "rb"))
    assert x["jeu"]["nom"] == "Jeu Retire" and x["jeu"]["sources"]["nom"] == f"protondb {DATE}", x
    assert "plateformes_steam" not in x["jeu"] and "protondb" in x["compat"], x  # l'export, sans resume
    assert "crossover" not in json.dumps(w) + json.dumps(x)
    # le verificateur : rien de change a la main, l'index va avec les fiches
    verif = os.path.join(ICI, "verifier_catalogue.py")
    outil = os.path.join(RACINE, "tests", "fiche_profil.sh")
    if os.path.exists(outil):
        idx = subprocess.run(["sh", outil, "generer-index", profils], capture_output=True, text=True, check=True).stdout
        with open(os.path.join(profils, "index.toml"), "w") as f:
            f.write(idx)
        r = subprocess.run([sys.executable, "-I", verif, depot, profils], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr + r.stdout
        with open(os.path.join(profils, f"{WIN}.toml")) as f:
            t = f.read()
        with open(os.path.join(profils, f"{WIN}.toml"), "w") as f:
            f.write(t.replace('moteur = "unreal"', 'moteur = "unity"'))
        r = subprocess.run([sys.executable, "-I", verif, depot, profils], capture_output=True, text=True)
        assert r.returncode == 1 and "jeu.moteur" in r.stderr, r.stderr
        os.remove(os.path.join(profils, f"{RETIRE}.toml"))
        r = subprocess.run([sys.executable, "-I", verif, depot, profils], capture_output=True, text=True)
        assert r.returncode == 1 and f"{RETIRE} sans fiche" in r.stderr, r.stderr


def unitaires_steam_cloud(tmp):
    """La section `ufs` de Steam -> [compat.steam_cloud], et la lecture de SteamCMD."""
    m = charger_outil()
    v = m.steam_cloud_valeurs

    # pas de Steam Cloud ; API Remote Storage (un quota, aucun dossier declare)
    assert v(None) == {"methode": "aucune", "synchro": "aucune"}
    assert v({"quota": "0", "maxnumfiles": "0"}) == {"methode": "aucune", "synchro": "aucune"}
    assert v({"quota": "10000000", "maxnumfiles": "100"}) == {"methode": "api", "synchro": "steam-api"}

    # Auto-Cloud, Windows seulement : Steam ne sait pas resoudre la racine sur macOS
    x = v({"quota": "1", "savefiles": {"0": {"root": "WinAppDataLocal", "path": "Studio/Saved/SaveGames/{64BitSteamID}",
                                             "pattern": "*.sav", "recursive": "1"}}})
    assert x == {"methode": "auto", "synchro": "copie", "racine_windows": "WinAppDataLocal/Studio/Saved/SaveGames/{64BitSteamID}",
                 "motifs": "*.sav (recursif)", "dossier_windows": "AppData/Local/Studio/Saved/SaveGames"}, x

    # la meme regle sur les deux systemes, par rootoverrides (useinstead, addpath, pathtransforms)
    x = v({"quota": "1", "savefiles": {"1": {"root": "WinAppDataLocalLow", "path": "Editeur/Jeu/saves", "pattern": "*.bin"}},
           "rootoverrides": {"0": {"root": "WinAppDataLocalLow", "os": "MacOS", "oscompare": "=", "useinstead": "MacAppSupport",
                                   "pathtransforms": {"0": {"find": "Editeur/Jeu/saves", "replace": "Editeur/Jeu/saves"}}},
                             "1": {"root": "WinAppDataLocalLow", "os": "linux", "oscompare": "=", "useinstead": "LinuxXdgConfigHome",
                                   "addpath": "unity3d"}}})
    assert x["synchro"] == "steam-lien" and x["partage"] == "multiplateforme", x
    assert x["liens"] == "AppData/LocalLow/Editeur/Jeu/saves => Library/Application Support/Editeur/Jeu/saves", x
    assert x["racine_macos"] == "MacAppSupport/Editeur/Jeu/saves" and "motifs_macos" not in x and "sans_lien" not in x, x
    x = v({"quota": "1", "savefiles": {"0": {"root": "WinSavedGames", "path": "Jeu\\Saves", "pattern": "*"}},
           "rootoverrides": {"0": {"root": "WinSavedGames", "os": "macos", "oscompare": "=", "useinstead": "MacHome",
                                   "addpath": "Library/Preferences"}}})
    assert x["liens"] == "Saved Games/Jeu/Saves => Library/Preferences/Jeu/Saves", x

    # une regle par systeme, memes motifs : lien, mais Steam garde des fichiers distincts par systeme
    par_systeme = {"quota": "1", "savefiles": {
        "0": {"root": "WinAppDataLocalLow", "path": "Dev/Jeu", "pattern": "*.jeu", "platforms": {"1": "Windows"}},
        "1": {"root": "LinuxXdgConfigHome", "path": "unity3d/Dev/Jeu", "pattern": "*.jeu", "platforms": {"1": "Linux"}},
        "2": {"root": "MacAppSupport", "path": "unity.Dev.Jeu", "pattern": "*.jeu", "platforms": {"1": "MacOS"}}}}
    x = v(par_systeme)
    assert x["synchro"] == "steam-lien" and x["partage"] == "par-plateforme", x
    assert x["liens"] == "AppData/LocalLow/Dev/Jeu => Library/Application Support/unity.Dev.Jeu", x
    # ... motifs differents = formats differents : pas de lien
    par_systeme["savefiles"]["2"]["pattern"] = "*.plist"
    x = v(par_systeme)
    assert x["synchro"] == "copie" and x["sans_lien"] == "motifs differents" and "liens" not in x, x
    assert x["motifs"] == "*.jeu" and x["motifs_macos"] == "*.plist", x

    # jamais vers le dossier du jeu (le client le cherche dans SA bibliotheque), ni une racine entiere
    x = v({"quota": "1", "savefiles": {"0": {"root": "gameinstall", "path": "save", "pattern": "*", "recursive": "1"}}})
    assert x["synchro"] == "copie" and x["sans_lien"] == "fichiers dans le dossier du jeu", x
    assert x["dossier_windows"] == "jeu:save" and x["racine_macos"] == "gameinstall/save", x
    # ... et on ne deplace jamais un dossier du jeu Windows, meme vers un vrai dossier macOS
    x = v({"quota": "1", "savefiles": {"0": {"root": "gameinstall", "path": "Binaries/Win32", "pattern": "*.sav"}},
           "rootoverrides": {"0": {"root": "gameinstall", "os": "MacOS", "oscompare": "=", "useinstead": "MacAppSupport",
                                   "pathtransforms": {"0": {"find": "Binaries/Win32", "replace": "com.studio.jeu/SaveDir"}}}}})
    assert x["synchro"] == "copie" and x["sans_lien"] == "fichiers dans le dossier du jeu" and "liens" not in x, x
    # l'inverse (racine du jeu redirigee vers AppData sous Windows) se lie
    x = v({"quota": "1", "savefiles": {"1": {"root": "gameinstall", "path": "", "pattern": "*", "recursive": "1"}},
           "rootoverrides": {"0": {"root": "gameinstall", "os": "Windows", "oscompare": "=", "useinstead": "WinAppDataLocalLow",
                                   "pathtransforms": {"0": {"find": "", "replace": "Studio/Jeu/"}}},
                             "1": {"root": "gameinstall", "os": "MacOS", "oscompare": "=", "useinstead": "MacAppSupport",
                                   "pathtransforms": {"0": {"find": "", "replace": "Studio/Jeu/"}}}}})
    assert x["liens"] == "AppData/LocalLow/Studio/Jeu => Library/Application Support/Studio/Jeu", x
    x = v({"quota": "1", "savefiles": {"0": {"root": "WinMyDocuments", "path": "./", "pattern": "*.sav"}},
           "rootoverrides": {"0": {"root": "WinMyDocuments", "os": "MacOS", "oscompare": "=", "useinstead": "MacDocuments"}}})
    assert x["synchro"] == "copie" and x["sans_lien"] == "racine entiere" and "dossier_windows" not in x, x
    # une regle Windows que rien ne reprend sur macOS : tout ou rien, pas de lien partiel
    x = v({"quota": "1", "savefiles": {"0": {"root": "WinAppDataRoaming", "path": "Vieux", "pattern": "*", "platforms": {"1": "Windows"}},
                                       "1": {"root": "WinAppDataRoaming", "path": "Studio/Jeu", "pattern": "*"}},
           "rootoverrides": {"0": {"root": "WinAppDataRoaming", "os": "MacOS", "oscompare": "=", "useinstead": "MacAppSupport"}}})
    assert x["synchro"] == "copie" and x["sans_lien"] == "regle Windows sans equivalent macOS", x
    # un chemin qui remonte est ignore ; une racine inconnue aussi
    x = v({"quota": "1", "savefiles": {"0": {"root": "WinAppDataRoaming", "path": "../../x", "pattern": "*"},
                                       "1": {"root": "RacineInconnue", "path": "x", "pattern": "*"}}})
    assert x == {"methode": "auto", "synchro": "copie"}, x

    # le format texte de Valve, et le decoupage de la sortie de SteamCMD
    assert m.vdf_lire('"a"\n{\n\t"b"\t\t"c \\"d\\""\n\t"e"\n\t{\n\t}\n}\n') == {"a": {"b": 'c "d"', "e": {}}}
    sortie = ("Steam>\r\nAppID : 11, change number : 5/5, last change : x\r\n\"11\"\r\n{\r\n\t\"common\"\r\n\t{\r\n"
              "\t\t\"name\"\t\t\"Onze\"\r\n\t}\r\n}\r\nNo app info for AppID 12 found, requesting...\r\n")
    assert m.steam_appinfo_decouper(sortie) == {"11": {"common": {"name": "Onze"}}}

    # un faux SteamCMD : le jeu 12 ne sort qu'au second passage, le 13 n'est pas public
    faux = os.path.join(tmp, "steamcmd.sh")
    with open(faux, "w", encoding="utf-8") as f:
        f.write("""#!/bin/sh
n=$(cat "$HOME/passes" 2>/dev/null || echo 0); n=$((n + 1)); echo $n >"$HOME/passes"
echo "$@" >>"$HOME/appels"
bloc() { printf 'AppID : %s, change number : 1/1, last change : x\\n"%s"\\n{\\n%s}\\n' "$1" "$1" "$2"; }
for a in "$@"; do case $a in
   11) bloc 11 '\t"common"\n\t{\n\t\t"name"\t\t"Onze"\n\t\t"oslist"\t\t"windows,macos"\n\t}\n\t"ufs"\n\t{\n\t\t"quota"\t\t"1000"\n\t}\n' ;;
   12) [ $n -ge 2 ] && bloc 12 '\t"common"\n\t{\n\t\t"name"\t\t"Douze"\n\t}\n' || echo "No app info for AppID 12 found, requesting..." ;;
   13) bloc 13 '\t"extended"\n\t{\n\t}\n' ;;
esac; done
""")
    os.chmod(faux, 0o755)
    cidre_dir = os.path.join(tmp, "cidre")
    ancien = os.environ.get("CIDRE_DIR")
    os.environ["CIDRE_DIR"] = cidre_dir
    try:
        toile = m.Toile(os.path.join(tmp, "cache-steam"))
        assert m.steam_appinfo_charger(toile, ["11", "12", "13", "local-x"], faux) == 3
        foyer = os.path.join(cidre_dir, "steamcmd-anonyme")  # son dossier a lui, jamais celui du client
        appels = open(os.path.join(foyer, "appels"), encoding="utf-8").read().splitlines()
        assert len(appels) == 2 and appels[0].startswith("+login anonymous ") and appels[0].endswith(" +quit"), appels
        assert "+app_info_print 11" in appels[0] and "+app_info_print 11" not in appels[1] and "+app_info_print 12" in appels[1]
        assert m._steam_appinfo(toile, "11")["corps"] == {"ufs": {"quota": "1000"}, "nom": "Onze", "oslist": "windows,macos"}
        assert m._steam_appinfo(toile, "12")["statut"] == 200 and m._steam_appinfo(toile, "13")["statut"] == 403
        assert m.steam_appinfo_charger(toile, ["11", "12", "13"], faux) == 0 and len(open(os.path.join(foyer, "appels")).readlines()) == 2
        # dans la fiche : le jeu public oui, celui que Steam ne montre pas sans compte non
        fiche = m.Fiche({"jeu": {"appid": 11}})
        assert m.importer_steam_cloud(fiche, "11", toile)["synchro"] == "steam-api"
        assert fiche.doc["compat"]["steam_cloud"] == {"methode": "api", "synchro": "steam-api", "source": "steam",
                                                      "date": m.aujourdhui()}, fiche.doc
        fiche = m.Fiche({"jeu": {"appid": 13}})
        assert m.importer_steam_cloud(fiche, "13", toile) is None and "compat" not in fiche.doc
        # hors reseau : SteamCMD n'est pas lance
        hors = m.Toile(os.path.join(tmp, "cache-vide"), sans_reseau=True)
        assert m.steam_appinfo_charger(hors, ["11"], faux) == 0 and len(open(os.path.join(foyer, "appels")).readlines()) == 2
    finally:
        if ancien is None:
            del os.environ["CIDRE_DIR"]
        else:
            os.environ["CIDRE_DIR"] = ancien


def main():
    tmp = tempfile.mkdtemp(prefix="test-importer-")
    try:
        profils = os.path.join(tmp, "profils")
        os.makedirs(profils)
        fiche = os.path.join(profils, f"{APPID}.toml")
        shutil.copy(os.path.join(FIXTURES, "fiche-avant.toml"), fiche)
        avant = tomllib.load(open(fiche, "rb"))

        rapport = lancer(profils, os.path.join(tmp, "rapport.json"))
        d = tomllib.load(open(fiche, "rb"))
        texte = open(fiche, encoding="utf-8").read()

        # 1. rien de protege n'a bouge
        assert d["jeu"]["moteur"] == "hashlink", d["jeu"]
        assert d["jeu"]["anticheat"] == "none", d["jeu"]
        assert d["jeu"]["exe"] == "JeuFictif.exe"
        assert {k: v for k, v in d["cidre"].items() if k in avant["cidre"]} == avant["cidre"], d["cidre"]
        assert {k: v for k, v in d["compat"].items() if not isinstance(v, dict)} == avant["compat"], d["compat"]
        assert "moteur" not in d["jeu"].get("sources", {}) and "anticheat" not in d["jeu"].get("sources", {})
        # ... et les desaccords sont rapportes
        champs = {(c["champ"], str(c["import"])) for c in rapport["contradictions"]}
        assert ("jeu.moteur", "unity") in champs, champs
        assert ("jeu.anticheat", "eac") in champs, champs
        assert rapport["erreurs"] == []

        # 2. les champs importes, avec source et date
        assert d["jeu"]["bits"] == 64 and d["jeu"]["bits_32_aussi"] is True
        assert d["jeu"]["api_disponibles"] == "d3d11 d3d12" and "api" not in d["jeu"], d["jeu"]
        assert d["jeu"]["moteur_nom"] == "Unity"
        # ... dont l'inventaire Steam Cloud (source steam, date de la lecture)
        sc = d["compat"]["steam_cloud"]
        assert sc == {"methode": "auto", "synchro": "steam-lien", "partage": "multiplateforme",
                      "racine_windows": "WinAppDataLocalLow/Studio Fictif/Jeu Fictif/saves/{64BitSteamID}",
                      "motifs": "*.sav (recursif)", "dossier_windows": "AppData/LocalLow/Studio Fictif/Jeu Fictif/saves",
                      "racine_macos": "MacAppSupport/com.studiofictif.jeufictif/saves/{64BitSteamID}",
                      "liens": "AppData/LocalLow/Studio Fictif/Jeu Fictif/saves/{64BitSteamID} => "
                               "Library/Application Support/com.studiofictif.jeufictif/saves/{64BitSteamID}",
                      "source": "steam", "date": DATE}, sc
        assert rapport["steam_cloud"] == {"steam-lien": 1}, rapport
        assert d["jeu"]["drm"] == "denuvo anti-tamper ; steam"
        assert d["jeu"]["plateformes_steam"] == "windows"
        assert d["jeu"]["sources"]["bits"] == f"pcgamingwiki {DATE}", d["jeu"]["sources"]
        assert d["jeu"]["sources"]["plateformes_steam"] == f"steam {DATE}"
        p = d["compat"]["protondb"]
        assert p["palier"] == "gold" and p["score"] == 61 and p["rapports"] == 42
        assert p["options_lancement_1"] == "-dx11 %command% (x5)"
        assert p["anticheat_signale"] == "easyAntiCheat:6" and p["lanceur_secondaire"] == "non:7 oui:1"
        assert p["source"] == "protondb" and p["date"] == DATE
        w = d["compat"]["pcgamingwiki"]
        assert w["fichiers_reglages"] == "AppData/Local/StudioFictif/JeuFictif/settings.cfg", w
        assert w["sauvegardes"] == "jeu:save/*.sav ; registre:HKEY_CURRENT_USER/Software/StudioFictif", w
        assert w["correspondance"] == "appid" and w["url"].endswith("/wiki/Jeu_Fictif")
        a = d["compat"]["applegamingwiki"]
        assert a["crossover"] == "jouable" and a["wine"] == "parfait" and a["parallels"] == "ko"
        assert a["methodes"] == "crossover gptk whisky" and a["dernier_temoignage"] == "2025-05-09", a
        assert "natif" not in a  # na = pas d'information

        # 2 bis. la recette CrossOver : valeurs techniques de l'entree en vigueur (24), pour Mac et Steam
        x = d["compat"]["crossover"]
        assert set(x) == {"recette", "correspondance", "confiance", "recette_date", "crossover_version", "bouteille",
                          "dll_overrides", "dll_overrides_par_exe", "dependances", "dependances_non_traduites",
                          "graphismes", "environnement", "registre", "source", "date", "url"}, sorted(x)
        assert x["recette"] == "com.codeweavers.c4.90001" and x["crossover_version"] == "24", x
        assert x["recette_date"] == "2024-05-02" and x["bouteille"] == "win7_64", x
        assert x["correspondance"] == "steamid+titre" and x["confiance"] == "haute", x
        assert x["dll_overrides"] == "xaudio2_7=n ; x3daudio1_7=n ; msvcp140=n,b ; mfplay= ; d3d11=b", x
        assert x["dll_overrides_par_exe"] == "JeuFictif.exe:dinput8=n,b", x
        assert x["dependances"] == "vcrun2015 dotnet462 directx_jun2010", x
        assert x["dependances_non_traduites"] == "com.codeweavers.c4.90013", x
        assert x["environnement"] == "WINED3DMETAL=1 ; VKD3D_CONFIG=heap_multi_bind" and x["graphismes"] == "d3dmetal", x
        assert x["registre"] == "Direct3D:renderer=vulkan", x
        assert x["source"] == "crossover" and x["date"] == DATE, x
        assert x["url"] == "https://www.codeweavers.com/compatibility/browse/name/?app_id=90001", x
        # ... fondue dans [cidre] : `native` seul devient n,b, d3d11 reste a Cidre, la provenance est par cle
        assert d["cidre"]["dll_overrides"] == "xaudio2_7,x3daudio1_7,msvcp140=n,b;mfplay=", d["cidre"]
        assert d["cidre"]["sources"] == {"dll_overrides": f"crossover {DATE}",
                                         "windows_version": f"crossover {DATE}"}, d["cidre"]
        # ... sans ecraser ce qui y etait a la main : le desaccord est rapporte
        assert d["cidre"]["dependances"] == "vcrun2019"
        assert ("cidre.dependances", "vcrun2015 dotnet462 directx_jun2010") in champs, champs
        # ... et windows_version aussi : le gabarit win7_64 de la recette est un choix (CrossOver 24)
        assert d["cidre"]["windows_version"] == "win7", d["cidre"]
        b = rapport["crossover"]
        assert b["recettes"] == 1 and b["cidre"] == {"dll_overrides": 1, "windows_version": 1}, b
        assert b["windows_version_retenues"] == [], b
        assert texte.index("[cidre]") < texte.index("[cidre.sources]") < texte.index("[[reglages_jeu]]")

        # 3. pas de texte editorial, ni rien d'une recette perimee, d'une autre plateforme ou d'un nom douteux
        for interdit in ("Texte editorial", "Autre texte", "Refdevice", "{{", "Prose CrossOver", "Erfundenes", "medal",
                         "perimee", "linuxseulement", "pouruneautreappli", "piege", "inconnue", "dotnet35sp1", "Installe"):
            assert interdit not in texte, interdit
        # tout ce qui etait ecrit a la main est intact, commentaires compris
        assert texte.startswith("# Jeu Fictif : fiche de test (fixture).")
        avant_texte = open(os.path.join(FIXTURES, "fiche-avant.toml"), encoding="utf-8").read()
        for bloc in ("moteur = \"hashlink\"   # commentaire en fin de ligne, a garder",
                     "# commentaire interne : l'import ne doit pas le perdre",
                     avant_texte[avant_texte.index("[[reglages_jeu]]"):avant_texte.index("[compat]")],
                     avant_texte[avant_texte.index("[compat]"):]):
            assert bloc in texte, bloc
        assert d["reglages_jeu"] == avant["reglages_jeu"] and d["rapports"] == avant["rapports"]
        # [jeu.sources] est place juste apres [jeu], les blocs d'import a la fin
        assert texte.index("[jeu.sources]") < texte.index("[cidre]")
        assert texte.index("[[rapports]]") < texte.index("[compat.protondb]")

        # 4. idempotent
        rapport2 = lancer(profils, os.path.join(tmp, "rapport2.json"))
        assert rapport2["fiches_modifiees"] == 0, rapport2
        assert open(fiche, encoding="utf-8").read() == texte

        # 4 bis. windows_version retire sur demande (il sort alors dans le rapport), puis repose : memes valeurs
        # (la cle reposee va a la fin de sa section : le texte n'est plus celui du premier passage)
        r3 = lancer(profils, os.path.join(tmp, "rapport-wv.json"), "--sans-crossover-windows-version")
        w = tomllib.load(open(fiche, "rb"))
        assert "windows_version" not in w["cidre"] and "windows_version" not in w["cidre"]["sources"], w["cidre"]
        assert r3["crossover"]["cidre"] == {"dll_overrides": 1}, r3["crossover"]
        assert r3["crossover"]["windows_version_retenues"] == [{"appid": APPID, "nom": "Jeu Fictif", "windows_version": "win7",
                                                                "recette": "com.codeweavers.c4.90001"}], r3["crossover"]
        lancer(profils, os.path.join(tmp, "rapport-wv2.json"), "--crossover-windows-version")  # l'ancien nom, encore accepte
        assert tomllib.load(open(fiche, "rb")) == tomllib.loads(texte)
        assert lancer(profils, os.path.join(tmp, "rapport-wv3.json"))["fiches_modifiees"] == 0

        # 5. fiche neuve (sans fiche de depart) : [compat] non-teste, date du jour
        profils2 = os.path.join(tmp, "profils2")
        os.makedirs(profils2)
        lancer(profils2, os.path.join(tmp, "rapport3.json"))
        n = tomllib.load(open(os.path.join(profils2, f"{APPID}.toml"), "rb"))
        assert n["compat"]["etat"] == "non-teste" and n["compat"]["date"] == DATE
        assert n["jeu"]["moteur"] == "unity" and n["jeu"]["anticheat"] == "eac"
        assert n["jeu"]["sources"]["anticheat"] == f"pcgamingwiki {DATE}"
        assert n["cidre"] == {"windows_version": "win7", "dll_overrides": "xaudio2_7,x3daudio1_7,msvcp140=n,b;mfplay=",
                              "dependances": "vcrun2015 dotnet462 directx_jun2010",
                              "sources": {"windows_version": f"crossover {DATE}", "dll_overrides": f"crossover {DATE}",
                                          "dependances": f"crossover {DATE}"}}, n["cidre"]
        neuve = open(os.path.join(profils2, f"{APPID}.toml"), encoding="utf-8").read()
        assert neuve.index("[jeu.sources]") < neuve.index("[cidre]") < neuve.index("[compat]") < neuve.index("[compat.crossover]")
        # une seule source demandee : les autres blocs ne sont pas ecrits
        profils3 = os.path.join(tmp, "profils3")
        os.makedirs(profils3)
        lancer(profils3, os.path.join(tmp, "rapport4.json"), "--sources", "crossover")
        s3 = tomllib.load(open(os.path.join(profils3, f"{APPID}.toml"), "rb"))
        assert set(s3["compat"]) == {"etat", "date", "crossover"} and set(s3["jeu"]) == {"appid"}, s3

        # 6. le lecteur shell relit la fiche (sous-ensemble TOML du README)
        lecteur = os.path.join(RACINE, "tests", "fiche_profil.sh")
        if os.path.exists(lecteur):
            r = subprocess.run(["sh", lecteur, "toml", fiche], capture_output=True, text=True)
            assert r.returncode == 0, r.stderr
            lignes = {tuple(l.split("\t")) for l in r.stdout.splitlines()}
            assert ("jeu", "moteur", "s", "hashlink") in lignes
            assert ("jeu", "bits", "n", "64") in lignes
            assert ("compat.protondb", "palier", "s", "gold") in lignes
            assert ("jeu.sources", "bits", "s", f"pcgamingwiki {DATE}") in lignes
            assert ("cidre", "dll_overrides", "s", "xaudio2_7,x3daudio1_7,msvcp140=n,b;mfplay=") in lignes
            assert ("cidre.sources", "dll_overrides", "s", f"crossover {DATE}") in lignes
            # les options de lancement rendues au lanceur : la provenance n'en fait pas partie
            r = subprocess.run(["sh", lecteur, "plat", APPID], capture_output=True, text=True,
                               env={**os.environ, "CIDRE_PROFILS_BASE": profils})
            assert r.returncode == 0, r.stderr
            assert 'dll_overrides = "xaudio2_7,x3daudio1_7,msvcp140=n,b;mfplay="' in r.stdout, r.stdout
            assert 'windows_version = "win7"' in r.stdout, r.stdout
            assert "crossover" not in r.stdout and "sources" not in r.stdout, r.stdout
        else:
            print("fiche_profil.sh absent : lecture shell non verifiee", file=sys.stderr)
        unitaires_crossover(tmp)
        unitaires_steam_cloud(tmp)
        unitaires_catalogue(tmp)
        print("test_importer_profils : OK")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
