-- AMC Phase 2 schema step. Not a function install and not a seed.
-- Adds the confirmed booking quote, one credit reservation per request,
-- and one visit row per service request.
--
-- Do not run this until the read-only duplicate check below returns no rows.
-- The script aborts before any change when that check finds a duplicate.
-- Existing bookings keep a null quote and an empty snapshot. No price is inserted.
--
--   psql -U solar_app_user -d SolarDB -v ON_ERROR_STOP=1 -f SQLScripts/08_amc_credit_reservation_and_quote.sql

-- Read-only check. Run this first and stop if it returns any service_request_id:
-- SELECT service_request_id, COUNT(*) AS visit_count
--   FROM solar_app.site_visit_details
--  WHERE service_request_id IS NOT NULL
--  GROUP BY service_request_id
-- HAVING COUNT(*) > 1;

BEGIN;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
          FROM solar_app.site_visit_details
         WHERE service_request_id IS NOT NULL
         GROUP BY service_request_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION
            'Active or inactive site visits already share a service_request_id. Resolve those rows before adding uq_sv_one_service_request.';
    END IF;
END $$;

ALTER TABLE solar_app.service_request_details
    ADD COLUMN quoted_charge_amount NUMERIC(12,2),
    ADD COLUMN quoted_currency_code CHAR(3),
    ADD COLUMN visit_charge_slab_id BIGINT,
    ADD COLUMN fee_quote_snapshot_json JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN quote_confirmed_on TIMESTAMPTZ;

ALTER TABLE solar_app.service_request_details
    ADD CONSTRAINT fk_sr_quote_currency FOREIGN KEY (quoted_currency_code) REFERENCES solar_app.ref_currencies (currency_code) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_sr_quote_slab FOREIGN KEY (visit_charge_slab_id) REFERENCES solar_app.ref_visit_charge_slabs (visit_charge_slab_id) ON DELETE RESTRICT,
    ADD CONSTRAINT chk_sr_quote_amount CHECK (quoted_charge_amount IS NULL OR quoted_charge_amount >= 0),
    ADD CONSTRAINT chk_sr_quote_pair CHECK ((quoted_charge_amount IS NULL) = (quoted_currency_code IS NULL)),
    ADD CONSTRAINT chk_sr_quote_confirmed CHECK (
        quote_confirmed_on IS NULL
        OR (
            quoted_charge_amount IS NOT NULL
            AND quoted_currency_code IS NOT NULL
            AND visit_charge_slab_id IS NOT NULL
        )
    );

COMMENT ON COLUMN solar_app.service_request_details.quoted_charge_amount IS 'Confirmed offline visit fee. NULL until the booking quote is confirmed.';
COMMENT ON COLUMN solar_app.service_request_details.quoted_currency_code IS 'Currency of quoted_charge_amount. NULL until the booking quote is confirmed.';
COMMENT ON COLUMN solar_app.service_request_details.visit_charge_slab_id IS 'Charge slab selected for the confirmed quote.';
COMMENT ON COLUMN solar_app.service_request_details.fee_quote_snapshot_json IS 'Immutable snapshot of the confirmed quote. Empty until a quote is confirmed.';
COMMENT ON COLUMN solar_app.service_request_details.quote_confirmed_on IS 'Timestamp when the confirmed quote was stored. NULL means the quote is not confirmed.';

CREATE TABLE solar_app.amc_credit_reservation_details (
    amc_credit_reservation_id BIGINT GENERATED ALWAYS AS IDENTITY,
    service_request_id        BIGINT      NOT NULL,
    amc_contract_id           BIGINT      NOT NULL,
    credit_seq                INTEGER     NOT NULL,
    reservation_status        VARCHAR(20) NOT NULL,
    active_ind                BOOLEAN     NOT NULL DEFAULT TRUE,
    created_by                VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    updated_by                VARCHAR(50) NOT NULL DEFAULT 'SYSTEM',
    created_on                TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_on                TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_amc_credit_reservation PRIMARY KEY (amc_credit_reservation_id),
    CONSTRAINT fk_acr_request FOREIGN KEY (service_request_id) REFERENCES solar_app.service_request_details (service_request_id) ON DELETE RESTRICT,
    CONSTRAINT fk_acr_contract FOREIGN KEY (amc_contract_id) REFERENCES solar_app.amc_contract_details (amc_contract_id) ON DELETE RESTRICT,
    CONSTRAINT chk_acr_seq CHECK (credit_seq >= 1),
    CONSTRAINT chk_acr_status CHECK (reservation_status IN ('RESERVED', 'CONSUMED', 'RELEASED')),
    CONSTRAINT chk_acr_hide CHECK (active_ind IS TRUE OR reservation_status = 'RELEASED')
);

COMMENT ON TABLE solar_app.amc_credit_reservation_details IS 'One held or consumed free-visit credit for a service request. A released row keeps history and frees that credit sequence for reuse.';
COMMENT ON COLUMN solar_app.amc_credit_reservation_details.amc_credit_reservation_id IS 'Surrogate primary key.';
COMMENT ON COLUMN solar_app.amc_credit_reservation_details.service_request_id IS 'Booking that holds this credit. At most one RESERVED or CONSUMED row is allowed per request.';
COMMENT ON COLUMN solar_app.amc_credit_reservation_details.amc_contract_id IS 'Sold AMC contract whose allowance supplies this credit.';
COMMENT ON COLUMN solar_app.amc_credit_reservation_details.credit_seq IS 'Credit number within the contract. The same number may be used again only after the earlier row is RELEASED.';
COMMENT ON COLUMN solar_app.amc_credit_reservation_details.reservation_status IS 'RESERVED, CONSUMED, or RELEASED. Stored as a check constraint so the hold does not depend on reference-data load order.';
COMMENT ON COLUMN solar_app.amc_credit_reservation_details.active_ind IS 'Soft-delete flag. A RESERVED or CONSUMED row cannot be hidden; release it first.';
COMMENT ON COLUMN solar_app.amc_credit_reservation_details.created_by IS 'Actor who created the row. Taken from payload logged_in_user_id; default SYSTEM.';
COMMENT ON COLUMN solar_app.amc_credit_reservation_details.updated_by IS 'Actor who last updated the row. Set only inside SQL functions (no triggers).';
COMMENT ON COLUMN solar_app.amc_credit_reservation_details.created_on IS 'Row insert timestamp with time zone (UTC).';
COMMENT ON COLUMN solar_app.amc_credit_reservation_details.updated_on IS 'Last update timestamp with time zone (UTC). Set only inside SQL functions (no triggers).';

CREATE UNIQUE INDEX uq_acr_contract_credit
    ON solar_app.amc_credit_reservation_details (amc_contract_id, credit_seq)
    WHERE reservation_status IN ('RESERVED', 'CONSUMED')
      AND active_ind IS TRUE;
CREATE UNIQUE INDEX uq_acr_request_open
    ON solar_app.amc_credit_reservation_details (service_request_id)
    WHERE reservation_status IN ('RESERVED', 'CONSUMED')
      AND active_ind IS TRUE;
CREATE INDEX idx_acr_contract_status
    ON solar_app.amc_credit_reservation_details (amc_contract_id, reservation_status)
    WHERE active_ind IS TRUE;

CREATE UNIQUE INDEX uq_sv_one_service_request
    ON solar_app.site_visit_details (service_request_id)
    WHERE service_request_id IS NOT NULL;

COMMENT ON COLUMN solar_app.site_visit_details.service_request_id IS 'Optional preventive service booking. FK added after service_request_details exists. At most one visit row may reference a service request.';

COMMIT;
