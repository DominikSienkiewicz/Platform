#!/usr/bin/env bash
# seed-community-health.sh — copy the default community health files of templates/github/community/ into a
# local clone of your `.github` repository, in the layout GitHub reads them from.
#
# Usage:
#   scripts/seed-community-health.sh [--overwrite] <checkout-dir>
#
#   <checkout-dir>  a local clone of <owner>/.github (a directory that has a .git entry)
#   --overwrite     replace a file that already exists and differs from the template; without it the script
#                   lists the differing files and copies nothing
#
# It only copies files. It makes no network call and creates no repository, commit or remote: create the public
# `.github` repository on GitHub, clone it, run this script, then review, commit and publish it yourself.
set -euo pipefail

usage='Usage: scripts/seed-community-health.sh [--overwrite] <checkout-dir>'
overwrite=0
checkout=""
for argument in "$@"; do
  case "$argument" in
    # --help drukuje blok komentarza z góry pliku, aż do pierwszej linii, która nim nie jest.
    -h | --help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0
      ;;
    --overwrite) overwrite=1 ;;
    -*)
      echo "Unknown option: $argument" >&2
      echo "$usage" >&2
      exit 2
      ;;
    *)
      [[ -z "$checkout" ]] || { echo "$usage" >&2; exit 2; }
      checkout=$argument
      ;;
  esac
done
[[ -n "$checkout" ]] || { echo "$usage" >&2; exit 2; }

root=$(cd "$(dirname "$0")/.." && pwd)
source_dir="$root/templates/github/community"
[[ -d "$source_dir" ]] || { echo "Missing $source_dir; run the script from a complete checkout." >&2; exit 1; }
[[ -d "$checkout" ]] || { echo "$checkout is not a directory." >&2; exit 1; }
checkout=$(cd "$checkout" && pwd -P)
[[ -e "$checkout/.git" ]] || {
  echo "$checkout is not a clone of a repository (it has no .git entry). Clone your .github repository first." >&2
  exit 1
}
# Platform (i każdy jej worktree) ma w korzeniu własne CONTRIBUTING.md, SECURITY.md i resztę; seed
# do niej nadpisałby je ogólnymi wersjami, więc takiego katalogu nie przyjmujemy.
[[ ! -e "$checkout/templates/github/community/CONTRIBUTING.md" ]] || {
  echo "Refusing to seed $checkout: it holds the templates themselves, not a .github repository clone." >&2
  exit 1
}

# .DS_Store zostawia Finder na macOS; nie jest szablonem i nie ma trafić do repozytorium.
files=()
while IFS= read -r path; do
  files+=("${path#./}")
done < <(cd "$source_dir" && find . -type f ! -name .DS_Store | LC_ALL=C sort)
[[ ${#files[@]} -gt 0 ]] || { echo "No template files under $source_dir." >&2; exit 1; }

# Pierwszy przebieg niczego nie zapisuje: zbiera pliki, które w klonie już są i się różnią.
conflicts=()
for relative in "${files[@]}"; do
  target="$checkout/$relative"
  [[ ! -d "$target" ]] || { echo "$relative is a directory in the checkout; expected a file." >&2; exit 1; }
  if [[ -e "$target" ]] && ! cmp -s "$source_dir/$relative" "$target"; then
    conflicts+=("$relative")
  fi
done
if [[ ${#conflicts[@]} -gt 0 && $overwrite -eq 0 ]]; then
  echo "These files already exist and differ from the templates; nothing was copied:" >&2
  printf '  %s\n' "${conflicts[@]}" >&2
  echo "Review them, or run again with --overwrite to replace them." >&2
  exit 1
fi

copied=0
unchanged=0
for relative in "${files[@]}"; do
  target="$checkout/$relative"
  # Identyczny plik zostaje nietknięty, więc drugie uruchomienie nic nie zmienia.
  if [[ -e "$target" ]] && cmp -s "$source_dir/$relative" "$target"; then
    unchanged=$((unchanged + 1))
    continue
  fi
  mkdir -p "$(dirname "$target")"
  cp "$source_dir/$relative" "$target"
  echo "  $relative"
  copied=$((copied + 1))
done
echo "Copied $copied file(s) into $checkout; $unchanged already up to date."
echo "Nothing was committed or published: review the files, then commit and publish the repository yourself."
