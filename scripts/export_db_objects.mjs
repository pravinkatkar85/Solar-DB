#!/usr/bin/env node

/**
 * Export the current PostgreSQL schema objects to individual SQL files and
 * refresh lightweight Markdown documentation.
 *
 * Prerequisites:
 *   - Node.js 18+
 *   - PostgreSQL client tools (pg_dump and psql)
 *   - Access to the target database/schema
 *
 * No npm packages are required. PostgreSQL tools are located from PATH,
 * PG_BIN/PGBIN, or common Windows installation directories.
 */

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const DB_ROOT = path.dirname(SCRIPT_DIR);

const DB_NAME = process.env.PGDATABASE || 'SolarDB';
const DB_USER = process.env.PGUSER || 'solar_app_user';
const DB_HOST = process.env.PGHOST || 'localhost';
const DB_PORT = process.env.PGPORT || '5432';
const DB_SCHEMA = process.env.PGSCHEMA || 'solar_app';

const OBJECTS_ROOT = path.join(DB_ROOT, 'DB-Objects');
const TABLE_SQL_DIR = path.join(OBJECTS_ROOT, 'Tables');
const FUNCTION_SQL_DIR = path.join(OBJECTS_ROOT, 'Functions');
const DOCS_ROOT = path.join(DB_ROOT, 'DB-Docs');
const TABLE_DOC_DIR = path.join(DOCS_ROOT, 'Tables');
const FUNCTION_DOC_DIR = path.join(DOCS_ROOT, 'Functions');
// Authored sources. This export must not write or delete these directories:
//   DB-Objects/SQLFunctions
//   DB-Docs/SQLFunctions
const INDEX_DOC = path.join(DOCS_ROOT, 'DATABASE_OBJECTS_INDEX.md');

function safeFilename(value) {
  return value.replace(/[^A-Za-z0-9_.-]+/g, '_').replace(/^[._]+|[._]+$/g, '') || 'object';
}

function sqlLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function markdownEscape(value) {
  return String(value)
    .replaceAll('|', '\\|')
    .replaceAll('\n', ' ')
    .replaceAll('\r', ' ')
    .replaceAll('`', '\\`');
}

function executableCandidates(binary) {
  const executable = process.platform === 'win32' ? `${binary}.exe` : binary;
  const candidates = [];

  for (const configuredDirectory of [process.env.PG_BIN, process.env.PGBIN]) {
    if (configuredDirectory) {
      candidates.push(path.join(configuredDirectory, executable));
    }
  }

  if (process.platform === 'win32') {
    const roots = [
      process.env.ProgramFiles,
      process.env['ProgramFiles(x86)'],
      'C:\\Program Files',
      'C:\\Program Files (x86)',
    ].filter(Boolean);

    for (const root of new Set(roots)) {
      const postgresqlRoot = path.join(root, 'PostgreSQL');
      if (fs.existsSync(postgresqlRoot)) {
        const versions = fs
          .readdirSync(postgresqlRoot, { withFileTypes: true })
          .filter((entry) => entry.isDirectory())
          .map((entry) => entry.name)
          .sort((left, right) => right.localeCompare(left, undefined, { numeric: true }));

        for (const version of versions) {
          candidates.push(path.join(postgresqlRoot, version, 'bin', executable));
        }
      }

      candidates.push(path.join(root, 'pgAdmin 4', 'runtime', executable));
    }
  }

  return candidates;
}

function findExecutable(binary) {
  const lookupCommand = process.platform === 'win32' ? 'where.exe' : 'which';
  const lookup = spawnSync(lookupCommand, [binary], {
    encoding: 'utf8',
    windowsHide: true,
  });

  if (lookup.status === 0) {
    const firstMatch = (lookup.stdout || '')
      .split(/\r?\n/)
      .map((entry) => entry.trim())
      .find(Boolean);
    if (firstMatch) {
      return firstMatch;
    }
  }

  return executableCandidates(binary).find((candidate) => fs.existsSync(candidate)) || null;
}

