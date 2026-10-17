// node --test service/diag-depot/test/
import test from "node:test";
import assert from "node:assert/strict";
import worker, { ALPHABET, nouveauCode, normaliser } from "../worker.js";
import { fauxR2 } from "../local/faux_r2.mjs";

const env = (plus = {}) => ({
  DIAGS: fauxR2(), JETON_APP: "app-123", JETON_ADMIN: "admin-456",
  MAX_OCTETS: "1000", MAX_PAR_JOUR: "3", RETENTION_JOURS: "30", ...plus,
});
const depot = (e, corps = "archive", entetes = {}, quand) =>
  worker.fetch(new Request("https://x/depot", {
    method: "POST", body: corps,
    headers: { "x-cidre-jeton": "app-123", "content-length": String(corps.length), "x-cidre-jeu": "1137300", ...entetes },
  }), e, {}, quand);
const admin = (e, chemin, methode = "GET", quand) =>
  worker.fetch(new Request(`https://x${chemin}`, { method: methode, headers: { authorization: "Bearer admin-456" } }), e, {}, quand);

test("le code : court, sans signe ambigu, cle de controle", () => {
  for (const x of "01OILU") assert.ok(!ALPHABET.includes(x));
  for (let i = 0; i < 200; i++) {
    const c = nouveauCode();
    assert.match(c, /^CIDRE-[2-9A-Z]{4}-[2-9A-Z]{2}$/);
    assert.ok(normaliser(c));
    assert.equal(normaliser(c.toLowerCase().replace(/-/g, " ")), normaliser(c));
  }
  // une faute sur un signe, ou deux voisins echanges : refuse
  const c = normaliser(nouveauCode());
  const autre = ALPHABET[(ALPHABET.indexOf(c[1]) + 1) % 30];
  assert.equal(normaliser(c[0] + autre + c.slice(2)), null);
  if (c[0] !== c[1]) assert.equal(normaliser(c[1] + c[0] + c.slice(2)), null);
  assert.equal(normaliser("CIDRE-0000-00"), null);
});

// la meme cle de controle que le shell : tests/tester_diag.sh compare les deux

test("depot puis lecture par l'administration", async () => {
  const e = env();
  const r = await depot(e, "contenu-chiffre", { "x-cidre-chiffre": "1" });
  assert.equal(r.status, 201);
  const { code, expire } = await r.json();
  assert.ok(normaliser(code));
  assert.match(expire, /^\d{4}-\d{2}-\d{2}$/);
  const g = await admin(e, `/diag/${code}`);
  assert.equal(g.status, 200);
  assert.equal(await g.text(), "contenu-chiffre");
  assert.equal(g.headers.get("x-cidre-chiffre"), "1");
  assert.equal(g.headers.get("x-cidre-jeu"), "1137300");
  const l = await (await admin(e, "/liste")).json();
  assert.equal(l.length, 1);
  assert.equal(l[0].code, code);
  // le code ne suffit pas : sans le jeton d'administration, rien
  const sans = await worker.fetch(new Request(`https://x/diag/${code}`), e, {});
  assert.equal(sans.status, 401);
  assert.equal((await admin(e, `/diag/${code}`, "DELETE")).status, 204);
  assert.equal((await admin(e, `/diag/${code}`)).status, 404);
});

test("garde-fous : jeton, taille, plafond du jour, debit", async () => {
  const e = env();
  assert.equal((await depot(e, "x", { "x-cidre-jeton": "faux" })).status, 401);
  assert.equal((await depot(e, "y".repeat(1001))).status, 413);
  for (let i = 0; i < 3; i++) assert.equal((await depot(e)).status, 201);
  assert.equal((await depot(e)).status, 429);
  // le lendemain, de nouveau
  assert.equal((await depot(e, "a", {}, new Date(Date.now() + 86400000))).status, 201);
  const limite = env({ LIMITE_IP: { limit: async () => ({ success: false }) } });
  assert.equal((await depot(limite)).status, 429);
});

test("un rapport de plus de 30 jours n'est plus servi", async () => {
  const e = env();
  const { code } = await (await depot(e)).json();
  const plus_tard = new Date(Date.now() + 31 * 86400000);
  assert.equal((await admin(e, `/diag/${code}`, "GET", plus_tard)).status, 404);
  assert.equal((await (await admin(e, "/liste", "GET", plus_tard)).json()).length, 0);
});

test("code mal tape : 400", async () => {
  assert.equal((await admin(env(), "/diag/CIDRE-0OIL-11")).status, 400);
});
