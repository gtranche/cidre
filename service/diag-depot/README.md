# Service de dépôt des diagnostics

Un testeur appuie sur « Envoyer un diagnostic » dans Verger (ou lance `cidre diag <appid>`). Il voit ce qui va partir, accepte, et reçoit un code court : **`CIDRE-7K3P-Q9`**. Il le donne à la personne qui l'aide. La coordination récupère le diagnostic avec `tests/outils/lire_diag.sh CIDRE-7K3P-Q9`.

- Le code utilise 30 signes, sans `0`/`O`, sans `1`/`I`/`L` et sans `U`. Il porte 5 signes tirés au hasard et une clé de contrôle (Luhn mod 30). Une faute de frappe ou deux signes inversés sont donc détectés avant même d'interroger le service.
- Le code désigne un seul rapport et ne sert à rien sans le jeton d'administration. Un tiers qui le connaît ne peut rien télécharger.
- L'archive est chiffrée sur le Mac du testeur avec la clé publique de l'équipe : RSA-OAEP pour envelopper une clé AES-256, avec l'empreinte SHA-256 de l'archive. Cloudflare ne stocke que des octets illisibles. Seule la clé privée, sur la machine de la coordination, permet de les lire.
- Avant de chiffrer, `cidre diag` masque le nom de session et le nom complet, le dossier personnel, les noms et le numéro de série du Mac, les comptes Steam (SteamID, noms de connexion et de profil), les jetons, les e-mails et les adresses IP (`tests/masquer_diag.awk`). La capture d'écran n'est prise que si le testeur coche la case.
- Le service ne conserve aucune adresse IP. Un diagnostic est effacé au bout de 30 jours.
- L'archive est un `.tar.gz`, de quelques dizaines de Ko en général. zstd n'est pas installé sur un Mac neuf, et GitHub n'accepte pas les pièces jointes `.zst`. Or, sans réseau ou sans service, Verger propose justement de joindre l'archive à un incident.

## Le choix : Cloudflare Workers + R2

| Option | Coût pour nous | Limites gratuites | Conservation | Ce qui coince |
|---|---|---|---|---|
| **Cloudflare Worker + R2** (retenu) | 0 € à notre échelle | Workers : 100 000 requêtes par jour, 10 ms de processeur par requête, corps jusqu'à 100 Mo. R2 : 10 Go-mois, 1 M d'écritures et 10 M de lectures par mois, **sortie gratuite** | règle de cycle de vie du seau (30 j), et le Worker refuse en plus de servir un rapport plus vieux | R2 demande une carte bancaire au dossier, même dans la gratuité |
| Backblaze B2 + petite fonction de signature | quasi nul | 10 Go | règles de cycle de vie | il faut quand même héberger la fonction qui signe les dépôts |
| AWS S3 + Lambda (URL présignée) | quasi nul la 1re année | gratuité limitée à 12 mois pour S3 | règles de cycle de vie | IAM, deux services à configurer, facture au-delà de la 1re année |
| Supabase Storage | 0 € | 1 Go | à programmer | un projet gratuit est **mis en pause** après une semaine sans activité |
| Deno Deploy + KV | 0 € | — | expiration native | une valeur KV fait au plus 64 Kio : l'archive ne tient pas |
| transfer.sh, 0x0.st, gist | 0 € | — | variable | public ou anonyme, aucun contrôle des abus ni des accès |

Le dépassement est peu probable et coûte peu. Au-delà de la gratuité, R2 facture 0,015 $ par Go-mois et 4,50 $ par million d'écritures. 300 archives de 8 Mio par jour pendant 30 jours font environ 70 Go, soit à peu près 1 $ par mois. Le plafond quotidien empêche d'aller plus loin. Une archive réelle pèse plutôt 10 à 200 Ko.

### Protection contre les abus

- **Jeton d'application** (`X-Cidre-Jeton`) : il est livré avec Cidre, ce n'est donc pas un secret. Il écarte les robots qui frappent au hasard. S'il est usé, on le change (étape 4) et on livre un Cidre neuf.
- **Taille** : 8 Mio au plus (`MAX_OCTETS`). `cidre diag` réduit son archive en dessous de cette limite.
- **Débit** : 3 envois par minute et par adresse, avec le limiteur de Cloudflare (`[[ratelimits]]`). L'adresse sert de clé de comptage le temps d'une minute, elle n'est pas stockée.
- **Plafond quotidien** : 300 envois par jour UTC (`MAX_PAR_JOUR`). Au-delà, le service répond 429 jusqu'au lendemain.
- **Lecture** : uniquement avec le jeton d'administration (`Authorization: Bearer`), comparé en temps constant.

## Mise en place (à faire par toi, une fois, environ 15 minutes)

Claude n'a créé aucun compte et n'a rien déployé. Tout se fait depuis ton Mac, dans ce dossier (`service/diag-depot`).

### 1. Le compte Cloudflare et R2

