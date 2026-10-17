// Le stockage du service sur un disque (le volume persistant du conteneur),
// avec le sous-ensemble de l'API de R2 qu'utilise depot.js. Un objet = deux
// fichiers : <racine>/<prefixe>/<nom>.bin (les octets, tels que recus : une
// archive chiffree) et <nom>.json (metadonnees : recu, jeu, version, chiffre,
// format). Ecriture dans un fichier temporaire puis renommage : un objet est
// la en entier, ou pas du tout.
import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";

// les seules cles que fabrique depot.js : diag/<6 signes>, quota/<AAAA-MM-JJ>
const CLE = /^(diag|quota)\/[A-Za-z0-9-]{1,40}$/;

export class StockageDisque {
  constructor(racine) {
    this.racine = racine;
  }

  chemin(cle) {
    if (!CLE.test(cle)) throw new Error("cle refusee");
    return path.join(this.racine, cle);
  }

  async put(cle, corps, options = {}) {
    const base = this.chemin(cle);
    await fsp.mkdir(path.dirname(base), { recursive: true });
    const tmp = `${base}.${process.pid}.${Date.now()}.tmp`;
    try {
      if (corps == null || typeof corps === "string" || corps instanceof Uint8Array) {
        await fsp.writeFile(tmp, corps ?? "");
      } else {
        await pipeline(Readable.fromWeb(corps), fs.createWriteStream(tmp, { mode: 0o600 }));
      }
      const { size } = await fsp.stat(tmp);
      const meta = { ...(options.customMetadata || {}) };
      await fsp.writeFile(`${tmp}.json`, JSON.stringify(meta), { mode: 0o600 });
      await fsp.rename(`${tmp}.json`, `${base}.json`);
      await fsp.rename(tmp, `${base}.bin`);
      return { key: cle, size };
    } catch (e) {
      await fsp.rm(tmp, { force: true });
      await fsp.rm(`${tmp}.json`, { force: true });
      throw e;
    }
  }

  async meta(cle) {
    const base = this.chemin(cle);
    try {
      const st = await fsp.stat(`${base}.bin`);
      let customMetadata = {};
      try { customMetadata = JSON.parse(await fsp.readFile(`${base}.json`, "utf8")); } catch {}
      return { key: cle, size: st.size, uploaded: st.mtime, customMetadata, base };
    } catch {
      return null;
    }
  }

  async head(cle) {
    const m = await this.meta(cle);
    return m && { key: m.key, size: m.size, uploaded: m.uploaded, customMetadata: m.customMetadata };
  }

  async get(cle) {
    const m = await this.meta(cle);
    if (!m) return null;
    return {
      key: m.key, size: m.size, uploaded: m.uploaded, customMetadata: m.customMetadata,
      get body() { return Readable.toWeb(fs.createReadStream(`${m.base}.bin`)); },
      text: () => fsp.readFile(`${m.base}.bin`, "utf8"),
    };
  }

  async delete(cle) {
    const base = this.chemin(cle);
    await fsp.rm(`${base}.bin`, { force: true });
    await fsp.rm(`${base}.json`, { force: true });
  }

  async list({ prefix = "" } = {}) {
    const dossier = prefix.replace(/\/$/, "");
    let noms = [];
    try { noms = await fsp.readdir(path.join(this.racine, dossier)); } catch {}
    const objects = [];
    for (const n of noms) {
      if (!n.endsWith(".bin")) continue;
      const m = await this.head(`${dossier}/${n.slice(0, -4)}`).catch(() => null);
      if (m) objects.push(m);
    }
    return { objects, truncated: false };
  }

  // Efface ce qui a plus de `ageMs` (diagnostics et compteurs du jour), et les
  // fichiers temporaires d'une ecriture interrompue. Rend le nombre de diagnostics effaces.
  async purger(ageMs, maintenant = Date.now()) {
    let n = 0;
    for (const dossier of ["diag", "quota"]) {
      let noms = [];
      try { noms = await fsp.readdir(path.join(this.racine, dossier)); } catch { continue; }
      for (const nom of noms) {
        const f = path.join(this.racine, dossier, nom);
        const st = await fsp.stat(f).catch(() => null);
        if (!st) continue;
        const age = maintenant - st.mtimeMs;
        if (nom.endsWith(".tmp") || nom.endsWith(".tmp.json")) {
          if (age > 3600_000) await fsp.rm(f, { force: true });
        } else if (nom.endsWith(".bin") && age > ageMs) {
          await this.delete(`${dossier}/${nom.slice(0, -4)}`);
          if (dossier === "diag") n++;
        }
      }
    }
    return n;
  }
}
