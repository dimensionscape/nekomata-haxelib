// A library's run.n that prints what haxelib runs it with: its arguments, folder and
//  environment. Arguments exit=N and throw end it those ways
class Run {
	static function main() {
		var args = Sys.args();
		var json = try haxe.Json.parse(sys.io.File.getContent("haxelib.json")) catch (e:Dynamic) null;
		Sys.println('printargs ${json == null ? "?" : json.version}');
		Sys.println('args: ${args.length}');
		for (a in args)
			Sys.println('  [$a]');
		Sys.println('cwd: ${Sys.getCwd()}');
		for (name in ["HAXELIB_RUN", "HAXELIB_RUN_NAME", "HAXELIB_LIBNAME", "NEKOMATA_HAXELIB_TEST"])
			Sys.println('$name: ${Sys.getEnv(name)}');
		Sys.println('programPath: ${Sys.programPath()}');
		Sys.println('module: ${neko.vm.Module.local().name}');
		// The neko running the script, which a script would start again (deprecated for
		//  programPath, which is the script)
		var exe = haxe.io.Path.withoutExtension(haxe.io.Path.withoutDirectory(Sys.executablePath())).toLowerCase();
		Sys.println('executable: $exe, ${sys.FileSystem.exists(Sys.executablePath()) ? "exists" : "missing"}');
		Sys.stderr().writeString("printargs on stderr\n");
		for (a in args) {
			if (StringTools.startsWith(a, "exit="))
				Sys.exit(Std.parseInt(a.substr(5)));
			if (a == "throw")
				throw "printargs threw";
		}
	}
}
