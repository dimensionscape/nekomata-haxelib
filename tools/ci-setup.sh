#!/bin/sh
# Installs Haxe 4.3.7 and neko 2.4.1 from their release archives into <dir> and puts
#  them on PATH for the steps after this one, for CI on Windows, Linux and macOS.
#  Neko is the tests' oracle; the port needs no neko.
#
#  tools/ci-setup.sh <dir>
#
# On Linux and macOS, libneko goes in /usr/local/lib, where Haxe's own haxelib and neko
#  on Linux look for it.
set -e

HAXE_VERSION=4.3.7
NEKO_VERSION=2.4.1
NEKO_TAG=v$(echo "$NEKO_VERSION" | tr . -)

dir=$1
if [ -z "$dir" ]; then
	echo "usage: $0 <dir>" >&2
	exit 1
fi

case "$(uname -s)" in
	MINGW*|MSYS*|CYGWIN*) os=windows; haxe_archive=haxe-$HAXE_VERSION-win64.zip; neko_archive=neko-$NEKO_VERSION-win64.zip ;;
	Darwin) os=mac; haxe_archive=haxe-$HAXE_VERSION-osx.tar.gz; neko_archive=neko-$NEKO_VERSION-osx-universal.tar.gz ;;
	*) os=linux; haxe_archive=haxe-$HAXE_VERSION-linux64.tar.gz; neko_archive=neko-$NEKO_VERSION-linux64.tar.gz ;;
esac

# fetch <url> <into>: the archive's one top folder becomes <into>
fetch() {
	tmp=$dir/download
	rm -rf "$tmp" "$2"
	mkdir -p "$tmp"
	curl -fsSL --retry 3 -o "$tmp/archive" "$1"
	case "$1" in
		*.zip) unzip -q "$tmp/archive" -d "$tmp/x" ;;
		*) mkdir -p "$tmp/x" && tar xzf "$tmp/archive" -C "$tmp/x" ;;
	esac
	mv "$tmp/x"/* "$2"
	rm -rf "$tmp"
}

mkdir -p "$dir"
fetch "https://github.com/HaxeFoundation/haxe/releases/download/$HAXE_VERSION/$haxe_archive" "$dir/haxe"
fetch "https://github.com/HaxeFoundation/neko/releases/download/$NEKO_TAG/$neko_archive" "$dir/neko"

if [ "$os" != windows ]; then
	sudo mkdir -p /usr/local/lib
	sudo cp -P "$dir/neko"/libneko* /usr/local/lib/
	if [ "$os" = linux ]; then
		sudo ldconfig
	fi
fi

for d in "$dir/haxe" "$dir/neko"; do
	if [ -n "$GITHUB_PATH" ]; then
		if [ "$os" = windows ]; then cygpath -w "$d"; else echo "$d"; fi >> "$GITHUB_PATH"
	fi
done
PATH="$dir/haxe:$dir/neko:$PATH"
haxe -version
neko -version
haxelib version
