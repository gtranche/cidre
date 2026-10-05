/* cidre-outil : ce que le script `cidre` ne sait pas faire en sh.
 *
 *    cidre-outil session <steamcmd.sh> <arguments de SteamCMD...>
 *    cidre-outil bibliotheque [--texte] <licences.txt> [appid installe ...]
 *
 * Livre construit dans le runtime (build/cidre-outil) : un Mac sans outils de
 * developpement n'a ni Python ni compilateur, et `/usr/bin/python3` n'y est
 * qu'un relais qui propose de les installer.
 *
 * session -- lance SteamCMD sur la session memorisee, sans jamais tenter de mot
 * de passe. Sans session memorisee, SteamCMD demande un mot de passe ; si
 * personne ne peut repondre (entree fermee), il envoie un mot de passe vide, et
 * c'est une tentative de connexion ratee sur le compte. Ici on lui prete un
 * terminal, on relaie sa sortie, et s'il demande un mot de passe on l'arrete
 * AVANT qu'il n'essaie : code de retour 3, « pas de session ». Sinon, son propre
 * code de retour. Le terminal a un second interet : SteamCMD n'ecrit ligne a
 * ligne que sur un terminal, et l'avancement d'un telechargement arrive alors au
 * fil de l'eau.
 *
 * bibliotheque -- les jeux que possede le compte Steam, en JSON (pour `cidre
 * library`). licences.txt est la sortie de `steamcmd +login <compte>
 * +licenses_print` : elle dit quels paquets le compte possede, et les
 * applications de chacun. Les noms, types et plateformes viennent du cache du
 * client Steam (appcache/appinfo.vdf, format binaire v27 a v29), qu'on lit sans
 * rien y ecrire. SteamCMD tronque la liste d'applications des gros paquets : on
 * la complete par packageinfo.vdf.
 */
#include <ctype.h>
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/wait.h>
#include <unistd.h>
#include <util.h>
#include <wctype.h>
#include <xlocale.h>

/* ------------------------------------------------------------------ session */

static const char *const PAS_DE_SESSION[] = { "cached credentials not found", "password:" };
enum { MEMOIRE = 200, BLOC = 4096 };

static int cmd_session(char **argv)
{
   int maitre;
   pid_t pid = forkpty(&maitre, NULL, NULL, NULL);
   if (pid < 0) {
      perror("forkpty");
      return 1;
   }
   if (pid == 0) {
      execv(argv[0], argv);
      perror(argv[0]);
      _exit(127);
   }

   /* les derniers octets vus, en minuscules : un message peut arriver coupe
    * entre deux lectures */
   char vu[MEMOIRE + BLOC];
   size_t nvu = 0;
   int sans_session = 0;
   while (!sans_session) {
      char bloc[BLOC];
      ssize_t n = read(maitre, bloc, sizeof bloc);
      if (n < 0 && errno == EINTR)
         continue;
      if (n <= 0)
         break;
      for (ssize_t fait = 0; fait < n;) {
         ssize_t e = write(STDOUT_FILENO, bloc + fait, (size_t)(n - fait));
         if (e < 0 && errno == EINTR)
            continue;
         if (e < 0)
            _exit(1);
         fait += e;
      }
      for (ssize_t i = 0; i < n; i++)
         vu[nvu++] = (char)tolower((unsigned char)bloc[i]);
      for (size_t m = 0; m < sizeof PAS_DE_SESSION / sizeof *PAS_DE_SESSION; m++)
         if (memmem(vu, nvu, PAS_DE_SESSION[m], strlen(PAS_DE_SESSION[m])))
            sans_session = 1;
      if (nvu > MEMOIRE) {
         memmove(vu, vu + nvu - MEMOIRE, MEMOIRE);
         nvu = MEMOIRE;
      }
   }
   /* Tout le groupe (steamcmd.sh et le binaire qu'il a lance), et on lache le
    * terminal : un processus qui sort attend que sa sortie soit lue, et
    * resterait bloque a mi-chemin si on gardait le terminal sans le lire. */
   if (sans_session)
      killpg(pid, SIGKILL);
   close(maitre);
   int etat = 0;
   while (waitpid(pid, &etat, 0) < 0 && errno == EINTR)
      ;
   if (sans_session)
      return 3;
   return WIFEXITED(etat) ? WEXITSTATUS(etat) : 1;
}

/* ------------------------------------------------------------- bibliotheque */

