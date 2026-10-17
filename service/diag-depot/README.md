# Service de dépôt des diagnostics

Un testeur appuie sur « Envoyer un diagnostic » dans Verger (ou lance `cidre diag <appid>`). Il voit ce qui va partir, accepte, et reçoit un code court : **`CIDRE-7K3P-Q9`**. Il le donne à la personne qui l'aide. On retrouve ensuite le diagnostic de deux façons : à l'œil, sur la page `/consulter` du service, ou par l'API, avec `tests/outils/lire_diag.sh CIDRE-7K3P-Q9` côté coordination.

Le service tourne sur ton Kubernetes, en conteneur. Une alternative sans serveur, sur Cloudflare, est décrite en fin de page. Dans les deux cas, Cidre et Verger ne connaissent qu'une URL, celle de `outil-steam/diag-service.conf`.

## Ce que le service garantit

- **Le code** : 30 signes possibles, sans `0`/`O`, sans `1`/`I`/`L` et sans `U`. Il contient 5 signes tirés au hasard et une clé de contrôle (Luhn mod 30), si bien qu'une faute de frappe ou deux signes inversés sont détectés tout de suite. Il désigne un seul rapport. Sans la clé d'administration, il ne donne accès à rien.
- **Le chiffrement** : l'archive est chiffrée sur le Mac du testeur, avant de partir, avec la clé publique de l'équipe (RSA-OAEP enveloppant une clé AES-256, plus l'empreinte SHA-256 de l'archive). Le serveur ne stocke que des octets illisibles. Pour lire, il faut la clé privée : `lire_diag.sh` l'utilise en local, et la page `/consulter` déchiffre dans ton navigateur, sans jamais envoyer la clé.
- **Le masquage** : avant même de chiffrer, `cidre diag` retire le nom de session et le nom complet, le dossier personnel, les noms et le numéro de série du Mac, les comptes Steam (SteamID, noms de connexion et de profil), les jetons, les e-mails et les adresses IP. La capture d'écran n'est prise que si le testeur coche la case.
- **L'archive** : un `.tar.gz` de quelques dizaines de Ko, 8 Mio au plus. Pourquoi pas zstd : il n'est pas installé sur un Mac neuf, et GitHub refuse les pièces jointes `.zst`. Or, quand le service est injoignable, Verger propose justement de joindre l'archive à un incident GitHub.
- **Les garde-fous** :
  - un jeton d'application obligatoire pour envoyer ;
  - 8 Mio par archive ;
  - 3 envois par minute et par adresse ;
  - 300 envois par jour ;
  - 30 jours de conservation, avec une purge toutes les heures ;
  - lecture et effacement réservés à la clé d'administration.
- **Les journaux** : une ligne par requête (méthode, route, statut, taille, durée). Jamais d'adresse IP, de code, de jeton ni de contenu.

## Ce que contient ce dossier

| Fichier | Rôle |
|---|---|
| `depot.js` | le service lui-même (routes, garde-fous, codes), commun aux deux hébergements |
| `serveur/serveur.mjs`, `serveur/stockage.mjs` | l'hôte conteneur : Node 22 sans aucune dépendance, stockage sur le volume persistant, purge, limiteur de débit |
| `serveur/public/` | la page `/consulter` (liste, ouverture, téléchargement, effacement) |
| `Dockerfile` | l'image (`node:22.11.0-alpine3.20`, utilisateur non root) |
| `k8s/` | Namespace, PVC, Deployment, Service, Ingress avec TLS ; `secret.exemple.yaml` montre seulement la forme du Secret |
| `worker.js`, `wrangler.toml` | l'alternative Cloudflare |

L'API :

| Requête | Accès | Réponse |
|---|---|---|
| `POST /depot` (corps = l'archive) | en-tête `X-Cidre-Jeton: <JETON_APP>` | `201 {"code":"CIDRE-…","expire":"AAAA-MM-JJ"}` |
| `GET /diag/<code>` | `Authorization: Bearer <JETON_ADMIN>` | l'archive, telle que reçue |
| `DELETE /diag/<code>` | idem | `204` |
| `GET /liste` | idem | les diagnostics des 30 derniers jours, sans leur contenu |
| `GET /consulter` | la page demande la clé d'administration | l'interface |
| `GET /sante` | libre | `ok`, pour les sondes de Kubernetes |

## Mise en place sur Kubernetes (à faire par toi, environ 20 minutes)

Claude n'a ni accédé au cluster, ni rien déployé, ni créé de compte. Toutes les commandes ci-dessous se lancent depuis ton Mac qui a accès au cluster. Les valeurs écrites `EN_MAJUSCULES` sont à remplacer.

Prérequis côté cluster :
- un contrôleur d'Ingress : les annotations fournies visent ingress-nginx ;
- cert-manager avec un `ClusterIssuer` Let's Encrypt ;
- une classe de stockage par défaut, ou une autre que tu indiques dans `k8s/pvc.yaml`.

### 1. Le nom DNS chez Gandi

1. Choisis un nom, par exemple `diag.EXEMPLE.fr`.
2. Dans l'interface Gandi, ouvre Domaines, puis ton domaine, puis Enregistrements DNS, puis Ajouter. Crée l'un des deux enregistrements suivants :
   - si l'Ingress a une adresse IP fixe : type `A`, nom `diag`, valeur = cette IP, TTL 1800 ;
   - si ton cluster expose un nom d'hôte (répartiteur de charge d'un hébergeur) : type `CNAME`, nom `diag`, valeur = ce nom suivi d'un point final.
