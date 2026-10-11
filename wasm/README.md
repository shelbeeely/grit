# grit for WebAssembly

grit can be built with [Emscripten](https://emscripten.org) to run in Node.js
or in a web browser. The output is identical to the native build.

## Building

With the Emscripten SDK activated (`source emsdk_env.sh`):

```sh
make wasm
```

This creates two flavors in `build/wasm/`:

- `grit-node.js` + `grit-node.wasm`: A command line tool for Node.js that uses
  the real filesystem. It's a drop-in replacement for the native binary:

  ```sh
  node build/wasm/grit-node.js image.png -gB4 -ftc
  ```

- `grit.mjs` + `grit.wasm` + `grit-wasm.mjs`: An ES module for browsers, web
  workers and Node.js, which works on an in-memory filesystem. `index.html` is
  a small demo page (serve the directory over HTTP to try it).

`make wasm-node` and `make wasm-module` build only one of them.

## Usage from JavaScript

`grit-wasm.mjs` exports `runGrit()`, which runs grit once with the given input
files and returns every file it created or modified:

```js
import { runGrit } from './grit-wasm.mjs';

const png = new Uint8Array(await (await fetch('sprite.png')).arrayBuffer());

const result = await runGrit({
    args: ['sprite.png', '-gB4', '-ftc'],
    files: { 'sprite.png': png },
});

result.exitCode;          // 0 on success
result.stdout;            // Log output
result.stderr;
result.files['sprite.c']; // Uint8Array
result.files['sprite.h'];
```

Paths in `files` and `args` are relative to the working directory of the
in-memory filesystem, and may contain subdirectories (for example
`'gfx/sprite.png'`).

grit calls `exit()` on errors and keeps global state, so each call creates a
new module instance. The compiled WebAssembly is cached by the browser, so
this is cheap. `moduleOptions` is passed to the Emscripten module factory, for
example `{ locateFile: (path) => '/assets/' + path }` if `grit.wasm` is not
served next to `grit.mjs`.

For lower level access, `createGritModule` (the Emscripten factory) is also
exported. The module exposes `FS` and `callMain`.
