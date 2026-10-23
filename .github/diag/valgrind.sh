#!/usr/bin/env bash
# Run fpm-test under valgrind's memcheck and print its report, which says for
# each invalid access where the memory was allocated and where it was freed.
# Usage: valgrind.sh <label> [fpm-test arguments...]
label=$1
shift
log="$RUNNER_TEMP/valgrind-$label.txt"

timeout 900 valgrind --tool=memcheck --leak-check=no --track-origins=yes \
  --read-var-info=yes --num-callers=40 --error-limit=no \
  --log-file="$log" "$EXE" "$@"
echo "fpm-test exit code: $?"

summary=$(grep -oE 'ERROR SUMMARY: [0-9]+ errors from [0-9]+ contexts' "$log")
echo "$summary"
echo "- gcc $GCC, $label: $summary" >> "$GITHUB_STEP_SUMMARY"
cat "$log"
