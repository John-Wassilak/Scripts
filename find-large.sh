#!/bin/bash

# crawls every real, on-disk filesystem and lists files/dirs over a
# size threshold (default 512M), largest first, for finding cleanup
# targets. runs as whatever user invoked it -- if not run with sudo,
# paths without read permission are silently skipped by du/findmnt.
#
# usage: ./find-large.sh [threshold]
#   threshold: any size du accepts, e.g. 512M, 1G, 100M (default 512M)

set -uo pipefail

THRESHOLD="${1:-512M}"

# pseudo/virtual filesystems that shouldn't be walked
SKIP_FSTYPES='proc|sysfs|devtmpfs|devpts|tmpfs|cgroup2?|pstore|bpf|tracefs|debugfs|mqueue|hugetlbfs|autofs|overlay|squashfs|fuse\.gvfsd-fuse|fuse\.sshfs|fusectl|configfs|binfmt_misc|efivarfs'

mapfile -t MOUNTS < <(findmnt -rno TARGET,FSTYPE | awk -v skip="$SKIP_FSTYPES" '$2 !~ "^("skip")$" {print $1}')

if [[ -t 1 ]]; then
	RED=$'\e[31m'
	YELLOW=$'\e[33m'
	RESET=$'\e[0m'
else
	RED=''
	YELLOW=''
	RESET=''
fi

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

for mnt in "${MOUNTS[@]}"; do
	du -a -x --threshold="$THRESHOLD" -B1 "$mnt" 2>/dev/null
done | sort -rn > "$TMPFILE"

awk -v red="$RED" -v yellow="$YELLOW" -v reset="$RESET" '
{
	size = $1
	$1 = ""
	sub(/^ /, "")
	path = $0

	human = size
	unit = "B"
	if (size >= 1099511627776) { human = size / 1099511627776; unit = "T" }
	else if (size >= 1073741824) { human = size / 1073741824; unit = "G" }
	else if (size >= 1048576) { human = size / 1048576; unit = "M" }

	color = (size >= 10737418240) ? red : (size >= 1073741824 ? yellow : "")
	printf "%s%8.1f%s  %s%s\n", color, human, unit, path, reset
}' "$TMPFILE"
