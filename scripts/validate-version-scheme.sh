#!/usr/bin/env bash
#
# validate-version-scheme.sh — Phase 1 evidence test.
#
# Validates the dpkg version scheme used by this project's nginx packages
# against real nginx.org version strings, using dpkg's own comparison:
#
#   ours:  <NGINX_VERSION>-1ncb<n>~<CODENAME>
#   e.g.   1.30.7-1ncb1~jammy
#
#   (vendor suffix "ncb<n>" is placed BEFORE the "~codename" part; this is
#   deliberate — see the first test group. A scheme like "1~jammy+ncb1"
#   was evaluated and REJECTED because "~" sorts before end-of-string in
#   dpkg, making "1~jammy+ncb1" LESS than the bare revision "1".)
#
# Expected ordering semantics:
#   1) ours must be GREATER than nginx.org's same-revision package
#      (clean "apt upgrade" over an existing nginx.org install), and also
#      greater than a hypothetical bare "-1" revision;
#   2) a nginx.org revision bump (-2~<codename>) must be GREATER than ours
#      (nginx.org remains the authoritative upgrade/rollback target);
#   3) our own rebuilds must increase monotonically (ncb<n>);
#   4) newer upstream versions always dominate older ones regardless of
#      revision suffixes.
#
# Must run in a Debian/Ubuntu environment with dpkg available
# (run inside a disposable target container, never on a host with nginx).
#
set -euo pipefail

pass=0
fail=0

check() {
    # check <left> <op> <right> <description>
    local left="$1" op="$2" right="$3" desc="$4"
    if dpkg --compare-versions "$left" "$op" "$right"; then
        printf 'PASS  %-24s %-3s %-24s  %s\n' "$left" "$op" "$right" "$desc"
        pass=$((pass + 1))
    else
        printf 'FAIL  %-24s %-3s %-24s  %s\n' "$left" "$op" "$right" "$desc"
        fail=$((fail + 1))
    fi
}

echo "dpkg version: $(dpkg --version | head -1)"
echo

# --- 1) take-over: ours > nginx.org same upstream version ---
check "1.30.7-1ncb1~jammy"  gt "1.30.7-1~jammy"   "upgrade over nginx.org stable jammy"
check "1.30.7-1ncb1~jammy"  gt "1.30.7-1~jammy1"  "upgrade over nginx.org jammy rev-suffixed"
check "1.30.7-1ncb1~jammy"  gt "1.30.7-1"         "beats hypothetical bare revision (tilde-first pitfall avoided)"
check "1.31.9-1ncb1~jammy"  gt "1.31.9-1~jammy"   "upgrade over nginx.org mainline jammy"
check "1.30.7-1ncb1~noble"  gt "1.30.7-1~noble"   "upgrade over nginx.org stable noble"
check "1.30.7-1ncb1~focal"  gt "1.30.7-1~focal"   "upgrade over nginx.org stable focal (legacy target)"
check "1.26.3-1ncb1~bionic" gt "1.26.3-1~bionic"  "upgrade over nginx.org stable bionic (legacy target)"

# --- 2) nginx.org authority: their revision bump supersedes ours ---
check "1.30.7-2~jammy" gt "1.30.7-1ncb1~jammy"  "nginx.org rev bump supersedes ours"
check "1.30.7-3~jammy" gt "1.30.7-1ncb1~jammy"  "nginx.org further rev bumps keep superseding"
check "1.31.9-2~jammy" gt "1.31.9-1ncb1~jammy"  "nginx.org mainline rev bump supersedes ours"

# --- 3) our rebuilds increase monotonically ---
check "1.30.7-1ncb2~jammy"  gt "1.30.7-1ncb1~jammy"  "our rebuild increments"
check "1.30.7-1ncb10~jammy" gt "1.30.7-1ncb9~jammy"  "multi-digit rebuild increments numerically"

# --- 4) upstream version dominates ---
check "1.30.7-1ncb1~jammy" gt "1.28.0-1~jammy" "newer upstream beats older nginx.org"
check "1.31.9-1ncb1~jammy" gt "1.30.7-2~jammy" "mainline beats stable with higher rev"
check "1.26.3-1ncb1~jammy" lt "1.30.7-1~jammy" "requested old exact version loses to nginx.org current (documented downgrade-back path)"

# --- 5) sanity: equality, empty/codename revisions, Ubuntu distro nginx ---
check "1.30.7-1ncb1~jammy" eq "1.30.7-1ncb1~jammy" "identical strings are equal"
check "1.30.7-1ncb1~jammy" gt "1.30.7"             "revision present beats bare upstream version"
check "1.30.7-1ncb1~jammy" gt "1.15.8-0ubuntu10.4" "beats Ubuntu distro nginx sharing older upstream (rev 0)"
check "1.30.7-1ncb1~jammy" gt "1.30.7-1~jammy9"    "ours beats hypothetical tilde-digit sub-rev (monitored)"

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
