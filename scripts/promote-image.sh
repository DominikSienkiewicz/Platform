#!/usr/bin/env bash
# Promocja obrazu — KANON Platform (uruchamiana przez promote.yml w kopii roboczej repo docelowego).
# Użycie: promote-image.sh MESSAGE FILE=TAG [FILE=TAG...]
#   • FILE jest ścieżką względną do korzenia kopii roboczej (bieżącego katalogu), TAG musi być semver,
#   • zmienia wyłącznie `tag:` bezpośrednio w bloku `image:` (bez yq), dokładnie jedno trafienie na plik,
#   • wszystko jest walidowane przed zapisem: jeden zły argument nie zmienia żadnego pliku,
#   • jeden commit jako platform-promote, push na HEAD, do 3 prób z `git pull --rebase` po odrzuceniu.
# Kody: 0 zapisano albo bez zmian, 1 błąd, 2 użycie.
set -euo pipefail

readonly TAG_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'
readonly MAX_PUSH_ATTEMPTS=3

usage() { echo "usage: promote-image.sh MESSAGE FILE=TAG [FILE=TAG...]" >&2; exit 2; }
die() { echo "ERROR: $*" >&2; exit 1; }

# set_image_tag FILE TAG: wypisuje plik z podmienionym image.tag; wypisuje liczbę trafień do pliku $3.
set_image_tag() {
  awk -v tag="$2" -v countfile="$3" '
    function indent_of(line) { match(line, /^[ \t]*/); return RLENGTH }
    /^image:[ \t]*(#.*)?$/ { in_image = 1; child = -1; print; next }
    /^[^ \t#]/ { in_image = 0 }
    in_image && child < 0 && /^[ \t]+[^ \t#]/ { child = indent_of($0) }
    in_image && /^[ \t]+tag:([ \t]|$)/ && indent_of($0) == child {
      lead = indent_of($0)
      rest = substr($0, lead + 5)
      comment = ""
      if (match(rest, /[ \t]+#.*$/)) comment = substr(rest, RSTART)
      print substr($0, 1, lead) "tag: " tag comment
      hits++
      next
    }
    { print }
    END { print hits + 0 > countfile }
  ' "$1"
}

[[ $# -ge 2 ]] || usage
message=$1
shift
[[ -n "$message" ]] || usage

files=()
tags=()
for pair in "$@"; do
  [[ "$pair" == *=* ]] || usage
  file=${pair%%=*}
  tag=${pair#*=}
  [[ -n "$file" && "$file" != /* && "$file" != *..* ]] || usage
  [[ "$tag" =~ $TAG_PATTERN ]] || usage
  files+=("$file")
  tags+=("$tag")
done

work=$(mktemp -d)
trap 'rm -r -f "$work"' EXIT

for i in "${!files[@]}"; do
  file=${files[$i]}
  [[ -f "$file" ]] || die "$file does not exist"
  set_image_tag "$file" "${tags[$i]}" "$work/count" > "$work/$i.new"
  hits=$(cat "$work/count")
  [[ "$hits" -eq 1 ]] || die "$file has $hits image.tag entries, expected exactly 1"
done

for i in "${!files[@]}"; do
  cat "$work/$i.new" > "${files[$i]}"
done

if [[ -z "$(git status --porcelain -- "${files[@]}")" ]]; then
  echo "No changes: every image.tag already has the requested value"
  exit 0
fi

export GIT_AUTHOR_NAME=platform-promote GIT_AUTHOR_EMAIL=platform-promote@users.noreply.github.com
export GIT_COMMITTER_NAME=$GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL=$GIT_AUTHOR_EMAIL
git add -- "${files[@]}"
git commit -q -m "$message" -- "${files[@]}"

branch=$(git symbolic-ref --short HEAD) || die "HEAD is detached, cannot rebase onto a branch"
for attempt in $(seq 1 "$MAX_PUSH_ATTEMPTS"); do
  if git push origin HEAD; then
    exit 0
  fi
  echo "Push attempt $attempt of $MAX_PUSH_ATTEMPTS was rejected" >&2
  if [[ $attempt -lt $MAX_PUSH_ATTEMPTS ]]; then
    git pull --rebase origin "$branch" || { git rebase --abort 2> /dev/null || true; die "rebase onto origin/$branch failed"; }
  fi
done
die "could not push after $MAX_PUSH_ATTEMPTS attempts"
