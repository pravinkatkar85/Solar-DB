# M8 Invoice / Payment SQL — Deployment Note

**Status:** Deployed to development `SolarDB` on 2026-11-12.  
**Canonical closeout:** `Solar-Docs/M8_CLOSEOUT.md`  
**Project tracker:** `Solar-Docs/PROJECT_STATUS.md`

## Functions on SolarDB

Installed individually (transactional); `02_functions.sql` was **not** executed for this deploy:

- `solar_app.fn_create_invoice_details(jsonb)`
- `solar_app.fn_update_invoice_details(jsonb)`
- `solar_app.fn_get_invoice_details(jsonb)`
- `solar_app.fn_create_payment_details(jsonb)`
- `solar_app.fn_update_payment_details(jsonb)`
- `solar_app.fn_get_payment_details(jsonb)`

Authored source: `DB-Objects/SQLFunctions/`. Contracts: `DB-Docs/SQLFunctions/`.

## Verification

- Restore ITs `SQLScripts/14_test_m8_1_invoice_register_restore.sql` and `15_test_m8_2_payment_register_restore.sql` **passed** on isolated `SolarDB_restore_check` only.
- After live API E2E cleanup, SolarDB held **no** M8 invoice/payment test fixtures.

## Backup / rollback

- Package: `Solar-local-backups/m8_pre_deploy_20261112_163433/`
- Dump SHA256: `699062D64B9D5C8660B6D0C7FC694E5C4C5C7AC141BB6148F138F22FD6B2B055`
- Function rollback: `rollback/01_rollback_m8_functions.sql` (DROP — pre-deploy state was absent)
- Deploy report: `deploy_m8_20261112/DEPLOY_REPORT.md`
