#!/usr/bin/env python3
"""Test de tests/outils/rapports_vers_fiches.py sur des incidents fabriques.

    python3 -I tests/outils/test_rapports_vers_fiches.py

Les fixtures (tests/outils/fixtures/rapports_vers_fiches/) : incidents.json a
la forme de `gh issue list --json`, les corps sont ceux que Verger ecrit
(GameReport.swift) et ce qu'un utilisateur peut en faire ; deux fiches. On
verifie :
  - le bloc [[rapports]] rendu (champs, notes sur une ligne, `incident`) ;
  - que sans --appliquer rien n'est ecrit, et que --proposer-compat n'ecrit jamais ;
  - que les corps mal formes sont refuses avec leur raison, un titre piege aussi ;
  - que --appliquer ajoute le bloc sans toucher au reste ([compat], commentaires),
    cree la fiche minimale qui manque, et ne rajoute pas un incident deja integre ;
  - que tests/fiche_profil.sh relit les fiches produites ;
  - la regle de --proposer-compat, cas par cas.
"""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE = os.path.abspath(os.path.join(ICI, "..", ".."))
OUTIL = os.path.join(ICI, "rapports_vers_fiches.py")
FIXTURES = os.path.join(ICI, "fixtures", "rapports_vers_fiches")
DATE = "2026-10-13"
URL = "https://github.com/gtranche/cidre/issues/"


def lancer(profils, *options):
    cmd = [sys.executable, "-I", OUTIL, "--profils", profils, "--defauts", os.path.join(FIXTURES, "defauts.toml"),
           "--date", DATE, *options, os.path.join(FIXTURES, "incidents.json")]
    r = subprocess.run(cmd, capture_output=True, text=True)
    assert r.returncode == 0, f"rc={r.returncode}\n{r.stderr}"
    return r.stdout


def etat_du_dossier(profils):
    return {n: open(os.path.join(profils, n), encoding="utf-8").read() for n in sorted(os.listdir(profils))}


def section(sortie, numero):
    """Ce que l'outil dit d'un incident : de son titre « == #N » au suivant."""
    debut = sortie.index(f"== #{numero} ")
    fin = sortie.find("\n== ", debut + 1)
    return sortie[debut:fin if fin > 0 else len(sortie)]


