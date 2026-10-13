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
    provenance sans ecraser ce qui y est, crossover reste au dernier rang.
"""
import gzip
import importlib.util
import json
import os
import shutil
import subprocess
import sys
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
        assert d["cidre"]["sources"] == {"dll_overrides": f"crossover {DATE}"}, d["cidre"]
        # ... sans ecraser ce qui y etait a la main : le desaccord est rapporte
        assert d["cidre"]["dependances"] == "vcrun2019"
        assert ("cidre.dependances", "vcrun2015 dotnet462 directx_jun2010") in champs, champs
        # ... et windows_version reste dans le rapport tant qu'on ne le demande pas
        assert "windows_version" not in d["cidre"]
        b = rapport["crossover"]
        assert b["recettes"] == 1 and b["cidre"] == {"dll_overrides": 1}, b
        assert b["windows_version_retenues"] == [{"appid": APPID, "nom": "Jeu Fictif", "windows_version": "win7",
                                                  "recette": "com.codeweavers.c4.90001"}], b
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

        # 4 bis. windows_version sur demande, puis retire quand on ne le demande plus : aller-retour exact
        r3 = lancer(profils, os.path.join(tmp, "rapport-wv.json"), "--crossover-windows-version")
        w = tomllib.load(open(fiche, "rb"))
        assert w["cidre"]["windows_version"] == "win7", w["cidre"]
        assert w["cidre"]["sources"]["windows_version"] == f"crossover {DATE}", w["cidre"]
        assert r3["crossover"]["cidre"] == {"dll_overrides": 1, "windows_version": 1}, r3["crossover"]
        lancer(profils, os.path.join(tmp, "rapport-wv2.json"))
        assert open(fiche, encoding="utf-8").read() == texte

        # 5. fiche neuve (sans fiche de depart) : [compat] non-teste, date du jour
        profils2 = os.path.join(tmp, "profils2")
        os.makedirs(profils2)
        lancer(profils2, os.path.join(tmp, "rapport3.json"))
        n = tomllib.load(open(os.path.join(profils2, f"{APPID}.toml"), "rb"))
        assert n["compat"]["etat"] == "non-teste" and n["compat"]["date"] == DATE
        assert n["jeu"]["moteur"] == "unity" and n["jeu"]["anticheat"] == "eac"
        assert n["jeu"]["sources"]["anticheat"] == f"pcgamingwiki {DATE}"
        assert n["cidre"] == {"dll_overrides": "xaudio2_7,x3daudio1_7,msvcp140=n,b;mfplay=",
                              "dependances": "vcrun2015 dotnet462 directx_jun2010",
                              "sources": {"dll_overrides": f"crossover {DATE}", "dependances": f"crossover {DATE}"}}, n["cidre"]
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
            assert "crossover" not in r.stdout and "sources" not in r.stdout, r.stdout
        else:
            print("fiche_profil.sh absent : lecture shell non verifiee", file=sys.stderr)
        unitaires_crossover(tmp)
        print("test_importer_profils : OK")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
