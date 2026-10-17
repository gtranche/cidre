// L'interface de consultation : la liste des diagnostics recus et chaque
// diagnostic ouvert dans la page. Tout ce qui vient d'une archive est ecrit en
// texte (textContent), jamais interprete : elle vient d'un Mac qu'on ne connait pas.
import { importerClePrivee, ouvrirDiagnostic, texte } from "./dechiffrement.js";

const $ = (id) => document.getElementById(id);
let cleAdmin = "";
let clePrivee = null;
let courant = null; // { code, octets, fichiers }

try { cleAdmin = sessionStorage.getItem("cle-admin") || ""; } catch {}
if (cleAdmin) $("cle-admin").value = cleAdmin;

async function api(chemin, options = {}) {
  const r = await fetch(chemin, { ...options, headers: { authorization: `Bearer ${cleAdmin}`, ...(options.headers || {}) } });
  if (r.status === 401) throw new Error("clé d'administration refusée");
  return r;
}

function ligne(cellules) {
  const tr = document.createElement("tr");
  for (const [valeur, classe] of cellules) {
    const td = document.createElement("td");
    td.textContent = valeur;
    if (classe) td.className = classe;
    tr.append(td);
  }
  return tr;
}

const taille = (n) => (n > 1048576 ? `${(n / 1048576).toFixed(1)} Mo` : `${Math.max(1, Math.round(n / 1024))} Ko`);

async function charger() {
  const r = await api("/liste");
  const liste = await r.json();
  const corps = $("liste");
  corps.replaceChildren();
  for (const d of liste) {
    const tr = ligne([[d.code, "code"], [(d.recu || "").slice(0, 16).replace("T", " ")], [d.jeu || "?"], [d.version || "?"], [taille(d.octets)], [d.chiffre ? "oui" : "NON"]]);
    tr.addEventListener("click", () => ouvrir(d.code));
    corps.append(tr);
  }
  $("vide").hidden = liste.length > 0;
  $("liste-section").hidden = false;
}

async function ouvrir(code) {
  const net = code.trim().toUpperCase();
  $("detail").hidden = false;
  $("detail-titre").textContent = net;
  $("detail-etat").textContent = "Téléchargement…";
  $("resume").textContent = "";
  $("fichiers").replaceChildren();
  $("fichier-vue").hidden = true;
  courant = null;
  try {
    const r = await api(`/diag/${encodeURIComponent(net)}`);
    if (!r.ok) {
      const e = await r.json().catch(() => ({}));
      throw new Error(e.message || `HTTP ${r.status}`);
    }
    const octets = new Uint8Array(await r.arrayBuffer());
    const recu = r.headers.get("x-cidre-recu") || "";
    courant = { code: net, octets, fichiers: [] };
    $("detail-etat").textContent = `Reçu ${recu.slice(0, 16).replace("T", " ")} · jeu ${r.headers.get("x-cidre-jeu") || "?"} · cidre ${r.headers.get("x-cidre-version") || "?"} · ${taille(octets.length)}`;
    const d = await ouvrirDiagnostic(octets, clePrivee);
    courant.fichiers = d.fichiers;
    const resume = d.fichiers.find((f) => f.nom === "resume.txt");
    $("resume").textContent = resume ? texte(resume.octets) : "(pas de resume.txt)";
    for (const f of d.fichiers) {
      const li = document.createElement("li");
      const b = document.createElement("button");
      b.type = "button";
      b.textContent = `${f.nom} (${taille(f.octets.length)})`;
      b.addEventListener("click", () => montrer(f));
      li.append(b);
      $("fichiers").append(li);
    }
  } catch (e) {
    $("detail-etat").textContent += `${$("detail-etat").textContent ? " — " : ""}${e.message}`;
  }
}

function montrer(f) {
  $("fichier-vue").hidden = false;
  $("fichier-nom").textContent = f.nom;
  const image = /\.png$/i.test(f.nom);
  $("fichier-image").hidden = !image;
  $("fichier-texte").hidden = image;
  if (image) {
    $("fichier-image").src = URL.createObjectURL(new Blob([f.octets], { type: "image/png" }));
  } else {
    $("fichier-texte").textContent = texte(f.octets);
  }
  $("fichier-vue").scrollIntoView({ behavior: "smooth" });
}

function telecharger(octets, nom) {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([octets], { type: "application/octet-stream" }));
  a.download = nom;
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 10000);
}

$("form-acces").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  cleAdmin = $("cle-admin").value.trim();
  try { sessionStorage.setItem("cle-admin", cleAdmin); } catch {}
  $("etat-acces").textContent = "";
  try {
    const f = $("cle-privee").files[0];
    if (f) clePrivee = await importerClePrivee(await f.text());
    await charger();
    $("etat-acces").textContent = clePrivee ? "Clé privée chargée (dans cette page seulement)." : "Sans clé privée : seuls les diagnostics non chiffrés s'ouvrent.";
  } catch (e) {
    $("etat-acces").textContent = e.message;
  }
});
$("rafraichir").addEventListener("click", () => charger().catch((e) => ($("etat-acces").textContent = e.message)));
$("form-code").addEventListener("submit", (ev) => { ev.preventDefault(); if ($("code").value.trim()) ouvrir($("code").value); });
$("telecharger").addEventListener("click", () => courant && telecharger(courant.octets, `${courant.code}${courant.octets[0] === 0x1f ? ".tar.gz" : ".cidre"}`));
$("effacer").addEventListener("click", async () => {
  if (!courant || !confirm(`Effacer ${courant.code} du service ? Ce n'est pas réversible.`)) return;
  const r = await api(`/diag/${encodeURIComponent(courant.code)}`, { method: "DELETE" });
  if (r.status === 204) { $("detail").hidden = true; await charger(); }
});
