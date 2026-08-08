#!/usr/bin/env bash
#
# clean-asset-dupes.sh — Assets.xcassets 안의 Finder식 " 2"(" 3"…) 복사본 정리
#
# 로고 파일을 이미 파일이 있는 imageset에 드래그/복사하면 macOS가 이름 충돌을 피하려
# "logo 2.svg", "Contents 2.json" 같은 사본을 만든다. 이 사본들은 Contents.json이
# 참조하지 않는 orphan이라 actool이 빌드 이슈로 잡는다(원본과 무관).
#
# 이 스크립트는 그런 사본 중 "git에 추적되지 않은(untracked)" 것만 골라 정리한다.
# 추적되는 원본은 절대 건드리지 않는다.
#
# 사용법:
#   scripts/clean-asset-dupes.sh          # 미리보기(dry-run) — 삭제 대상만 나열
#   scripts/clean-asset-dupes.sh --apply  # 실제 정리 — /tmp 백업으로 이동 후 목록 출력
#
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
ASSETS="$ROOT/Titans/Assets.xcassets"
APPLY="${1:-}"

cd "$ROOT"

# untracked + " N.ext" 패턴만 후보로. (tracked/원본은 제외됨)
# macOS 기본 bash 3.2 호환: NUL 구분 입력을 while-read로 수집한다.
CANDS=()
while IFS= read -r -d '' f; do
  case "$f" in
    *\ [0-9].svg|*\ [0-9].png|*\ [0-9].jpg|*\ [0-9].jpeg|*\ [0-9].pdf|*\ [0-9].json) CANDS+=("$f");;
  esac
done < <(git ls-files --others --exclude-standard -z -- "$ASSETS")

if [ "${#CANDS[@]}" -eq 0 ]; then
  echo "✅ 정리할 복사본 없음 (untracked ' N' 사본 0개)"
  exit 0
fi

echo "발견된 untracked 복사본: ${#CANDS[@]}개"
printf '  %s\n' "${CANDS[@]}"

if [ "$APPLY" != "--apply" ]; then
  echo
  echo "미리보기 모드입니다. 실제로 정리하려면:  scripts/clean-asset-dupes.sh --apply"
  exit 0
fi

BK="/tmp/asset-dupes-backup-$(date +%Y%m%d-%H%M%S)"
for f in "${CANDS[@]}"; do
  dest="$BK/$f"
  mkdir -p "$(dirname "$dest")"
  mv "$f" "$dest"
done
echo
echo "🧹 ${#CANDS[@]}개를 백업으로 이동: $BK"
echo "   (되돌리려면 위 경로에서 원위치로 복사)"
