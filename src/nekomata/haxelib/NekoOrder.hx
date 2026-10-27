package nekomata.haxelib;

// The order neko gives an object's fields in: its field table keeps them sorted by
//  the hash of their names. haxelib reads the fields of objects parsed from JSON, such
//  as a haxelib.json's dependencies, in that order on neko, where hxcpp gives them in
//  the order they were set
class NekoOrder {
	public static function fields(o:Dynamic):Array<String> {
		var names = Reflect.fields(o);
		var keyed = [for (n in names) {name: n, hash: nekomata.neko.Hash.field(n)}];
		keyed.sort((a, b) -> a.hash < b.hash ? -1 : a.hash > b.hash ? 1 : 0);
		return [for (k in keyed) k.name];
	}
}
