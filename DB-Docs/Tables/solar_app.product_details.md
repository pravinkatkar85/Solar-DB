# Table: `solar_app.product_details`

- Database: `SolarDB`
- Schema: `solar_app`
- Last exported: 2026-10-10 19:33:54 GMT+5:30
- Table comment: Admin-maintained catalogue of sellable and related products shown to registered users when published.

## Columns

| Column | Data type | Nullable | Default | Comment |
|---|---|---|---|---|
| `product_id` | `bigint` | NO | `` | Surrogate primary key. |
| `product_code` | `character varying(40)` | NO | `` | Business SKU; unique among active catalogue rows. |
| `product_name` | `character varying(200)` | NO | `` | Catalogue card and detail title. |
| `category_ref_data_id` | `bigint` | NO | `` | FK to PRODUCT_CATEGORIES. |
| `short_description` | `character varying(500)` | YES | `` | List-card blurb. |
| `long_description` | `text` | YES | `` | Product detail body. |
| `specs_json` | `jsonb` | NO | `'{}'::jsonb` | Flexible specification table (wattage, warranty years, …). |
| `list_price` | `numeric(14,2)` | NO | `` | Indicative list price; formal quote is a separate object. |
| `currency_code` | `character(3)` | NO | `` | ISO currency for list_price. |
| `tax_classification_code` | `character varying(30)` | YES | `` | Optional country-specific product tax classification. |
| `thumbnail_url` | `character varying(500)` | YES | `` | List thumbnail URL. |
| `is_published` | `boolean` | NO | `false` | TRUE = visible to registered users; FALSE = admin draft. Publish enqueues NTF_CATALOGUE_NEW. |
| `published_on` | `timestamp with time zone` | YES | `` | When the product was last published. |
| `sort_order` | `integer` | NO | `0` | Featured/list order (lower first). |
| `active_ind` | `boolean` | NO | `true` | Soft-delete flag. FALSE hides the row from default queries; set only inside SQL functions (no triggers). |
| `created_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM. |
| `updated_by` | `character varying(50)` | NO | `'SYSTEM'::character varying` | Actor who last updated the row. Set only inside SQL functions (no triggers). |
| `created_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Row insert timestamp with time zone (UTC). |
| `updated_on` | `timestamp with time zone` | NO | `CURRENT_TIMESTAMP` | Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers). |

## Notes

This document is generated from the live database catalog. Review business purpose and usage notes here if needed, but do not manually edit generated SQL files.
