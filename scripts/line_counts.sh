#!/bin/bash
# Count Swift lines per target (total, and code lines excluding blank and comment-only lines).
cd "$(dirname "$0")/.."
total=0; code_total=0; declare -A lines code
for d in Sources/*/; do
  name=$(basename "$d")
  files=$(find "$d" -name '*.swift')
  [ -z "$files" ] && continue
  lines[$name]=$(cat $files | wc -l)
  code[$name]=$(cat $files | grep -v -E '^\s*$|^\s*//' | wc -l)
  total=$((total + lines[$name])); code_total=$((code_total + code[$name]))
done
printf "%-18s %7s %7s %7s\n" target lines code "%code"
for name in "${!lines[@]}"; do
  printf "%-18s %7d %7d %6d%%\n" "$name" "${lines[$name]}" "${code[$name]}" $((100 * code[$name] / code_total))
done | sort
printf "%-18s %7d %7d\n" "Total (Sources)" $total $code_total
t=$(find Tests -name '*.swift' | xargs cat | wc -l)
printf "%-18s %7d\n" "Swift tests" $t
