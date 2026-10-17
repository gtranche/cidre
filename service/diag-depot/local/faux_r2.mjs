// Un seau R2 en memoire, pour essayer le Worker sans compte Cloudflare
// (test/worker.test.mjs). Seulement ce que le Worker utilise.
async function octets(corps) {
  if (corps == null) return new Uint8Array();
  if (typeof corps === "string") return new TextEncoder().encode(corps);
  if (corps instanceof Uint8Array) return corps;
  return new Uint8Array(await new Response(corps).arrayBuffer());
}

export function fauxR2() {
  const objets = new Map();
  const vue = (key, o) => ({
    key, size: o.donnees.length, uploaded: o.uploaded, customMetadata: o.customMetadata,
    body: new Response(o.donnees).body,
    text: async () => new TextDecoder().decode(o.donnees),
  });
  return {
    objets,
    async put(key, corps, options = {}) {
      const donnees = await octets(corps);
      objets.set(key, { donnees, uploaded: new Date(), customMetadata: options.customMetadata || {} });
      return { key, size: donnees.length };
    },
    async get(key) { const o = objets.get(key); return o ? vue(key, o) : null; },
    async head(key) { const o = objets.get(key); return o ? { key, size: o.donnees.length } : null; },
    async delete(key) { objets.delete(key); },
    async list({ prefix = "" } = {}) {
      const liste = [...objets.entries()].filter(([k]) => k.startsWith(prefix)).map(([k, o]) => vue(k, o));
      return { objects: liste, truncated: false };
    },
  };
}