def main():
    tmp = tempfile.mkdtemp(prefix="test-rapports-")
    try:
        profils = os.path.join(tmp, "profils")
        shutil.copytree(os.path.join(FIXTURES, "profils"), profils)
        depart = etat_du_dossier(profils)
        f1, f2, f3 = (os.path.join(profils, f"99000000{i}.toml") for i in (1, 2, 3))

        # 1. sans option : les blocs, rien d'ecrit
        sortie = lancer(profils)
        assert etat_du_dossier(profils) == depart, "sans --appliquer rien ne doit etre ecrit"
        # le rapport tel que Verger l'ecrit (corps en CRLF) : notes ramenees a une ligne,
        # l'option qui differe de la fiche, l'adresse de l'incident ; le diagnostic n'est pas lu
        assert "\n".join([
            "[[rapports]]",
            'date = "2026-10-11"',
            'machine = "M1 Max 32 Go"',
            'cidre_version = "1.5.7"',
            'etat = "or"',
            "fps_menu = 120",
            "fps_jeu = 45",
            'notes = "Il dit \\"ça marche\\" ; chemin C:\\\\Jeu / Deuxième ligne tab. Lance avec vsync=false (differe de la fiche)."',
            f'incident = "{URL}9001"',
        ]) in section(sortie, 9001), section(sortie, 9001)
        assert "ligne-piege" not in sortie and "0.3.12" not in sortie, "le diagnostic ne doit pas etre recopie"
        # Verger en anglais (« Effective profile ») : meme lecture ; rien ne differe de la fiche -> pas de notes
        s = section(sortie, 9002)
        assert 'machine = "M4 16 Go"' in s and "fps_jeu = 60" in s and "notes" not in s and "fps_menu" not in s, s
        assert "Lance avec tso=false, d3d11=dxmt (differe de la fiche)." in section(sortie, 9003)
        # retouche par l'utilisateur : lu, et chaque ecart est dit au mainteneur
        s = section(sortie, 9004)
        for attendu in ('etat = "argent"', "fps_jeu = 40\n", 'date = "2026-10-12"', 'cidre_version = "1.5.7"',
                        'machine = "M2 Pro 16 Go"', f'incident = "{URL}9004"',
                        "etat « Silver » lu « argent »", "fps_jeu « 40-45 fps » lu 40", "date absente",
                        "cle inconnue ignoree : humeur", "`incident` ecrit dans le corps : ignore", "un lien dans les notes"):
            assert attendu in s, (attendu, s)
        assert "evil.example" not in sortie
        # caracteres de controle et marque d'ordre bidirectionnel retires ; fps 0 = non mesure
        s = section(sortie, 9005)
        assert 'notes = "Écran noir au lancement etrevni"' in s and "fps_menu" not in s and 'cidre_version = "dev"' in s, s
        assert "n'existe pas (creee, minimale, par --appliquer)" in s
        # les mal formes : refuses, avec la raison
        assert "ILLISIBLE : aucun bloc [[rapports]]" in section(sortie, 9006)
        assert "ILLISIBLE : etat inconnu : « super »" in section(sortie, 9007)
        assert "ILLISIBLE : identifiant de jeu refuse" in section(sortie, 9008) and "[[rapports]]" not in section(sortie, 9008)
        assert "pas de fiche creee d'office" in section(sortie, 9009)
        assert "deja integre (profils/990000001.toml)" in section(sortie, 9010)
        # titre refait : la balise du corps dit le jeu ; meme auteur, meme jeu qu'un autre incident
        s = section(sortie, 9011)
        assert f'incident = "{URL}9011"' in s and "990000002.toml" in s and "meme auteur et meme jeu que #9003" in s, s
        assert "11 incident(s) : 0 integre(s), 7 a integrer, 1 deja integre(s), 3 illisible(s)" in sortie, sortie[-400:]

        # 2. --proposer-compat : une proposition, un desaccord avec nos tests ; rien d'ecrit
        sortie = lancer(profils, "--proposer-compat")
        assert etat_du_dossier(profils) == depart, "--proposer-compat ne doit rien ecrire"
        prop = sortie[sortie.index("== [compat]"):]
        assert "-- 990000002 Autre Jeu" in prop and "2 machines donnent « argent » (M1 Max 32 Go ; M2 Pro 16 Go)" in prop, prop
        assert '[compat]\netat = "argent"\nsource = "utilisateur"\ndate = "2026-10-13"\nmachine = "M1 Max 32 Go"' in prop, prop
        s = prop[prop.index("-- 990000001"):prop.index("-- 990000002")]
        assert "2 machines donnent « or »" in s and "nos tests priment" in s and "[compat]\n" not in s, s
        assert "990000003" not in prop  # une seule machine : rien a dire

        # 3. --appliquer --incident N : celui-la seul, a sa place, le reste intact
        sortie = lancer(profils, "--appliquer", "--incident", "9001")
        apres = etat_du_dossier(profils)
        assert set(apres) == set(depart) and apres["990000002.toml"] == depart["990000002.toml"]
        texte = apres["990000001.toml"]
        bloc = texte[texte.index('[[rapports]]\ndate = "2026-10-11"'):texte.index("# commentaire de la section d'apres")]
        assert texte.replace("\n" + bloc.rstrip("\n") + "\n", "", 1) == depart["990000001.toml"], "seul le bloc doit etre ajoute"
        assert texte.index(f"{URL}9010") < texte.index(f"{URL}9001") < texte.index("# commentaire de la section d'apres") < texte.index("[compat.protondb]")
        d, avant = tomllib.loads(texte), tomllib.loads(depart["990000001.toml"])
        assert d["compat"] == avant["compat"] and d["cidre"] == avant["cidre"] and d["jeu"] == avant["jeu"]
        assert d["rapports"][:1] == avant["rapports"] and len(d["rapports"]) == 2
        assert d["rapports"][1]["notes"].startswith('Il dit "ça marche" ; chemin C:\\Jeu / Deuxième ligne tab.')
        assert "1 integre(s), 0 a integrer" in sortie, sortie[-300:]

        # 4. --appliquer : tout ce qui est lisible ; fiche minimale creee ; [compat] jamais touche
        sortie = lancer(profils, "--appliquer")
        assert "5 integre(s), 1 a integrer, 2 deja integre(s), 3 illisible(s)" in sortie, sortie[-400:]
        assert sorted(os.listdir(profils)) == ["990000001.toml", "990000002.toml", "990000003.toml"], os.listdir(profils)
        d1, d2, d3 = (tomllib.load(open(f, "rb")) for f in (f1, f2, f3))
        assert d1["compat"] == avant["compat"] and [r["incident"][len(URL):] for r in d1["rapports"]] == ["9010", "9001", "9002"]
        avant2 = tomllib.loads(depart["990000002.toml"])
        assert d2["compat"] == avant2["compat"] and d2["jeu"] == avant2["jeu"]
        assert [r["incident"][len(URL):] for r in d2["rapports"]] == ["9003", "9004", "9011"]
        t2 = open(f2, encoding="utf-8").read()
        assert t2.index('date = "2026-10-11"\n\n[[rapports]]') < t2.index("[compat.protondb]"), "apres [compat], avant ses sous-tables"
        assert d3["jeu"] == {"appid": 990000003, "nom": "Jeu Neuf: L'Édition « Dorée »"}, d3["jeu"]
        assert d3["compat"] == {"etat": "non-teste", "date": DATE} and len(d3["rapports"]) == 1 and d3["rapports"][0]["etat"] == "ko"
        assert "fiche creee" in section(sortie, 9005) and "non applique" in section(sortie, 9009)
        for texte in etat_du_dossier(profils).values():
            assert "evil.example" not in texte and "ligne-piege" not in texte
            assert not any(ord(c) < 32 and c != "\n" for c in texte) and "\u202e" not in texte

        # 5. idempotent : un second passage ne change rien
        fige = etat_du_dossier(profils)
        sortie = lancer(profils, "--appliquer")
        assert etat_du_dossier(profils) == fige
        assert "0 integre(s), 1 a integrer, 7 deja integre(s), 3 illisible(s)" in sortie, sortie[-400:]

        # 6. le lecteur shell relit les fiches (sous-ensemble TOML du README)
        lecteur = os.path.join(RACINE, "tests", "fiche_profil.sh")
        if os.path.exists(lecteur):
            for f, n, numero in ((f1, 3, 9002), (f2, 3, 9011), (f3, 1, 9005)):
                r = subprocess.run(["sh", lecteur, "toml", f], capture_output=True, text=True)
                assert r.returncode == 0, r.stderr
                lignes = {tuple(l.split("\t")) for l in r.stdout.splitlines()}
                assert (f"rapports.{n}", "incident", "s", f"{URL}{numero}") in lignes, (f, sorted(lignes)[-8:])
            assert ("rapports.2", "notes", "s", d1["rapports"][1]["notes"]) in {
                tuple(l.split("\t")) for l in subprocess.run(["sh", lecteur, "toml", f1], capture_output=True, text=True).stdout.splitlines()}
        else:
            print("fiche_profil.sh absent : lecture shell non verifiee", file=sys.stderr)

        # 7. la regle de --proposer-compat, cas par cas
        sys.dont_write_bytecode = True  # pas de __pycache__ dans le depot
        spec = importlib.util.spec_from_file_location("rapports_vers_fiches", OUTIL)
        outil = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(outil)

        def r(machine, etat, date="2026-10-10", **k):
            return dict({"machine": machine, "etat": etat, "date": date}, **k)
        non_teste = {"compat": {"etat": "non-teste", "date": "2026-10-11"}}
        # une seule machine, meme deux fois : rien
        assert outil.proposer_compat(non_teste, [r("M1 8 Go", "or"), r("m1  8 go", "or")])[::2] == (False, None)
        # deux machines d'accord
        montrer, _, prop = outil.proposer_compat(non_teste, [
            r("M1 8 Go", "or", fps_jeu=50, incident=URL + "1"), r("M4 16 Go", "or", "2026-10-12", fps_jeu=70, cidre_version="1.5.7", incident=URL + "2")])
        assert montrer and prop == {"etat": "or", "source": "utilisateur", "date": "2026-10-12", "machine": "M4 16 Go",
                                    "cidre_version": "1.5.7", "fps_jeu": 70, "notes": prop["notes"]}, prop
        assert "#1 #2" in prop["notes"]
        # egalite entre deux etats : desaccord, pas de proposition
        montrer, constat, prop = outil.proposer_compat(non_teste, [r("A", "or"), r("B", "or"), r("C", "ko"), r("D", "ko")])
        assert montrer and prop is None and "desaccord" in constat
        # le rapport le plus recent d'une machine compte seul : A est passee de bronze a or
        _, _, prop = outil.proposer_compat(non_teste, [r("A", "bronze", "2026-10-01"), r("B", "bronze"), r("A", "or", "2026-10-12"), r("C", "or")])
        assert prop and prop["etat"] == "or"
        # un rapport sans machine ne compte pas
        assert outil.proposer_compat(non_teste, [r("A", "or"), r("", "or")])[2] is None
        # [compat] deja a cet etat : rien a montrer ; cidre-test ou ecrit a la main : jamais remplace
        assert outil.proposer_compat({"compat": {"etat": "or", "source": "utilisateur"}}, [r("A", "or"), r("B", "or")])[::2] == (False, None)
        for compat in ({"etat": "argent", "source": "cidre-test"}, {"etat": "argent"}):
            montrer, constat, prop = outil.proposer_compat({"compat": compat}, [r("A", "or"), r("B", "or")])
            assert montrer and prop is None and "a retester" in constat
        # un [compat] « utilisateur » se relit
        assert outil.proposer_compat({"compat": {"etat": "bronze", "source": "utilisateur"}}, [r("A", "or"), r("B", "or")])[2]["etat"] == "or"

        # 8. le corps minimal de Verger (date et verdict seuls), et un corps vide
        lu = outil.lire_rapport({"number": 7, "title": "Rapport de jeu : X (42)", "createdAt": "2026-01-03T00:00:00Z",
                                 "body": "```toml\n[[rapports]]\ndate = \"2026-01-02\"\netat = \"ko\"\n```\n"}, "gtranche/cidre")
        assert lu["erreurs"] == [] and lu["appid"] == "42" and lu["champs"] == {"date": "2026-01-02", "etat": "ko"} and lu["url"] == URL + "7"
        assert outil.lire_rapport({"number": 8, "title": "Rapport de jeu : X (42)", "body": None}, "gtranche/cidre")["erreurs"]
        # une adresse d'un autre depot n'est pas reprise comme `incident`
        lu = outil.lire_rapport({"number": 9, "title": "Rapport de jeu : X (42)", "url": "https://github.com/autre/depot/issues/9",
                                 "body": "etat = or\ndate = 2026-01-02"}, "gtranche/cidre")
        assert lu["url"] == URL + "9" and lu["champs"]["etat"] == "or" and lu["champs"]["date"] == "2026-01-02", lu
        print("test_rapports_vers_fiches : OK")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
