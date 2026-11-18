#!/bin/sh
# Cle de code figee de KosmicKrisp (KK_CODEGEN_FIGE, correctif 0464 ; INTEGRATION_D4.md).
#
# La cle des caches de nuanceurs (0208) suit l'empreinte des sources qui font le code. Les correctifs 0464-0494
# touchent kk_shader.c (hache) sans changer ni le MSL ni le format serialise : le pilote du joueur de Diablo IV
# (kk-0494) est construit avec l'empreinte figee a celle de kk-I4f, et ses caches (plusieurs Gio, des heures de
# compilation) restent valables. Figer n'est juste que si les sources hachees sont celles qu'on a verifiees :
# empreinte calculee 1fbdc554... (kk-0494, 11/11). Au-dela, un correctif qui change le code servirait de vieux
# nuanceurs : la cle doit alors etre recalculee (CIDRE_KK_CODEGEN_FIGE=0) ou figee a nouveau apres verification.
#
#   cle_kk_figee.sh valeur              la valeur a exporter dans KK_CODEGEN_FIGE (vide : ne pas figer)
#   cle_kk_figee.sh verifier <build>    apres ninja : l'empreinte calculee est-elle celle qui a ete verifiee ?
#                                       (code 3 et message sinon)
FIGEE=fe23de315cfc449df36f16d2b4403b2b4a878b55b525ef4a820858646fa9c728
# 12/11 : 0492 coupe par defaut (CIDRE_FOND_FROIDS=1 pour l'activer) : seul changement des sources hachees depuis
# kk-0494 (1fbdc554...), une ligne d'ordonnancement de kk_shader.c, sans effet sur le MSL ni le format serialise.
# 13/11 : 0495 (NAN_STRICT) : sous CIDRE_NAN_STRICT=1, code et UUID de cache de pipelines identiques a avant (verifie
# par vulkaninfo : c1f4526f... des deux cotes) ; sans lui, bit 63 des contournements : cles nouvelles.
# 18/11 : 0498 (variantes connues en QoS haute, reserve AIR indexee) : ordonnancement de kkvar et compteurs seulement
# dans kk_shader.c, ni MSL ni format serialise touches ; partie D4 du 18/11 (26,5 min, caches du joueur reutilises,
# rendu normal). Comparaison des UUID vulkaninfo non faite.
CALCULEE_VERIFIEE=0cd6be94580bb977dddf002a66b7ad6cdb0c6a3530e01d85fe75cea63873b73e
case ${1:-} in
   valeur)
      case ${CIDRE_KK_CODEGEN_FIGE:-$FIGEE} in 0) echo "" ;; *) echo "${CIDRE_KK_CODEGEN_FIGE:-$FIGEE}" ;; esac ;;
   verifier)
      L=${2:?usage: cle_kk_figee.sh verifier <build mesa>}/src/kosmickrisp/vulkan/kk_codegen_sources.h.liste
      [ -f "$L" ] || { echo "cle kk : $L absent (pilote pas encore construit ?)" >&2; exit 2; }
      if ! grep -q 'empreinte figee par KK_CODEGEN_FIGE' "$L"; then echo "cle kk : calculee (non figee)"; exit 0; fi
      c=$(sed -n 's/.*calculee : \([0-9a-f]*\).*/\1/p' "$L")
      if [ "$c" = "$CALCULEE_VERIFIEE" ]; then
         echo "cle kk : figee a ${FIGEE%"${FIGEE#????????????????}"}, sources hachees identiques a kk-0494 ($c)"
      else
         echo "ATTENTION cle kk : figee, mais les sources hachees ont change depuis kk-0494 (calculee $c, verifiee $CALCULEE_VERIFIEE) :" >&2
         echo "  verifier que le code produit est le meme, ou reconstruire avec CIDRE_KK_CODEGEN_FIGE=0 (caches neufs)" >&2
         exit 3
      fi ;;
   *) sed -n '2,13p' "$0"; exit 2 ;;
esac
