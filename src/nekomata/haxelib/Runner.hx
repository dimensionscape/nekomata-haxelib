package nekomata.haxelib;

// What haxelib's ScriptRunner calls in place of Sys.command. A library's run.n runs on
//  Nekomata in this process, with the arguments, folder and environment haxelib set up
//  for neko, and its exit code is what neko's would be; anything else, such as haxe
//  for a library with a Run.hx, starts as before
class Runner {
	public static function command(cmd:String, args:Array<String>):Int {
		if (cmd != "neko" || args.length == 0)
			return Sys.command(cmd, args);
		var path = Sys.getEnv("PATH");
		var own = ownNekoDir();
		// A script that starts neko itself gets the one beside this executable when no
		//  other is on PATH, where haxelib on neko would have failed to start it
		if (own != null && findOnPath("neko") == null)
			Sys.putEnv("PATH", path == null || path == "" ? own : path + pathSeparator() + own);
		var code = runNeko(args[0], args.slice(1));
		if (own != null)
			Sys.putEnv("PATH", path);
		return code;
	}

	// What neko <file> <args> does, as the Nekomata host does it, on the JIT unless
	//  NEKOMATA_JIT=0. Sys.executablePath() is neko's own path on neko, which scripts
	//  start again to run other modules: here it is the neko beside this executable
	static function runNeko(file:String, args:Array<String>):Int {
		nekomata.Main.setExePath(ownNeko());
		return nekomata.Main.runModule(file, args);
	}

	static inline function windows():Bool
		return Sys.systemName() == "Windows";

	static inline function pathSeparator():String
		return windows() ? ";" : ":";

	static function names(command:String):Array<String>
		return windows() ? [for (ext in [".exe", ".com", ".bat", ".cmd"]) command + ext] : [command];

	// The folder of the first command of that name on PATH, or null
	static function findOnPath(command:String):Null<String> {
		var path = Sys.getEnv("PATH");
		if (path == null)
			return null;
		for (dir in path.split(pathSeparator())) {
			if (dir == "")
				continue;
			for (name in names(command))
				if (isFile(dir + "/" + name))
					return dir;
		}
		return null;
	}

	// The neko built beside this executable, or null
	static function ownNeko():Null<String> {
		var dir = haxe.io.Path.directory(Sys.programPath());
		return Lambda.find([for (name in names("neko")) dir + (windows() ? "\\" : "/") + name], isFile);
	}

	static function ownNekoDir():Null<String> {
		var neko = ownNeko();
		return neko == null ? null : haxe.io.Path.directory(neko);
	}

	static function isFile(path:String):Bool
		return sys.FileSystem.exists(path) && !sys.FileSystem.isDirectory(path);
}