1. Crée un compte sur <https://dash.cloudflare.com/sign-up> (le plan Free suffit).
2. Dans le tableau de bord, ouvre **R2 Object Storage** et active R2. Cloudflare demande une carte bancaire même pour l'offre gratuite.
3. Connecte l'outil en ligne de commande. Il s'installe à la volée et il faut Wrangler 4.36 ou plus pour le limiteur de débit :

```bash
npx wrangler@latest login
```

### 2. Le seau et sa durée de conservation

```bash
npx wrangler r2 bucket create cidre-diags
```

```bash
npx wrangler r2 bucket lifecycle add cidre-diags expire-30j --expire-days 30
```

La seconde commande crée une règle qui efface tout objet de plus de 30 jours. Si elle demande un préfixe, réponds `diag/`. Tu peux aussi la créer dans le tableau de bord : R2 > cidre-diags > Settings > Object lifecycle rules.

### 3. Les deux jetons

Tire deux valeurs au hasard :

```bash
openssl rand -hex 24
```

Lance la commande deux fois. Garde le premier résultat pour l'application, le second pour l'administration. Donne-les au Worker (chaque commande demande la valeur) :

```bash
npx wrangler secret put JETON_APP
```

```bash
npx wrangler secret put JETON_ADMIN
```

### 4. Le déploiement

```bash
npx wrangler deploy
```

Wrangler affiche l'adresse, du type `https://cidre-diag.<ton-sous-domaine>.workers.dev`. Si ton compte refuse le limiteur de débit, retire le bloc `[[ratelimits]]` de `wrangler.toml` : le Worker fonctionne sans lui, il reste protégé par le jeton, la taille et le plafond quotidien.

Vérifie :

```bash
curl https://cidre-diag.<ton-sous-domaine>.workers.dev/
```

La réponse attendue est « Service de diagnostic de Cidre. »

### 5. La paire de clés de chiffrement

Sur la machine de la coordination, et nulle part ailleurs pour la clé privée :

```bash
mkdir -p ~/.config/cidre-diag && chmod 700 ~/.config/cidre-diag
```

```bash
/usr/bin/openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out ~/.config/cidre-diag/cle_privee.pem
```

```bash
/usr/bin/openssl pkey -in ~/.config/cidre-diag/cle_privee.pem -pubout -out ~/.config/cidre-diag/diag-cle.pem
```

Sauvegarde `cle_privee.pem` dans ton gestionnaire de mots de passe. Sans elle, les diagnostics reçus deviennent illisibles. Ne la commite jamais.

### 6. Ce que Cidre livre, et ce que la coordination garde

La coordination copie ces fichiers dans le dépôt et les commite. Ils ne sont pas secrets et partent dans le runtime grâce à `tests/empaqueter_runtime.sh` :

- `outil-steam/diag-cle.pem` : la clé **publique** produite à l'étape 5 ;
- `outil-steam/diag-service.conf`, sur le modèle de `outil-steam/diag-service.conf.exemple` :

```
url=https://cidre-diag.<ton-sous-domaine>.workers.dev
jeton=<JETON_APP>
cle=diag-cle.pem
```

Ces fichiers restent sur la seule machine de la coordination, hors du dépôt, dans `~/.config/cidre-diag/conf` :

```
url=https://cidre-diag.<ton-sous-domaine>.workers.dev
jeton_admin=<JETON_ADMIN>
cle_privee=~/.config/cidre-diag/cle_privee.pem
```

### 7. Essai

Sur ton Mac, une fois la configuration posée (le runtime livré, ou `~/Library/Application Support/Cidre/diag-service.conf` avec la clé publique à côté) :

```bash
cidre diag service
```

```bash
cidre diag 1137300
```

Réponds `o` à la question. Le code s'affiche. Puis, côté coordination :

```bash
sh tests/outils/lire_diag.sh CIDRE-XXXX-XX
```

## Côté coordination

- `lire_diag.sh <CODE>` : télécharge, déchiffre, vérifie l'empreinte, déballe dans `~/Dev/diags-recus/<CODE>/` et résume en 20 lignes (versions, machine, doctor, cause probable, shaders, profil, plantages, système).
- `lire_diag.sh --liste` : les diagnostics des 30 derniers jours.
- `lire_diag.sh --fichier diag-….tar.gz` : une archive reçue autrement, par exemple jointe à un incident GitHub quand le testeur n'avait pas de réseau.
- `lire_diag.sh --effacer <CODE>` : efface un diagnostic avant son expiration.

## Développement

- `node --test test/` : les essais du Worker, avec un seau en mémoire.
- `sh tests/tester_diag.sh` (racine du dépôt) : le circuit complet (masquage, archive chiffrée, code, `lire_diag.sh`) sur le Worker servi en local (`local/serveur_local.mjs`), sans compte Cloudflare.

Changer le jeton d'application : `npx wrangler secret put JETON_APP`, puis mettre à jour `outil-steam/diag-service.conf` et livrer. Les Cidre déjà installés ne peuvent plus envoyer jusqu'à leur mise à jour. Ils retombent alors sur l'archive dans le Finder et le formulaire GitHub.
