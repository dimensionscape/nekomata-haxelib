package nekomata.haxelib;

// The haxelib executable: haxelib's own client, running library scripts on Nekomata in
//  its own process. A copy or link of it named neko is the Nekomata host standing in for
//  neko, for scripts that start neko themselves
class Main {
	static function main() {
		if (nekomata.Launcher.isNeko(Sys.programPath())) {
			@:privateAccess nekomata.Main.main();
			return;
		}
		try {
			@:privateAccess haxelib.client.Main.main();
		} catch (e:haxe.Exception) {
			// haxelib --debug rethrows the error it stops on: report it as neko reports an
			//  uncaught exception, with this program's stack, and exit as neko does
			var report = new StringBuf();
			var stack = e.stack;
			var i = stack.length;
			while (i-- > 0)
				switch stack[i] {
					case FilePos(_, file, line, _):
						report.add('Called from $file line $line\n');
					default:
				}
			report.add('Uncaught exception - ${e.toString()}\n');
			Sys.stdout().flush();
			Sys.stderr().writeString(report.toString());
			Sys.exit(1);
		}
	}
}
