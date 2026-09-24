#!/bin/sh
# Echantillonne la charge GPU et le processeur d'un jeu, et publie des medianes.
#
#   mesurer_gpu.sh <motif-du-processus> [nombre-d-echantillons] [intervalle]
#
# Les statistiques GPU viennent d'ioreg, lisible sans privileges sur Apple
# Silicon. On publie des medianes parce qu'un echantillon isole ne veut rien
# dire sur une charge qui varie.
set -e
motif=${1:?usage : mesurer_gpu.sh motif [n] [intervalle]}
n=${2:-12}
pause=${3:-2}

reste=$(pgrep -f "wineserver" | wc -l | tr -d ' ')
echo "processus wineserver vivants : $reste"

i=0
while [ "$i" -lt "$n" ]; do
   stats=$(ioreg -r -d 1 -w 0 -c AGXAccelerator 2>/dev/null | tr ',' '\n')
   dev=$(echo "$stats" | sed -n 's/.*"Device Utilization %"=\([0-9]*\).*/\1/p' | head -1)
   ren=$(echo "$stats" | sed -n 's/.*"Renderer Utilization %"=\([0-9]*\).*/\1/p' | head -1)
   til=$(echo "$stats" | sed -n 's/.*"Tiler Utilization %"=\([0-9]*\).*/\1/p' | head -1)
   cpu=$(ps aux | grep "$motif" | grep -v grep | awk '{s+=$3} END {printf "%.0f", s}')
   echo "${dev:-0} ${ren:-0} ${til:-0} ${cpu:-0}"
   i=$((i + 1))
   sleep "$pause"
done | awk '
   { d[NR]=$1; r[NR]=$2; t[NR]=$3; c[NR]=$4 }
   function med(a, n,   i, tmp) {
      for (i = 1; i <= n; i++) tmp[i] = a[i]
      for (i = 1; i <= n; i++) for (j = i+1; j <= n; j++)
         if (tmp[j] < tmp[i]) { x = tmp[i]; tmp[i] = tmp[j]; tmp[j] = x }
      return (n % 2) ? tmp[(n+1)/2] : (tmp[n/2] + tmp[n/2+1]) / 2
   }
   END {
      printf "medianes sur %d echantillons\n", NR
      printf "  GPU (device)   : %s %%\n", med(d, NR)
      printf "  GPU (renderer) : %s %%\n", med(r, NR)
      printf "  GPU (tiler)    : %s %%\n", med(t, NR)
      printf "  processeur     : %s %% par coeur\n", med(c, NR)
   }'
