// Le serveur du conteneur : stockage sur disque, purge, limiteur, journaux,
// pages de consultation, et l'ouverture d'une archive (dechiffrement.js).
import test from "node:test";
import assert from "node:assert/strict";
import fsp from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { creerServeur, limiteurParMinute } from "../serveur/serveur.mjs";
import { StockageDisque } from "../serveur/stockage.mjs";
import { lireTar, ouvrirDiagnostic } from "../serveur/public/dechiffrement.js";

async function demarrer(plus = {}) {
  const dossier = await fsp.mkdtemp(path.join(os.tmpdir(), "cidre-diag-"));
  const lignes = [];
  const stockage = new StockageDisque(dossier);
  const serveur = creerServeur({
    stockage, jetonApp: "app-0123456789abcdef", jetonAdmin: "admin-0123456789abcdef",
    maxOctets: 2000, maxParJour: 50, retentionJours: 30, debitParMinute: 2, enteteIpClient: "x-real-ip",
    journal: (l) => lignes.push(l), ...plus,
  });
  await new Promise((ok) => serveur.listen(0, "127.0.0.1", ok));
  const base = `http://127.0.0.1:${serveur.address().port}`;
  return { dossier, lignes, stockage, base, fin: async () => { serveur.close(); await fsp.rm(dossier, { recursive: true, force: true }); } };
}
const deposer = (s, corps, ip = "10.0.0.1", jeton = "app-0123456789abcdef") =>
  fetch(`${s.base}/depot`, { method: "POST", body: corps, headers: { "x-cidre-jeton": jeton, "x-real-ip": ip, "x-cidre-jeu": "1137300" } });
const lire = (s, chemin, methode = "GET") => fetch(`${s.base}${chemin}`, { method: methode, headers: { authorization: "Bearer admin-0123456789abcdef" } });

test("depot sur disque, relu, liste, efface", async () => {
  const s = await demarrer();
  try {
    const r = await deposer(s, "octets-chiffres");
    assert.equal(r.status, 201);
    const { code } = await r.json();
    const fichiers = await fsp.readdir(path.join(s.dossier, "diag"));
    assert.equal(fichiers.filter((f) => f.endsWith(".bin")).length, 1);
    assert.equal(await (await lire(s, `/diag/${code}`)).text(), "octets-chiffres");
    assert.equal((await (await lire(s, "/liste")).json())[0].code, code);
    assert.equal((await fetch(`${s.base}/diag/${code}`)).status, 401);
    assert.equal((await lire(s, `/diag/${code}`, "DELETE")).status, 204);
    assert.equal((await lire(s, `/diag/${code}`)).status, 404);
  } finally { await s.fin(); }
});

test("garde-fous : taille, jeton, debit par adresse", async () => {
  const s = await demarrer();
  try {
    assert.equal((await deposer(s, "x".repeat(2001))).status, 413);
    assert.equal((await deposer(s, "x", "10.0.0.9", "faux")).status, 401);
    assert.equal((await deposer(s, "a", "10.0.0.2")).status, 201);
    assert.equal((await deposer(s, "b", "10.0.0.2")).status, 201);
    assert.equal((await deposer(s, "c", "10.0.0.2")).status, 429);
    // une autre adresse n'est pas genee
    assert.equal((await deposer(s, "d", "10.0.0.3")).status, 201);
    // l'adresse posee par le client lui-meme est ignoree
    const r = await fetch(`${s.base}/depot`, { method: "POST", body: "e", headers: { "x-cidre-jeton": "app-0123456789abcdef", "x-real-ip": "10.0.0.2", "x-cidre-ip-client": "1.2.3.4" } });
    assert.equal(r.status, 429);
  } finally { await s.fin(); }
});

