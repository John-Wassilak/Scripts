#!/bin/bash

# cleanup the trash
# distfiles bit might be redundant.

sudo bash -c "eclean distfiles && \
              eclean packages && \
              rm -rf /var/tmp/portage/* && \
              rm -rf /var/cache/distfiles/* && \
	      eclean-kernel -n 2"

# rust-bin keeps every installed SLOT around (eselect-rust just switches
# the active symlink), so old versions never get removed on their own.
# Some packages (firefox) pin to exact old SLOTs matched to a specific
# LLVM build, so skip any SLOT still referenced by an installed package's
# BDEPEND/DEPEND instead of ripping it out and forcing a re-download.
for slot in $(eselect rust list | grep -v '\*' | grep -oP 'rust-bin-\K[0-9.]+'); do
	if grep -rqP "rust-bin:${slot}([^0-9.]|\$)" /var/db/pkg/*/*/BDEPEND /var/db/pkg/*/*/DEPEND 2>/dev/null; then
		echo "keeping dev-lang/rust-bin:${slot} (still required by an installed package)"
		continue
	fi
	sudo emerge -C "dev-lang/rust-bin:${slot}"
done

# gentoo-sources and gentoo-kernel-bin are also SLOTted per version and
# pile up the same way; keep only the newest 2 of each.
keep_latest_n() {
	local pkg="$1" keep="$2"
	mapfile -t versions < <(qlist -Iv "$pkg" | sed "s|^${pkg}-||" | sort -V)
	local remove_count=$(( ${#versions[@]} - keep ))
	(( remove_count > 0 )) || return 0
	for v in "${versions[@]:0:remove_count}"; do
		sudo emerge -C "=${pkg}-${v}"
	done
}
keep_latest_n sys-kernel/gentoo-sources 2
keep_latest_n sys-kernel/gentoo-kernel-bin 2
