// Le noyau du service de depot des diagnostics de Cidre : les routes, les
// garde-fous et les codes, sans rien savoir de l'hebergement. Deux hotes :
//   serveur/serveur.mjs  le conteneur (Kubernetes) : stockage sur disque,
//                        limiteur de debit en memoire, interface /consulter
//   worker.js            un Cloudflare Worker et un seau R2 (alternative)
// Le stockage `env.DIAGS` suit le sous-ensemble de l'API de R2 que voici :
// put(cle, corps, {customMetadata}), get(cle), head(cle), delete(cle),
// list({prefix, cursor, include}).
//
// Un testeur envoie l'archive que fait `cidre diag` (chiffree pour la cle de
// l'equipe : le service ne peut pas la lire) et recoit un code court,
// CIDRE-7K3P-Q9, qu'il donne a la personne qui l'aide. Seule l'equipe, avec la
// cle d'administration, la telecharge (tests/outils/lire_diag.sh, /consulter).
// Le code ne donne acces qu'a ce rapport-la, et a rien sans la cle.
//
//   POST   /depot          X-Cidre-Jeton: <JETON_APP>, corps = l'archive
//                          -> 201 {"code":"CIDRE-7K3P-Q9","expire":"2026-11-16"}
//   GET    /diag/<code>    Authorization: Bearer <JETON_ADMIN> -> l'archive
//   DELETE /diag/<code>    idem -> 204
//   GET    /liste          idem -> [{"code","octets","recu","jeu","version","chiffre"}]
//   GET    /sante          -> 200 (sondes de Kubernetes)
//
// Garde-fous : jeton d'application (ecarte les envois au hasard ; il est dans
// Cidre, ce n'est pas un secret), taille (MAX_OCTETS), debit par adresse
// (env.LIMITE_IP, si l'hote en fournit un ; l'adresse arrive dans
// X-Cidre-Ip-Client, posee par l'hote, ou CF-Connecting-IP chez Cloudflare),
// plafond quotidien (MAX_PAR_JOUR), conservation (RETENTION_JOURS : l'hote
// efface ; le noyau refuse en plus de servir un rapport plus ancien). Aucune
// adresse IP n'est gardee.

export const ALPHABET = "23456789ABCDEFGHJKMNPQRSTVWXYZ"; // ni 0/O, ni 1/I/L, ni U

// Luhn mod 30 sur les 5 signes tires au hasard : une faute sur un signe, ou
// deux signes voisins echanges, donnent un code invalide. Meme calcul que
// tests/envoyer_diag.sh, tests/outils/lire_diag.sh et serveur/public/consulter.js.
export function controle(signes) {
  const n = ALPHABET.length;
  let f = 2, s = 0;
  for (let i = signes.length - 1; i >= 0; i--) {
    const a = f * ALPHABET.indexOf(signes[i]);
    f = f === 2 ? 1 : 2;
    s += Math.floor(a / n) + (a % n);
  }
  return ALPHABET[(n - (s % n)) % n];
}

export function nouveauCode(aleatoire = (t) => crypto.getRandomValues(t)) {
  // 30 * 8 = 240 : un octet de 240 ou plus est rejete, la distribution reste uniforme
  let signes = "";
  while (signes.length < 5) {
    for (const o of aleatoire(new Uint8Array(8))) if (o < 240 && signes.length < 5) signes += ALPHABET[o % 30];
  }
  return mettreEnForme(signes + controle(signes));
}

export function mettreEnForme(six) {
  return `CIDRE-${six.slice(0, 4)}-${six.slice(4)}`;
}

// « cidre 7k3p q9 », « CIDRE-7K3P-Q9 » -> « 7K3PQ9 », ou null
export function normaliser(code) {
  const c = String(code || "").toUpperCase().replace(/[\s-]/g, "").replace(/^CIDRE/, "");
  if (c.length !== 6 || [...c].some((x) => !ALPHABET.includes(x))) return null;
  return controle(c.slice(0, 5)) === c[5] ? c : null;
}

