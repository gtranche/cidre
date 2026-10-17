// Le Worker sur http://127.0.0.1:<port>, avec un seau en memoire : pour essayer
// `cidre diag envoyer` et tests/outils/lire_diag.sh sans compte Cloudflare
// (tests/tester_diag.sh).
//   node serveur_local.mjs <port> <jeton_app> <jeton_admin>
import http from "node:http";
import worker from "../worker.js";
import { fauxR2 } from "./faux_r2.mjs";

const [port = "8787", app = "app", adm = "admin"] = process.argv.slice(2);
const env = { DIAGS: fauxR2(), JETON_APP: app, JETON_ADMIN: adm, MAX_OCTETS: "8388608", MAX_PAR_JOUR: "300", RETENTION_JOURS: "30" };

http.createServer(async (req, res) => {
  const morceaux = [];
  for await (const m of req) morceaux.push(m);
  const corps = Buffer.concat(morceaux);
  const r = await worker.fetch(new Request(`http://127.0.0.1:${port}${req.url}`, {
    method: req.method, headers: req.headers,
    body: ["GET", "HEAD", "DELETE"].includes(req.method) ? undefined : corps,
  }), env, {});
  res.writeHead(r.status, Object.fromEntries(r.headers));
  res.end(Buffer.from(await r.arrayBuffer()));
}).listen(Number(port), "127.0.0.1", () => console.log(`pret ${port}`));
