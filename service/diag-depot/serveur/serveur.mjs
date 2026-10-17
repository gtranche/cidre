// Le service de depot des diagnostics de Cidre, en conteneur (Dockerfile,
// k8s/). Node seul, sans dependance : depot.js pour les routes, le stockage
// sur le volume persistant (stockage.mjs), un limiteur de debit en memoire, la
// purge des diagnostics de plus de RETENTION_JOURS, et l'interface de
// consultation (/consulter : la liste, et chaque diagnostic dechiffre DANS LE
// NAVIGATEUR avec la cle privee de l'equipe, qui ne quitte pas le poste).
//
// Une seule replique : le stockage est un volume ReadWriteOnce, le limiteur et
// le plafond du jour vivent ici.
//
// Configuration (environnement) :
//   JETON_APP, JETON_ADMIN   obligatoires (Secret Kubernetes) ; ou leurs
//                            fichiers : JETON_APP_FICHIER, JETON_ADMIN_FICHIER
//   PORT                     8080
//   DONNEES                  /donnees (le volume persistant)
//   MAX_OCTETS               8388608 (8 Mio par archive)
//   MAX_PAR_JOUR             300
//   RETENTION_JOURS          30
//   DEBIT_PAR_MINUTE         3 envois par minute et par adresse (0 : sans limite)
//   ENTETE_IP_CLIENT         l'en-tete ou l'Ingress met l'adresse du client
//                            (x-real-ip pour ingress-nginx ; x-forwarded-for :
//                            on prend sa DERNIERE adresse, celle qu'a vue
//                            l'Ingress) ; vide : l'adresse de la connexion
//
// Journaux : une ligne par requete, methode, route, statut, taille, duree.
// Jamais d'adresse IP, de code, de jeton ni de contenu.
import http from "node:http";
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { Readable } from "node:stream";
import { fileURLToPath } from "node:url";
import { traiter } from "../depot.js";
import { StockageDisque } from "./stockage.mjs";

const ici = path.dirname(fileURLToPath(import.meta.url));
const lire = (nom) => {
  if (process.env[nom]) return process.env[nom].trim();
  const f = process.env[`${nom}_FICHIER`];
  return f ? fs.readFileSync(f, "utf8").trim() : "";
};

export function limiteurParMinute(parMinute, horloge = () => Date.now()) {
  const fenetres = new Map();
  return {
    async limit({ key }) {
      if (!parMinute) return { success: true };
      const minute = Math.floor(horloge() / 60000);
      const f = fenetres.get(key);
      if (!f || f.minute !== minute) {
        // on oublie les adresses des minutes passees : rien ne s'accumule
        if (fenetres.size > 10000) fenetres.clear();
        fenetres.set(key, { minute, n: 1 });
        return { success: true };
      }
      f.n++;
      return { success: f.n <= parMinute };
    },
  };
}

function adresseClient(req, entete) {
  if (entete) {
    const v = req.headers[entete.toLowerCase()];
    if (v) {
      const liste = String(v).split(",").map((x) => x.trim()).filter(Boolean);
      if (liste.length) return liste[liste.length - 1];
    }
  }
  return req.socket.remoteAddress || "?";
}

const STATIQUES = {
  "/consulter": ["consulter.html", "text/html; charset=utf-8"],
  "/consulter.js": ["consulter.js", "text/javascript; charset=utf-8"],
  "/consulter.css": ["consulter.css", "text/css; charset=utf-8"],
  "/dechiffrement.js": ["dechiffrement.js", "text/javascript; charset=utf-8"],
};
const SECURITE = {
  "content-security-policy": "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' blob: data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
  "x-content-type-options": "nosniff",
  "referrer-policy": "no-referrer",
  "x-frame-options": "DENY",
};

const route = (p) => (p.startsWith("/diag/") ? "/diag/…" : (STATIQUES[p] || ["/", "/depot", "/liste", "/sante"].includes(p)) ? p : "/autre");

