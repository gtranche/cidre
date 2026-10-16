# Donne a chaque bibliotheque du script de pipelines recolte (metal-source) le
# chemin de sa metallib : DXMT et KosmicKrisp (AIR distribue) chargent leurs bibliotheques depuis la memoire ou un fichier sans le nommer, le
# script ne les nomme que par le SHA-256 du fichier.
#   reecrire_script_pipelines.py <script.mtlp-json> <sortie> <dossier de metallibs>...
import hashlib, json, os, sys
j = json.load(open(sys.argv[1])); carte = {}
for d in sys.argv[3:]:
    for f in os.listdir(d):
        if f.endswith(".metallib"):
            p = os.path.join(d, f); carte[hashlib.sha256(open(p, "rb").read()).hexdigest().upper()] = p
manque = 0
for l in j["libraries"]["paths"]:
    if l["label"] in carte: l["path"] = carte[l["label"]]
    elif not os.path.exists(l["path"]): manque += 1
json.dump(j, open(sys.argv[2], "w"))
print("%d bibliotheques, %d sans fichier" % (len(j["libraries"]["paths"]), manque))
