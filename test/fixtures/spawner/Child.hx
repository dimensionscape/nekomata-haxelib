// The module spawner's run.n starts with neko
class Child {
	static function main() {
		Sys.println('child: ${Sys.args().join("|")} (HAXELIB_RUN_NAME ${Sys.getEnv("HAXELIB_RUN_NAME")})');
		Sys.exit(3);
	}
}
