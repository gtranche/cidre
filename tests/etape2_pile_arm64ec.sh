#!/bin/sh
# Pile entierement arm64, invite x86_64 : PE Windows x86_64 -> FEX ARM64EC ->
# Wine arm64 -> DXVK -> winevulkan -> chargeur Vulkan arm64 -> KosmicKrisp ->
# Metal. Aucune traduction Rosetta nulle part.
#
#   etape2_pile_arm64ec.sh <programme.exe> [args...]
#
# WINEPREFIX doit exister ; le creer avec « wineboot --init » une premiere fois.
# Tout le corps est entre accolades, ferme par `exit` : le shell lit ainsi le
# fichier ENTIER avant d'executer quoi que ce soit, et n'y revient jamais. Sans
# cela, il lit au fil de l'execution : un fichier modifie pendant qu'un jeu
# tourne (mise a jour, edition) est repris a l'ancien decalage, au milieu d'une
# autre commande -- le 2026-10-13, `cidre play` a ainsi fini dans la
# desinstallation et efface le jeu. tests/tester_profils.sh verifie l'enveloppe.
{
set -e
R=$(cd "$(dirname "$0")/.." && pwd)
WINE=${WINE:-$R/wine/wine11-arm64/bin/wine}
export WINEPREFIX=${WINEPREFIX:-$R/wine/pfx-arm64ec}
export WINEDEBUG=${WINEDEBUG:--all}
# dxgi/d3d11 = DXVK (natif). d3d12/d3d12core : builtin par defaut (CIDRE_D3D12=b)
# -- le d3d12 builtin de Wine tombe proprement en D3D11/DXVK si le jeu demande une
# interface D3D12 recente (cas PEAK : FL 12.1 non supporte par KosmicKrisp -> DX11).
# lancer_depuis_steam.sh pose CIDRE_D3D12=n (natif) quand l'option dx12 est vraie :
# il installe alors vkd3d-proton arm64ec en system32 pour du vrai D3D12 (FL 12.0).
# CIDRE_DLL_OVERRIDES : overrides DLL par jeu (profil dll_overrides), ajoutes aux
# defauts ci-dessus (ex. "xaudio2_9=n" pour un jeu dont l'audio builtin bogue).
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-mscoree,mshtml=;dxgi,d3d11=n;d3d12,d3d12core=${CIDRE_D3D12:-b}}${CIDRE_DLL_OVERRIDES:+;$CIDRE_DLL_OVERRIDES}"
export VK_DRIVER_FILES=$R/prefix/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json
export DYLD_LIBRARY_PATH=$R/wine/vklib-arm64:$R/prefix/lib
export MESA_KK_EXPERIMENTAL=${MESA_KK_EXPERIMENTAL:-custom_border,image_view_min_lod}

# FEX ne detecte pas CRC32/AES/PMULL sur l'hote Apple sous Wine (chemin de detection
# Windows incomplet), donc il n'annonce pas SSE4.2 dans le CPUID invite -- et un jeu qui
# teste ce bit refuse de demarrer (Dead by Daylight : « This CPU does not support a required
# feature (SSE4.2) »). Le CPU Apple a reellement ces instructions ; enablecrypto remet le bit
# a la verite (SSE4.2 + AES-NI + PCLMULQDQ), ce n'est pas un maquillage. Mesure : sonde CPUID
# ECX 0xbcc8330d -> 0xbed8330f. Separe par virgule si on ajoute d'autres drapeaux hote.
export FEX_HOSTFEATURES=${FEX_HOSTFEATURES:-enablecrypto}

