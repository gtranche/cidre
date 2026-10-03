#!/bin/sh
cd /Users/gtranche/Dev/cidre
EXE=third_party/godot/Godot_v4.7.2-stable_win64_console.exe
arret() {
  pkill -9 -f "Godot_v4" 2>/dev/null
  i=0
  while pgrep -f "Godot_v4" >/dev/null 2>&1 && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
  sleep 5
}
for k in 1 2 3; do
  for lbl in barriere suivi; do
    [ "$lbl" = barriere ] && M=blanket_barrier || M=""
    arret
    L=/tmp/g-$lbl-$k.log; rm -f "$L"
    MESA_KK_DEBUG=$M WINEDEBUG=-all ./tests/etape2_pile_wine.sh "$EXE" --path build/godot-heavy \
      --rendering-driver d3d12 --resolution 1920x1080 -- objects=3000 lights=24 shadows=1 post=1 \
      > "$L" 2>&1 &
    i=0
    while ! grep -q "^RESULT" "$L" 2>/dev/null && [ $i -lt 400 ]; do sleep 2; i=$((i+1)); done
    echo "$k $lbl $(grep -o 'mediane=[0-9.]* ms ([0-9.]* img/s)' "$L" | tail -1)"
    arret
  done
done
echo "=== termine ==="
