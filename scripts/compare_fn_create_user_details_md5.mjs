import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const srcPath = join(
  root,
  'DB-Objects/SQLFunctions/solar_app.fn_create_user_details.sql',
);
const src = readFileSync(srcPath, 'utf8');
const match = src.match(/AS\s+\$\$([\s\S]*)\$\$\s*;/i);
if (!match) {
  console.error('Could not extract function body from source');
  process.exit(1);
}
const sourceMd5 = createHash('md5').update(match[1], 'utf8').digest('hex');
const installed = execFileSync(
  'psql',
  [
    '-At',
    '-c',
    `SELECT md5(p.prosrc) || '|' || pg_get_function_identity_arguments(p.oid) || '|' || pg_get_function_result(p.oid)
     FROM pg_proc p
     JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'solar_app'
       AND p.proname = 'fn_create_user_details';`,
  ],
  { encoding: 'utf8' },
).trim();
if (!installed) {
  console.error('Installed function not found');
  process.exit(1);
}
const [installedMd5, args, result] = installed.split('|');
console.log(`SOURCE_BODY_MD5=${sourceMd5}`);
console.log(`INSTALLED_BODY_MD5=${installedMd5}`);
console.log(`INSTALLED_ARGS=${args}`);
console.log(`INSTALLED_RESULT=${result}`);
console.log(`BODY_MD5_MATCH=${sourceMd5 === installedMd5}`);
if (sourceMd5 !== installedMd5) process.exit(2);
if (args !== 'p_payload jsonb') process.exit(3);
if (result.toLowerCase() !== 'jsonb') process.exit(4);
