# Banc de non-régression nocturne (M1)

Compare chaque nuit, sans intervention, le runtime installé (**A** = `~/Dev/proton-ouvert`, la dernière release
posée) à une livraison candidate (**B** = A + les fichiers d'un `liste.tsv`), sur deux arbres fantômes. Rien n'est
écrit dans l'installé.

| Fichier | Rôle |
|---|---|
| `nuit.sh` | la nuit entière : gardes, verrou du M1, montage, témoins, jeux, rapport |
| `monter.sh <…/arbres/A\|B> [liste.tsv]` | arbre fantôme : runtime, préfixe, `prefix/` (KK + ICD), FEX et `build/logs` clonés (APFS), le reste en liens ; préfixe remis en accord (`system32\ntdll.dll`, `xtajit64`, `xtajit`, `syswow64\ntdll.dll`, plus de renommage en attente) |
| `manche_jeu.sh` | une manche au menu : `cidre play` de l'arbre, 120 s, images/s (`CIDRE_DXMT_STATS`, `CIDRE_WSI_STATS`), `cidre stop` (jamais de pkill), sortie du jeu et du wineserver |
| `temoins.sh construire\|passer` | témoins hors jeu de `temoins.tsv`, mêmes .exe pour A et B, dans un préfixe à part (`wine/pfx-temoins`, clone) |
| `rapport.py` | `rapport.md` (tableaux A/B, écarts) et `synthese.txt` (une ligne) |
| `verrou_m1.sh` | verrou partagé du M1 (voir plus bas) |
| `planifier.sh activer [HH:MM]\|desactiver\|etat` | agent launchd de l'utilisateur ; **désactivé par défaut** |
| `jeux.tsv`, `temoins.tsv` | listes de référence (seuils d'écart par jeu) |

## Données (`$CIDRE_BANC`, par défaut `~/Dev/cidre-banc-nocturne`)

- `candidat` : une ligne, le chemin du `liste.tsv` de la livraison à juger (format de
  `cidre-release-*/livraison/liste.tsv` : chemin de pose relatif à `$R`, sha1, source). Absent : contre-épreuve A/A
  (le bruit du banc).
- `nuits/<date>_<heure>/` : `rapport.md`, `synthese.txt`, `resultats.tsv`, `nuit.log`, journaux par jeu et par arbre,
  `temoins-A/`, `temoins-B/`, et la copie du banc qui a tourné (`banc/`).
- `synthese.txt` : une ligne par nuit. `derniere.txt` : la ligne de la dernière nuit. `derniere` : lien vers son dossier.
- `arbres/A`, `arbres/B` : remontés à chaque nuit (clones APFS : quelques Mo réels).

Au matin : `cat ~/Dev/cidre-banc-nocturne/derniere.txt`, puis `derniere/rapport.md` s'il signale un écart.

## Refus

Le banc ne lance rien et l'écrit dans la synthèse si : un wineserver, un processus Wine ou un jeu tourne ; l'écran est
verrouillé (`CGSSessionScreenIsLocked`) ou la session n'est pas à la console ; le verrou du M1 est tenu. Pendant la
nuit, `caffeinate -dimsu` garde l'écran allumé ; une manche où l'écran s'est verrouillé est marquée `invalide`. Un jeu
ou un wineserver qui ne s'arrête pas après `cidre stop` arrête la série (`arret-impossible`). Un jeu dont le disque
manque (`chemin-requis` de `jeux.tsv`) est `absent`.

`sh nuit.sh --sec` : monte les arbres, construit les témoins, passe les gardes sans refuser et dit ce qu'il ferait ;
ni Wine ni jeu. Ses dossiers ne remplacent pas la dernière vraie nuit.

## Verrou du M1 (`~/Dev/cidre-coordination/m1.verrou`)

À prendre par toute session qui lance un jeu ou un témoin sur le M1 :

```sh
sh tests/banc_nocturne/verrou_m1.sh prendre <session> <minutes> "<objet>"   # 1 = tenu : attendre
sh tests/banc_nocturne/verrou_m1.sh rendre <session>
sh tests/banc_nocturne/verrou_m1.sh etat
```

Création atomique. Un verrou est périmé (donc reprenable) si son `pid` est mort, ou s'il n'a pas de pid et que son
échéance est passée. Une session prend sans pid ; le banc prend avec le sien (`CIDRE_VERROU_PID=$$`) pour 150 min.

## Planification

```sh
sh tests/banc_nocturne/planifier.sh activer 03:30    # ~/Library/LaunchAgents/fr.cidre.banc-nocturne.plist
sh tests/banc_nocturne/planifier.sh desactiver
sh tests/banc_nocturne/planifier.sh etat
```

Le Mac doit rester en session ouverte et déverrouillée la nuit (sinon : refus « écran verrouillé », sans dégât).