function run(command, args, env) {
  const result = spawnSync(command, args, {
    env,
    encoding: 'utf8',
    windowsHide: true,
    maxBuffer: 100 * 1024 * 1024,
  });

  if (result.error) {
    throw new Error(`Could not execute ${command}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(
      `Command failed (${result.status}): ${command} ${args.join(' ')}\n` +
        String(result.stderr || '').trim(),
    );
  }

  return result.stdout || '';
}

function psqlQuery(psql, sql, env) {
  const output = run(
    psql,
    [
      '-X',
      '-w',
      '-h',
      DB_HOST,
      '-p',
      DB_PORT,
      '-U',
      DB_USER,
      '-d',
      DB_NAME,
      '-v',
      'ON_ERROR_STOP=1',
      '-A',
      '-t',
      '-q',
      '-P',
      'pager=off',
      '-c',
      sql,
    ],
    env,
  );

  return output.split(/\r?\n/).filter((line) => line.trim());
}

function decodeHexJson(value) {
  return JSON.parse(Buffer.from(value.trim(), 'hex').toString('utf8'));
}

function promptForPassword(promptText) {
  if (!process.stdin.isTTY) {
    throw new Error(
      'No interactive terminal is available for password entry. Set PGPASSWORD for this process.',
    );
  }

  return new Promise((resolve, reject) => {
    const previousRawMode = Boolean(process.stdin.isRaw);
    let password = '';

    const cleanup = () => {
      process.stdin.off('data', onData);
      process.stdin.setRawMode(previousRawMode);
      process.stdin.pause();
    };

    const onData = (chunk) => {
      for (const character of chunk) {
        if (character === '\u0003') {
          cleanup();
          process.stdout.write(`${os.EOL}`);
          reject(new Error('Password entry cancelled.'));
          return;
        }
        if (character === '\r' || character === '\n') {
          cleanup();
          process.stdout.write(`${os.EOL}`);
          resolve(password);
          return;
        }
        if (character === '\b' || character === '\u007f') {
          password = password.slice(0, -1);
          continue;
        }
        password += character;
      }
    };

    process.stdout.write(promptText);
    process.stdin.setEncoding('utf8');
    process.stdin.setRawMode(true);
    process.stdin.resume();
    process.stdin.on('data', onData);
  });
}

function getColumnsMarkdown(psql, tableName, env) {
  const sql = `
    SELECT encode(convert_to(json_build_array(
             a.attname,
             format_type(a.atttypid, a.atttypmod),
             CASE WHEN a.attnotnull THEN 'NO' ELSE 'YES' END,
             COALESCE(pg_get_expr(d.adbin, d.adrelid), ''),
             COALESCE(col_description(c.oid, a.attnum), '')
           )::text, 'UTF8'), 'hex')
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid
    LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
    WHERE n.nspname = ${sqlLiteral(DB_SCHEMA)}
      AND c.relname = ${sqlLiteral(tableName)}
      AND a.attnum > 0
      AND NOT a.attisdropped
    ORDER BY a.attnum
  `;

  const output = [];
  for (const row of psqlQuery(psql, sql, env)) {
    try {
      const [column, dataType, nullable, defaultValue, comment] = decodeHexJson(row);
      output.push(
        `| \`${markdownEscape(column)}\` | \`${markdownEscape(dataType)}\` | ` +
          `${nullable} | \`${defaultValue ? markdownEscape(defaultValue) : ''}\` | ` +
          `${comment ? markdownEscape(comment) : '—'} |`,
      );
    } catch {
      output.push(`| \`${markdownEscape(row)}\` | (parse error) | — | — | — |`);
    }
  }

  return output.length > 0 ? output.join('\n') : '| — | — | — | — | — |';
}