function json(corps, statut = 200) {
  return new Response(JSON.stringify(corps), {
    status: statut,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}
const erreur = (statut, message) => json({ erreur: statut, message }, statut);

async function egal(a, b) {
  const enc = new TextEncoder();
  const x = enc.encode(String(a)), y = enc.encode(String(b));
  if (x.length !== y.length || x.length === 0) return false;
  if (crypto.subtle && crypto.subtle.timingSafeEqual) return crypto.subtle.timingSafeEqual(x, y);
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}

const nombre = (v, defaut) => (Number.isFinite(Number(v)) && Number(v) > 0 ? Number(v) : defaut);
const jour = (d) => d.toISOString().slice(0, 10);

async function deposer(requete, env, maintenant) {
  if (!env.JETON_APP || !(await egal(requete.headers.get("x-cidre-jeton") || "", env.JETON_APP)))
    return erreur(401, "jeton d'application absent ou faux");
  const max = nombre(env.MAX_OCTETS, 8 * 1024 * 1024);
  const longueur = Number(requete.headers.get("content-length"));
  if (!Number.isFinite(longueur) || longueur <= 0) return erreur(411, "taille de l'archive inconnue");
  if (longueur > max) return erreur(413, `archive trop lourde (${longueur} octets, ${max} au plus)`);

  if (env.LIMITE_IP) {
    const ip = requete.headers.get("x-cidre-ip-client") || requete.headers.get("cf-connecting-ip") || "?";
    const { success } = await env.LIMITE_IP.limit({ key: ip });
    if (!success) return erreur(429, "trop d'envois depuis cette adresse : reessaie dans une minute");
  }
  // plafond quotidien, approximatif (lecture puis ecriture) : il borne le cout
  const cleQuota = `quota/${jour(maintenant)}`;
  const quota = await env.DIAGS.get(cleQuota);
  const deja = quota ? Number(await quota.text()) || 0 : 0;
  if (deja >= nombre(env.MAX_PAR_JOUR, 300)) return erreur(429, "trop d'envois aujourd'hui : reessaie demain");

  let code = null;
  for (let essai = 0; essai < 6 && !code; essai++) {
    const c = nouveauCode();
    if (!(await env.DIAGS.head(`diag/${normaliser(c)}`))) code = c;
  }
  if (!code) return erreur(503, "aucun code libre, reessaie");

  const entete = (n, d = "?") => (requete.headers.get(n) || d).slice(0, 40).replace(/[^A-Za-z0-9._-]/g, "_");
  const objet = await env.DIAGS.put(`diag/${normaliser(code)}`, requete.body, {
    httpMetadata: { contentType: "application/octet-stream" },
    customMetadata: {
      recu: maintenant.toISOString(),
      jeu: entete("x-cidre-jeu"),
      version: entete("x-cidre-version"),
      chiffre: entete("x-cidre-chiffre", "0"),
      format: entete("x-cidre-format"),
    },
  });
  if (!objet) return erreur(500, "depot impossible");
  if (objet.size > max) {
    await env.DIAGS.delete(`diag/${normaliser(code)}`);
    return erreur(413, "archive trop lourde");
  }
  await env.DIAGS.put(cleQuota, String(deja + 1));
  const expire = new Date(maintenant.getTime() + nombre(env.RETENTION_JOURS, 30) * 86400000);
  return json({ code, expire: jour(expire) }, 201);
}

function perime(objet, env, maintenant) {
  const recu = Date.parse(objet.customMetadata?.recu || objet.uploaded);
  return maintenant.getTime() - recu > nombre(env.RETENTION_JOURS, 30) * 86400000;
}

async function administrer(requete, env, url, maintenant) {
  const jeton = (requete.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!env.JETON_ADMIN || !(await egal(jeton, env.JETON_ADMIN))) return erreur(401, "jeton d'administration absent ou faux");

  if (url.pathname === "/liste" && requete.method === "GET") {
    const liste = [];
    let curseur;
    do {
      const page = await env.DIAGS.list({ prefix: "diag/", cursor: curseur, include: ["customMetadata"] });
      for (const o of page.objects) {
        if (perime(o, env, maintenant)) continue;
        const m = o.customMetadata || {};
        liste.push({ code: mettreEnForme(o.key.slice(5)), octets: o.size, recu: m.recu, jeu: m.jeu, version: m.version, chiffre: m.chiffre === "1" });
      }
      curseur = page.truncated ? page.cursor : undefined;
    } while (curseur);
    liste.sort((a, b) => String(b.recu).localeCompare(String(a.recu)));
    return json(liste);
  }

  const m = url.pathname.match(/^\/diag\/([^/]+)$/);
  if (!m) return erreur(404, "inconnu");
  const code = normaliser(decodeURIComponent(m[1]));
  if (!code) return erreur(400, "code invalide (une faute de frappe ?)");
  const cle = `diag/${code}`;
  if (requete.method === "DELETE") {
    await env.DIAGS.delete(cle);
    return new Response(null, { status: 204 });
  }
  if (requete.method !== "GET") return erreur(405, "methode refusee");
  const objet = await env.DIAGS.get(cle);
  if (!objet || perime(objet, env, maintenant)) return erreur(404, "aucun diagnostic sous ce code (expire ?)");
  const md = objet.customMetadata || {};
  return new Response(objet.body, {
    headers: {
      "content-type": "application/octet-stream",
      "content-length": String(objet.size),
      "cache-control": "no-store",
      "x-cidre-recu": md.recu || "",
      "x-cidre-jeu": md.jeu || "",
      "x-cidre-version": md.version || "",
      "x-cidre-chiffre": md.chiffre || "0",
      "x-cidre-format": md.format || "",
    },
  });
}

export async function traiter(requete, env, maintenant = new Date()) {
    const url = new URL(requete.url);
    try {
      if (url.pathname === "/sante") return new Response("ok\n");
      if (url.pathname === "/depot") {
        if (requete.method !== "POST") return erreur(405, "POST seulement");
        return await deposer(requete, env, maintenant);
      }
      if (url.pathname === "/liste" || url.pathname.startsWith("/diag/")) return await administrer(requete, env, url, maintenant);
      return erreur(404, "inconnu");
    } catch (e) {
      return erreur(500, "erreur du service");
    }
}
