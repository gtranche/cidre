#!/bin/sh
# Construire GnuTLS et ses dependances dans le prefixe du projet.
#
# Pourquoi : notre Wine etait bati --without-gnutls, donc sans schannel, donc
# aucun invite ne pouvait faire de HTTPS. Mesure au §272 : l'amorceur d'Easy
# Anti-Cheat echoue en « SSL connect error (35) » avant meme d'avoir une chance
# de repondre quoi que ce soit.
#
# Rien n'est installe dans le systeme : tout va dans prefix/, que les scripts de
# lancement mettent deja sur DYLD_LIBRARY_PATH, et que le configure de Wine
# regarde deja via CPPFLAGS/LDFLAGS.
#
# La chaine est imposee : gnutls a besoin de nettle et libtasn1, nettle a besoin
# de GMP. On construit GMP plutot que d'emprunter celui de Homebrew, pour que la
# pile reste dans son dossier.
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
P=$R/prefix
D=$R/src/deps
J=${J:-8}

# pkg-config vient de Homebrew : le retirer du PATH fait echouer le configure de
# gnutls sur « Libnettle 3.6 was not found », alors que nettle est bien installe.
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PKG_CONFIG_PATH=$P/lib/pkgconfig
export CPPFLAGS="-I$P/include"
export LDFLAGS="-L$P/lib"
export MACOSX_DEPLOYMENT_TARGET=11.0
# makeinfo n'est pas installe et ne sert qu'aux manuels.
export MAKEINFO=true

batir()
{
   nom=$1; shift
   src=$D/$nom
   obj=$R/build/$nom
   [ -d "$src" ] || { echo "$nom : sources absentes"; exit 2; }
   echo "=== $nom"
   mkdir -p "$obj"
   ( cd "$obj" && "$src/configure" --prefix="$P" "$@" >configure.log 2>&1 ) || {
      echo "  configure a echoue, fin du journal :"; tail -20 "$obj/configure.log"; exit 1; }
   ( cd "$obj" && make -j"$J" >make.log 2>&1 ) || {
      echo "  make a echoue, fin du journal :"; tail -25 "$obj/make.log"; exit 1; }
   ( cd "$obj" && make install >install.log 2>&1 ) || {
      echo "  install a echoue :"; tail -15 "$obj/install.log"; exit 1; }
   echo "  ok"
}

batir gmp-6.3.0        --disable-static --enable-shared --enable-cxx=no
batir nettle-3.10.1    --disable-static --enable-shared --disable-documentation \
                       --with-include-path="$P/include" --with-lib-path="$P/lib"
batir libtasn1-4.19.0  --disable-static --enable-shared --disable-doc
batir gnutls-3.8.8     --disable-static --enable-shared --disable-doc --disable-tests \
                       --disable-tools --disable-cxx --disable-guile --disable-nls \
                       --without-p11-kit --without-idn --without-tpm --without-tpm2 \
                       --without-zlib --without-brotli --without-zstd \
                       --with-included-unistring --disable-full-test-suite

echo
echo "=== verification : architecture et dependances"
for l in libgmp libnettle libhogweed libtasn1 libgnutls; do
   f=$(ls "$P"/lib/$l*.dylib 2>/dev/null | head -1)
   [ -n "$f" ] || { echo "  $l : ABSENT"; continue; }
   printf "  %-12s %s\n" "$(basename "$f")" "$(file -b "$f" | sed 's/Mach-O 64-bit dynamically linked shared library //')"
done
echo
echo "gnutls installe dans $P ; Wine peut maintenant etre reconstruit sans --without-gnutls"
