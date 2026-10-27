// Copies the port the C++ build wrote into a folder, as haxelib and as neko:
//  haxe --cwd tools --run Install <build folder> <folder>
// build.hxml runs it for bin/. Put the folder on PATH and haxelib, and the neko that
//  library scripts start, are the port
class Install {
	static function main() {
		var args = Sys.args();
		if (args.length != 2) {
			Sys.println("usage: haxe --cwd tools --run Install <build folder> <folder>");
			Sys.exit(1);
		}
		var ext = Sys.systemName() == "Windows" ? ".exe" : "";
		var built = args[0] + "/haxelib" + ext;
		if (!sys.FileSystem.exists(built)) {
			Sys.println('no $built: build it with haxe build.hxml');
			Sys.exit(1);
		}
		sys.FileSystem.createDirectory(args[1]);
		for (name in ["haxelib", "neko"]) {
			var to = args[1] + "/" + name + ext;
			if (sys.FileSystem.exists(to))
				sys.FileSystem.deleteFile(to);
			sys.io.File.copy(built, to);
			if (ext == "")
				Sys.command("chmod", ["755", to]);
			Sys.println('installed $to');
		}
	}
}