static void *memoire(void *p, size_t n)
{
   p = realloc(p, n ? n : 1);
   if (!p) {
      perror("cidre-outil");
      exit(1);
   }
   return p;
}

/* un ensemble d'identifiants : on y verse, on trie, puis on cherche */
typedef struct {
   uint32_t *v;
   size_t n, cap;
} Ens;

static void ens_ajoute(Ens *e, uint32_t x)
{
   if (e->n == e->cap)
      e->v = memoire(e->v, (e->cap = e->cap ? e->cap * 2 : 256) * sizeof *e->v);
   e->v[e->n++] = x;
}

static int cmp_u32(const void *a, const void *b)
{
   uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
   return (x > y) - (x < y);
}

static void ens_trie(Ens *e)
{
   size_t n = 0;
   qsort(e->v, e->n, sizeof *e->v, cmp_u32);
   for (size_t i = 0; i < e->n; i++)
      if (n == 0 || e->v[n - 1] != e->v[i])
         e->v[n++] = e->v[i];
   e->n = n;
}

static int ens_contient(const Ens *e, uint32_t x)
{
   return e->n && bsearch(&x, e->v, e->n, sizeof *e->v, cmp_u32) != NULL;
}

/* les nombres d'un texte, jusqu'a `fin` */
static void ens_ajoute_nombres(Ens *e, const char *s, const char *fin)
{
   while (s < fin) {
      if (!isdigit((unsigned char)*s)) {
         s++;
         continue;
      }
      unsigned long long x = 0;
      for (; s < fin && isdigit((unsigned char)*s); s++)
         if (x <= UINT32_MAX)
            x = x * 10 + (unsigned)(*s - '0');
      if (x <= UINT32_MAX)
         ens_ajoute(e, (uint32_t)x);
   }
}

/* un fichier entier en memoire, suivi d'un octet nul ; NULL s'il est illisible */
static unsigned char *lire_fichier(const char *chemin, size_t *taille)
{
   FILE *f = fopen(chemin, "rb");
   if (!f)
      return NULL;
   size_t n = 0, cap = 1 << 16;
   unsigned char *d = memoire(NULL, cap + 1);
   for (size_t lu; (lu = fread(d + n, 1, cap - n, f)) > 0;)
      if ((n += lu) == cap)
         d = memoire(d, (cap *= 2) + 1);
   int erreur = ferror(f);
   fclose(f);
   if (erreur) {
      free(d);
      return NULL;
   }
   d[n] = 0;
   *taille = n;
   return d;
}

static uint32_t u32(const unsigned char *p)
{
   uint32_t x;
   memcpy(&x, p, sizeof x);
   return x; /* petit-boutiste, comme le fichier */
}

static int64_t i64(const unsigned char *p)
{
   int64_t x;
   memcpy(&x, p, sizeof x);
   return x;
}

/* Lecture d'un dictionnaire VDF binaire, sans construire d'arbre : chaque cle
 * est presentee a `visite`, avec la profondeur du dictionnaire qui la porte
 * (0 = racine) et les cles des dictionnaires qui l'entourent. */
enum { VDF_DICT = 0x00, VDF_CHAINE = 0x01, VDF_ENTIER = 0x02, PROF_MAX = 64 };

typedef struct Lecteur Lecteur;
struct Lecteur {
   const unsigned char *d;
   size_t pos, fin;
   const char **table; /* v29 : les cles sont des indices dans cette table */
   uint32_t ntable;
   const char *cles[PROF_MAX];
   unsigned rang; /* rang (depuis 1) de la cle de la racine en cours */
   void (*visite)(Lecteur *, int prof, const char *cle, int type, const char *chaine, int64_t entier);
   void *ctx;
};

static const char *vdf_chaine(Lecteur *L)
{
   const unsigned char *s = L->d + L->pos;
   const unsigned char *nul = memchr(s, 0, L->fin - L->pos);
   if (!nul)
      return NULL;
   L->pos = (size_t)(nul - L->d) + 1;
   return (const char *)s;
}

