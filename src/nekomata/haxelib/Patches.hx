package nekomata.haxelib;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;

// The changes the port makes to haxelib and to Haxe's C++ std as it compiles, so that
//  the fetched sources stay as upstream has them. Each makes the port print what
//  haxelib prints on neko, and fails the build when the code it changes no longer
//  looks as it expects
class Patches {
	public static function apply() {
		Compiler.addMetadata("@:build(nekomata.haxelib.Patches.scriptRunner())", "haxelib.api.ScriptRunner");
		Compiler.addMetadata("@:build(nekomata.haxelib.Patches.usage())", "haxelib.client.Main");
		Compiler.addMetadata("@:build(nekomata.haxelib.Patches.socketConnect())", "sys.net.Socket");
		Compiler.addMetadata("@:build(nekomata.haxelib.Patches.socketConnect())", "sys.ssl.Socket");
		Compiler.addGlobalMetadata("haxelib", "@:build(nekomata.haxelib.Patches.reflectFields())", true, true, false);
		Compiler.addMetadata("@:build(nekomata.haxelib.Patches.reflectFields())", "haxe.format.JsonPrinter");
	}

	// haxelib, and the JSON it prints, read objects' fields with Reflect.fields, which
	//  neko gives in the order of their hashes: NekoOrder.fields gives them so
	static function reflectFields():Array<Field> {
		var fields = Context.getBuildFields();
		function walk(e:Expr):Expr {
			return switch e.expr {
				case ECall(macro Reflect.fields, [o]):
					macro @:pos(e.pos) nekomata.haxelib.NekoOrder.fields(${walk(o)});
				default:
					haxe.macro.ExprTools.map(e, walk);
			}
		}
		for (f in fields)
			switch f.kind {
				case FFun(fn) if (fn.expr != null):
					fn.expr = walk(fn.expr);
				case FVar(t, e) if (e != null):
					f.kind = FVar(t, walk(e));
				case FProp(get, set, t, e) if (e != null):
					f.kind = FProp(get, set, t, walk(e));
				default:
			}
		return fields;
	}

	// ScriptRunner.run starts a library's script with Sys.command(cmd, args), cmd being
	//  neko for a run.n: Runner.command runs that in this process instead
	static function scriptRunner():Array<Field> {
		return patch("run", "one Sys.command call", e -> switch e.expr {
			case ECall(macro Sys.command, [cmd, args]):
				macro @:pos(e.pos) nekomata.haxelib.Runner.command($cmd, $args);
			default: null;
		});
	}

	// haxelib help lists the commands of each category from a Map, which neko iterates
	//  in the order the categories are declared and hxcpp in another: list them in the
	//  declared order
	static function usage():Array<Field> {
		return patch("usage", "one loop over the categories", e -> switch e.expr {
			case EFor(macro $i{name} => $i{commands} in categories, body):
				macro @:pos(e.pos) for ($i{name} in haxe.EnumTools.getConstructors(haxelib.client.Args.CommandCategory)) {
					final $commands = categories[$i{name}];
					if ($i{commands} != null)
						$body;
				}
			default: null;
		});
	}

	// A connection that fails throws "EOF" from hxcpp's socket_connect, where Haxe's
	//  C++ Socket.connect looks for "Invalid socket handle" to throw what neko's throws
	//  for any failed connect: "Failed to connect on host:port"
	static function socketConnect():Array<Field> {
		return patch("connect", "one test for a failed connect", e -> switch e.expr {
			case EBinop(OpEq, s = macro $i{_}, macro "Invalid socket handle"):
				macro @:pos(e.pos) ($s == "Invalid socket handle" || $s == "EOF");
			default: null;
		});
	}

	// Rewrites the expressions of the function name that replace gives a new one for,
	//  which must be exactly one
	static function patch(name:String, expected:String, replace:Expr->Null<Expr>):Array<Field> {
		var fields = Context.getBuildFields();
		var replaced = 0;
		function walk(e:Expr):Expr {
			var r = replace(e);
			if (r != null) {
				replaced++;
				return r;
			}
			return haxe.macro.ExprTools.map(e, walk);
		}
		for (f in fields)
			switch f.kind {
				case FFun(fn) if (f.name == name && fn.expr != null):
					fn.expr = walk(fn.expr);
				default:
			}
		if (replaced != 1)
			Context.fatalError('${Context.getLocalClass()}.$name: expected $expected, found $replaced', Context.currentPos());
		return fields;
	}
}
#end