3. Pour retrouver l'adresse de l'Ingress :

```bash
kubectl -n ingress-nginx get svc
```

4. Vérifie la propagation. La commande doit afficher l'adresse attendue :

```bash
dig +short diag.EXEMPLE.fr
```

### 2. L'image

Depuis ce dossier, `service/diag-depot`, construis l'image pour les deux architectures et pousse-la dans ton registre (`REGISTRE` : par exemple `ghcr.io/gtranche` ou ton registre privé) :

```bash
docker buildx build --platform linux/amd64,linux/arm64 -t REGISTRE/cidre-diag:1.0.0 --push .
```

Si ton registre est privé, ajoute un `imagePullSecrets` au Deployment, comme pour tes autres applications.

### 3. Les manifestes

Remplace les valeurs à adapter :
- dans `k8s/kustomization.yaml` : `REGISTRE/cidre-diag` et la version ;
- dans `k8s/ingress.yaml` : `diag.EXEMPLE.fr` (il apparaît deux fois), `ingressClassName` et le nom de ton `ClusterIssuer` ;
- dans `k8s/pvc.yaml`, si besoin : `storageClassName`.

Si ton Ingress est Traefik plutôt que nginx : passe `ENTETE_IP_CLIENT` à `x-forwarded-for` dans `k8s/deployment.yaml`, et remplace les annotations `nginx.ingress.kubernetes.io/*` par leurs équivalents Traefik. La taille maximale d'un corps de requête doit rester d'au moins 9 Mo.

Crée d'abord l'espace de noms :

```bash
kubectl apply -f k8s/namespace.yaml
```

### 4. Les secrets

Tire les deux jetons et range-les tout de suite dans ton gestionnaire de mots de passe :

```bash
openssl rand -hex 24
```

Lance cette commande deux fois. Le premier résultat sera le jeton d'application, le second la clé d'administration ; ils doivent être différents. Crée ensuite le Secret en remplaçant les deux valeurs :

```bash
kubectl -n cidre-diag create secret generic cidre-diag-jetons --from-literal=JETON_APP=PREMIER_JETON --from-literal=JETON_ADMIN=SECOND_JETON
```

Le serveur refuse de démarrer si les jetons sont absents, trop courts (moins de 16 caractères) ou identiques.

### 5. Le déploiement

```bash
kubectl apply -k k8s/
```

```bash
kubectl -n cidre-diag rollout status deployment/cidre-diag
```

```bash
curl -s https://diag.EXEMPLE.fr/sante
```

La dernière commande doit répondre `ok`. Le certificat peut mettre une ou deux minutes à arriver ; pour suivre son état :

```bash
kubectl -n cidre-diag get certificate
```

### 6. La paire de clés de chiffrement

À faire sur la machine de la coordination. La clé privée ne doit exister nulle part ailleurs.

```bash
mkdir -p ~/.config/cidre-diag && chmod 700 ~/.config/cidre-diag
```

```bash
/usr/bin/openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out ~/.config/cidre-diag/cle_privee.pem
```

```bash
/usr/bin/openssl pkey -in ~/.config/cidre-diag/cle_privee.pem -pubout -out ~/.config/cidre-diag/diag-cle.pem
```

Garde une copie de `cle_privee.pem` dans ton gestionnaire de mots de passe : sans elle, les diagnostics reçus deviennent illisibles. Pour consulter les diagnostics à l'œil depuis un autre poste, tu y choisiras ce fichier dans la page `/consulter`. Ne le commite jamais.

### 7. Ce que Cidre livre, et ce que la coordination garde

À commiter dans le dépôt Cidre. Rien de secret : ces fichiers partent dans le runtime grâce à `tests/empaqueter_runtime.sh`.
- `outil-steam/diag-cle.pem` : la clé **publique**, produite à l'étape 6 ;
- `outil-steam/diag-service.conf`, sur le modèle de `outil-steam/diag-service.conf.exemple` :

```
url=https://diag.EXEMPLE.fr
jeton=PREMIER_JETON
cle=diag-cle.pem
```

À garder sur la machine de la coordination seulement, hors du dépôt, dans `~/.config/cidre-diag/conf` :

```
url=https://diag.EXEMPLE.fr
jeton_admin=SECOND_JETON
cle_privee=~/.config/cidre-diag/cle_privee.pem
```

### 8. Essai