static int vdf_lire(Lecteur *L, int prof)
{
   for (;;) {
      if (L->pos >= L->fin)
         return -1;
      unsigned char t = L->d[L->pos++];
      if (t == 0x08 || t == 0x0B)
         return 0;
      const char *cle;
      if (L->table) {
         if (L->fin - L->pos < 4)
            return -1;
         uint32_t i = u32(L->d + L->pos);
         L->pos += 4;
         if (i >= L->ntable)
            return -1;
         cle = L->table[i];
      } else if (!(cle = vdf_chaine(L)))
         return -1;
      if (prof == 0)
         L->rang++;
      switch (t) {
      case 0x00:
         if (prof + 1 >= PROF_MAX)
            return -1;
         L->visite(L, prof, cle, VDF_DICT, NULL, 0);
         L->cles[prof] = cle;
         if (vdf_lire(L, prof + 1))
            return -1;
         break;
      case 0x01: {
         const char *s = vdf_chaine(L);
         if (!s)
            return -1;
         L->visite(L, prof, cle, VDF_CHAINE, s, 0);
         break;
      }
      case 0x02:
      case 0x03:
         if (L->fin - L->pos < 4)
            return -1;
         L->visite(L, prof, cle, VDF_ENTIER, NULL, (int32_t)u32(L->d + L->pos));
         L->pos += 4;
         break;
      case 0x07:
      case 0x0A:
         if (L->fin - L->pos < 8)
            return -1;
         L->visite(L, prof, cle, VDF_ENTIER, NULL, i64(L->d + L->pos));
         L->pos += 8;
         break;
      default:
         return -1; /* type VDF inconnu */
      }
   }
}

/* packageinfo.vdf : les applications des paquets a completer. Le corps d'un
 * paquet est le premier dictionnaire de sa racine ; ses applications y sont
 * sous `appids`. */
static void visite_paquet(Lecteur *L, int prof, const char *cle, int type, const char *chaine, int64_t entier)
{
   (void)cle, (void)chaine;
   if (type == VDF_ENTIER && prof == 2 && L->rang == 1 && !strcmp(L->cles[1], "appids") &&
       entier >= 0 && entier <= UINT32_MAX)
      ens_ajoute(L->ctx, (uint32_t)entier);
}

/* Verse dans `possedes` les applications des paquets `a_completer`. Un fichier
 * illisible ou abime ne donne rien du tout. */
static void lire_paquets(const char *chemin, const Ens *a_completer, Ens *possedes)
{
   size_t n;
   unsigned char *d = lire_fichier(chemin, &n);
   if (!d)
      return;
   Ens trouves = { 0 }, ignores = { 0 };
   uint32_t magie = n >= 8 ? u32(d) : 0, version = magie & 0xFF;
   int ok = magie >> 8 == 0x065655 && (version == 0x27 || version == 0x28);
   size_t pos = 8;
   while (ok) {
      if (n - pos < 4) {
         ok = 0;
         break;
      }
      uint32_t pid = u32(d + pos);
      if (pid == 0xFFFFFFFF)
         break;
      /* apres l'identifiant : sha1, numero de changement, et (v28) jeton */
      pos += 4 + 20 + 4 + (version == 0x28 ? 8 : 0);
      if (pos > n) {
         ok = 0;
         break;
      }
      Lecteur L = { .d = d, .pos = pos, .fin = n, .visite = visite_paquet };
      L.ctx = ens_contient(a_completer, pid) ? &trouves : &ignores;
      ignores.n = 0;
      if (vdf_lire(&L, 0))
         ok = 0;
      pos = L.pos;
   }
   if (ok)
      for (size_t i = 0; i < trouves.n; i++)
         ens_ajoute(possedes, trouves.v[i]);
   free(trouves.v);
   free(ignores.v);
   free(d);
}

/* ce qu'on retient de la section `common` d'une application */
typedef struct {
   const char *nom, *type, *os;
} Commun;

typedef struct {
   Commun sous_appinfo, racine; /* appinfo/common, ou common a la racine */
   int a_appinfo;
} Fiche;

static void visite_appinfo(Lecteur *L, int prof, const char *cle, int type, const char *chaine, int64_t entier)
{
   (void)entier;
   Fiche *f = L->ctx;
   Commun *c = NULL;
   if (prof == 0 && type == VDF_DICT && !strcmp(cle, "appinfo"))
      f->a_appinfo = 1;
   if (prof == 2 && !strcmp(L->cles[0], "appinfo") && !strcmp(L->cles[1], "common"))
      c = &f->sous_appinfo;
   else if (prof == 1 && !strcmp(L->cles[0], "common"))
      c = &f->racine;
   if (!c || type != VDF_CHAINE)
      return;
   if (!strcmp(cle, "name"))
      c->nom = chaine;
   else if (!strcmp(cle, "type"))
      c->type = chaine;
   else if (!strcmp(cle, "oslist"))
      c->os = chaine;
}

