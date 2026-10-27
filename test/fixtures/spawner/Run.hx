// A library's run.n that starts neko on another module, as some run scripts do, with
//  Sys.command and with a process whose output it reads
class Run {
	static function main() {
		Sys.println("spawner: before");
		var child = Sys.getCwd() + "child.n";
		var code = Sys.command("neko", [child, "one", "two words"]);
		Sys.println('spawner: child exited with $code');
		var p = new sys.io.Process("neko", [child, "piped"]);
		var out = p.stdout.readAll().toString();
		var piped = p.exitCode();
		p.close();
		Sys.print('spawner: piped child printed ${out}');
		Sys.println('spawner: piped child exited with $piped');
		// As scripts start their own VM again
		var again = Sys.command(Sys.executablePath(), [child, "through executablePath"]);
		Sys.println('spawner: child through executablePath exited with $again');
	}
}