# Ce dossier precede les chemins systeme : il sert a presenter les bonnes
# tranches arm64. /usr/local/lib contient un libfreetype x86_64 (la pile
# Rosetta), que dlopen du soname nu trouvait d'abord -- d'ou « Wine cannot find
# the FreeType font library » alors que configure l'avait bien trouve.
mkdir -p "$R/wine/vklib-arm64"
ln -sf "$R/prefix/lib/libvulkan.1.dylib" "$R/wine/vklib-arm64/libMoltenVK.dylib"
# Un runtime installe embarque FreeType dans libs/ (aucun Homebrew requis) ; un
# depot de developpement prend celui de Homebrew. SDL2 : winebus.sys le charge
# par dlopen pour les manettes (sans lui, une manette Xbox 360 vue par macOS
# n'arrive jamais au jeu : winebus laisse les manettes IOHID a SDL).
for l in libfreetype.6.dylib libfontconfig.1.dylib libSDL2-2.0.0.dylib; do
   if [ -f "$R/libs/$l" ]; then ln -sf "$R/libs/$l" "$R/wine/vklib-arm64/$l"
   elif [ -f /opt/homebrew/lib/$l ]; then ln -sf /opt/homebrew/lib/$l "$R/wine/vklib-arm64/$l"
   fi
done
# GStreamer du runtime (prefix/, tests/construire_gstreamer.sh) : winegstreamer
# y decode les videos que les jeux lisent par Media Foundation (.mp4 H.264/AAC
# des cinematiques Unreal 4). Ses plugins seulement -- ni ceux d'un GStreamer
# Homebrew, ni ~/.local -- et un registre a lui, regenere quand le runtime bouge.
if [ -d "$R/prefix/lib/gstreamer-1.0" ]; then
   export GST_PLUGIN_SYSTEM_PATH="$R/prefix/lib/gstreamer-1.0"
   export GST_PLUGIN_SCANNER="$R/prefix/libexec/gstreamer-1.0/gst-plugin-scanner"
   export GST_REGISTRY="$R/wine/gstreamer-registre.bin"
   unset GST_PLUGIN_PATH GST_PLUGIN_PATH_1_0
fi

# FEX est repose a chaque fois : « make install » de Wine remet ses propres
# bouchons xtajit, et la trace dit alors « x64 emulation not implemented ».
sh "$R/tests/installer_fex.sh" >/dev/null

# Langue annoncee par Wine (lancer_depuis_steam.sh, tests/langue_cidre.sh) :
# posee ici, pour Wine seul -- les scripts qui precedent restent en locale C.
# Elle remplace celle que l'appelant a heritee (Steam : LC_ALL=en_US.UTF-8 ;
# Verger : LANG=C.UTF-8), dont Wine aurait tire la locale Windows du jeu.
if [ -n "${CIDRE_LOCALE:-}" ]; then
   export LC_ALL="$CIDRE_LOCALE" LANG="$CIDRE_LOCALE"
   unset LC_CTYPE LC_MESSAGES
fi

# Débogage sous winedbg : si PROTON_OUVERT_WINEDBG pointe un fichier de commandes,
# on lance le programme sous winedbg en lui donnant ce fichier comme entrée (les
# commandes s'exécutent quand winedbg s'arrête sur la faute). Garde-fou : ne change
# rien tant que la variable n'est pas posée.
if [ -n "${PROTON_OUVERT_WINEDBG:-}" ]; then
   exec "$WINE" winedbg "$@" < "$PROTON_OUVERT_WINEDBG"
fi

# Overlay Steam : la bibliotheque que Steam injecte dans un jeu Mac natif, posee
# ici et pas plus haut -- macOS retire les variables DYLD_* a chaque passage par
# /bin/sh, elle doit donc etre exportee par le dernier script avant Wine. Wine se
# re-execute et la variable survit ; les processus enfants du jeu en heritent.
# L'overlay ne dessine que dans -[MTLCommandBuffer presentDrawable:] (Metal 3) ;
# KosmicKrisp presente en Metal 4, sauf si on lui demande de passer par un tampon
# Metal 3 ordonne apres l'image du jeu (correctif 0080, NOTES §312).
# La meme variable retire A2B10G10R10 en SDR (correctif 0173) : l'overlay
# n'a pas de pipeline RGB10A2 : un drawable RGB10A2 (UE4/UE5) virait au bleu.
if [ -n "${CIDRE_OVERLAY_DYLIB:-}" ] && [ -f "$CIDRE_OVERLAY_DYLIB" ]; then
   export DYLD_INSERT_LIBRARIES="$CIDRE_OVERLAY_DYLIB"
   export MESA_WSI_METAL_PRESENT_WITH_COMMAND_BUFFER=1
fi

exec "$WINE" "$@"
exit $?
}
