#!/bin/sh
set -e
cd "$(dirname "$0")"
mkdir -p build

odin_exe=$(command -v odin)
odin_root=$(CDPATH= cd -- "$(dirname "$odin_exe")" && pwd)

out=build/noe
lua_src=
lua_dst=
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*)
	out=build/noe.exe
	lua_src="$odin_root/vendor/lua/5.4/windows/lua54.dll"
	lua_dst=build/lua54.dll
	;;
Linux)
	lua_src="$odin_root/vendor/lua/5.4/linux/liblua54.so"
	lua_dst=build/liblua54.so
	;;
Darwin)
	lua_src="$odin_root/vendor/lua/5.4/darwin/liblua54.dylib"
	lua_dst=build/liblua54.dylib
	;;
esac

odin build src -out:"$out" -debug

if [ -n "$lua_src" ] && [ -f "$lua_src" ]; then
	cp -f "$lua_src" "$lua_dst"
elif [ -f "$odin_root/lua54.dll" ]; then
	cp -f "$odin_root/lua54.dll" build/lua54.dll
fi

if [ "${1:-}" = "run" ]; then
	"$out"
fi
