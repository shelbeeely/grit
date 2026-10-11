// SPDX-License-Identifier: CC0-1.0
//
// High-level wrapper around the Emscripten build of grit (grit.mjs).
//
// grit calls exit() on errors and keeps global state between runs, so every
// call to runGrit() creates a fresh module instance. The browser caches the
// compiled WebAssembly, so this is cheap.
//
// Usage:
//
//     import { runGrit } from './grit-wasm.mjs';
//
//     const png = new Uint8Array(await (await fetch('sprite.png')).arrayBuffer());
//     const result = await runGrit({
//         args: ['sprite.png', '-gB4', '-ftc'],
//         files: { 'sprite.png': png },
//     });
//
//     result.exitCode;          // 0 on success
//     result.stdout;            // Log output
//     result.stderr;
//     result.files['sprite.c']; // Uint8Array with the generated file
//     result.files['sprite.h'];

import createGritModule from './grit.mjs';

const WORKDIR = '/work';

function mkdirTree(FS, path) {
    let current = '';
    for (const part of path.split('/').filter(Boolean)) {
        current += '/' + part;
        try {
            FS.mkdir(current);
        } catch {
            // Already exists
        }
    }
}

function readTree(FS, dir, prefix, out) {
    for (const name of FS.readdir(dir)) {
        if (name === '.' || name === '..')
            continue;

        const full = dir + '/' + name;
        const rel = prefix ? prefix + '/' + name : name;
        const stat = FS.stat(full);

        if (FS.isDir(stat.mode))
            readTree(FS, full, rel, out);
        else
            out[rel] = FS.readFile(full);
    }
}

/**
 * Run grit with the given arguments on an in-memory filesystem.
 *
 * @param {object} options
 * @param {string[]} options.args Command line arguments (without "grit").
 * @param {Object<string, Uint8Array|string>} [options.files] Input files,
 *        keyed by path relative to the working directory.
 * @param {object} [options.moduleOptions] Extra options for the Emscripten
 *        module factory (e.g. locateFile, wasmBinary).
 * @returns {Promise<{exitCode: number, stdout: string, stderr: string,
 *          files: Object<string, Uint8Array>}>} Exit code, log output, and
 *          every file that was created or modified by grit.
 */
export async function runGrit({ args, files = {}, moduleOptions = {} }) {
    const stdout = [];
    const stderr = [];

    const Module = await createGritModule({
        print: (text) => stdout.push(text),
        printErr: (text) => stderr.push(text),
        ...moduleOptions,
    });

    const { FS } = Module;

    mkdirTree(FS, WORKDIR);
    FS.chdir(WORKDIR);

    const inputs = new Map();
    for (const [path, data] of Object.entries(files)) {
        const slash = path.lastIndexOf('/');
        if (slash > 0)
            mkdirTree(FS, WORKDIR + '/' + path.slice(0, slash));
        FS.writeFile(path, data);
        inputs.set(path, FS.readFile(path));
    }

    // In Node.js, exit() sets process.exitCode. Restore it afterwards so that
    // the status is only reported to the caller, not to the host process.
    const hostProcess = globalThis.process;
    const savedExitCode = hostProcess?.exitCode;

    let exitCode;
    try {
        exitCode = Module.callMain([...args]);
    } catch (e) {
        if (e && e.name === 'ExitStatus')
            exitCode = e.status;
        else
            throw e;
    } finally {
        if (hostProcess)
            hostProcess.exitCode = savedExitCode;
    }

    const all = {};
    readTree(FS, WORKDIR, '', all);

    // Only return files that grit created or changed
    const output = {};
    for (const [path, data] of Object.entries(all)) {
        const before = inputs.get(path);
        if (before && before.length === data.length &&
            before.every((v, i) => v === data[i]))
            continue;
        output[path] = data;
    }

    return {
        exitCode: exitCode ?? 0,
        stdout: stdout.join('\n'),
        stderr: stderr.join('\n'),
        files: output,
    };
}

export { createGritModule };