typedef struct {
   uint32_t appid;
   Commun c;
   int windows, macos; /* rang dans la liste (1, 2), 0 = absent */
   uint32_t *cle;      /* le nom en minuscules, point de code par point de code */
   size_t ncle;
} Jeu;

typedef struct {
   Jeu *v;
   size_t n, cap;
} Jeux;

/* La section `common` des applications voulues, dans l'ordre du fichier.
 * Rend 0, ou -1 (message ecrit) si le fichier n'est pas celui qu'on attend. */
static int lire_appinfo(const char *chemin, const Ens *voulus, Jeux *jeux)
{
   size_t n;
   unsigned char *d = lire_fichier(chemin, &n);
   if (!d) {
      perror(chemin);
      return -1;
   }
   uint32_t magie = n >= 8 ? u32(d) : 0, version = magie & 0xFF;
   if (magie >> 8 != 0x075644 || version < 0x27 || version > 0x29) {
      fprintf(stderr, "appinfo.vdf : format inconnu (%#x)\n", magie);
      return -1;
   }
   size_t pos = 8, limite = n;
   const char **table = NULL;
   uint32_t ntable = 0;
   if (version == 0x29) {
      /* v29 : les cles sont rangees une fois pour toutes en fin de fichier */
      int64_t debut = n >= 16 ? i64(d + 8) : -1;
      if (debut < 16 || (uint64_t)debut > n - 4)
         goto tronque;
      pos = 16;
      limite = (size_t)debut;
      ntable = u32(d + debut);
      table = memoire(NULL, (size_t)ntable * sizeof *table);
      const unsigned char *s = d + debut + 4;
      for (uint32_t i = 0; i < ntable; i++) {
         const unsigned char *nul = s < d + n ? memchr(s, 0, (size_t)(d + n - s)) : NULL;
         if (!nul)
            goto tronque;
         table[i] = (const char *)s;
         s = nul + 1;
      }
   }
   /* entete d'une entree, apres appid et taille : etat, date, jeton, sha1,
    * numero de changement, et (v28+) sha1 binaire */
   size_t entete = 4 + 4 + 8 + 20 + 4 + (version >= 0x28 ? 20 : 0);
   for (;;) {
      if (limite - pos < 4)
         goto tronque;
      uint32_t appid = u32(d + pos);
      if (appid == 0)
         return 0; /* `d` et `table` restent : les fiches pointent dedans */
      if (limite - pos < 8)
         goto tronque;
      size_t taille = u32(d + pos + 4);
      size_t fin = taille < limite - pos - 8 ? pos + 8 + taille : limite;
      if (ens_contient(voulus, appid) && fin - pos - 8 > entete) {
         Fiche f = { 0 };
         Lecteur L = { .d = d, .pos = pos + 8 + entete, .fin = fin, .table = table,
                       .ntable = ntable, .visite = visite_appinfo, .ctx = &f };
         if (vdf_lire(&L, 0) == 0) {
            size_t i = 0;
            while (i < jeux->n && jeux->v[i].appid != appid)
               i++;
            if (i == jeux->n) {
               if (jeux->n == jeux->cap)
                  jeux->v = memoire(jeux->v, (jeux->cap = jeux->cap ? jeux->cap * 2 : 256) * sizeof *jeux->v);
               jeux->n++;
            }
            jeux->v[i] = (Jeu){ .appid = appid, .c = f.a_appinfo ? f.sous_appinfo : f.racine };
         }
      }
      if (taille > limite - pos - 8)
         goto tronque;
      pos += 8 + taille;
   }
tronque:
   fprintf(stderr, "appinfo.vdf : fichier tronque\n");
   return -1;
}

/* Le point de code UTF-8 en s[*i], et avance. Une suite invalide rend U+FFFD
 * et n'avale que ce qui etait mal forme. */
static uint32_t utf8_lire(const unsigned char *s, size_t *i)
{
   unsigned char c = s[(*i)++], bas = 0x80, haut = 0xBF;
   uint32_t cp;
   int suite;
   if (c < 0x80)
      return c;
   if (c >= 0xC2 && c <= 0xDF) {
      suite = 1;
      cp = c & 0x1F;
   } else if (c >= 0xE0 && c <= 0xEF) {
      suite = 2;
      cp = c & 0x0F;
      if (c == 0xE0)
         bas = 0xA0;
      if (c == 0xED)
         haut = 0x9F;
   } else if (c >= 0xF0 && c <= 0xF4) {
      suite = 3;
      cp = c & 0x07;
      if (c == 0xF0)
         bas = 0x90;
      if (c == 0xF4)
         haut = 0x8F;
   } else
      return 0xFFFD;
   while (suite--) {
      if (s[*i] < bas || s[*i] > haut)
         return 0xFFFD;
      cp = cp << 6 | (s[(*i)++] & 0x3F);
      bas = 0x80;
      haut = 0xBF;
   }
   return cp;
}

