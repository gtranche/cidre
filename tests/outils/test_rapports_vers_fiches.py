#!/usr/bin/env python3
"""Test de tests/outils/rapports_vers_fiches.py sur des incidents fabriques.

    python3 -I tests/outils/test_rapports_vers_fiches.py

Les fixtures (tests/outils/fixtures/rapports_vers_fiches/) : incidents.json a
la forme de `gh issue list --json`, les corps sont ceux que Verger ecrit
(GameReport.swift) et ce qu'un utilisateur peut en faire ; deux fiches. Deux
formes de corps : sans formulaire (Verger <= 0.3.13, #9001 a #9011) et par le
formulaire d'incident .github/ISSUE_TEMPLATE/rapport-jeu.yml (« ### Rapport »
puis le champ, #9012 a #9015). On verifie :
  - le bloc [[rapports]] rendu (champs, notes sur une ligne, `incident`) ;
  - que sans --appliquer rien n'est ecrit, et que --proposer-compat n'ecrit jamais ;
  - que les corps mal formes sont refuses avec leur raison, un titre piege aussi ;
  - que --appliquer ajoute le bloc sans toucher au reste ([compat], commentaires),
    cree la fiche minimale qui manque, et ne rajoute pas un incident deja integre ;
  - que tests/fiche_profil.sh relit les fiches produites ;
  - la regle de --proposer-compat, cas par cas ;
  - que le modele du formulaire du depot, envoye tel quel, est refuse, et que
    rempli il se lit.
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
        # --- par le formulaire d'incident : le corps commence par « ### Rapport »
        # rempli par Verger, titre refait : la balise dit le jeu ; profil lu, diagnostic non
        s = section(sortie, 9012)
        assert "\n".join([
            "[[rapports]]",
            'date = "2026-10-13"',
            'machine = "M2 16 Go"',
            'cidre_version = "1.5.10"',
            'etat = "or"',
            "fps_menu = 110",
            "fps_jeu = 72",
            'notes = "Rien à redire. Lance avec tso=false (differe des reglages par defaut)."',
            f'incident = "{URL}9012"',
        ]) in s and "990000004.toml n'existe pas" in s and "attention" not in s, s
        # rempli a la main (corps en CRLF) : les commentaires du modele ne genent pas, fps laisse a 0 = non
        # mesure, le texte libre et ce qui suit « ### Diagnostic » ne sont pas lus
        s = section(sortie, 9013)
        for attendu in ('date = "2026-10-12"', 'machine = "M3 Pro 18 Go"', 'cidre_version = "1.5.10"', 'etat = "argent"',
                        "fps_jeu = 48\n", 'notes = "Le son grésille au menu."', f'incident = "{URL}9013"'):
            assert attendu in s, (attendu, s)
        assert "fps_menu" not in s and "attention" not in s and "merci pour Cidre" not in s, s
        # envoye tel quel : ni le titre ni le modele ne passent pour un rapport
        s = section(sortie, 9014)
        assert "ILLISIBLE : identifiant de jeu refuse : « APPID »" in s and "ILLISIBLE : etat absent" in s and "[[rapports]]" not in s, s
        # rapport colle sous le modele laisse en place : c'est le bloc qui donne un etat qui est lu ;
        # sans label, l'incident est quand meme lu, et son absence est dite
        s = section(sortie, 9015)
        assert 'date = "2026-10-14"' in s and 'etat = "or"' in s and "fps_jeu = 70\n" in s and f'incident = "{URL}9015"' in s, s
        assert "attention : sans le label rapport-jeu" in s and sortie.count("sans le label rapport-jeu") == 1, s
        assert "15 incident(s) : 0 integre(s), 10 a integrer, 1 deja integre(s), 4 illisible(s)" in sortie, sortie[-400:]

        # 2. --proposer-compat : une proposition, un desaccord avec nos tests ; rien d'ecrit
        sortie = lancer(profils, "--proposer-compat")
        assert etat_du_dossier(profils) == depart, "--proposer-compat ne doit rien ecrire"
        prop = sortie[sortie.index("== [compat]"):]
        assert "-- 990000002 Autre Jeu" in prop and "2 machines donnent « argent » (M1 Max 32 Go ; M2 Pro 16 Go)" in prop, prop
        assert '[compat]\netat = "argent"\nsource = "utilisateur"\ndate = "2026-10-13"\nmachine = "M1 Max 32 Go"' in prop, prop
        s = prop[prop.index("-- 990000001"):prop.index("-- 990000002")]
        assert "2 machines donnent « or »" in s and "nos tests priment" in s and "[compat]\n" not in s, s
        assert "990000003" not in prop  # une seule machine : rien a dire
        assert "990000004" not in prop  # deux machines, deux etats (la plus recente de « M2 16 Go » compte seule)

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
        assert "8 integre(s), 1 a integrer, 2 deja integre(s), 4 illisible(s)" in sortie, sortie[-400:]
        assert sorted(os.listdir(profils)) == ["990000001.toml", "990000002.toml", "990000003.toml", "990000004.toml"], os.listdir(profils)
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
        # les trois rapports arrives par le formulaire : une fiche creee par le premier, les autres a la suite
        f4 = os.path.join(profils, "990000004.toml")
        d4 = tomllib.load(open(f4, "rb"))
        assert d4["jeu"] == {"appid": 990000004, "nom": "990000004"} and d4["compat"] == {"etat": "non-teste", "date": DATE}, d4
        assert [(r["incident"][len(URL):], r["etat"], r["machine"]) for r in d4["rapports"]] == [
            ("9012", "or", "M2 16 Go"), ("9013", "argent", "M3 Pro 18 Go"), ("9015", "or", "M2 16 Go")], d4["rapports"]
        assert "fiche creee" in section(sortie, 9012) and "ajoute a" in section(sortie, 9013) and "ajoute a" in section(sortie, 9015)
        for texte in etat_du_dossier(profils).values():
            assert "evil.example" not in texte and "ligne-piege" not in texte
            assert not any(ord(c) < 32 and c != "\n" for c in texte) and "\u202e" not in texte

        # 5. idempotent : un second passage ne change rien
        fige = etat_du_dossier(profils)
        sortie = lancer(profils, "--appliquer")
        assert etat_du_dossier(profils) == fige
        assert "0 integre(s), 1 a integrer, 10 deja integre(s), 4 illisible(s)" in sortie, sortie[-400:]

        # 6. le lecteur shell relit les fiches (sous-ensemble TOML du README)
        lecteur = os.path.join(RACINE, "tests", "fiche_profil.sh")
        if os.path.exists(lecteur):
            for f, n, numero in ((f1, 3, 9002), (f2, 3, 9011), (f3, 1, 9005), (f4, 3, 9015)):
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

        # 9. le formulaire du depot : son champ a l'identifiant que Verger remplit, il pose le label que
        # l'outil cherche, et son modele, envoye tel quel, est refuse ; rempli, il se lit
        formulaire = os.path.join(RACINE, ".github", "ISSUE_TEMPLATE", "rapport-jeu.yml")
        yml = open(formulaire, encoding="utf-8").read()
        assert f'labels: ["{outil.LABEL}"]' in yml and "    id: rapport\n" in yml and "type: textarea" in yml, "formulaire : label ou champ"
        assert 'title: "Rapport de jeu : NOM DU JEU (APPID)"' in yml
        debut = yml.index("      value: |\n        ```toml")
        modele = "\n".join(l[8:] for l in yml[debut:yml.index("    validations:")].split("\n")[1:]).strip("\n")
        assert modele.startswith("```toml\n[[rapports]]\n") and modele.endswith("```") and 'etat = ""' in modele, modele
        def par_le_formulaire(titre, champ):
            return outil.lire_rapport({"number": 10, "title": titre, "createdAt": "2026-01-03T00:00:00Z", "labels": [{"name": "rapport-jeu"}],
                                       "body": "### Rapport\n\n" + champ}, "gtranche/cidre")
        lu = par_le_formulaire("Rapport de jeu : NOM DU JEU (APPID)", modele)
        assert any("APPID" in e for e in lu["erreurs"]) and "etat absent" in lu["erreurs"], lu["erreurs"]
        assert "etat absent" in par_le_formulaire("Rapport de jeu : X (42)", modele)["erreurs"]
        rempli = modele.replace('date = ""', 'date = "2026-01-02"').replace('etat = ""', 'etat = "bronze"').replace("fps_jeu = 0", "fps_jeu = 25")
        lu = par_le_formulaire("Rapport de jeu : X (42)", rempli)
        assert lu["erreurs"] == [] and lu["appid"] == "42" and lu["champs"] == {"date": "2026-01-02", "etat": "bronze", "fps_jeu": 25}, lu
        assert lu["avertissements"] == ["machine absente : ce rapport ne comptera pas pour --proposer-compat"], lu["avertissements"]
        # ce qui suit l'intitule du diagnostic, en titre de formulaire comme en gras, n'est jamais un rapport
        for intitule in ("### Diagnostic", "**Diagnostic**"):
            lu = par_le_formulaire("Rapport de jeu : X (42)", f"Rien à dire.\n\n{intitule}\n\netat = \"or\"\ndate = \"2026-01-02\"\n")
            assert lu["erreurs"] == ["aucun bloc [[rapports]] ni ligne « etat = ... » dans le corps"], (intitule, lu["erreurs"])

        # 10. compatibilite par famille de Mac : famille_gpu et voie dans le rapport,
        # deduites sinon ; une entree [[compat.machines]] proposee par famille
        lu = outil.lire_rapport({"number": 11, "title": "Rapport de jeu : X (42)", "body":
                                 '[[rapports]]\ndate = "2026-01-02"\nmachine = "M4 24 Go"\nfamille_gpu = 9\nvoie = "d3d12"\netat = "bronze"\n'}, "gtranche/cidre")
        assert lu["erreurs"] == [] and lu["champs"]["famille_gpu"] == 9 and lu["champs"]["voie"] == "d3d12", lu
        assert outil.bloc_toml(lu["champs"], URL + "11")[3:5] == ["famille_gpu = 9", 'voie = "d3d12"'], outil.bloc_toml(lu["champs"], URL + "11")
        lu = outil.lire_rapport({"number": 12, "title": "Rapport de jeu : X (42)", "body":
                                 'date = "2026-01-02"\nfamille_gpu = "neuf"\nvoie = "metal"\netat = "or"\n'}, "gtranche/cidre")
        assert "famille_gpu" not in lu["champs"] and "voie" not in lu["champs"], lu["champs"]
        assert any("famille_gpu illisible" in a for a in lu["avertissements"]) and any("voie inconnue" in a for a in lu["avertissements"]), lu
        assert [outil.famille_de(x) for x in ({"machine": "iMac M4 24 Go"}, {"machine": "M1 Max 32 Go"}, {"machine": "M2 Pro"},
                                               {"famille_gpu": 8, "machine": "M4"}, {"machine": "Intel i9"}, {"machine": "M7 Max"})] == [9, 7, 8, 8, None, None]
        assert [outil.voie_de(*x) for x in (({"voie": "dxvk"}, {"dx12": True}), ({}, {"dx12": True, "d3d11": "dxmt"}),
                                             ({}, {"d3d11": "dxmt"}), ({}, {}))] == ["dxvk", "d3d12", "dxmt", ""]
        assert [outil.evaluer_si(c, {"famille_gpu": 9, "gamme": "max"}) for c in
                ("famille_gpu >= 8", "famille_gpu <= 7", "famille_gpu >= 8 et gamme == max", "gamme != max", "coeurs_gpu > 2", "famille_gpu >= huit", "")] \
            == [True, False, True, False, None, None, None]
        exp33 = {"compat": {"etat": "argent", "source": "cidre-test", "voie": "dxmt", "machine": "M1 Max 32 Go", "machines": [
            {"nom": "M1", "si": "famille_gpu <= 7", "voie": "d3d12", "etat": "ko", "source": "cidre-test"},
            {"nom": "M2 et suivants", "si": "famille_gpu >= 8", "voie": "d3d12", "etat": "bronze", "source": "cidre-test"}]}}
        assert outil.compat_pour(exp33, 9, "d3d12")[:2] == ("bronze", "cidre-test")
        assert outil.compat_pour(exp33, 7, "dxmt")[2] == "[compat]" and outil.compat_pour(exp33, 7, "dxvk")[0] == "non-teste"
        # deux M4 en D3D12 disent argent : la fiche dit bronze (cidre-test) -> signale, pas propose
        resume, fam = outil.proposer_par_famille(exp33, [r("iMac M4 24 Go", "argent", voie="d3d12"), r("Mac mini M4 Pro 48 Go", "argent", voie="d3d12")])
        assert resume == ["Apple9 (M3, M4), d3d12 : argent x2"] and len(fam) == 1 and fam[0][1] is None and "a retester" in fam[0][0], (resume, fam)
        # deux M2 en DXVK disent or, la fiche n'en dit rien : une entree pour la famille 8
        resume, fam = outil.proposer_par_famille(exp33, [r("MacBook Air M2 16 Go", "or", voie="dxvk", fps_jeu=40, incident=URL + "3"),
                                                         r("Mac mini M2 Pro 32 Go", "or", "2026-10-12", famille_gpu=8, _profil={"d3d11": "dxvk"}, incident=URL + "4")])
        assert len(fam) == 1 and fam[0][1] == {"nom": "M2", "si": "famille_gpu == 8", "voie": "dxvk", "etat": "or", "source": "utilisateur",
                                              "date": "2026-10-12", "machine": "Mac mini M2 Pro 32 Go", "notes": fam[0][1]["notes"]}, fam
        assert "#3 #4" in fam[0][1]["notes"] and "n'en dit rien" in fam[0][0]
        # la fiche reelle d'Expedition 33 se relit, et une M1 en DXMT d'accord avec [compat] ne donne rien
        e33 = outil.lire_fiche(os.path.join(RACINE, "profils", "1903340.toml"))
        assert [m["nom"] for m in e33["compat"]["machines"]] == ["M1", "M2 et suivants", "M2 et suivants"]
        assert outil.proposer_par_famille(e33, [r("M1 Max 32 Go", "argent", voie="dxmt"), r("M1 Pro 16 Go", "argent", voie="dxmt")])[1] == []
        # une famille sans voie connue est resumee, jamais proposee
        resume, fam = outil.proposer_par_famille({}, [r("M2 8 Go", "or"), r("M2 Max 64 Go", "or")])
        assert resume == ["Apple8 (M2), voie inconnue : or x2"] and fam == [], (resume, fam)
        print("test_rapports_vers_fiches : OK")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
