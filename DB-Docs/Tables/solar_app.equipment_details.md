# Table: `solar_app.equipment_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Installed asset register (panel/inverter/structure/battery) at a site, optionally linked to a catalogue product.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `equipment_id` | `bigint` | NO | `` | Surrogate primary key. |
| `site_id` | `bigint` | NO | `` | Site where this asset is installed. |
| `product_id` | `bigint` | YES | `` | Optional catalogue SKU this asset corresponds to. |
| `equipment_type_ref_data_id` | `bigint` | NO | `` | FK to EQUIPMENT_TYPES (panel, inverter, structure, battery). |
| `brand_ref_data_id` | `bigint` | YES | `` | FK to EQUIPMENT_BRANDS. |
| `model_name` | `character varying(150)` | YES | `` | Manufacturer model name. |
| `serial_no` | `character varying(80)` | YES | `` | Serial number; unique among active rows when present. |
| `barcode` | `character varying(80)` | YES | `` | Barcode or QR value scanned in the field. |
| `quantity` | `numeric(12,3)` | NO | `1` | Count of identical units on this row (typical for panels). |
| `panel_wattage` | `numeric(10,3)` | YES | `` | Wattage per panel when type is panel. |
| `inverter_capacity_kw` | `numeric(8,3)` | YES | `` | Inverter capacity when type is inverter. |
| `phase_type_ref_data_id` | `bigint` | YES | `` | FK to PHASE_TYPES (single / three phase). |
| `monitoring_dongle_id` | `character varying(80)` | YES | `` | Wi-Fi / dongle id for inverter monitoring (no telemetry table in v1). |
| `structure_type_ref_data_id` | `bigint` | YES | `` | FK to STRUCTURE_TYPES. |
| `battery_capacity_ah` | `numeric(10,2)` | YES | `` | Battery bank Ah when type is battery. |
| `extra_json` | `jsonb` | NO | `'{}'::jsonb` | Rare type-specific attributes that do not need dedicated columns. |
| `commissioned_on` | `date` | YES | `` | Asset commissioning date if different from site. |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