static void utf8_ecrire(uint32_t cp)
{
   if (cp < 0x80)
      putchar((int)cp);
   else if (cp < 0x800)
      printf("%c%c", 0xC0 | cp >> 6, 0x80 | (cp & 0x3F));
   else if (cp < 0x10000)
      printf("%c%c%c", 0xE0 | cp >> 12, 0x80 | (cp >> 6 & 0x3F), 0x80 | (cp & 0x3F));
   else
      printf("%c%c%c%c", 0xF0 | cp >> 18, 0x80 | (cp >> 12 & 0x3F), 0x80 | (cp >> 6 & 0x3F), 0x80 | (cp & 0x3F));
}

static void json_chaine(const char *s)
{
   const unsigned char *u = (const unsigned char *)s;
   putchar('"');
   for (size_t i = 0; u[i];) {
      uint32_t cp = utf8_lire(u, &i);
      switch (cp) {
      case '"': fputs("\\\"", stdout); break;
      case '\\': fputs("\\\\", stdout); break;
      case '\n': fputs("\\n", stdout); break;
      case '\r': fputs("\\r", stdout); break;
      case '\t': fputs("\\t", stdout); break;
      case '\b': fputs("\\b", stdout); break;
      case '\f': fputs("\\f", stdout); break;
      default:
         if (cp < 0x20)
            printf("\\u%04x", (unsigned)cp);
         else
            utf8_ecrire(cp);
      }
   }
   putchar('"');
}

/* ordre alphabetique sans tenir compte de la casse ; a nom egal, l'ordre du
 * fichier (le tri est stable) */
static int cmp_jeu(const void *a, const void *b)
{
   const Jeu *x = a, *y = b;
   for (size_t i = 0; i < x->ncle && i < y->ncle; i++)
      if (x->cle[i] != y->cle[i])
         return x->cle[i] < y->cle[i] ? -1 : 1;
   return (x->ncle > y->ncle) - (x->ncle < y->ncle);
}

