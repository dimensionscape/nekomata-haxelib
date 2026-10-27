# nekomata-haxelib

haxelib, compiled to C++, that runs library scripts on
[Nekomata](https://github.com/dimensionscape/nekomata) in its own process. It needs no
neko install.

It is the haxelib client Haxe 4.3.7 ships (4.2.0, at
[HaxeFoundation/haxelib@20199d4e](https://github.com/HaxeFoundation/haxelib/tree/20199d4e6c1eec17286efdc52067ad6ff94bb3d7)),
built with hxcpp against [libhxcpp](https://github.com/openfl/libhxcpp), with Nekomata's
sources linked in. Stock haxelib runs a library's `run.n` by starting `neko`; this one
runs it on Nekomata, which translates neko bytecode to cppia and runs it on cppia's JIT,
with the same arguments, folder and environment. The build also writes a `neko` beside
`haxelib`, the same executable, which acts as neko when it runs under that name, for
run scripts that start `neko` themselves.

`haxelib version` prints `4.2.0 (20199d4e6c1eec17286efdc52067ad6ff94bb3d7)`, as Haxe
4.3.7's haxelib does.

## Status

Every test of the harness gives the same stdout, stderr and exit code on the port as on
stock haxelib under neko 2.4.1, on Windows, Linux and macOS (see CI). That covers
`version`, `help`, `config`, `setup`, `newrepo`, `deleterepo`, `list`, `path`, `libpath`,
`install` from zips, hxml files and haxelib.json, `remove`, `set`, `dev`, `git`,
`update`, `convertxml`, `state save` and `state load`, the switches, a newer haxelib
installed in the repository, error cases, and `run` of: a `run.n` printing what it was
run with, a `run.n` that starts `neko` (also with no neko on PATH), a `Run.hx`, and
libhxcpp's `run.n` building a C program with `hxcpp.n`.

## How it works

- `tools/fetch.sh` fetches haxelib and Nekomata, each at a pinned commit, into
  `haxelib/` and `nekomata/`. They are plain clones rather than submodules because
  haxelib's build reads its version from the `.git` folder of the folder it builds in,
  as Haxe's release build does, and a submodule's `.git` is a file.
- `build.hxml` builds haxelib's client from that tree unchanged, with the flags
  Nekomata's `host.hxml` builds its host with (`-D scriptable`, `--dce no`,
  `--macro include("nekomata.rt")`, `HXCPP_CATCH_SEGV`, `HXCPP_STACK_TRACE`,
  `HXCPP_STACK_LINE`).
- The port's changes are build macros in
  [`src/nekomata/haxelib/Patches.hx`](src/nekomata/haxelib/Patches.hx), applied as it
  compiles, so the fetched source stays as upstream has it. Each one fails the build if
  the code it changes no longer looks as it expects:
  - `ScriptRunner.run` calls [`Runner.command`](src/nekomata/haxelib/Runner.hx) instead
    of `Sys.command`. For `neko <run.n> <args>` it runs the module on Nekomata in this
    process, after haxelib has set the folder and `HAXELIB_RUN` and `HAXELIB_RUN_NAME`
    as it does for neko, and returns the exit code neko would give, 1 for an uncaught
    exception, which is reported as neko reports it. A script that calls `Sys.exit`
    ends haxelib with that code, as the neko process would have. Anything else, such as
    `haxe` for a library with a `Run.hx`, starts as before.
  - haxelib reads objects from JSON, such as a haxelib.json's dependencies, with
    `Reflect.fields`, which neko gives in the order of the field names' hashes and hxcpp
    in the order they were set. `Reflect.fields` in haxelib and in Haxe's JSON printer
    gives neko's order, so dependencies install, and `convertxml` writes, as on neko.
  - `haxelib help` lists its command categories from a Map, which neko iterates in the
    order they are declared: the port lists them in that order.
  - A connection that fails throws `EOF` from hxcpp's `socket_connect`, where Haxe's C++
    `Socket.connect` looks for another message, so hxcpp programs report a refused
    connection as `EOF`. The port reports `Failed to connect on host:port`, as neko does.
- Library scripts that start neko get the `neko` beside `haxelib`: when no `neko` is on
  PATH, the port adds its own folder to the end of PATH while a script runs, a case in
  which stock haxelib could not have run the script at all. `Sys.executablePath()` in a
  script is that `neko` too, as it is neko's own path on neko.
- `haxelib --debug` rethrows the error it stops on; the port reports it as neko reports
  an uncaught exception, with the port's own stack, and exits with 1.

## Building

You need Haxe 4.3.7, git, a C++ compiler hxcpp can use (Visual Studio on Windows,
g++ or clang elsewhere), and a libhxcpp checkout whose build tool has been built:

```bash
git clone https://github.com/openfl/libhxcpp
```

```bash
cd libhxcpp/tools/hxcpp && haxe compile.hxml
```

Then, in this repository, fetch the pinned sources and point a haxelib repository
local to this checkout at libhxcpp, which leaves your global haxelib setup alone:

```bash
tools/fetch.sh
```

```bash
haxelib newrepo
```

```bash
haxelib dev hxcpp path/to/libhxcpp
```

```bash
haxe build.hxml
```

The build writes `bin/haxelib` and `bin/neko` (`.exe` on Windows), the same
executable under two names. `oracle.hxml` builds stock haxelib for neko, from the same
source, to `bin/oracle/run.n`; the tests build it themselves.

## Running

Put `bin` on PATH, ahead of any other haxelib, or copy both executables into a folder
that is:

```bash
haxe --cwd tools --run Install ../bin/cpp path/to/folder
```

`haxelib` then works as stock haxelib does, with the same repository and settings.
`NEKOMATA_JIT=0` runs library scripts in cppia's interpreter rather than its JIT, and
Nekomata keeps the modules it translates in a cache (see Nekomata's README for
`NEKOMATA_CACHE`).

## Testing

```bash
haxe test/harness.hxml
```

runs each test's haxelib commands on stock haxelib under neko, the oracle, and on the
port, and compares their stdout, stderr and exit codes. It needs the port built, Haxe and
neko on PATH (or `--neko path/to/neko`), and, for the tests that use them, git and a
libhxcpp checkout with `hxcpp.n` built (`libhxcpp/` by default, or `--libhxcpp dir`). It
builds the oracle and the test libraries in `test/fixtures` itself, exits with 1 when a
test fails, and ends with a summary of the failures.

Each side runs a test in a sandbox of its own, at the same path in a temporary folder,
emptied in between, so that paths print alike: its own home folder (`HOME`,
`USERPROFILE`), its own haxelib repository (`HAXELIB_PATH`), and no `HAXEPATH`, so
nothing reads or changes your haxelib setup. Some steps also say what both sides must
do, such as exit with 0 or print a line, so that a test cannot pass by both sides
failing alike.

Options:

- `--build` builds the port first
- `--filter text` runs only the tests whose name contains the text, and can be repeated
- `--network` also runs the tests that reach lib.haxe.org; without it, haxelib's server
  is an address nothing listens on, so commands that ask it fail alike on both sides
- `--strict` fails a test skipped for want of git or libhxcpp, as CI does
- `--keep` keeps the temporary folder, `--tmp dir` puts it elsewhere
- `-v` prints every command's output, `--list` lists the tests

## Licenses

This repository is under the MIT license (see [LICENSE](LICENSE)). The executables it
builds also hold haxelib (MIT, Haxe Foundation), Nekomata (MIT, Dimensionscape LLC) and
libhxcpp (hxcpp's BSD-style license), whose license files are in `haxelib/LICENSE`,
`nekomata/LICENSE` and libhxcpp's `LICENSE.txt`; their notices go with any copy of the
executables you share.
