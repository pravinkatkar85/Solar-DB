import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const names = [
  'fn_create_technician_details',
  'fn_update_technician_details',
  'fn_get_technician_details',
  'fn_create_job_assignment_details',
  'fn_get_job_assignment_details',
  'fn_update_job_assignment_details',
];

let fail = 0;
for (const name of names) {
  const src = readFileSync(
    join(root, 'DB-Objects/SQLFunctions', `solar_app.${name}.sql`),
    'utf8',
  );
  const match = src.match(/AS\s+\$\$([\s\S]*)\$\$\s*;/i);
  if (!match) {
    console.log(`${name}|SOURCE_EXTRACT_FAIL`);
    fail += 1;
    continue;
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
       WHERE n.nspname = 'solar_app' AND p.proname = '${name}'`,
    ],
    { encoding: 'utf8' },
  ).trim();
  const [installedMd5, args, result] = installed.split('|');
  const ok =
    sourceMd5 === installedMd5 &&
    args === 'p_payload jsonb' &&
    result.toLowerCase() === 'jsonb';
  console.log(
    `${name}|src=${sourceMd5}|inst=${installedMd5}|args=${args}|result=${result}|MATCH=${ok}`,
  );
  if (!ok) fail += 1;
}
process.exit(fail ? 2 : 0);
