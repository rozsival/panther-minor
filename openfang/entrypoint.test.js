import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const ENTRYPOINT_PATH = join(process.cwd(), 'openfang/entrypoint.sh');
const ARGV_START_FOREGROUND_PATTERN = /^argv:start --foreground$/m;
const ARGV_DOCTOR_PATTERN = /^argv:doctor$/m;
const OPENFANG_ONE_PATTERN = /^openfang_one:alpha$/m;
const OPENFANG_TWO_PATTERN = /^openfang_two:beta=gamma$/m;
const HF_TOKEN_PATTERN = /^hf_token:unset$/m;

const createTempDir = () => mkdtempSync(join(tmpdir(), 'openfang-entrypoint-'));

const createFakeExecutable = (directoryPath) => {
  const executablePath = join(directoryPath, 'fake-openfang.sh');
  writeFileSync(
    executablePath,
    [
      '#!/bin/sh',
      'printf \'argv:%s\\n\' "$*"',
      `printf 'openfang_one:%s\\n' "\${OPENFANG_ONE-unset}"`,
      `printf 'openfang_two:%s\\n' "\${OPENFANG_TWO-unset}"`,
      `printf 'hf_token:%s\\n' "\${HF_TOKEN-unset}"`,
    ].join('\n')
  );
  chmodSync(executablePath, 0o755);
  return executablePath;
};

test('entrypoint injects only OPENFANG_ variables and restores the OpenFang executable', () => {
  const tempDirectoryPath = createTempDir();

  try {
    writeFileSync(
      join(tempDirectoryPath, '.env'),
      ['# Comment should be ignored', 'OPENFANG_ONE=alpha', 'HF_TOKEN=super-secret', 'OPENFANG_TWO=beta=gamma'].join(
        '\n'
      )
    );

    const executablePath = createFakeExecutable(tempDirectoryPath);
    const output = execFileSync('/bin/bash', [ENTRYPOINT_PATH, 'start', '--foreground'], {
      cwd: process.cwd(),
      encoding: 'utf8',
      env: {
        ...process.env,
        OPENFANG_EXECUTABLE: executablePath,
        OPENFANG_HOME: tempDirectoryPath,
      },
    });

    assert.match(output, ARGV_START_FOREGROUND_PATTERN);
    assert.match(output, OPENFANG_ONE_PATTERN);
    assert.match(output, OPENFANG_TWO_PATTERN);
    assert.match(output, HF_TOKEN_PATTERN);
  } finally {
    rmSync(tempDirectoryPath, { force: true, recursive: true });
  }
});

test('entrypoint preserves an explicit executable command', () => {
  const tempDirectoryPath = createTempDir();

  try {
    writeFileSync(join(tempDirectoryPath, '.env'), 'OPENFANG_ONE=alpha\n');

    const executablePath = createFakeExecutable(tempDirectoryPath);
    const output = execFileSync('/bin/bash', [ENTRYPOINT_PATH, executablePath, 'doctor'], {
      cwd: process.cwd(),
      encoding: 'utf8',
      env: {
        ...process.env,
        OPENFANG_EXECUTABLE: join(tempDirectoryPath, 'unused-openfang'),
        OPENFANG_HOME: tempDirectoryPath,
      },
    });

    assert.match(output, ARGV_DOCTOR_PATTERN);
    assert.match(output, OPENFANG_ONE_PATTERN);
  } finally {
    rmSync(tempDirectoryPath, { force: true, recursive: true });
  }
});