test("journaux sans adresse, code, jeton ni contenu", async () => {
  const s = await demarrer();
  try {
    const { code } = await (await deposer(s, "contenu-secret", "192.0.2.77")).json();
    await (await lire(s, `/diag/${code}`)).text();
    // la ligne s'ecrit apres la reponse
    await new Promise((ok) => setTimeout(ok, 50));
    const tout = s.lignes.join("\n");
    for (const interdit of ["192.0.2.77", code, code.slice(6), "app-0123456789abcdef", "admin-0123456789abcdef", "contenu-secret", "1137300"]) {
      assert.ok(!tout.includes(interdit), `journal : ${interdit}`);
    }
    assert.match(tout, /POST \/depot 201/);
    assert.match(tout, /GET \/diag\/… 200/);
  } finally { await s.fin(); }
});

test("purge des diagnostics de plus de 30 jours", async () => {
  const s = await demarrer();
  try {
    const { code } = await (await deposer(s, "vieux")).json();
    const n = await s.stockage.purger(30 * 86400000, Date.now() + 31 * 86400000);
    assert.equal(n, 1);
    assert.equal((await lire(s, `/diag/${code}`)).status, 404);
  } finally { await s.fin(); }
});

test("pages de consultation, avec leurs en-tetes de securite", async () => {
  const s = await demarrer();
  try {
    for (const p of ["/consulter", "/consulter.js", "/dechiffrement.js", "/consulter.css"]) {
      const r = await fetch(`${s.base}${p}`);
      assert.equal(r.status, 200, p);
      assert.match(r.headers.get("content-security-policy"), /script-src 'self'/);
    }
    assert.equal((await fetch(`${s.base}/sante`)).status, 200);
    assert.equal((await fetch(`${s.base}/`, { redirect: "manual" })).headers.get("location"), "/consulter");
  } finally { await s.fin(); }
});

test("limiteur : une fenetre par minute et par adresse", async () => {
  let t = 0;
  const l = limiteurParMinute(2, () => t);
  assert.ok((await l.limit({ key: "a" })).success);
  assert.ok((await l.limit({ key: "a" })).success);
  assert.ok(!(await l.limit({ key: "a" })).success);
  t = 60000;
  assert.ok((await l.limit({ key: "a" })).success);
  assert.ok((await limiteurParMinute(0).limit({ key: "a" })).success);
});

test("archive non chiffree : gzip puis tar, dossier de tete retire", async () => {
  // une archive faite comme par diag_cidre.sh (tar -czf de diag-<id>-<date>/)
  const { execFileSync } = await import("node:child_process");
  const d = await fsp.mkdtemp(path.join(os.tmpdir(), "cidre-tar-"));
  try {
    await fsp.mkdir(path.join(d, "diag-1-20261017-120000", "plantages"), { recursive: true });
    await fsp.writeFile(path.join(d, "diag-1-20261017-120000", "resume.txt"), "cause probable : essai\n");
    await fsp.writeFile(path.join(d, "diag-1-20261017-120000", "plantages", "wine-2026.ips"), "{}");
    execFileSync("tar", ["-czf", "a.tar.gz", "diag-1-20261017-120000"], { cwd: d, env: { ...process.env, COPYFILE_DISABLE: "1" } });
    const o = await ouvrirDiagnostic(new Uint8Array(await fsp.readFile(path.join(d, "a.tar.gz"))), null);
    assert.equal(o.chiffre, false);
    assert.deepEqual(o.fichiers.map((f) => f.nom).sort(), ["plantages/wine-2026.ips", "resume.txt"]);
    assert.equal(new TextDecoder().decode(o.fichiers.find((f) => f.nom === "resume.txt").octets), "cause probable : essai\n");
    await assert.rejects(ouvrirDiagnostic(new TextEncoder().encode("CIDRE-DIAG-1\nxx\ntar.gz\n"), null), /cle privee/);
    assert.deepEqual(lireTar(new Uint8Array(1024)), []);
  } finally { await fsp.rm(d, { recursive: true, force: true }); }
});