async function main() {
  const psql = findExecutable('psql');
  const pgDump = findExecutable('pg_dump');

  if (!psql || !pgDump) {
    const missing = [
      !psql ? 'psql' : null,
      !pgDump ? 'pg_dump' : null,
    ].filter(Boolean);
    console.error(
      `ERROR: ${missing.join(' and ')} not found. Set PG_BIN to the PostgreSQL bin directory ` +
        'or add that directory to PATH.',
    );
    return 2;
  }

  const password =
    process.env.PGPASSWORD ||
    (await promptForPassword(`Password for PostgreSQL user ${DB_USER}: `));
  const env = {
    ...process.env,
    PGPASSWORD: password,
    PGCLIENTENCODING: process.env.PGCLIENTENCODING || 'UTF8',
  };

  const connectionVersion = run(
    psql,
    [
      '-X',
      '-w',
      '-h',
      DB_HOST,
      '-p',
      DB_PORT,
      '-U',
      DB_USER,
      '-d',
      DB_NAME,
      '-v',
      'ON_ERROR_STOP=1',
      '-A',
      '-t',
      '-c',
      "SELECT current_database() || ' | ' || current_user",
    ],
    env,
  ).trim();

  const schemaExists = psqlQuery(
    psql,
    `SELECT 1 FROM information_schema.schemata WHERE schema_name = ${sqlLiteral(DB_SCHEMA)}`,
    env,
  );
  if (schemaExists.length === 0) {
    console.error(`ERROR: schema '${DB_SCHEMA}' was not found in database '${DB_NAME}'.`);
    return 3;
  }

  const tableRows = psqlQuery(
    psql,
    `
      SELECT encode(convert_to(json_build_array(
               c.relname,
               COALESCE(obj_description(c.oid, 'pg_class'), '')
             )::text, 'UTF8'), 'hex')
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = ${sqlLiteral(DB_SCHEMA)}
        AND c.relkind IN ('r', 'p')
      ORDER BY c.relname
    `,
    env,
  );

  const functionRows = psqlQuery(
    psql,
    `
      SELECT encode(convert_to(json_build_array(
               p.proname,
               pg_get_function_identity_arguments(p.oid),
               pg_get_function_result(p.oid),
               l.lanname,
               COALESCE(obj_description(p.oid, 'pg_proc'), ''),
               pg_get_functiondef(p.oid)
             )::text, 'UTF8'), 'hex')
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_language l ON l.oid = p.prolang
      WHERE n.nspname = ${sqlLiteral(DB_SCHEMA)}
        AND p.prokind IN ('f', 'p')
      ORDER BY p.proname, pg_get_function_identity_arguments(p.oid)
    `,
    env,
  );

  for (const directory of [
    TABLE_SQL_DIR,
    FUNCTION_SQL_DIR,
    TABLE_DOC_DIR,
    FUNCTION_DOC_DIR,
  ]) {
    fs.mkdirSync(directory, { recursive: true });
  }

  const timestamp = new Date().toLocaleString('sv-SE', {
    timeZoneName: 'short',
  });
  const tableNames = [];
  const functionNames = [];
  const errors = [];

  for (const encodedRow of tableRows) {
    let tableName;
    let tableComment;
    try {
      [tableName, tableComment] = decodeHexJson(encodedRow);
    } catch (error) {
      errors.push(`Could not parse table metadata row: ${error.message}`);
      continue;
    }

    tableNames.push(tableName);
    const baseName = safeFilename(`${DB_SCHEMA}.${tableName}`);
    const outputFile = path.join(TABLE_SQL_DIR, `${baseName}.sql`);

    try {
      const ddl = run(
        pgDump,
        [
          '-w',
          '-h',
          DB_HOST,
          '-p',
          DB_PORT,
          '-U',
          DB_USER,
          '-d',
          DB_NAME,
          '--schema-only',
          '--no-owner',
          '--no-privileges',
          '--table',
          `${DB_SCHEMA}.${tableName}`,
        ],
        env,
      );
      if (!ddl.trim()) {
        errors.push(`No DDL returned for table ${DB_SCHEMA}.${tableName}`);
        continue;
      }

      fs.writeFileSync(
        outputFile,
        `-- Generated from live database: ${DB_NAME}.${DB_SCHEMA}.${tableName}\n` +
          `-- Exported at: ${timestamp}\n` +
          '-- Generated by export_db_objects.mjs; do not edit this export manually.\n\n' +
          ddl,
        'utf8',
      );
    } catch (error) {
      errors.push(error.message);
      continue;
    }

    const documentationFile = path.join(TABLE_DOC_DIR, `${baseName}.md`);
    fs.writeFileSync(
      documentationFile,
      `# Table: \`${DB_SCHEMA}.${tableName}\`\n\n` +
        `- Database: \`${DB_NAME}\`\n` +
        `- Schema: \`${DB_SCHEMA}\`\n` +
        `- Last exported: ${timestamp}\n` +
        `- Table comment: ${tableComment || '(no table comment in database)'}\n\n` +
        '## Columns\n\n' +
        '| Column | Data type | Nullable | Default | Comment |\n' +
        '|---|---|---|---|---|\n' +
        getColumnsMarkdown(psql, tableName, env) +
        '\n\n## Notes\n\n' +
        'This document is generated from the live database catalog. Review business purpose ' +
        'and usage notes here if needed, but do not manually edit generated SQL files.\n',
      'utf8',
    );
  }

  for (const encodedRow of functionRows) {
    let name;
    let identityArguments;
    let resultType;
    let language;
    let comment;
    let definition;
    try {
      [name, identityArguments, resultType, language, comment, definition] =
        decodeHexJson(encodedRow);
    } catch (error) {
      errors.push(`Could not parse function metadata row: ${error.message}`);
      continue;
    }

    const signature = `${name}(${identityArguments})`;
    functionNames.push(signature);
    const baseName = safeFilename(
      `${DB_SCHEMA}.${name}_${identityArguments || 'no_args'}`,
    );

    fs.writeFileSync(
      path.join(FUNCTION_SQL_DIR, `${baseName}.sql`),
      `-- Generated from live database: ${DB_NAME}.${DB_SCHEMA}.${signature}\n` +
        `-- Exported at: ${timestamp}\n` +
        '-- Generated by export_db_objects.mjs; do not edit this export manually.\n\n' +
        `${definition.trim()}\n`,
      'utf8',
    );

    fs.writeFileSync(
      path.join(FUNCTION_DOC_DIR, `${baseName}.md`),
      `# Function/Procedure: \`${DB_SCHEMA}.${signature}\`\n\n` +
        `- Database: \`${DB_NAME}\`\n` +
        `- Schema: \`${DB_SCHEMA}\`\n` +
        `- Return type: \`${resultType}\`\n` +
        `- Language: \`${language}\`\n` +
        `- Last exported: ${timestamp}\n` +
        `- Database comment: ${comment || '(no function comment in database)'}\n\n` +
        '## Definition\n\n' +
        'The matching `.sql` file contains the current definition retrieved from ' +
        '`pg_get_functiondef`.\n\n' +
        '## Business purpose / usage\n\n' +
        'Add or maintain the purpose, input payload contract, return JSON structure, ' +
        'validation rules, and callers here. This section is not inferred from the ' +
        'database definition.\n',
      'utf8',
    );
  }

  const indexLines = [
    '# Database Objects Index',
    '',
    `- Database: \`${DB_NAME}\``,
    `- Schema: \`${DB_SCHEMA}\``,
    `- Connection check: \`${connectionVersion}\``,
    `- Exported at: ${timestamp}`,
    '',
    '## Tables',
    '',
    `Tables found: **${tableNames.length}**`,
    '',
    ...tableNames.map(
      (name) =>
        `- [\`${name}\`](Tables/${safeFilename(`${DB_SCHEMA}.${name}`)}.md)`,
    ),
    '',
    '## Functions and procedures',
    '',
    `Functions/procedures found: **${functionNames.length}**`,
    '',
    ...functionNames.map((signature) => `- \`${signature}\``),
  ];

  if (errors.length > 0) {
    indexLines.push(
      '',
      '## Export warnings/errors',
      '',
      ...errors.map((error) => `- ${error.replaceAll('\n', ' ')}`),
    );
  }
  fs.writeFileSync(INDEX_DOC, `${indexLines.join('\n')}\n`, 'utf8');

  console.log(`\nConnected: ${connectionVersion}`);
  console.log(`Schema: ${DB_SCHEMA}`);
  console.log(`Tables found: ${tableNames.length}`);
  console.log(`Functions/procedures found: ${functionNames.length}`);
  console.log(`Table SQL folder: ${TABLE_SQL_DIR}`);
  console.log(`Function SQL folder: ${FUNCTION_SQL_DIR}`);
  console.log(`Documentation folder: ${DOCS_ROOT}`);
  console.log(`Index: ${INDEX_DOC}`);

  if (errors.length > 0) {
    console.log(`\nCompleted with ${errors.length} warning(s):`);
    for (const error of errors) {
      console.log(` - ${error.replaceAll('\n', ' ')}`);
    }
    return 1;
  }

  console.log('\nExport completed.');
  return 0;
}

try {
  process.exitCode = await main();
} catch (error) {
  console.error(`ERROR: ${error.message}`);
  process.exitCode = 1;
}
