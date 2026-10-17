// Le service de depot en Cloudflare Worker + seau R2 : l'alternative a
// l'hebergement en conteneur (README.md, « Alternative : Cloudflare »). Tout le
// service est dans depot.js ; ici, seulement l'accueil.
import { traiter } from "./depot.js";

export default {
  async fetch(requete, env, _ctx, maintenant = new Date()) {
    if (new URL(requete.url).pathname === "/") {
      return new Response("Service de diagnostic de Cidre.\n", { headers: { "content-type": "text/plain; charset=utf-8" } });
    }
    return traiter(requete, env, maintenant);
  },
};