export function creerServeur(config) {
  const env = {
    DIAGS: config.stockage,
    JETON_APP: config.jetonApp,
    JETON_ADMIN: config.jetonAdmin,
    MAX_OCTETS: String(config.maxOctets),
    MAX_PAR_JOUR: String(config.maxParJour),
    RETENTION_JOURS: String(config.retentionJours),
    LIMITE_IP: limiteurParMinute(config.debitParMinute),
  };
  const journal = config.journal ?? ((l) => console.log(l));

  const serveur = http.createServer(async (req, res) => {
    const debut = Date.now();
    const url = new URL(req.url, "http://service");
    let statut = 500, octets = 0;
    try {
      if (req.method === "GET" && STATIQUES[url.pathname]) {
        const [f, type] = STATIQUES[url.pathname];
        const corps = await fsp.readFile(path.join(ici, "public", f));
        statut = 200; octets = corps.length;
        res.writeHead(200, { "content-type": type, "cache-control": "no-cache", ...SECURITE });
        res.end(corps);
        return;
      }
      if (url.pathname === "/" && req.method === "GET") {
        statut = 302;
        res.writeHead(302, { location: "/consulter" });
        res.end();
        return;
      }
      const entetes = new Headers();
      for (const [k, v] of Object.entries(req.headers)) {
        // l'adresse du client, c'est nous qui la posons
        if (k === "x-cidre-ip-client" || k === "cf-connecting-ip") continue;
        entetes.set(k, Array.isArray(v) ? v.join(", ") : v);
      }
      entetes.set("x-cidre-ip-client", adresseClient(req, config.enteteIpClient));
      const sansCorps = ["GET", "HEAD", "DELETE"].includes(req.method);
      const requete = new Request(new URL(req.url, "http://service"), {
        method: req.method, headers: entetes,
        body: sansCorps ? undefined : Readable.toWeb(req), duplex: "half",
      });
      const r = await traiter(requete, env);
      statut = r.status;
      const h = Object.fromEntries(r.headers);
      res.writeHead(r.status, { ...h, "x-content-type-options": "nosniff" });
      if (r.body) {
        for await (const morceau of Readable.fromWeb(r.body)) { octets += morceau.length; res.write(morceau); }
      }
      res.end();
      // un envoi refuse avant lecture : on ne lit pas le reste
      if (!sansCorps && !req.readableEnded) req.destroy();
    } catch {
      statut = 500;
      if (!res.headersSent) res.writeHead(500, { "content-type": "application/json" });
      res.end('{"erreur":500,"message":"erreur du service"}');
    } finally {
      journal(`${new Date().toISOString()} ${req.method} ${route(url.pathname)} ${statut} ${octets}o ${Date.now() - debut}ms`);
    }
  });
  serveur.requestTimeout = 120_000;
  serveur.headersTimeout = 20_000;
  return serveur;
}

// --- Lancement --------------------------------------------------------------
if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const config = {
    jetonApp: lire("JETON_APP"),
    jetonAdmin: lire("JETON_ADMIN"),
    maxOctets: Number(process.env.MAX_OCTETS || 8388608),
    maxParJour: Number(process.env.MAX_PAR_JOUR || 300),
    retentionJours: Number(process.env.RETENTION_JOURS || 30),
    debitParMinute: Number(process.env.DEBIT_PAR_MINUTE ?? 3),
    enteteIpClient: process.env.ENTETE_IP_CLIENT ?? "x-real-ip",
    stockage: new StockageDisque(process.env.DONNEES || "/donnees"),
  };
  if (config.jetonApp.length < 16 || config.jetonAdmin.length < 16 || config.jetonApp === config.jetonAdmin) {
    console.error("JETON_APP et JETON_ADMIN : deux valeurs differentes, de 16 caracteres au moins (openssl rand -hex 24)");
    process.exit(2);
  }
  const purger = async () => {
    try {
      const n = await config.stockage.purger(config.retentionJours * 86400000);
      if (n) console.log(`${new Date().toISOString()} purge : ${n} diagnostic(s) de plus de ${config.retentionJours} jours`);
    } catch (e) {
      console.error(`${new Date().toISOString()} purge impossible : ${e.code || "erreur"}`);
    }
  };
  await fsp.mkdir(path.join(config.stockage.racine, "diag"), { recursive: true });
  await purger();
  setInterval(purger, 3600_000).unref();
  const port = Number(process.env.PORT || 8080);
  const serveur = creerServeur(config).listen(port, () => console.log(`service de diagnostic de Cidre sur le port ${port}`));
  const arreter = () => serveur.close(() => process.exit(0));
  process.on("SIGTERM", arreter);
  process.on("SIGINT", arreter);
}
