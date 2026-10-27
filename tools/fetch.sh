#!/bin/sh
# Fetches the sources the port builds from, each at a pinned commit:
#  haxelib/   HaxeFoundation/haxelib as Haxe 4.3.7 ships it, with the libraries its
#             client builds with (hx3compat, hx4compat, crypto)
#  nekomata/  Nekomata, whose sources run library scripts in the port's own process
#
#  tools/fetch.sh
#
# Each is a plain clone, not a submodule: haxelib's build reads its version from the
#  .git folder of the folder it builds in, as Haxe's release build does, and a
#  submodule's .git is a file. A clone already at its commit is left as it is.
set -e

HAXELIB_REPO=https://github.com/HaxeFoundation/haxelib.git
# The commit haxelib version prints on Haxe 4.3.7: 4.2.0 (20199d4e...)
HAXELIB_COMMIT=20199d4e6c1eec17286efdc52067ad6ff94bb3d7
NEKOMATA_REPO=https://github.com/dimensionscape/nekomata.git
NEKOMATA_COMMIT=35004e17e99a2796fa2f274cc274b9ece6994084

root=$(cd "$(dirname "$0")/.." && pwd)

# fetch <dir> <repo> <commit>
fetch() {
	dir=$root/$1
	if [ -d "$dir/.git" ] && [ "$(git -C "$dir" rev-parse HEAD)" = "$3" ]; then
		echo "$1 is at ${3%"${3#????????????}"}"
		return
	fi
	if [ ! -d "$dir/.git" ]; then
		rm -rf "$dir"
		git init -q "$dir"
		git -C "$dir" remote add origin "$2"
	fi
	git -C "$dir" fetch -q --depth 1 origin "$3"
	git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
	echo "fetched $1 at ${3%"${3#????????????}"}"
}

fetch haxelib "$HAXELIB_REPO" "$HAXELIB_COMMIT"
# record-macros is only for haxelib's server
git -C "$root/haxelib" submodule update -q --init --depth 1 hx3compat hx4compat crypto
fetch nekomata "$NEKOMATA_REPO" "$NEKOMATA_COMMIT"
