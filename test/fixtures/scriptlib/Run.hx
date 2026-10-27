// A run script haxelib starts with haxe --run, having no run.n
class Run {
	static function main() {
		Sys.println('scriptlib: ${Sys.args().join("|")}');
		Sys.println('scriptlib: HAXELIB_RUN_NAME ${Sys.getEnv("HAXELIB_RUN_NAME")}');
	}
}
