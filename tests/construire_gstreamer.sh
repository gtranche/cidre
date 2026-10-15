#!/bin/sh
# Construire GStreamer (arm64, perimetre minimal) dans le prefixe du projet, pour
# winegstreamer : les videos que les jeux lisent par Media Foundation (.mp4 en
# H.264/AAC, cinematiques d'Unreal 4 par WmfMedia, etc.).
#
# Pourquoi : notre Wine etait bati --without-gstreamer --without-ffmpeg. Dans Wine
# 11, le demultiplexeur .mp4 passe par winedmo (FFmpeg) ou, a defaut, par
# winegstreamer, et le decodeur H.264/AAC n'existe que dans winegstreamer : aucune
# video Media Foundation ne pouvait jouer. Mesure (2026-10-15, Sherlock Holmes
# Chapter One, SH9/Content/Movies/UE4_Logo.mp4) : MFCreateSourceReaderFromURL
# rendait MF_E_UNSUPPORTED_BYTESTREAM_TYPE (0xc00d36c4) ; avec ce GStreamer, 100
# images et 157 echantillons audio decodes en 2 s. Le jeu restait sur un ecran noir.
#
# Meme perimetre que le GStreamer de CrossOver 25, sans libav : H.264/HEVC par
# VideoToolbox et AAC par AudioToolbox (plugin applemedia), demultiplexage par
# isomp4 (et avi, asf, wav), plus les elements que winegstreamer cree lui-meme
# (decodebin, videoconvert, videoflip, deinterlace, audioconvert, audioresample).
#
# Rien n'est installe dans le systeme : tout va dans prefix/, deja sur le
# DYLD_LIBRARY_PATH des scripts de lancement ; glib vient de Homebrew (brew
# install glib) et empaqueter_runtime.sh l'embarque. Le configure de Wine trouve
# ce GStreamer par pkg-config (construire_pile_arm64.sh).
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
P=${CIDRE_PREFIXE_GST:-$R/prefix}
D=$R/src/deps
V=1.24.12
J=${J:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}

# bison >= 2.4 (celui de macOS est en 2.3), meson et ninja du projet.
export PATH="$R/toolchain/bin:/opt/homebrew/opt/bison/bin:/usr/local/opt/bison/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PKG_CONFIG_PATH="$P/lib/pkgconfig:/opt/homebrew/lib/pkgconfig"
export MACOSX_DEPLOYMENT_TARGET=11.0
# Compilateur arm64 explicite : un ninja ou un shell sous Rosetta construirait
# sinon en x86_64, que le Wine arm64 ne peut pas charger.
export CC="xcrun clang -arch arm64" CXX="xcrun clang++ -arch arm64" OBJC="xcrun clang -arch arm64"

# Archives officielles, verifiees par leur somme SHA-256 publiee.
mkdir -p "$D"
while read -r somme nom; do
   a="$D/$nom-$V.tar.xz"
   if [ ! -f "$a" ] || ! echo "$somme  $a" | shasum -a 256 -c >/dev/null 2>&1; then
      echo "=== telechargement $nom-$V"
      # Le serveur de GStreamer coupe souvent les transferts : on reprend.
      n=0
      until curl --http1.1 -fsSL -C - -o "$a" "https://gstreamer.freedesktop.org/src/$nom/$nom-$V.tar.xz" &&
            echo "$somme  $a" | shasum -a 256 -c >/dev/null 2>&1; do
         n=$((n+1)); [ $n -lt 30 ] || { echo "  $nom : telechargement impossible"; exit 1; }
         sleep 3
      done
   fi
   [ -d "$D/$nom-$V" ] || tar -xJf "$a" -C "$D"
done <<EOF
b3522d1b4fe174fff3b3c7f0603493e2367bd1c43f5804df15b634bd22b1036f gstreamer
f6efbaa8fea8d00bc380bccca76a530527b1f083e8523eafb3e9b1e18bc653d3 gst-plugins-base
d0e66e2f935d1575f6adbef7d0a2b3faba7360344383c51bf0233b39e0489a64 gst-plugins-good
3d386af3d1dbd1a06c74a6251250c269b481e703f0e3255ba89ef6c1e063afea gst-plugins-bad
EOF

commun="--prefix=$P --libdir=lib --buildtype=release -Dauto_features=disabled
   -Dtests=disabled -Dexamples=disabled -Ddoc=disabled -Dnls=disabled"
batir()
{
   nom=$1; shift
   obj=$R/build/$nom-$V
   echo "=== $nom"
   if [ ! -f "$obj/build.ninja" ]; then
      meson setup "$obj" "$D/$nom-$V" $commun "$@" >"$obj.setup.log" 2>&1 || {
         echo "  configuration echouee, fin du journal :"; tail -20 "$obj.setup.log"; exit 1; }
   fi
   ninja -C "$obj" -j"$J" >"$obj.log" 2>&1 || { echo "  echec, fin du journal :"; tail -25 "$obj.log"; exit 1; }
   ninja -C "$obj" install >/dev/null
   echo "  ok"
}

batir gstreamer -Dintrospection=disabled -Dtools=enabled -Dgst_debug=true -Dcheck=disabled \
   -Dbenchmarks=disabled -Dlibunwind=disabled -Dlibdw=disabled -Dbash-completion=disabled \
   -Dcoretracers=disabled
# GstGL (Cocoa/CGL) : applemedia en a besoin pour vtdec.
batir gst-plugins-base -Dintrospection=disabled -Dtools=disabled -Dorc=disabled \
   -Dgl=enabled -Dgl_api=opengl -Dgl_platform=cgl -Dgl_winsys=cocoa \
   -Dgl-graphene=disabled -Dgl-jpeg=disabled -Dgl-png=disabled \
   -Dapp=enabled -Daudioconvert=enabled -Daudioresample=enabled -Dplayback=enabled \
   -Dtypefind=enabled -Dvideoconvertscale=enabled -Dvideorate=enabled -Dvolume=enabled
batir gst-plugins-good -Dorc=disabled \
   -Disomp4=enabled -Daudioparsers=enabled -Dwavparse=enabled -Did3demux=enabled \
   -Ddeinterlace=enabled -Dvideofilter=enabled -Davi=enabled -Dautodetect=enabled
batir gst-plugins-bad -Dintrospection=disabled -Dorc=disabled -Dgl=enabled \
   -Dapplemedia=enabled -Dvideoparsers=enabled

echo
echo "=== verification : architecture et elements utiles a winegstreamer"
file -b "$P/lib/libgstreamer-1.0.0.dylib"
G="GST_PLUGIN_SYSTEM_PATH=$P/lib/gstreamer-1.0 GST_PLUGIN_SCANNER=$P/libexec/gstreamer-1.0/gst-plugin-scanner GST_REGISTRY=$R/build/gstreamer-registre-verif.bin"
manque=
for e in decodebin videoconvert videoflip deinterlace audioconvert audioresample qtdemux h264parse vtdec atdec; do
   env $G "$P/bin/gst-inspect-1.0" "$e" >/dev/null 2>&1 || manque="$manque $e"
done
[ -z "$manque" ] || { echo "  elements absents :$manque"; exit 1; }
echo "  tous presents"
echo
echo "GStreamer $V installe dans $P ; Wine peut maintenant etre reconstruit avec winegstreamer"
