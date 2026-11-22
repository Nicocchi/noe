#!/bin/sh
set -e
cd "$(dirname "$0")"
mkdir -p build

odin_exe=$(command -v odin)
odin_root=$(CDPATH= cd -- "$(dirname "$odin_exe")" && pwd)

out=build/noe
lua_src=
lua_dst=
subsystem=
resource=
case "$(uname -s)" in
MINGW*|MSYS*|CYGWIN*)
	out=build/noe.exe
	lua_src="$odin_root/vendor/lua/5.4/windows/lua54.dll"
	lua_dst=build/lua54.dll
	subsystem=-subsystem:windows
	resource=-resource:res/noe.rc
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

mode=${1:-}
if [ "$mode" = "release" ]; then
	odin build src -out:"$out" -o:speed $subsystem $resource
else
	odin build src -out:"$out" -debug $subsystem $resource
fi
if [ -n "$lua_src" ] && [ -f "$lua_src" ]; then
	cp -f "$lua_src" "$lua_dst"
elif [ -f "$odin_root/lua54.dll" ]; then
	cp -f "$odin_root/lua54.dll" build/lua54.dll
fi
if [ "$mode" = "run" ]; then
	"$out"
elif [ "$mode" = "release" ]; then
	zip=build/noe-windows.zip
	rm -f "$zip"
	powershell.exe -NoProfile -Command \
		"Compress-Archive -LiteralPath 'build/noe.exe','build/lua54.dll' -DestinationPath '$zip' -Force"
	echo "wrote $zip"
fi