static int cmd_bibliotheque(int argc, char **argv)
{
   int texte = argc > 0 && !strcmp(argv[0], "--texte");
   if (texte)
      argc--, argv++;
   if (argc < 1)
      return 2;

   size_t n;
   char *licences = (char *)lire_fichier(argv[0], &n);
   if (!licences) {
      perror(argv[0]);
      return 1;
   }
   Ens installes = { 0 }, possedes = { 0 }, a_completer = { 0 };
   for (int i = 1; i < argc; i++)
      if (argv[i][0] && strspn(argv[i], "0123456789") == strlen(argv[i]))
         ens_ajoute_nombres(&installes, argv[i], argv[i] + strlen(argv[i]));
   ens_trie(&installes);

   /* Une licence : « License packageID <n>: », puis plus bas « - Apps : ... »,
    * la liste (peut-etre tronquee par « ... ») suivie de « (<n> in total) ». */
   int en_attente = 0;
   uint32_t paquet = 0;
   for (char *l = licences, *fin; l < licences + n; l = fin + 1) {
      fin = memchr(l, '\n', (size_t)(licences + n - l));
      if (!fin)
         fin = licences + n;
      *fin = 0;
      if (!en_attente) {
         static const char debut[] = "License packageID ";
         char *p = l + sizeof debut - 1, *q;
         if (strncmp(l, debut, sizeof debut - 1) || !isdigit((unsigned char)*p))
            continue;
         unsigned long long x = strtoull(p, &q, 10);
         if (*q != ':')
            continue;
         paquet = x <= UINT32_MAX ? (uint32_t)x : UINT32_MAX;
         en_attente = 1;
      } else if (!strncmp(l, " - Apps", 7)) {
         char *p = l + 7;
         while (*p == ' ' || *p == '\t' || *p == '\r')
            p++;
         if (*p != ':')
            continue;
         char *parenthese = strchr(p, '(');
         ens_ajoute_nombres(&possedes, p, parenthese ? parenthese : fin);
         if (strstr(p, "..."))
            ens_ajoute(&a_completer, paquet);
         en_attente = 0;
      }
   }

   const char *home = getenv("HOME");
   char chemin[4096];
   if (a_completer.n) {
      ens_trie(&a_completer);
      snprintf(chemin, sizeof chemin, "%s/Library/Application Support/Steam/appcache/packageinfo.vdf", home ? home : "");
      lire_paquets(chemin, &a_completer, &possedes);
   }
   ens_trie(&possedes);

   Jeux jeux = { 0 };
   snprintf(chemin, sizeof chemin, "%s/Library/Application Support/Steam/appcache/appinfo.vdf", home ? home : "");
   if (lire_appinfo(chemin, &possedes, &jeux))
      return 1;

   /* on garde les jeux, sur Windows ou macOS */
   locale_t utf8 = newlocale(LC_CTYPE_MASK, "en_US.UTF-8", NULL);
   size_t gardes = 0;
   for (size_t i = 0; i < jeux.n; i++) {
      Jeu j = jeux.v[i];
      if (!j.c.type || strcasecmp(j.c.type, "game") || !j.c.nom || !*j.c.nom)
         continue;
      /* sans oslist, Steam considere le jeu comme Windows */
      const char *os = j.c.os && *j.c.os ? j.c.os : "windows";
      int rang = 0;
      for (const char *p = os;; p += strcspn(p, ",") + 1) {
         size_t l = strcspn(p, ",");
         if (l == 7 && !strncmp(p, "windows", l) && !j.windows)
            j.windows = ++rang;
         else if (l == 5 && !strncmp(p, "macos", l) && !j.macos)
            j.macos = ++rang;
         if (!p[l])
            break;
      }
      if (!rang)
         continue;
      const unsigned char *u = (const unsigned char *)j.c.nom;
      j.cle = memoire(NULL, strlen(j.c.nom) * sizeof *j.cle);
      for (size_t k = 0; u[k];) {
         uint32_t cp = utf8_lire(u, &k);
         j.cle[j.ncle++] = utf8 ? (uint32_t)towlower_l((wint_t)cp, utf8) : cp < 0x80 ? (uint32_t)tolower((int)cp) : cp;
      }
      jeux.v[gardes++] = j;
   }
   mergesort(jeux.v, gardes, sizeof *jeux.v, cmp_jeu);

   if (texte)
      printf("%-9s %-40s %-15s %s\n", "APPID", "JEU", "PLATEFORMES", "INSTALLE");
   else
      putchar('[');
   for (size_t i = 0; i < gardes; i++) {
      const Jeu *j = &jeux.v[i];
      const char *premier = j->windows == 1 ? "windows" : "macos";
      const char *second = j->windows == 2 ? "windows" : j->macos == 2 ? "macos" : NULL;
      int installe = ens_contient(&installes, j->appid);
      if (texte) {
         /* le nom sur 40 colonnes : coupe et complete en caracteres, pas en octets */
         const unsigned char *u = (const unsigned char *)j->c.nom;
         int colonnes = 0;
         char os[16];
         printf("%-9u ", j->appid);
         for (size_t k = 0; u[k] && colonnes < 40; colonnes++)
            utf8_ecrire(utf8_lire(u, &k));
         snprintf(os, sizeof os, "%s%s%s", premier, second ? "," : "", second ? second : "");
         printf("%*s %-15s %s\n", 40 - colonnes, "", os, installe ? "oui" : "");
      } else {
         printf("%s{\"appid\": %u, \"nom\": ", i ? ", " : "", j->appid);
         json_chaine(j->c.nom);
         printf(", \"plateformes\": [\"%s\"", premier);
         if (second)
            printf(", \"%s\"", second);
         printf("], \"installe\": %s}", installe ? "true" : "false");
      }
   }
   if (!texte)
      puts("]");
   return fflush(stdout) || ferror(stdout) ? 1 : 0;
}

int main(int argc, char **argv)
{
   if (argc >= 3 && !strcmp(argv[1], "session"))
      return cmd_session(argv + 2);
   if (argc >= 3 && !strcmp(argv[1], "bibliotheque"))
      return cmd_bibliotheque(argc - 2, argv + 2);
   fprintf(stderr, "usage: cidre-outil session <steamcmd.sh> <arguments...>\n"
                   "       cidre-outil bibliotheque [--texte] <licences.txt> [appid installe ...]\n");
   return 2;
}
