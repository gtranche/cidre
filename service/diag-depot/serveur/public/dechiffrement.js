// Ouvrir un diagnostic recu, dans le navigateur (et sous node pour les essais) :
// l'enveloppe CIDRE-DIAG-1 de tests/envoyer_diag.sh, puis l'archive .tar.gz.
// Web Crypto seulement : la cle privee reste dans la page.
//
// Enveloppe : "CIDRE-DIAG-1\n" + base64(RSA-OAEP-SHA1("<cle hex> <iv hex> <sha256 hex>")) + "\n"
//             + "<format>\n" + AES-256-CBC(archive)
const enc = new TextEncoder();
const dec = new TextDecoder();

const hexEnOctets = (h) => new Uint8Array(h.match(/../g).map((x) => parseInt(x, 16)));
const octetsEnHex = (o) => [...new Uint8Array(o)].map((x) => x.toString(16).padStart(2, "0")).join("");
function base64EnOctets(b) {
  const s = atob(b.replace(/\s+/g, ""));
  const o = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) o[i] = s.charCodeAt(i);
  return o;
}

export function estChiffre(octets) {
  return dec.decode(octets.subarray(0, 12)) === "CIDRE-DIAG-1";
}

// la cle privee PEM (PKCS#8, « BEGIN PRIVATE KEY », celle d'openssl genpkey)
export async function importerClePrivee(pem) {
  const m = String(pem).match(/-----BEGIN PRIVATE KEY-----([\s\S]+?)-----END PRIVATE KEY-----/);
  if (!m) throw new Error("ce fichier n'est pas une cle privee PKCS#8 (BEGIN PRIVATE KEY)");
  return crypto.subtle.importKey("pkcs8", base64EnOctets(m[1]), { name: "RSA-OAEP", hash: "SHA-1" }, false, ["decrypt"]);
}

export async function dechiffrer(octets, clePrivee) {
  const lignes = [];
  let debut = 0;
  for (let i = 0; i < octets.length && lignes.length < 3; i++) {
    if (octets[i] === 10) { lignes.push(dec.decode(octets.subarray(debut, i))); debut = i + 1; }
  }
  if (lignes.length < 3 || lignes[0] !== "CIDRE-DIAG-1") throw new Error("enveloppe CIDRE-DIAG-1 illisible");
  let ouvert;
  try {
    ouvert = dec.decode(await crypto.subtle.decrypt({ name: "RSA-OAEP" }, clePrivee, base64EnOctets(lignes[1])));
  } catch {
    throw new Error("ce diagnostic n'a pas ete chiffre pour cette cle");
  }
  const [k, iv, empreinte] = ouvert.trim().split(/\s+/);
  const cle = await crypto.subtle.importKey("raw", hexEnOctets(k), { name: "AES-CBC" }, false, ["decrypt"]);
  const archive = new Uint8Array(await crypto.subtle.decrypt({ name: "AES-CBC", iv: hexEnOctets(iv) }, cle, octets.subarray(debut)));
  if (octetsEnHex(await crypto.subtle.digest("SHA-256", archive)) !== empreinte) throw new Error("archive abimee : empreinte differente");
  return { archive, format: lignes[2] };
}

export async function degzipper(octets) {
  if (octets[0] !== 0x1f || octets[1] !== 0x8b) throw new Error("archive inconnue (ni gzip, ni chiffree)");
  const flux = new Blob([octets]).stream().pipeThrough(new DecompressionStream("gzip"));
  return new Uint8Array(await new Response(flux).arrayBuffer());
}

// Les fichiers d'un tar (ustar, pax) : [{nom, octets}]. Le dossier de tete
// (diag-<id>-<date>/) est retire. Les liens et dossiers sont ignores.
export function lireTar(tar) {
  const fichiers = [];
  let i = 0, paxNom = null;
  const champ = (o, a, n) => dec.decode(tar.subarray(o + a, o + a + n)).replace(/\0.*$/s, "");
  while (i + 512 <= tar.length) {
    if (tar.subarray(i, i + 512).every((x) => x === 0)) break;
    const nom = champ(i, 0, 100), prefixe = champ(i, 345, 155);
    const taille = parseInt(champ(i, 124, 12).trim() || "0", 8);
    const type = String.fromCharCode(tar[i + 156] || 48);
    const donnees = tar.subarray(i + 512, i + 512 + taille);
    if (type === "x") {
      const m = dec.decode(donnees).match(/\d+ path=([^\n]*)\n/);
      paxNom = m ? m[1] : null;
    } else if (type === "0" || type === "\0") {
      let chemin = paxNom || (prefixe ? `${prefixe}/${nom}` : nom);
      chemin = chemin.replace(/^\.\//, "").replace(/^diag-[^/]+\//, "");
      if (chemin && !chemin.startsWith("._") && !chemin.includes("/._")) fichiers.push({ nom: chemin, octets: donnees.slice() });
      paxNom = null;
    } else if (type !== "g") {
      paxNom = null;
    }
    i += 512 + Math.ceil(taille / 512) * 512;
  }
  return fichiers;
}

// du corps recu (chiffre ou non) a la liste des fichiers
export async function ouvrirDiagnostic(octets, clePrivee) {
  let archive = octets, chiffre = false;
  if (estChiffre(octets)) {
    if (!clePrivee) throw new Error("diagnostic chiffre : choisis la cle privee de l'equipe");
    archive = (await dechiffrer(octets, clePrivee)).archive;
    chiffre = true;
  }
  return { chiffre, archive, fichiers: lireTar(await degzipper(archive)) };
}

export const texte = (octets) => dec.decode(octets);
export { enc };