Sur un Mac qui a Cidre, pose la configuration de l'étape 7 : soit avec le runtime livré, soit en copiant `diag-service.conf` et `diag-cle.pem` dans `~/Library/Application Support/Cidre/`. Puis :

```bash
cidre diag service
```

```bash
cidre diag 1137300
```

Réponds `o` : le code s'affiche. Pour le relire côté coordination :

```bash
sh tests/outils/lire_diag.sh CIDRE-XXXX-XX
```

Tu peux aussi ouvrir `https://diag.EXEMPLE.fr/consulter`, y saisir la clé d'administration, choisir `cle_privee.pem`, puis cliquer sur le diagnostic.

## Exploitation

- **Journaux** : `kubectl -n cidre-diag logs deploy/cidre-diag`. Ils ne contiennent aucune donnée de testeur.
- **Sauvegarde** : inutile. Les diagnostics sont jetables, et ils expirent de toute façon au bout de 30 jours.
- **Changer le jeton d'application** : recrée le Secret avec `kubectl -n cidre-diag delete secret cidre-diag-jetons`, puis la commande de l'étape 4. Redémarre ensuite le service avec `kubectl -n cidre-diag rollout restart deployment/cidre-diag`. Enfin, mets à jour `outil-steam/diag-service.conf` et livre. Tant que les Cidre déjà installés ne sont pas mis à jour, ils ne peuvent plus envoyer : ils retombent sur l'archive dans le Finder et le formulaire GitHub.
- **Mettre à jour l'image** : pousse une nouvelle version, change `newTag` dans `k8s/kustomization.yaml`, puis relance `kubectl apply -k k8s/`. Le Deployment est en `Recreate` : comme le volume est en `ReadWriteOnce`, l'ancien pod s'arrête avant que le nouveau démarre.
- **Une seule réplique** : le stockage, le limiteur de débit et le plafond du jour vivent dans ce pod unique. C'est bien assez pour quelques centaines de testeurs.

## Côté coordination

- `lire_diag.sh <CODE>` : télécharge le diagnostic, le déchiffre, vérifie l'empreinte, le déballe dans `~/Dev/diags-recus/<CODE>/` et le résume en 20 lignes (versions, machine, doctor, cause probable, shaders, profil, plantages, système).
- `lire_diag.sh --liste` : les diagnostics des 30 derniers jours.
- `lire_diag.sh --fichier diag-….tar.gz` : une archive reçue autrement, par exemple jointe à un incident GitHub.
- `lire_diag.sh --effacer <CODE>` : efface un diagnostic avant son expiration.

## Alternative : Cloudflare Workers + R2

Le même service tourne sans serveur, avec `worker.js` qui reprend `depot.js`, et le stockage R2. C'est gratuit à cette échelle :
- Workers : 100 000 requêtes par jour, 10 ms de processeur par requête ;
- R2 : 10 Go-mois, 1 M d'écritures par mois, sortie gratuite.

En revanche, R2 exige une carte bancaire au dossier, et la page `/consulter` n'y est pas servie : il ne reste que `lire_diag.sh`. La mise en place, depuis ce dossier :

```bash
npx wrangler@latest login
```

```bash
npx wrangler r2 bucket create cidre-diags
```

```bash
npx wrangler r2 bucket lifecycle add cidre-diags expire-30j --expire-days 30
```

```bash
npx wrangler secret put JETON_APP
```

```bash
npx wrangler secret put JETON_ADMIN
```

```bash
npx wrangler deploy
```

L'URL `https://cidre-diag.<sous-domaine>.workers.dev` va ensuite dans `diag-service.conf`. Le limiteur de débit `[[ratelimits]]` demande Wrangler 4.36 ou plus. Si ton compte le refuse, retire-le de `wrangler.toml` : les autres garde-fous suffisent.

Autres pistes écartées :
- Supabase : un projet gratuit est mis en pause après une semaine sans activité ;
- Deno KV : une valeur fait au plus 64 Kio ;
- S3 + Lambda : la gratuité s'arrête au bout de 12 mois et la configuration IAM est lourde ;
- transfer.sh, gist : publics, sans aucun contrôle des accès.

## Développement

- `node --test test/` : le noyau, le Worker (avec un seau en mémoire) et le serveur du conteneur (stockage sur disque, purge, débit, journaux, pages, ouverture d'une archive).
- `sh tests/tester_diag.sh`, à la racine du dépôt : le circuit complet sur le serveur du conteneur lancé en local. Il couvre le masquage, l'archive chiffrée, le code, `lire_diag.sh` et le déchiffrement par le code de la page `/consulter`.
- Pour lancer le serveur à la main (avec des jetons d'au moins 16 caractères) :

```bash
DONNEES=/tmp/cidre-diag JETON_APP=0123456789abcdefA JETON_ADMIN=0123456789abcdefB ENTETE_IP_CLIENT= node serveur/serveur.mjs
```

La page est alors sur <http://localhost:8080/consulter>.
