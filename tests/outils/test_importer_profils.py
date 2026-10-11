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
  - que tests/fiche_profil.sh relit la fiche produite (sous-ensemble TOML).
"""
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


def lancer(profils, rapport):
    cmd = [sys.executable, "-I", OUTIL, "--sans-reseau", "--cache", os.path.join(FIXTURES, "cache"),
           "--profils", profils, "--bibliotheque", os.path.join(FIXTURES, "bibliotheque.json"),
           "--rapport", rapport, "--date", DATE, APPID]
    r = subprocess.run(cmd, capture_output=True, text=True)
    assert r.returncode == 0, f"rc={r.returncode}\n{r.stderr}"
    with open(rapport, "rb") as f:
        return json.load(f)


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
        assert d["cidre"] == avant["cidre"], d["cidre"]
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

        # 3. pas de texte editorial
        for interdit in ("Texte editorial", "Autre texte", "Refdevice", "{{"):
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

        # 5. fiche neuve (sans fiche de depart) : [compat] non-teste, date du jour
        profils2 = os.path.join(tmp, "profils2")
        os.makedirs(profils2)
        lancer(profils2, os.path.join(tmp, "rapport3.json"))
        n = tomllib.load(open(os.path.join(profils2, f"{APPID}.toml"), "rb"))
        assert n["compat"]["etat"] == "non-teste" and n["compat"]["date"] == DATE
        assert n["jeu"]["moteur"] == "unity" and n["jeu"]["anticheat"] == "eac"
        assert n["jeu"]["sources"]["anticheat"] == f"pcgamingwiki {DATE}"

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
        else:
            print("fiche_profil.sh absent : lecture shell non verifiee", file=sys.stderr)
        print("test_importer_profils : OK")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
