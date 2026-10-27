import haxe.io.Bytes;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

using StringTools;

// Runs each test's haxelib commands on stock haxelib under neko, the oracle, and on the
//  port, and compares what they print to stdout and stderr and their exit codes.
//  Each side runs a test in a sandbox of its own at the same path, emptied in between,
//  with its own home folder and haxelib repository, so that paths print alike and
//  nothing reaches the user's haxelib setup. Run from the repository's root:
//  haxe test/harness.hxml [options]
class Harness {
	static final usage = "usage: haxe test/harness.hxml [options]
  --build           build the port first (haxe build.hxml)
  --filter <text>   only run tests whose name contains text (repeatable)
  --network         also run the tests that reach lib.haxe.org
  --strict          a test skipped for want of git or libhxcpp fails
  --keep            keep the temporary folder
  --list            list the tests and exit
  -v, --verbose     print every command's output
  --neko <path>     the neko to run the oracle on (default: the first on PATH)
  --libhxcpp <dir>  a libhxcpp checkout with hxcpp.n built (default: libhxcpp/)
  --tmp <dir>       where the temporary folder goes (default: the system's)";

	static final windows = Sys.systemName() == "Windows";
	static final exe = windows ? ".exe" : "";

	static var root:String;
	static var tmp:String;
	static var sandbox:String;
	static var fixtures:String;
	static var verbose = false;
	static var network = false;
	static var strict = false;

	static var neko:String;
	static var oracleRun:String;
	static var oracleBin:String;
	static var portBin:String;
	static var libhxcpp:Null<String>;
	static var git:Null<String>;
	static var haveNekotools = false;

	static function main() {
		var filters = [];
		var keep = false, list = false, build = false;
		var nekoOption:Null<String> = null, libhxcppOption:Null<String> = null, tmpOption:Null<String> = null;
		var args = Sys.args();
		var i = 0;
		function value():String {
			if (++i >= args.length)
				fail('${args[i - 1]} needs a value\n$usage');
			return args[i];
		}
		while (i < args.length) {
			switch args[i] {
				case "--build": build = true;
				case "--filter": filters.push(value());
				case "--network": network = true;
				case "--strict": strict = true;
				case "--keep": keep = true;
				case "--list": list = true;
				case "-v" | "--verbose": verbose = true;
				case "--neko": nekoOption = value();
				case "--libhxcpp": libhxcppOption = value();
				case "--tmp": tmpOption = value();
				case "-h" | "--help":
					Sys.println(usage);
					return;
				case other:
					fail('unknown option $other\n$usage');
			}
			i++;
		}

		root = normalize(Sys.getCwd());
		if (!FileSystem.exists('$root/build.hxml') || !FileSystem.exists('$root/test/Harness.hx'))
			fail("run the tests from the repository's root: haxe test/harness.hxml");
		if (!FileSystem.exists('$root/haxelib/haxelib.json') || !FileSystem.exists('$root/nekomata/src'))
			fail("haxelib/ and nekomata/ are missing: fetch them with tools/fetch.sh");

		tmp = normalize(tmpOption != null ? FileSystem.absolutePath(tmpOption) : systemTemp()) + "/nekomata-haxelib-tests";
		sandbox = '$tmp/sandbox';
		fixtures = '$tmp/fixtures';
		portBin = '$root/bin';
		libhxcpp = libhxcppOption != null ? normalize(FileSystem.fullPath(libhxcppOption)) : '$root/libhxcpp';
		if (!FileSystem.exists('$libhxcpp/hxcpp.n'))
			libhxcpp = null;

		var all = tests();
		if (list) {
			for (t in all)
				Sys.println(t.name);
			return;
		}
		var selected = all.filter(t -> filters.length == 0 || Lambda.exists(filters, f -> t.name.indexOf(f) >= 0));

		if (build && command("haxe", ["build.hxml"]) != 0)
			fail("the port did not build");
		if (!FileSystem.exists('$portBin/haxelib$exe') || !FileSystem.exists('$portBin/neko$exe'))
			fail('no port in $portBin: build it with haxe build.hxml, or pass --build');

		neko = nekoOption != null ? normalize(FileSystem.fullPath(nekoOption)) : findOnPath("neko", [portBin]);
		if (neko == null)
			fail("no neko to run the oracle on: put it on PATH or pass --neko");
		git = findOnPath("git");

		// haxelib takes a .haxelib folder in any folder above its own as the repository
		var up = Path.directory(tmp);
		while (up != "" && up != Path.directory(up)) {
			if (FileSystem.exists('$up/.haxelib') && FileSystem.isDirectory('$up/.haxelib'))
				fail('$up holds a local haxelib repository, which the sandbox would use: pass --tmp');
			up = Path.directory(up);
		}
		removeTree(tmp);
		FileSystem.createDirectory(tmp);

		Sys.println('oracle: $neko on bin/oracle/run.n');
		Sys.println('port:   $portBin/haxelib$exe');
		Sys.println('git:    ${git == null ? "not found, its tests are skipped" : git}');
		Sys.println('hxcpp:  ${libhxcpp == null ? "no libhxcpp with hxcpp.n, its tests are skipped" : libhxcpp}');
		Sys.println('temp:   $tmp');
		prepare();

		var failed = [], skipped = [], passed = 0;
		for (t in selected) {
			var missing = t.needs == null ? null : Lambda.find(t.needs, n -> !available(n));
			if (missing != null) {
				if (missing == "network" || !strict) {
					skipped.push('${t.name} (needs $missing)');
					Sys.println('  skip ${t.name} (needs $missing)');
				} else {
					failed.push('${t.name} (needs $missing)');
					Sys.println('  FAIL ${t.name} (needs $missing, and --strict)');
				}
				continue;
			}
			var oracle = runTest(t, Oracle);
			var port = runTest(t, Port);
			var problems = compare(t, oracle, port);
			var time = 'oracle ${seconds(oracle.time)}, port ${seconds(port.time)}';
			if (problems.length == 0) {
				passed++;
				Sys.println('  ok   ${t.name} ($time)');
			} else {
				failed.push(t.name);
				Sys.println('  FAIL ${t.name} ($time)');
				for (p in problems)
					Sys.println(p);
			}
		}

		if (!keep)
			removeTree(tmp);
		Sys.println("");
		Sys.println('$passed passed, ${failed.length} failed, ${skipped.length} skipped');
		if (failed.length > 0) {
			Sys.println("failed:");
			for (f in failed)
				Sys.println('  $f');
			Sys.exit(1);
		}
	}

	// ---- The tests ----

	static function tests():Array<Test> {
		var zips = '$tmp/fixtures/zips';
		var libs = '$tmp/fixtures/libs';
		inline function zip(name:String)
			return '$zips/$name';
		return [
			{
				name: "version",
				steps: [hl(["version"], {code: 0, prints: "4.2.0 ("}), hl(["--version"])],
			},
			{
				name: "help",
				steps: [hl(["help"]), hl([]), hl(["nosuchcommand"]), hl(["install", "--nosuchflag"])],
			},
			{
				name: "config and setup",
				env: ["HAXELIB_PATH" => null],
				steps: [
					hl(["config"]),
					hl(["setup", '$sandbox/global']),
					hl(["config"]),
					hl(["list"]),
					// Asked for the folder on stdin
					hl(["setup"], {input: '$sandbox/other\n'}),
					hl(["config"]),
					hl(["setup", '$sandbox/global']),
					hl(["config"], {env: ["HAXELIB_PATH" => '$sandbox/repo']}),
				],
			},
			{
				name: "newrepo and deleterepo",
				steps: [
					hl(["newrepo"]),
					hl(["list"]),
					hl(["config"]),
					hl(["newrepo"]),
					hl(["install", zip("printargs-1.0.0.zip")]),
					hl(["list"]),
					hl(["path", "printargs"]),
					hl(["deleterepo"]),
					hl(["deleterepo"]),
					hl(["list"]),
					hl(["path", "printargs"]),
				],
			},
			{
				name: "install a zip, list, path, libpath, set, remove",
				steps: [
					hl(["install", zip("printargs-1.0.0.zip")], {code: 0, prints: "Current version is now 1.0.0"}),
					hl(["list"], {code: 0, prints: "printargs: [1.0.0]"}),
					hl(["path", "printargs"]),
					hl(["libpath", "printargs"]),
					hl(["install", zip("printargs-1.0.0.zip")]),
					hl(["install", zip("printargs-2.0.0.zip")]),
					hl(["list"]),
					hl(["list", "print"]),
					hl(["path", "printargs:1.0.0"]),
					hl(["libpath", "printargs:2.0.0"]),
					hl(["set", "printargs", "1.0.0"]),
					hl(["list"]),
					hl(["set", "printargs", "2.0.0"], {input: "n\n"}),
					hl(["set", "printargs", "2.0.0"], {input: "y\n"}),
					hl(["list"]),
					hl(["--always", "set", "printargs", "1.0.0"]),
					hl(["remove", "printargs", "2.0.0"]),
					hl(["list"]),
					hl(["remove", "printargs", "1.0.0"]),
					hl(["remove", "printargs"]),
					hl(["list"]),
				],
			},
			{
				name: "install with dependencies",
				steps: [
					hl(["install", zip("printargs-1.0.0.zip")]),
					hl(["install", zip("deplib-1.0.0.zip")]),
					hl(["list"]),
					hl(["path", "deplib"]),
					hl(["libpath", "deplib"]),
					hl(["--skip-dependencies", "install", zip("deplib-1.0.0.zip")]),
				],
			},
			{
				name: "install from hxml",
				setup: s -> {
					File.saveContent('$s/work/build.hxml', "-lib printargs:1.0.0\n-lib deplib:1.0.0\n-main Main\n--interp\n");
					File.saveContent('$s/work/nolibs.hxml', "-main Main\n--interp\n");
				},
				steps: [
					hl(["install", zip("printargs-1.0.0.zip")]),
					hl(["install", zip("printargs-2.0.0.zip")]),
					hl(["install", zip("deplib-1.0.0.zip")]),
					hl(["install", "build.hxml"], {input: "n\n"}),
					hl(["install", "build.hxml", "--always"]),
					hl(["list"]),
					hl(["install", "nolibs.hxml"]),
					hl(["install", "missing.hxml"]),
				],
			},
			{
				name: "install from haxelib.json",
				setup: s -> {
					File.saveContent('$s/work/haxelib.json', '{"name": "app", "version": "1.0.0", "dependencies": {"printargs": "1.0.0", "deplib": ""}}');
				},
				steps: [
					hl(["install", zip("printargs-1.0.0.zip")]),
					hl(["install", zip("deplib-1.0.0.zip")]),
					hl(["install", "haxelib.json"]),
					hl(["install"]),
					hl(["list"]),
				],
			},
			{
				name: "install a git library from hxml",
				needs: ["git"],
				setup: s -> {
					File.saveContent('$s/work/build.hxml', '-lib gitlib:git:$tmp/fixtures/gitlib.git\n-main Main\n');
				},
				steps: [
					hl(["install", "build.hxml", "--always"], {code: 0, prints: "Current version is now git"}),
					hl(["list"]),
					hl(["install", "build.hxml", "--always"]),
					hl(["path", "gitlib"]),
				],
			},
			{
				name: "install a git dependency from haxelib.json",
				needs: ["git"],
				setup: s -> {
					File.saveContent('$s/work/haxelib.json', '{"name": "app", "version": "1.0.0", "dependencies": {"gitlib": "git:$tmp/fixtures/gitlib.git"}}');
				},
				steps: [
					hl(["install", "haxelib.json"], {code: 0, prints: "Current version is now git"}),
					hl(["list"]),
					hl(["install", "haxelib.json", "--always"]),
					hl(["path", "gitlib"]),
				],
			},
			{
				name: "dependencies install in the order neko gives them",
				needs: ["git"],
				setup: s -> {
					var deps = [for (n in ["gitzeta", "gitalpha", "gitmid"]) '"$n": "git:$tmp/fixtures/$n.git"'].join(", ");
					File.saveContent('$s/work/haxelib.json', '{"name": "app", "version": "1.0.0", "dependencies": {$deps}}');
				},
				steps: [hl(["install", "haxelib.json"], {code: 0, prints: "Installing dependency gitmid git"}), hl(["list"])],
			},
			{
				name: "path of a library with several dependencies",
				steps: [
					for (lib in ["printargs-1.0.0", "spawner-1.0.0", "scriptlib-1.0.0", "deplib-1.0.0", "multidep-1.0.0"])
						hl(["--skip-dependencies", "install", zip('$lib.zip')], {code: 0}),
				].concat([
					hl(["path", "multidep"], {code: 0, prints: "-D deplib=1.0.0"}),
					hl(["libpath", "multidep"]),
					hl(["path", "multidep", "deplib", "printargs"]),
					hl(["path", "multidep", "printargs:2.0.0"]),
				]),
			},
			{
				name: "convertxml",
				setup: s -> File.copy('$libs/oldlib/haxelib.xml', '$s/work/haxelib.xml'),
				steps: [
					hl(["convertxml"], {code: 0}),
					show("work/haxelib.json"),
					hl(["convertxml"]),
					hl(["convertxml"], {cwd: "home"}),
				],
			},
			{
				name: "state save and load",
				steps: [
					hl(["install", zip("printargs-1.0.0.zip")]),
					hl(["dev", "devlib", '$libs/devlib']),
					hl(["state", "save", "libs.hxml"], {code: 0}),
					show("work/libs.hxml"),
					hl(["state", "save", "sub/dir/libs.hxml"]),
					show("work/sub/dir/libs.hxml"),
					hl(["remove", "printargs"]),
					hl(["state", "load", "libs.hxml"]),
					hl(["list"]),
					hl(["state", "load", "missing.hxml"]),
				],
			},
			{
				name: "switches and deprecated commands",
				steps: [
					hl(["local", zip("printargs-1.0.0.zip")]),
					hl(["--quiet", "install", zip("printargs-2.0.0.zip")]),
					hl(["--never", "set", "printargs", "1.0.0"]),
					hl(["list"]),
					hl(["--debug", "path", "printargs"]),
					// --debug rethrows the error, which ends haxelib as an uncaught exception
					hl(["--debug", "path", "nosuchlib"], {code: 1, stackTrace: true}),
					hl(["--debug", "install", "nosuch.zip"], {code: 1, stackTrace: true}),
					hl(["--global", "list"]),
					hl(["--system", "version"]),
					hl(["--no-timeout", "list"]),
					hl(["--notimeout", "--quiet", "path", "printargs"]),
					hl(["--always", "--never", "list"]),
					hl(["selfupdate"]),
				],
			},
			{
				name: "a newer haxelib installed in the repository",
				steps: [
					hl(["install", zip("haxelib-99.0.0.zip")], {code: 0}),
					hl(["version"], {code: 0, prints: "printargs 99.0.0"}),
					hl(["list", "an arg"], {code: 0, prints: "HAXELIB_RUN_NAME: haxelib"}),
					hl(["--system", "list"]),
					hl(["--debug", "version"]),
					hl(["exit=4"], {code: 4}),
				],
			},
			{
				name: "run a run.n in cppia's interpreter",
				env: ["NEKOMATA_JIT" => "0"],
				steps: [
					hl(["install", zip("printargs-1.0.0.zip")]),
					hl(["run", "printargs", "interpreted"], {code: 0, prints: "  [interpreted]"}),
					hl(["run", "printargs", "throw"], {code: 1}),
				],
			},
			{
				name: "dev",
				steps: [
					hl(["dev", "devlib", '$libs/devlib'], {code: 0}),
					hl(["list"]),
					hl(["path", "devlib"]),
					hl(["libpath", "devlib"]),
					hl(["dev", "devlib", '$libs/devlib/']),
					hl(["dev", "devlib"]),
					hl(["list"]),
					hl(["dev", "nosuchdir", '$sandbox/missing']),
					hl(["path", "nosuchdir"]),
				],
			},
			{
				name: "git",
				needs: ["git"],
				steps: [
					hl(["git", "gitlib", '$tmp/fixtures/gitlib.git'], {code: 0, prints: "Current version is now git"}),
					hl(["list"]),
					hl(["path", "gitlib"]),
					hl(["libpath", "gitlib"]),
					hl(["git", "gitlib", '$tmp/fixtures/gitlib.git'], {input: "y\n"}),
					hl(["update", "gitlib"]),
					hl(["remove", "gitlib"]),
					hl(["list"]),
					hl(["git", "nogit", '$sandbox/missing.git']),
				],
			},
			{
				name: "run a run.n",
				steps: [
					hl(["install", zip("printargs-1.0.0.zip")]),
					hl(["run", "printargs"], {code: 0, prints: "HAXELIB_RUN_NAME: printargs"}),
					hl(["run", "printargs", "one", "two words", "", "tab\there"], {code: 0, prints: "  [two words]"}),
					hl(["run", "printargs", "quote\"d", "back\\slash\\", "-D", "x=1", "--", "%PATH%"]),
					hl(["run", "printargs", "exit=3"], {code: 3}),
					hl(["run", "printargs", "exit=0"], {code: 0}),
					hl(["run", "printargs", "throw"], {code: 1}),
					hl(["run", "printargs:1.0.0", "versioned"]),
					hl(["run", "printargs", "from a subfolder"], {cwd: "work/sub"}),
					hl(["--cwd", '$sandbox/work/sub', "run", "printargs", "after --cwd"]),
				],
				setup: s -> FileSystem.createDirectory('$s/work/sub'),
			},
			{
				name: "run a version that is not current",
				steps: [
					hl(["install", zip("printargs-1.0.0.zip")]),
					hl(["install", zip("printargs-2.0.0.zip")]),
					hl(["run", "printargs:2.0.0"]),
					hl(["run", "printargs"]),
					hl(["run", "printargs:9.9.9"]),
				],
			},
			{
				name: "run a run.n that starts neko",
				steps: [
					hl(["install", zip("spawner-1.0.0.zip")]),
					hl(["run", "spawner"], {code: 0, prints: "piped child exited with 3"}),
				],
			},
			{
				name: "run a run.n that starts neko, with no neko on PATH",
				portPath: Bare,
				steps: [
					hl(["install", zip("spawner-1.0.0.zip")]),
					hl(["run", "spawner"], {code: 0, prints: "piped child exited with 3"}),
				],
			},
			{
				name: "run a Run.hx",
				steps: [
					hl(["install", zip("scriptlib-1.0.0.zip")]),
					hl(["run", "scriptlib", "an arg"], {code: 0, prints: "scriptlib: an arg|"}),
				],
			},
			{
				name: "run libhxcpp's run.n to build a C program",
				needs: ["hxcpp"],
				setup: s -> {
					for (f in ["Build.xml", "main.c"])
						File.copy('$root/test/fixtures/hello/$f', '$s/work/$f');
				},
				steps: [
					hl(["dev", "hxcpp", libhxcpp]),
					// HXCPP_NEKO_BUILDTOOL: hxcpp.n, the build tool for neko, and not a
					//  compiled BuildTool the checkout may hold
					hl(["run", "hxcpp", "Build.xml", "-DHXCPP_NEKO_BUILDTOOL=1"], {code: 0}),
					run('$sandbox/work/hello$exe', [], {code: 0, prints: "hello from a C program hxcpp built"}),
				],
			},
			{
				name: "errors",
				steps: [
					hl(["path", "nosuchlib"]),
					hl(["libpath", "nosuchlib"]),
					hl(["run", "nosuchlib"]),
					hl(["remove", "nosuchlib"]),
					hl(["set", "nosuchlib", "1.0.0"]),
					hl(["install", zip("printargs-1.0.0.zip")]),
					hl(["set", "printargs", "notaversion"]),
					hl(["set", "printargs", "9.9.9"]),
					hl(["path", "printargs:9.9.9"]),
					hl(["run", "deplib"]),
					hl(["install", zip("bad.zip")]),
					hl(["install", zip("nojson.zip")]),
					hl(["install", zip("badjson.zip")]),
					hl(["set"]),
					hl(["list"]),
				],
			},
			{
				name: "a repository that does not exist",
				env: ["HAXELIB_PATH" => '$sandbox/nosuchrepo'],
				steps: [hl(["list"]), hl(["install", zip("printargs-1.0.0.zip")]), hl(["config"])],
			},
			{
				name: "network: info and search",
				needs: ["network"],
				steps: [
					hl(["info", "hxcpp"], {code: 0}),
					hl(["search", "nekomata-no-such-library"]),
					hl(["search", "hxcp"]),
				],
			},
			{
				name: "network: install from lib.haxe.org",
				needs: ["network"],
				setup: s -> File.saveContent('$s/work/build.hxml', "-lib format:3.7.0\n-main Main\n"),
				steps: [
					hl(["install", "format", "3.7.0"], {code: 0, outputVaries: true}),
					hl(["list"]),
					hl(["path", "format"]),
					hl(["install", "build.hxml", "--always"]),
					hl(["install", "nekomata-no-such-library"]),
				],
			},
			{
				name: "network: install a dependency",
				needs: ["network"],
				setup: s -> File.saveContent('$s/work/haxelib.json', '{"name": "app", "version": "1.0.0", "dependencies": {"format": "3.7.0"}}'),
				steps: [hl(["install", "haxelib.json"], {code: 0, outputVaries: true}), hl(["list"])],
			},
		];
	}

	static function hl(args:Array<String>, ?options:StepOptions):Step
		return {haxelib: true, args: args, options: options == null ? {} : options};

	static function run(cmd:String, args:Array<String>, ?options:StepOptions):Step
		return {haxelib: false, args: [cmd].concat(args), options: options == null ? {} : options};

	// A file in the sandbox, compared as if a command had printed it
	static function show(file:String):Step
		return {haxelib: false, args: [file], show: true, options: {}};

	static function available(need:String):Bool {
		return switch need {
			case "git": git != null;
			case "hxcpp": libhxcpp != null;
			case "network": network;
			default: false;
		}
	}

	// ---- Fixtures ----

	static function prepare() {
		Sys.println("building the oracle and the fixtures");
		if (command("haxe", ["oracle.hxml"]) != 0)
			fail("the oracle did not build");
		oracleRun = '$root/bin/oracle/run.n';

		var libs = '$fixtures/libs', zips = '$fixtures/zips';
		FileSystem.createDirectory(libs);
		FileSystem.createDirectory(zips);
		for (name in ["printargs", "spawner", "deplib", "scriptlib", "devlib", "gitlib", "multidep", "oldlib"])
			copyTree('$root/test/fixtures/$name', '$libs/$name');
		compileNeko('$libs/printargs', "Run", "run.n");
		compileNeko('$libs/spawner', "Run", "run.n");
		compileNeko('$libs/spawner', "Child", "child.n");

		writeZip('$zips/printargs-1.0.0.zip', '$libs/printargs', ["haxelib.json", "run.n", "Run.hx"]);
		var two = File.getContent('$libs/printargs/haxelib.json').replace('"1.0.0"', '"2.0.0"');
		writeZip('$zips/printargs-2.0.0.zip', '$libs/printargs', ["run.n", "Run.hx"], ["haxelib.json" => two]);
		writeZip('$zips/spawner-1.0.0.zip', '$libs/spawner', ["haxelib.json", "run.n", "child.n"]);
		writeZip('$zips/deplib-1.0.0.zip', '$libs/deplib', ["haxelib.json", "src/Deplib.hx"]);
		writeZip('$zips/scriptlib-1.0.0.zip', '$libs/scriptlib', ["haxelib.json", "Run.hx"]);
		writeZip('$zips/multidep-1.0.0.zip', '$libs/multidep', ["haxelib.json", "src/Multidep.hx"]);
		// A newer haxelib installed in the repository, which haxelib hands every command to
		var newer = File.getContent('$libs/printargs/haxelib.json').replace('"printargs"', '"haxelib"').replace('"1.0.0"', '"99.0.0"');
		writeZip('$zips/haxelib-99.0.0.zip', '$libs/printargs', ["run.n"], ["haxelib.json" => newer]);
		File.saveContent('$zips/bad.zip', "this is not a zip file\n");
		writeZip('$zips/nojson.zip', '$libs/devlib', ["src/Devlib.hx"]);
		writeZip('$zips/badjson.zip', '$libs/devlib', ["src/Devlib.hx"], ["haxelib.json" => '{"name": "badjson", "version": '] );

		if (git != null) {
			makeGitRepo('$libs/gitlib', '$fixtures/gitlib.git');
			// Libraries whose names neko orders neither as written nor the other way
			for (name in ["gitzeta", "gitalpha", "gitmid"]) {
				copyTree('$libs/gitlib', '$libs/$name');
				File.saveContent('$libs/$name/haxelib.json', File.getContent('$libs/gitlib/haxelib.json').replace('"gitlib"', '"$name"'));
				makeGitRepo('$libs/$name', '$fixtures/$name.git');
			}
		}

		// Run scripts that start haxelib get the oracle's, booted as an executable
		oracleBin = '$tmp/oracle-bin';
		FileSystem.createDirectory(oracleBin);
		var nekotools = findOnPath("nekotools", [portBin]);
		if (nekotools == null)
			nekotools = findIn(Path.directory(neko), "nekotools");
		var booted = '$root/bin/oracle/run$exe';
		if (nekotools != null && command(nekotools, ["boot", oracleRun]) == 0 && FileSystem.exists(booted)) {
			File.copy(booted, '$oracleBin/haxelib$exe');
			if (!windows)
				command("chmod", ["755", '$oracleBin/haxelib']);
		} else if (windows) {
			File.saveContent('$oracleBin/haxelib.cmd', '@"${native(neko)}" "${native(oracleRun)}" %*\r\n');
		} else {
			File.saveContent('$oracleBin/haxelib', '#!/bin/sh\nexec "$neko" "$oracleRun" "$$@"\n');
			command("chmod", ["755", '$oracleBin/haxelib']);
		}
	}

	static function compileNeko(dir:String, main:String, out:String) {
		if (command("haxe", ["-cp", dir, "-main", main, "-neko", '$dir/$out', "-w", "-WDeprecated"]) != 0)
			fail('fixture $dir/$out did not build');
	}

	static function writeZip(path:String, dir:String, files:Array<String>, ?extra:Map<String, String>) {
		var entries = new haxe.ds.List<haxe.zip.Entry>();
		function add(name:String, data:Bytes) {
			entries.add({
				fileName: name,
				fileSize: data.length,
				fileTime: new Date(2024, 0, 1, 0, 0, 0),
				compressed: false,
				dataSize: data.length,
				data: data,
				crc32: haxe.crypto.Crc32.make(data),
			});
		}
		for (f in files)
			add(f, File.getBytes('$dir/$f'));
		if (extra != null)
			for (name => content in extra)
				add(name, Bytes.ofString(content));
		var out = File.write(path, true);
		new haxe.zip.Writer(out).write(entries);
		out.close();
	}

	// A git repository holding the library, committed at a fixed time by a fixed author,
	//  so that both sides clone the same commit
	static function makeGitRepo(from:String, repo:String) {
		copyTree(from, repo);
		var env = [
			"GIT_AUTHOR_NAME" => "Nekomata Tests", "GIT_AUTHOR_EMAIL" => "tests@example.com",
			"GIT_COMMITTER_NAME" => "Nekomata Tests", "GIT_COMMITTER_EMAIL" => "tests@example.com",
			"GIT_AUTHOR_DATE" => "2024-01-01T00:00:00Z", "GIT_COMMITTER_DATE" => "2024-01-01T00:00:00Z",
		];
		var saved = applyEnv(env);
		var ok = command("git", ["-c", "init.defaultBranch=main", "init", "-q", repo]) == 0
			&& command("git", ["-C", repo, "config", "core.autocrlf", "false"]) == 0
			&& command("git", ["-C", repo, "add", "-A"]) == 0
			&& command("git", ["-C", repo, "-c", "commit.gpgsign=false", "commit", "-q", "-m", "gitlib 0.1.0"]) == 0;
		applyEnv(saved);
		if (!ok)
			fail("could not make the git fixture");
	}

	// ---- Running a test ----

	static function runTest(t:Test, side:Side):TestRun {
		removeTree(sandbox);
		for (d in ["home", "repo", "work"])
			FileSystem.createDirectory('$sandbox/$d');
		if (t.setup != null)
			t.setup(sandbox);
		var start = haxe.Timer.stamp();
		var results = [for (step in t.steps) runStep(t, step, side)];
		return {results: results, time: haxe.Timer.stamp() - start};
	}

	static function runStep(t:Test, step:Step, side:Side):Result {
		var env = baseEnv(t, side);
		if (t.env != null)
			for (k => v in t.env)
				env.set(k, v);
		if (step.options.env != null)
			for (k => v in step.options.env)
				env.set(k, v);
		var cmd:String, args:Array<String>;
		if (!step.haxelib) {
			cmd = step.args[0];
			args = step.args.slice(1);
		} else if (side == Oracle) {
			cmd = neko;
			args = [oracleRun].concat(step.args);
		} else {
			cmd = '$portBin/haxelib$exe';
			args = step.args;
		}
		var cwd = '$sandbox/${step.options.cwd == null ? "work" : step.options.cwd}';
		var r = if (step.show == true) {
			var file = '$sandbox/${step.args[0]}';
			FileSystem.exists(file) ? {stdout: File.getContent(file), stderr: "", code: 0} : {stdout: "", stderr: 'no $file', code: 1};
		} else spawn(cmd, args, cwd, env, step.options.input);
		if (verbose) {
			Sys.println('    [${side == Oracle ? "oracle" : "port"}] ${describe(step)} -> exit ${r.code}');
			for (line in r.stdout.split("\n"))
				if (line != "")
					Sys.println('      out: ${visible(line)}');
			for (line in r.stderr.split("\n"))
				if (line != "")
					Sys.println('      err: ${visible(line)}');
		}
		return r;
	}

	static function baseEnv(t:Test, side:Side):Map<String, Null<String>> {
		var home = native('$sandbox/home');
		var env:Map<String, Null<String>> = [
			"HOME" => home,
			"HAXELIB_PATH" => native('$sandbox/repo'),
			// Windows haxelib makes its default repository in HAXEPATH
			"HAXEPATH" => null,
			"HAXELIB_RUN" => null,
			"HAXELIB_RUN_NAME" => null,
			"HAXELIB_NO_SSL" => null,
			// Offline tests reach no server, and fail fast if they try
			"HAXELIB_REMOTE" => network ? null : "http://127.0.0.1:9/",
			"HXCPP_NONINTERACTIVE" => "1",
			"HXCPP_COMPILE_CACHE" => null,
			"NEKOMATA_CACHE" => native('$tmp/cache'),
			"NEKOMATA_HAXELIB_TEST" => "set by the harness",
		];
		if (windows) {
			env.set("USERPROFILE", home);
			env.set("HOMEDRIVE", null);
			env.set("HOMEPATH", null);
		}
		var path = Sys.getEnv("PATH");
		var dirs = path == null ? [] : path.split(windows ? ";" : ":");
		var first = switch side {
			case Oracle: [oracleBin, Path.directory(neko)];
			case Port if (t.portPath == Bare):
				dirs = dirs.filter(d -> d != "" && normalize(d) != portBin && findIn(d, "neko") == null);
				[];
			case Port: [portBin];
		}
		env.set("PATH", [for (d in first) native(d)].concat(dirs).join(windows ? ";" : ":"));
		return env;
	}

	// Every process started, kept from the collector: see spawn
	static var processes:Array<Process> = [];

	// Runs a command to its end, with its stdin closed after any input, and reads its
	//  stdout, then its stderr. Haxe's interpreter holds its lock while it waits on a
	//  pipe, so a thread could neither read the other pipe meanwhile nor time the
	//  command out: a command that fills the stderr pipe before closing stdout would
	//  hang, and CI's time limit ends that. On Windows, closing a process's stdin leaves
	//  the handle for close() to close again, by when the number may name a handle of
	//  the harness's own, so processes there are never closed
	static function spawn(cmd:String, args:Array<String>, cwd:String, env:Map<String, Null<String>>, input:Null<String>):Result {
		var saved = applyEnv(env);
		var oldCwd = Sys.getCwd();
		Sys.setCwd(cwd);
		var p:Process = null;
		var error:Null<String> = null;
		try
			p = new Process(cmd, args)
		catch (e:Dynamic)
			error = Std.string(e);
		Sys.setCwd(oldCwd);
		applyEnv(saved);
		if (p == null)
			return {stdout: "", stderr: 'could not start $cmd: $error', code: -999};
		processes.push(p);
		try {
			if (input != null)
				p.stdin.writeString(input);
			p.stdin.close();
		} catch (e:Dynamic) {}
		var stdout = try p.stdout.readAll().toString() catch (e:Dynamic) "";
		var stderr = try p.stderr.readAll().toString() catch (e:Dynamic) "";
		var code = try p.exitCode() catch (e:Dynamic) -998;
		if (!windows)
			p.close();
		return {stdout: stdout, stderr: stderr, code: code};
	}

	// ---- Comparing ----

	static function compare(t:Test, oracle:TestRun, port:TestRun):Array<String> {
		var problems = [];
		for (i in 0...t.steps.length) {
			var step = t.steps[i];
			var o = oracle.results[i], p = port.results[i];
			var found = [];
			// What the step must do on both sides, so that a test cannot pass by both
			//  failing alike
			for (side in [{name: "oracle", r: o}, {name: "port", r: p}]) {
				if (step.options.code != null && side.r.code != step.options.code)
					found.push('      the ${side.name} exited with ${side.r.code}, not ${step.options.code}');
				if (step.options.prints != null && side.r.stdout.indexOf(step.options.prints) < 0)
					found.push('      the ${side.name} did not print "${step.options.prints}"');
			}
			if (o.code != p.code)
				found.push('      exit code: oracle ${o.code}, port ${p.code}');
			if (step.options.outputVaries != true) {
				diff("stdout", o.stdout, p.stdout, found);
				if (step.options.stackTrace == true)
					diff("stderr", withoutFrames(o.stderr), withoutFrames(p.stderr), found);
				else
					diff("stderr", o.stderr, p.stderr, found);
			}
			if (found.length > 0) {
				problems.push('    step ${i + 1}: ${describe(step)}');
				for (f in found)
					problems.push(f);
			}
		}
		return problems;
	}

	static function diff(what:String, oracle:String, port:String, found:Array<String>) {
		if (oracle == port)
			return;
		var a = oracle.split("\n"), b = port.split("\n");
		var line = 0;
		while (line < a.length && line < b.length && a[line] == b[line])
			line++;
		found.push('      $what differs from line ${line + 1}:');
		var from = line > 1 ? line - 2 : 0;
		for (side in [{name: "oracle", lines: a}, {name: "port  ", lines: b}]) {
			var to = verbose ? side.lines.length : Std.int(Math.min(side.lines.length, line + 4));
			for (j in from...to)
				found.push('        ${side.name} ${j == line ? ">" : " "} ${visible(side.lines[j])}');
		}
	}

	// A stack trace's frames name the source of the program that printed it, which neko
	//  and the port do not share
	static function withoutFrames(s:String):String
		return [for (line in s.split("\n")) if (!line.startsWith("Called from ")) line].join("\n");

	static function describe(step:Step):String {
		var shown = [for (a in step.args) a == "" || a.indexOf(" ") >= 0 ? '"$a"' : a].join(" ");
		return step.haxelib ? 'haxelib $shown' : step.show == true ? 'the file $shown' : shown;
	}

	static function visible(s:String):String {
		var b = new StringBuf();
		for (i in 0...s.length) {
			var c = s.charCodeAt(i);
			switch c {
				case "\r".code: b.add("\\r");
				case "\t".code: b.add("\\t");
				case 27: b.add("\\e");
				default: b.addChar(c);
			}
		}
		return b.toString();
	}

	// ---- Helpers ----

	static function applyEnv(env:Map<String, Null<String>>):Map<String, Null<String>> {
		var saved = new Map<String, Null<String>>();
		for (k => v in env) {
			saved.set(k, Sys.getEnv(k));
			Sys.putEnv(k, v);
		}
		return saved;
	}

	// A command run with the harness's own output, for building
	static function command(cmd:String, args:Array<String>):Int
		return Sys.command(cmd, args);

	static function findOnPath(name:String, ?skip:Array<String>):Null<String> {
		var path = Sys.getEnv("PATH");
		if (path == null)
			return null;
		for (dir in path.split(windows ? ";" : ":")) {
			if (dir == "" || (skip != null && skip.contains(normalize(dir))))
				continue;
			var found = findIn(dir, name);
			if (found != null)
				return found;
		}
		return null;
	}

	static function findIn(dir:String, name:String):Null<String> {
		for (ext in (windows ? [".exe", ".cmd", ".bat"] : [""])) {
			var p = '$dir/$name$ext';
			if (FileSystem.exists(p) && !FileSystem.isDirectory(p))
				return normalize(p);
		}
		return null;
	}

	static function systemTemp():String {
		for (v in ["RUNNER_TEMP", "TMPDIR", "TEMP", "TMP"]) {
			var t = Sys.getEnv(v);
			if (t != null && t != "")
				return t;
		}
		return "/tmp";
	}

	static function copyTree(from:String, to:String) {
		FileSystem.createDirectory(to);
		for (name in FileSystem.readDirectory(from)) {
			var f = '$from/$name', t = '$to/$name';
			if (FileSystem.isDirectory(f))
				copyTree(f, t);
			else
				File.copy(f, t);
		}
	}

	// Git makes its objects read-only, which FileSystem.deleteFile cannot remove on Windows
	static function removeTree(path:String) {
		if (!FileSystem.exists(path))
			return;
		if (windows)
			Sys.command("cmd", ["/c", "rd", "/s", "/q", native(path)]);
		else
			Sys.command("rm", ["-rf", path]);
		if (FileSystem.exists(path))
			fail('could not remove $path');
	}

	static function normalize(path:String):String {
		var p = Path.normalize(path.replace("\\", "/"));
		return p.length > 1 && p.endsWith("/") ? p.substr(0, p.length - 1) : p;
	}

	static function native(path:String):String
		return windows ? path.replace("/", "\\") : path;

	static function seconds(t:Float):String
		return '${Math.round(t * 10) / 10}s';

	static function fail(message:String) {
		Sys.stderr().writeString(message + "\n");
		Sys.exit(2);
	}
}

enum Side {
	Oracle;
	Port;
}

// The PATH the port runs a test with: the port's folder first, or with no folder that
//  holds a neko, the port's included
enum PortPath {
	Normal;
	Bare;
}

typedef Test = {
	var name:String;
	var steps:Array<Step>;
	// Files to make in the sandbox, the same for both sides
	@:optional var setup:(sandbox:String) -> Void;
	@:optional var env:Map<String, Null<String>>;
	// git, hxcpp or network
	@:optional var needs:Array<String>;
	@:optional var portPath:PortPath;
}

typedef Step = {
	// The arguments of a haxelib command, or a command and its arguments
	var haxelib:Bool;
	var args:Array<String>;
	// args[0] is a file to read, from the sandbox
	@:optional var show:Bool;
	var options:StepOptions;
}

typedef StepOptions = {
	// The folder the command runs in, from the sandbox: work by default
	@:optional var cwd:String;
	@:optional var env:Map<String, Null<String>>;
	// What the command reads on stdin, which is closed after it
	@:optional var input:String;
	// Only the exit codes are compared, as for downloads that print their progress
	@:optional var outputVaries:Bool;
	// stderr holds a stack trace of haxelib's own, compared without its frames
	@:optional var stackTrace:Bool;
	// The exit code both sides must give, and text both must print to stdout
	@:optional var code:Int;
	@:optional var prints:String;
}

typedef Result = {
	var stdout:String;
	var stderr:String;
	var code:Int;
}

typedef TestRun = {
	var results:Array<Result>;
	var time:Float;
}
