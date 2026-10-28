#!/usr/bin/env bash
# The outfit sweep's jobs, one per line: mesh|label|env (real_split's settings for that cut). Every mesh in meshes.txt
# (its path under Art/Character/PC): splits (straight, beside the neck, across the waist, after an arm, posed), waist
# cuts (posed, after an arm, high with the arms after, leaned 15 deg four ways), each arm and leg cut at 3-4 places
# (square, leaned 45 deg eight ways, 25 deg four ways), both thighs, a driven arm, a kept cape, arm then head, head planes
#   jobs.sh > jobs.txt       PC=<dir the mesh paths are under>, MESHES=<list>: other meshes (test/real/playas.sh)
HERE=$(cd "$(dirname "$0")" && pwd)
PC=${PC:-$HERE/../../../../../.cache/work/vanilla/SB/Content/Art/Character/PC}
while read -r p; do m=$(basename "$p")
  # the Skirt bones with a body in the outfit's physics asset (gore.lua keeps the skirt chains with none on the body
  # in a thigh cut: real_split's SKIRTBODIES)
  sb=$(strings -n 4 "$PC/$(dirname "$p")"/*_Physics.uasset 2>/dev/null | grep -E '^Ab.*Skirt' | sort -u | paste -sd, -)
  for posed in "" 1; do
    for e in "" "ACROSS=1" "BESIDE=2" "ACROSS=1 LOW=9" "ARMSPLIT=L BESIDE=2" "ARMSPLIT=R BESIDE=2" "FLIP=1 ARMSPLIT=R ARMAT=0.38 BESIDE=2"; do
      echo "$m|split $e posed=$posed|$e POSED=$posed"; done
    echo "$m|waist posed=$posed|WAIST=1 POSED=$posed"
  done
  echo "$m|waist armfirst|WAIST=1 ARMFIRST=1"
  echo "$m|waist high blade arms|WAIST=1 WAISTAT=0.88 WAISTTILT=10 ARMSAFTER=1"
  for d in 0 2 4 6; do echo "$m|waist tilt15 dir$d|WAIST=1 WAISTTILT=15 WAISTTILTDIR=$d"; done
  for s in L R; do
    for lb in "UpperArm Forearm 0.3" "UpperArm Forearm 0.7" "Forearm Hand 0.5" "Thigh Calf 0.4" "Thigh Calf 0.77" "Thigh Calf 0.15" "Calf Foot 0.5"; do
      set -- $lb; b=Bip001-$s-$1; en=Bip001-$s-$2; at=$3
      echo "$m|$b@$at|SKIRTBODIES=$sb ARM=1 ARMBONE=$b ARMEND=$en ARMAT=$at"
      for d in 0 1 2 3 4 5 6 7; do echo "$m|$b@$at tilt45 dir$d|SKIRTBODIES=$sb ARM=1 ARMBONE=$b ARMEND=$en ARMAT=$at ARMTILT=45 ARMTILTDIR=$d"; done
      for d in 0 2 4 6; do echo "$m|$b@$at tilt25 dir$d|SKIRTBODIES=$sb ARM=1 ARMBONE=$b ARMEND=$en ARMAT=$at ARMTILT=25 ARMTILTDIR=$d"; done
    done
  done
  echo "$m|thighs both|SKIRTBODIES=$sb HIPMOVED=1 ARM=1 ARMBONE=Bip001-L-Thigh ARMEND=Bip001-L-Calf ARMAT=0.4 LEGFIRST=Bip001-R-Thigh"
  echo "$m|thigh elbowhip|SKIRTBODIES=$sb ARM=1 ARMBONE=Bip001-L-Thigh ARMEND=Bip001-L-Calf ARMAT=0.47 ELBOWHIP=1"
  echo "$m|arm driven|ARM=1 DRIVEN=1"
  echo "$m|arm cape kept|ARM=1 KEEPCAPE=1"
  echo "$m|arm then head tilt|ARM=1 HEADAFTER=1 ARMTILT=52 ARMTILTDIR=6 ARMBONE=Bip001-R-UpperArm ARMEND=Bip001-R-Forearm ARMAT=0.3"
  for at in 0.7 0.85 1.0; do echo "$m|head plane $at|HEAD=1 HEADPLANE=1 HEADAT=$at"; done
done < "${MESHES:-$HERE/meshes.txt}"
