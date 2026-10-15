-- Subscriptions, wallet, payments and download history (schema billing). Owner C. Phase 3: M11-M14 (B38, B41, B44, B47).
-- Entities and relationships: docs/phase3/billing_entities.md, billing_relationships.md.
-- Rule group 10:
--   * subscription periods of one licence never overlap (ex_subscription_licence_period; cancelled ones excluded)
--   * the wallet ledger is append-only; a correction is a new entry that reverses the original (reverses_wallet_ledger_entry_id),
--     never an update; payment events (gateway webhooks) are append-only and idempotent (gateway + event id)
--   * wallet balance never goes negative: billing.post_ledger_entry locks the wallet row, writes the entry with
--     balance_after and updates the balance in the same transaction (ck_wallet_balance_non_negative)
--   * every profile download references its ledger debit (actor, subject, timestamp, credit deduction)
-- Wallet, ledger and download history are [api-write]: the application role reads them and writes through the
-- SECURITY DEFINER functions only.

SET app.current_user_id = '1';

-- ---------------------------------------------------------------------------------------------------
SELECT ref.create_lookup('ref.billing_cycle', 'plan billing cycle');
ALTER TABLE ref.billing_cycle ADD COLUMN cycle_months smallint NOT NULL DEFAULT 1;
COMMENT ON COLUMN ref.billing_cycle.cycle_months IS '[Public] Months per cycle; default 1';
SELECT ref.add_lookup_value('ref.billing_cycle', 'monthly',   'Monthly',   1);
SELECT ref.add_lookup_value('ref.billing_cycle', 'quarterly', 'Quarterly', 2);
SELECT ref.add_lookup_value('ref.billing_cycle', 'annual',    'Annual',    3);
UPDATE ref.billing_cycle SET cycle_months = CASE code WHEN 'quarterly' THEN 3 WHEN 'annual' THEN 12 ELSE 1 END;

SELECT ref.create_lookup('ref.subscription_status', 'subscription status');
SELECT ref.add_lookup_value('ref.subscription_status', 'pending_payment', 'Pending payment', 1);
SELECT ref.add_lookup_value('ref.subscription_status', 'active',          'Active',          2);
SELECT ref.add_lookup_value('ref.subscription_status', 'expired',         'Expired',         3);
SELECT ref.add_lookup_value('ref.subscription_status', 'cancelled',       'Cancelled',       4);

SELECT ref.create_lookup('ref.entitlement_type', 'what a plan entitles the account to');
SELECT ref.add_lookup_value('ref.entitlement_type', 'job_post_credit',      'Job postings',          1);
SELECT ref.add_lookup_value('ref.entitlement_type', 'profile_download',     'Profile downloads',     2);
SELECT ref.add_lookup_value('ref.entitlement_type', 'outreach_message',     'Outreach messages',     3);
SELECT ref.add_lookup_value('ref.entitlement_type', 'candidate_search',     'Candidate searches',    4);
SELECT ref.add_lookup_value('ref.entitlement_type', 'featured_job',         'Featured job slots',    5);

SELECT ref.create_lookup('ref.payment_gateway', 'payment gateway');
SELECT ref.add_lookup_value('ref.payment_gateway', 'razorpay', 'Razorpay', 1);
SELECT ref.add_lookup_value('ref.payment_gateway', 'stripe',   'Stripe',   2);

SELECT ref.create_lookup('ref.payment_status', 'payment order status');
SELECT ref.add_lookup_value('ref.payment_status', 'created',            'Created',            1);
SELECT ref.add_lookup_value('ref.payment_status', 'authorised',         'Authorised',         2);
SELECT ref.add_lookup_value('ref.payment_status', 'captured',           'Captured',           3);
SELECT ref.add_lookup_value('ref.payment_status', 'failed',             'Failed',             4);
SELECT ref.add_lookup_value('ref.payment_status', 'partially_refunded', 'Partially refunded', 5);
SELECT ref.add_lookup_value('ref.payment_status', 'refunded',           'Refunded',           6);

SELECT ref.create_lookup('ref.invoice_status', 'invoice status');
SELECT ref.add_lookup_value('ref.invoice_status', 'issued', 'Issued', 1);
SELECT ref.add_lookup_value('ref.invoice_status', 'paid',   'Paid',   2);
SELECT ref.add_lookup_value('ref.invoice_status', 'void',   'Void',   3);

SELECT ref.create_lookup('ref.refund_status', 'refund status');
SELECT ref.add_lookup_value('ref.refund_status', 'requested', 'Requested', 1);
SELECT ref.add_lookup_value('ref.refund_status', 'processed', 'Processed', 2);
SELECT ref.add_lookup_value('ref.refund_status', 'failed',    'Failed',    3);

SELECT ref.create_lookup('ref.ledger_entry_type', 'kind of wallet ledger entry');
SELECT ref.add_lookup_value('ref.ledger_entry_type', 'recharge',    'Recharge',    1);
SELECT ref.add_lookup_value('ref.ledger_entry_type', 'consumption', 'Consumption', 2);
SELECT ref.add_lookup_value('ref.ledger_entry_type', 'refund',      'Refund',      3);
SELECT ref.add_lookup_value('ref.ledger_entry_type', 'grant',       'Promotional grant', 4);
SELECT ref.add_lookup_value('ref.ledger_entry_type', 'correction',  'Correction (reversal)', 5);

SELECT ref.create_lookup('ref.consumption_purpose', 'what wallet credit was spent on');
SELECT ref.add_lookup_value('ref.consumption_purpose', 'job_posting',      'Job posting',      1);
SELECT ref.add_lookup_value('ref.consumption_purpose', 'profile_download', 'Profile download', 2);
SELECT ref.add_lookup_value('ref.consumption_purpose', 'profile_view',     'Profile view',     3);
SELECT ref.add_lookup_value('ref.consumption_purpose', 'outreach_message', 'Outreach message', 4);

-- ---------------------------------------------------------------------------------------------------
-- Plans and subscriptions
CREATE TABLE billing.plan (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  code                  d_code          NOT NULL,
  plan_name             varchar(150)    NOT NULL,
  label_key             varchar(150)    NOT NULL,
  billing_cycle_code    d_code          NOT NULL,
  price_amount          d_money         NOT NULL,
  price_currency_code   d_currency_code NOT NULL,
  max_users             integer         NOT NULL,
  max_devices_per_user  integer         NOT NULL,
  is_active             boolean         NOT NULL DEFAULT true,
  created_at            timestamptz     NOT NULL DEFAULT now(),
  created_by            bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at            timestamptz     NOT NULL DEFAULT now(),
  updated_by            bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_plan PRIMARY KEY (id),
  CONSTRAINT uq_plan_code UNIQUE (code),
  CONSTRAINT fk_plan_label_key FOREIGN KEY (label_key) REFERENCES ref.ui_label (label_key) ON UPDATE CASCADE ON DELETE RESTRICT,
  CONSTRAINT fk_plan_billing_cycle_code FOREIGN KEY (billing_cycle_code) REFERENCES ref.billing_cycle (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_plan_price_currency_code FOREIGN KEY (price_currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_plan_price_amount CHECK (price_amount >= 0),
  CONSTRAINT ck_plan_max_users_positive CHECK (max_users > 0),
  CONSTRAINT ck_plan_max_devices_per_user_positive CHECK (max_devices_per_user > 0)
);
COMMENT ON TABLE  billing.plan IS '[hard-delete] Commercial plan: price per cycle and the licence limits it grants; deactivated, not deleted, once sold';
COMMENT ON COLUMN billing.plan.code IS '[Public] Stable plan code (recruiter_pro)';
COMMENT ON COLUMN billing.plan.plan_name IS '[Public] English name; translations via label_key';
COMMENT ON COLUMN billing.plan.label_key IS '[Public] UI label key for the plan name';
COMMENT ON COLUMN billing.plan.billing_cycle_code IS '[Public] monthly, quarterly, annual';
COMMENT ON COLUMN billing.plan.price_amount IS '[Public] Price per cycle (0 for free plans)';
COMMENT ON COLUMN billing.plan.price_currency_code IS '[Public] Currency of price_amount';
COMMENT ON COLUMN billing.plan.max_users IS '[Public] Seats granted to the licence (copied at subscription start)';
COMMENT ON COLUMN billing.plan.max_devices_per_user IS '[Public] Devices per user granted to the licence (copied at subscription start)';
COMMENT ON COLUMN billing.plan.is_active IS '[Public] On sale; default true';

CREATE TABLE billing.plan_entitlement (
  id                     bigint GENERATED ALWAYS AS IDENTITY,
  plan_id                bigint      NOT NULL,
  entitlement_type_code  d_code      NOT NULL,
  quantity_per_cycle     integer     NOT NULL,
  created_at             timestamptz NOT NULL DEFAULT now(),
  created_by             bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_plan_entitlement PRIMARY KEY (id),
  CONSTRAINT uq_plan_entitlement_plan_id_entitlement_type_code UNIQUE (plan_id, entitlement_type_code),
  CONSTRAINT fk_plan_entitlement_plan_id FOREIGN KEY (plan_id) REFERENCES billing.plan (id) ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT fk_plan_entitlement_entitlement_type_code FOREIGN KEY (entitlement_type_code) REFERENCES ref.entitlement_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_plan_entitlement_quantity_per_cycle CHECK (quantity_per_cycle > 0)
);
COMMENT ON TABLE  billing.plan_entitlement IS '[hard-delete] Quantity of an entitlement a plan includes per billing cycle (owned by the plan)';
COMMENT ON COLUMN billing.plan_entitlement.plan_id IS '[Public] Owning plan';
COMMENT ON COLUMN billing.plan_entitlement.entitlement_type_code IS '[Public] Entitlement';
COMMENT ON COLUMN billing.plan_entitlement.quantity_per_cycle IS '[Public] Units included per cycle';

CREATE TABLE billing.subscription (
  id                        bigint GENERATED ALWAYS AS IDENTITY,
  licence_id                bigint          NOT NULL,
  plan_id                   bigint          NOT NULL,
  subscription_status_code  d_code          NOT NULL DEFAULT 'pending_payment',
  subscription_period       daterange       NOT NULL,
  price_amount              d_money         NOT NULL,
  price_currency_code       d_currency_code NOT NULL,
  is_auto_renew             boolean         NOT NULL DEFAULT true,
  created_at                timestamptz     NOT NULL DEFAULT now(),
  created_by                bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at                timestamptz     NOT NULL DEFAULT now(),
  updated_by                bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_subscription PRIMARY KEY (id),
  CONSTRAINT fk_subscription_licence_id FOREIGN KEY (licence_id) REFERENCES lic.licence (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_subscription_plan_id FOREIGN KEY (plan_id) REFERENCES billing.plan (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_subscription_subscription_status_code FOREIGN KEY (subscription_status_code) REFERENCES ref.subscription_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_subscription_price_currency_code FOREIGN KEY (price_currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_subscription_period CHECK (NOT isempty(subscription_period) AND lower(subscription_period) IS NOT NULL
                                           AND upper(subscription_period) IS NOT NULL),
  CONSTRAINT ck_subscription_price_amount CHECK (price_amount >= 0),
  -- RG10: periods of one licence never overlap (cancelled subscriptions free their period)
  CONSTRAINT ex_subscription_licence_period EXCLUDE USING gist (licence_id WITH =, subscription_period WITH &&)
    WHERE (subscription_status_code <> 'cancelled')
);
CREATE INDEX idx_subscription_plan_id ON billing.subscription (plan_id);
COMMENT ON TABLE  billing.subscription IS '[hard-delete] Paid period of a plan on a licence; periods of one licence never overlap. Renewal = a new row linked by subscription_renewal';
COMMENT ON COLUMN billing.subscription.licence_id IS '[Internal] Licence the subscription funds';
COMMENT ON COLUMN billing.subscription.plan_id IS '[Internal] Plan bought';
COMMENT ON COLUMN billing.subscription.subscription_status_code IS '[Internal] pending_payment, active, expired, cancelled; default pending_payment';
COMMENT ON COLUMN billing.subscription.subscription_period IS '[Internal] Dates [start, end) covered (both bounds required)';
COMMENT ON COLUMN billing.subscription.price_amount IS '[Internal] Price agreed at purchase (plan prices may change later)';
COMMENT ON COLUMN billing.subscription.price_currency_code IS '[Internal] Currency of price_amount';
COMMENT ON COLUMN billing.subscription.is_auto_renew IS '[Internal] Renew automatically at period end; default true';

CREATE TABLE billing.subscription_renewal (
  id                         bigint GENERATED ALWAYS AS IDENTITY,
  from_subscription_id       bigint      NOT NULL,
  to_subscription_id         bigint      NOT NULL,
  is_automatic               boolean     NOT NULL DEFAULT true,
  renewed_at                 timestamptz NOT NULL DEFAULT now(),
  created_at                 timestamptz NOT NULL DEFAULT now(),
  created_by                 bigint      NOT NULL DEFAULT public.current_actor_id(),
  updated_at                 timestamptz NOT NULL DEFAULT now(),
  updated_by                 bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_subscription_renewal PRIMARY KEY (id),
  CONSTRAINT uq_subscription_renewal_from_subscription_id UNIQUE (from_subscription_id),
  CONSTRAINT uq_subscription_renewal_to_subscription_id UNIQUE (to_subscription_id),
  CONSTRAINT fk_subscription_renewal_from_subscription_id FOREIGN KEY (from_subscription_id) REFERENCES billing.subscription (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_subscription_renewal_to_subscription_id FOREIGN KEY (to_subscription_id) REFERENCES billing.subscription (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_subscription_renewal_distinct CHECK (from_subscription_id <> to_subscription_id)
);
COMMENT ON TABLE  billing.subscription_renewal IS '[hard-delete] Renewal: links a subscription to the one that continues it (each renewed at most once)';
COMMENT ON COLUMN billing.subscription_renewal.from_subscription_id IS '[Internal] Subscription being renewed';
COMMENT ON COLUMN billing.subscription_renewal.to_subscription_id IS '[Internal] New subscription';
COMMENT ON COLUMN billing.subscription_renewal.is_automatic IS '[Internal] Auto-renewal (true) or manual; default true';
COMMENT ON COLUMN billing.subscription_renewal.renewed_at IS '[Internal] Renewal instant (UTC)';

CREATE TABLE billing.subscription_cancellation (
  id                   bigint GENERATED ALWAYS AS IDENTITY,
  subscription_id      bigint       NOT NULL,
  cancellation_reason  varchar(500) NOT NULL,
  effective_on         date         NOT NULL,
  cancelled_at         timestamptz  NOT NULL DEFAULT now(),
  created_at           timestamptz  NOT NULL DEFAULT now(),
  created_by           bigint       NOT NULL DEFAULT public.current_actor_id(),
  updated_at           timestamptz  NOT NULL DEFAULT now(),
  updated_by           bigint       NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_subscription_cancellation PRIMARY KEY (id),
  CONSTRAINT uq_subscription_cancellation_subscription_id UNIQUE (subscription_id),
  CONSTRAINT fk_subscription_cancellation_subscription_id FOREIGN KEY (subscription_id) REFERENCES billing.subscription (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
COMMENT ON TABLE  billing.subscription_cancellation IS '[hard-delete] Cancellation of a subscription (who = created_by); marks the subscription cancelled (trigger)';
COMMENT ON COLUMN billing.subscription_cancellation.subscription_id IS '[Internal] Subscription cancelled (once)';
COMMENT ON COLUMN billing.subscription_cancellation.cancellation_reason IS '[Internal] Why, max 500';
COMMENT ON COLUMN billing.subscription_cancellation.effective_on IS '[Internal] Date access ends';
COMMENT ON COLUMN billing.subscription_cancellation.cancelled_at IS '[Internal] When the cancellation was recorded (UTC)';

CREATE FUNCTION billing.apply_subscription_cancellation() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  UPDATE billing.subscription SET subscription_status_code = 'cancelled' WHERE id = NEW.subscription_id;
  RETURN NULL;
END
$$;
CREATE TRIGGER trg_subscription_cancellation_apply AFTER INSERT ON billing.subscription_cancellation
  FOR EACH ROW EXECUTE FUNCTION billing.apply_subscription_cancellation();

-- ---------------------------------------------------------------------------------------------------
-- Wallet and ledger
CREATE TABLE billing.wallet (
  id             bigint GENERATED ALWAYS AS IDENTITY,
  account_id     bigint          NOT NULL,
  currency_code  d_currency_code NOT NULL,
  balance        d_money         NOT NULL DEFAULT 0,
  created_at     timestamptz     NOT NULL DEFAULT now(),
  created_by     bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at     timestamptz     NOT NULL DEFAULT now(),
  updated_by     bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_wallet PRIMARY KEY (id),
  CONSTRAINT uq_wallet_account_id_currency_code UNIQUE (account_id, currency_code),
  CONSTRAINT fk_wallet_account_id FOREIGN KEY (account_id) REFERENCES org.account (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_wallet_currency_code FOREIGN KEY (currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_wallet_balance_non_negative CHECK (balance >= 0)
);
COMMENT ON TABLE  billing.wallet IS '[hard-delete] [api-write] Prepaid wallet of an account in one currency; balance changes only through billing.post_ledger_entry and always equals the sum of its ledger';
COMMENT ON COLUMN billing.wallet.account_id IS '[Internal] Owning account';
COMMENT ON COLUMN billing.wallet.currency_code IS '[Internal] Wallet currency';
COMMENT ON COLUMN billing.wallet.balance IS '[Internal] Current balance, never negative; default 0';

CREATE TABLE billing.payment_order (
  id                       bigint GENERATED ALWAYS AS IDENTITY,
  account_id               bigint          NOT NULL,
  subscription_id          bigint,
  wallet_id                bigint,
  order_amount             d_money         NOT NULL,
  order_currency_code      d_currency_code NOT NULL,
  payment_gateway_code     d_code          NOT NULL,
  idempotency_key          varchar(64)     NOT NULL,
  gateway_order_token  varchar(100),
  payment_status_code      d_code          NOT NULL DEFAULT 'created',
  created_at               timestamptz     NOT NULL DEFAULT now(),
  created_by               bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at               timestamptz     NOT NULL DEFAULT now(),
  updated_by               bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_payment_order PRIMARY KEY (id),
  CONSTRAINT uq_payment_order_idempotency_key UNIQUE (idempotency_key),
  CONSTRAINT uq_payment_order_gateway_order_token UNIQUE (payment_gateway_code, gateway_order_token),
  CONSTRAINT fk_payment_order_account_id FOREIGN KEY (account_id) REFERENCES org.account (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_payment_order_subscription_id FOREIGN KEY (subscription_id) REFERENCES billing.subscription (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_payment_order_wallet_id FOREIGN KEY (wallet_id) REFERENCES billing.wallet (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_payment_order_order_currency_code FOREIGN KEY (order_currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_payment_order_payment_gateway_code FOREIGN KEY (payment_gateway_code) REFERENCES ref.payment_gateway (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_payment_order_payment_status_code FOREIGN KEY (payment_status_code) REFERENCES ref.payment_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_payment_order_single_purpose CHECK (num_nonnulls(subscription_id, wallet_id) = 1),
  CONSTRAINT ck_payment_order_order_amount CHECK (order_amount > 0)
);
CREATE INDEX idx_payment_order_account_id ON billing.payment_order (account_id, created_at);
CREATE INDEX idx_payment_order_subscription_id ON billing.payment_order (subscription_id) WHERE subscription_id IS NOT NULL;
CREATE INDEX idx_payment_order_wallet_id ON billing.payment_order (wallet_id) WHERE wallet_id IS NOT NULL;
COMMENT ON TABLE  billing.payment_order IS '[hard-delete] Payment order sent to the gateway for a subscription or a wallet recharge; no card or bank data is stored (docket Section 6). Status follows payment_event';
COMMENT ON COLUMN billing.payment_order.account_id IS '[Internal] Paying account';
COMMENT ON COLUMN billing.payment_order.subscription_id IS '[Internal] Subscription paid for; null: wallet recharge';
COMMENT ON COLUMN billing.payment_order.wallet_id IS '[Internal] Wallet recharged; null: subscription payment';
COMMENT ON COLUMN billing.payment_order.order_amount IS '[Internal] Amount charged';
COMMENT ON COLUMN billing.payment_order.order_currency_code IS '[Internal] Currency of order_amount';
COMMENT ON COLUMN billing.payment_order.payment_gateway_code IS '[Internal] razorpay, stripe';
COMMENT ON COLUMN billing.payment_order.idempotency_key IS '[Internal] Client key so a retried checkout creates one order';
COMMENT ON COLUMN billing.payment_order.gateway_order_token IS '[Sensitive] Opaque gateway order token (payment reference, unique per gateway); null: not yet registered with the gateway';
COMMENT ON COLUMN billing.payment_order.payment_status_code IS '[Internal] created, authorised, captured, failed, partially_refunded, refunded; default created';

CREATE TABLE billing.payment_event (
  id                    bigint GENERATED ALWAYS AS IDENTITY,
  payment_order_id      bigint          NOT NULL,
  payment_gateway_code  d_code          NOT NULL,
  gateway_event_id      varchar(100)    NOT NULL,
  payment_status_code   d_code          NOT NULL,
  event_amount          d_money,
  event_currency_code   d_currency_code,
  received_at           timestamptz     NOT NULL DEFAULT now(),
  created_at            timestamptz     NOT NULL DEFAULT now(),
  created_by            bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_payment_event PRIMARY KEY (id),
  CONSTRAINT uq_payment_event_gateway_event UNIQUE (payment_gateway_code, gateway_event_id),
  CONSTRAINT fk_payment_event_payment_order_id FOREIGN KEY (payment_order_id) REFERENCES billing.payment_order (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_payment_event_payment_gateway_code FOREIGN KEY (payment_gateway_code) REFERENCES ref.payment_gateway (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_payment_event_payment_status_code FOREIGN KEY (payment_status_code) REFERENCES ref.payment_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_payment_event_event_currency_code FOREIGN KEY (event_currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_payment_event_amount_pair CHECK ((event_amount IS NULL) = (event_currency_code IS NULL))
);
CREATE INDEX idx_payment_event_payment_order_id ON billing.payment_event (payment_order_id, received_at);
COMMENT ON TABLE  billing.payment_event IS '[append-only] [integration-write] Gateway webhook event (payment transaction history). A replayed event is rejected by (gateway, event id); each event moves the order status';
COMMENT ON COLUMN billing.payment_event.payment_order_id IS '[Internal] Order the event is about';
COMMENT ON COLUMN billing.payment_event.payment_gateway_code IS '[Internal] Gateway that sent the event';
COMMENT ON COLUMN billing.payment_event.gateway_event_id IS '[Internal] Gateway event id; unique per gateway (idempotency); nofk: external gateway identifier';
COMMENT ON COLUMN billing.payment_event.payment_status_code IS '[Internal] Order status the event reports';
COMMENT ON COLUMN billing.payment_event.event_amount IS '[Internal] Amount in the event; null: status-only event (failure notice)';
COMMENT ON COLUMN billing.payment_event.event_currency_code IS '[Internal] Currency of event_amount; null: no amount in the event';
COMMENT ON COLUMN billing.payment_event.received_at IS '[Internal] When the webhook arrived (UTC)';

CREATE FUNCTION billing.apply_payment_event() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
BEGIN
  UPDATE billing.payment_order SET payment_status_code = NEW.payment_status_code WHERE id = NEW.payment_order_id;
  RETURN NULL;
END
$$;
CREATE TRIGGER trg_payment_event_apply AFTER INSERT ON billing.payment_event
  FOR EACH ROW EXECUTE FUNCTION billing.apply_payment_event();

CREATE TABLE billing.invoice (
  id                bigint GENERATED ALWAYS AS IDENTITY,
  account_id        bigint          NOT NULL,
  payment_order_id  bigint          NOT NULL,
  invoice_number    varchar(30)     NOT NULL,
  invoice_status_code d_code        NOT NULL DEFAULT 'issued',
  issued_on         date            NOT NULL,
  net_amount        d_money         NOT NULL,
  tax_amount        d_money         NOT NULL,
  total_amount      d_money         NOT NULL,
  currency_code     d_currency_code NOT NULL,
  created_at        timestamptz     NOT NULL DEFAULT now(),
  created_by        bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at        timestamptz     NOT NULL DEFAULT now(),
  updated_by        bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_invoice PRIMARY KEY (id),
  CONSTRAINT uq_invoice_invoice_number UNIQUE (invoice_number),
  CONSTRAINT uq_invoice_payment_order_id UNIQUE (payment_order_id),
  CONSTRAINT fk_invoice_account_id FOREIGN KEY (account_id) REFERENCES org.account (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_payment_order_id FOREIGN KEY (payment_order_id) REFERENCES billing.payment_order (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_invoice_status_code FOREIGN KEY (invoice_status_code) REFERENCES ref.invoice_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_invoice_currency_code FOREIGN KEY (currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_invoice_amounts CHECK (net_amount >= 0 AND tax_amount >= 0 AND total_amount = net_amount + tax_amount)
);
CREATE INDEX idx_invoice_account_id ON billing.invoice (account_id, issued_on);
COMMENT ON TABLE  billing.invoice IS '[hard-delete] Tax invoice for a payment order; corrections void the invoice and issue a new one';
COMMENT ON COLUMN billing.invoice.account_id IS '[Internal] Invoiced account';
COMMENT ON COLUMN billing.invoice.payment_order_id IS '[Internal] Order invoiced (one invoice per order)';
COMMENT ON COLUMN billing.invoice.invoice_number IS '[Internal] Sequential legal invoice number, max 30';
COMMENT ON COLUMN billing.invoice.invoice_status_code IS '[Internal] issued, paid, void; default issued';
COMMENT ON COLUMN billing.invoice.issued_on IS '[Internal] Invoice date';
COMMENT ON COLUMN billing.invoice.net_amount IS '[Internal] Amount before tax';
COMMENT ON COLUMN billing.invoice.tax_amount IS '[Internal] Tax (GST) amount';
COMMENT ON COLUMN billing.invoice.total_amount IS '[Internal] net_amount + tax_amount';
COMMENT ON COLUMN billing.invoice.currency_code IS '[Internal] Currency of all amounts';

CREATE TABLE billing.refund (
  id                        bigint GENERATED ALWAYS AS IDENTITY,
  payment_order_id          bigint          NOT NULL,
  refund_amount             d_money         NOT NULL,
  refund_currency_code      d_currency_code NOT NULL,
  refund_status_code        d_code          NOT NULL DEFAULT 'requested',
  refund_reason             varchar(500)    NOT NULL,
  gateway_refund_token  varchar(100),
  requested_at              timestamptz     NOT NULL DEFAULT now(),
  processed_at              timestamptz,
  created_at                timestamptz     NOT NULL DEFAULT now(),
  created_by                bigint          NOT NULL DEFAULT public.current_actor_id(),
  updated_at                timestamptz     NOT NULL DEFAULT now(),
  updated_by                bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_refund PRIMARY KEY (id),
  CONSTRAINT uq_refund_gateway_refund_token UNIQUE (gateway_refund_token),
  CONSTRAINT fk_refund_payment_order_id FOREIGN KEY (payment_order_id) REFERENCES billing.payment_order (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_refund_refund_currency_code FOREIGN KEY (refund_currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_refund_refund_status_code FOREIGN KEY (refund_status_code) REFERENCES ref.refund_status (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_refund_refund_amount CHECK (refund_amount > 0),
  CONSTRAINT ck_refund_processed CHECK ((refund_status_code = 'processed') = (processed_at IS NOT NULL))
);
CREATE INDEX idx_refund_payment_order_id ON billing.refund (payment_order_id);
COMMENT ON TABLE  billing.refund IS '[hard-delete] Refund against a captured payment; the sum of non-failed refunds never exceeds the payment (trg_refund_within_payment)';
COMMENT ON COLUMN billing.refund.payment_order_id IS '[Internal] Payment refunded';
COMMENT ON COLUMN billing.refund.refund_amount IS '[Internal] Amount refunded';
COMMENT ON COLUMN billing.refund.refund_currency_code IS '[Internal] Must equal the order currency';
COMMENT ON COLUMN billing.refund.refund_status_code IS '[Internal] requested, processed, failed; default requested';
COMMENT ON COLUMN billing.refund.refund_reason IS '[Internal] Why, max 500';
COMMENT ON COLUMN billing.refund.gateway_refund_token IS '[Sensitive] Opaque gateway refund token (payment reference, unique); null: not sent to the gateway yet';
COMMENT ON COLUMN billing.refund.requested_at IS '[Internal] Request instant (UTC)';
COMMENT ON COLUMN billing.refund.processed_at IS '[Internal] When the gateway confirmed (UTC); null: not processed';

CREATE FUNCTION billing.check_refund() RETURNS trigger
LANGUAGE plpgsql AS
$$
DECLARE
  v_order    billing.payment_order;
  v_refunded numeric;
BEGIN
  -- serialise refunds of one order
  SELECT * INTO v_order FROM billing.payment_order WHERE id = NEW.payment_order_id FOR UPDATE;
  IF v_order.payment_status_code NOT IN ('captured', 'partially_refunded') THEN
    RAISE EXCEPTION 'trg_refund_within_payment: order % is %, only captured payments can be refunded',
                    NEW.payment_order_id, v_order.payment_status_code USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.refund_currency_code <> v_order.order_currency_code THEN
    RAISE EXCEPTION 'trg_refund_within_payment: refund currency % differs from the payment currency %',
                    NEW.refund_currency_code, v_order.order_currency_code USING ERRCODE = 'check_violation';
  END IF;
  SELECT coalesce(sum(refund_amount), 0) INTO v_refunded FROM billing.refund
   WHERE payment_order_id = NEW.payment_order_id AND refund_status_code <> 'failed' AND id IS DISTINCT FROM NEW.id;
  IF NEW.refund_status_code <> 'failed' AND v_refunded + NEW.refund_amount > v_order.order_amount THEN
    RAISE EXCEPTION 'trg_refund_within_payment: refunds % + % exceed the payment %', v_refunded, NEW.refund_amount, v_order.order_amount
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_refund_within_payment BEFORE INSERT OR UPDATE OF refund_amount, refund_status_code ON billing.refund
  FOR EACH ROW EXECUTE FUNCTION billing.check_refund();

CREATE TABLE billing.wallet_ledger_entry (
  id                      bigint GENERATED ALWAYS AS IDENTITY,
  wallet_id               bigint          NOT NULL,
  ledger_entry_type_code  d_code          NOT NULL,
  amount                  d_money         NOT NULL,
  currency_code           d_currency_code NOT NULL,
  balance_after           d_money         NOT NULL,
  reverses_wallet_ledger_entry_id       bigint,
  payment_order_id        bigint,
  refund_id               bigint,
  idempotency_key         varchar(64)     NOT NULL,
  posted_at               timestamptz     NOT NULL DEFAULT now(),
  created_at              timestamptz     NOT NULL DEFAULT now(),
  created_by              bigint          NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_wallet_ledger_entry PRIMARY KEY (id),
  CONSTRAINT uq_wallet_ledger_entry_idempotency_key UNIQUE (idempotency_key),
  CONSTRAINT uq_wallet_ledger_entry_reverses_wallet_ledger_entry_id UNIQUE (reverses_wallet_ledger_entry_id),
  CONSTRAINT fk_wallet_ledger_entry_wallet_id FOREIGN KEY (wallet_id) REFERENCES billing.wallet (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_wallet_ledger_entry_ledger_entry_type_code FOREIGN KEY (ledger_entry_type_code) REFERENCES ref.ledger_entry_type (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_wallet_ledger_entry_currency_code FOREIGN KEY (currency_code) REFERENCES ref.currency (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_wallet_ledger_entry_reverses_wallet_ledger_entry_id FOREIGN KEY (reverses_wallet_ledger_entry_id) REFERENCES billing.wallet_ledger_entry (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_wallet_ledger_entry_payment_order_id FOREIGN KEY (payment_order_id) REFERENCES billing.payment_order (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_wallet_ledger_entry_refund_id FOREIGN KEY (refund_id) REFERENCES billing.refund (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_wallet_ledger_entry_amount_non_zero CHECK (amount <> 0),
  CONSTRAINT ck_wallet_ledger_entry_balance_after CHECK (balance_after >= 0),
  CONSTRAINT ck_wallet_ledger_entry_sign CHECK (
       (ledger_entry_type_code IN ('recharge', 'grant') AND amount > 0)
    OR (ledger_entry_type_code IN ('consumption', 'refund') AND amount < 0)
    OR  ledger_entry_type_code = 'correction'),
  CONSTRAINT ck_wallet_ledger_entry_correction CHECK ((ledger_entry_type_code = 'correction') = (reverses_wallet_ledger_entry_id IS NOT NULL)),
  CONSTRAINT ck_wallet_ledger_entry_recharge_paid CHECK (ledger_entry_type_code <> 'recharge' OR payment_order_id IS NOT NULL),
  CONSTRAINT ck_wallet_ledger_entry_refund_link CHECK ((ledger_entry_type_code = 'refund') = (refund_id IS NOT NULL))
);
CREATE INDEX idx_wallet_ledger_entry_wallet_id ON billing.wallet_ledger_entry (wallet_id, posted_at);
CREATE INDEX idx_wallet_ledger_entry_payment_order_id ON billing.wallet_ledger_entry (payment_order_id) WHERE payment_order_id IS NOT NULL;
CREATE INDEX idx_wallet_ledger_entry_refund_id ON billing.wallet_ledger_entry (refund_id) WHERE refund_id IS NOT NULL;
COMMENT ON TABLE  billing.wallet_ledger_entry IS '[append-only] [api-write] Wallet ledger: every recharge, consumption, refund, grant and correction (RG10). A correction reverses an earlier entry by a new row with the opposite amount';
COMMENT ON COLUMN billing.wallet_ledger_entry.wallet_id IS '[Internal] Wallet';
COMMENT ON COLUMN billing.wallet_ledger_entry.ledger_entry_type_code IS '[Internal] recharge, consumption, refund, grant, correction';
COMMENT ON COLUMN billing.wallet_ledger_entry.amount IS '[Internal] Signed amount: positive credits, negative debits (sign checked per type)';
COMMENT ON COLUMN billing.wallet_ledger_entry.currency_code IS '[Internal] Currency of amount and balance_after (the wallet currency)';
COMMENT ON COLUMN billing.wallet_ledger_entry.balance_after IS '[Internal] Wallet balance after this entry (running balance, never negative)';
COMMENT ON COLUMN billing.wallet_ledger_entry.reverses_wallet_ledger_entry_id IS '[Internal] Entry this correction reverses (each entry reversed at most once); null: not a correction';
COMMENT ON COLUMN billing.wallet_ledger_entry.payment_order_id IS '[Internal] Payment that funded a recharge; null: not a recharge';
COMMENT ON COLUMN billing.wallet_ledger_entry.refund_id IS '[Internal] Refund that debited the wallet; null: not a refund';
COMMENT ON COLUMN billing.wallet_ledger_entry.idempotency_key IS '[Internal] Caller key; posting the same key twice returns the first entry';
COMMENT ON COLUMN billing.wallet_ledger_entry.posted_at IS '[Internal] Posting instant (UTC)';

-- The only write path for wallet money (B47). Locks the wallet row, so concurrent postings on one wallet serialise and
-- the balance can never be driven negative by a race.
CREATE FUNCTION billing.post_ledger_entry(p_wallet_id bigint, p_ledger_entry_type_code text, p_amount numeric,
                                          p_idempotency_key text, p_reverses_wallet_ledger_entry_id bigint DEFAULT NULL,
                                          p_payment_order_id bigint DEFAULT NULL, p_refund_id bigint DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
DECLARE
  v_wallet   billing.wallet;
  v_original billing.wallet_ledger_entry;
  v_existing bigint;
  v_amount   numeric := p_amount;
  v_balance  numeric;
  v_id       bigint;
BEGIN
  SELECT * INTO v_wallet FROM billing.wallet WHERE id = p_wallet_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'billing.post_ledger_entry: wallet % does not exist', p_wallet_id USING ERRCODE = 'foreign_key_violation';
  END IF;
  -- idempotent: the same key returns the entry already posted
  SELECT id INTO v_existing FROM billing.wallet_ledger_entry WHERE idempotency_key = p_idempotency_key;
  IF FOUND THEN
    RETURN v_existing;
  END IF;
  IF p_ledger_entry_type_code = 'correction' THEN
    SELECT * INTO v_original FROM billing.wallet_ledger_entry WHERE id = p_reverses_wallet_ledger_entry_id;
    IF NOT FOUND OR v_original.wallet_id <> p_wallet_id THEN
      RAISE EXCEPTION 'billing.post_ledger_entry: entry % is not in wallet %', p_reverses_wallet_ledger_entry_id, p_wallet_id
        USING ERRCODE = 'check_violation';
    END IF;
    v_amount := -v_original.amount;   -- a correction exactly reverses the original
  END IF;
  v_balance := v_wallet.balance + v_amount;
  UPDATE billing.wallet SET balance = v_balance WHERE id = p_wallet_id;   -- ck_wallet_balance_non_negative guards here
  INSERT INTO billing.wallet_ledger_entry (wallet_id, ledger_entry_type_code, amount, currency_code, balance_after,
                                           reverses_wallet_ledger_entry_id, payment_order_id, refund_id, idempotency_key)
  VALUES (p_wallet_id, p_ledger_entry_type_code, v_amount, v_wallet.currency_code, v_balance,
          p_reverses_wallet_ledger_entry_id, p_payment_order_id, p_refund_id, p_idempotency_key)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$$;

CREATE TABLE billing.credit_consumption (
  id                        bigint GENERATED ALWAYS AS IDENTITY,
  wallet_ledger_entry_id    bigint      NOT NULL,
  consumption_purpose_code  d_code      NOT NULL,
  job_requirement_id        bigint,
  outreach_batch_id         bigint,
  units                     integer     NOT NULL DEFAULT 1,
  created_at                timestamptz NOT NULL DEFAULT now(),
  created_by                bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_credit_consumption PRIMARY KEY (id),
  CONSTRAINT uq_credit_consumption_wallet_ledger_entry_id UNIQUE (wallet_ledger_entry_id),
  CONSTRAINT fk_credit_consumption_wallet_ledger_entry_id FOREIGN KEY (wallet_ledger_entry_id) REFERENCES billing.wallet_ledger_entry (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_credit_consumption_consumption_purpose_code FOREIGN KEY (consumption_purpose_code) REFERENCES ref.consumption_purpose (code) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_credit_consumption_job_requirement_id FOREIGN KEY (job_requirement_id) REFERENCES job.job_requirement (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_credit_consumption_outreach_batch_id FOREIGN KEY (outreach_batch_id) REFERENCES src.outreach_batch (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT ck_credit_consumption_units CHECK (units > 0),
  CONSTRAINT ck_credit_consumption_subject CHECK (
       (consumption_purpose_code = 'job_posting' AND job_requirement_id IS NOT NULL AND outreach_batch_id IS NULL)
    OR (consumption_purpose_code = 'outreach_message' AND outreach_batch_id IS NOT NULL AND job_requirement_id IS NULL)
    OR (consumption_purpose_code IN ('profile_download', 'profile_view') AND job_requirement_id IS NULL AND outreach_batch_id IS NULL))
);
CREATE INDEX idx_credit_consumption_job_requirement_id ON billing.credit_consumption (job_requirement_id) WHERE job_requirement_id IS NOT NULL;
CREATE INDEX idx_credit_consumption_outreach_batch_id ON billing.credit_consumption (outreach_batch_id) WHERE outreach_batch_id IS NOT NULL;
COMMENT ON TABLE  billing.credit_consumption IS '[append-only] [api-write] What a ledger debit paid for: a job posting, an outreach batch, a profile download or view';
COMMENT ON COLUMN billing.credit_consumption.wallet_ledger_entry_id IS '[Internal] Ledger debit (one consumption per debit)';
COMMENT ON COLUMN billing.credit_consumption.consumption_purpose_code IS '[Internal] job_posting, profile_download, profile_view, outreach_message';
COMMENT ON COLUMN billing.credit_consumption.job_requirement_id IS '[Internal] Job posted; null: purpose is not a job posting';
COMMENT ON COLUMN billing.credit_consumption.outreach_batch_id IS '[Internal] Outreach batch sent; null: purpose is not outreach';
COMMENT ON COLUMN billing.credit_consumption.units IS '[Internal] Units consumed (messages, postings); default 1';

-- ---------------------------------------------------------------------------------------------------
-- Profile download history (RG10: actor, subject, timestamp, credit deduction)
CREATE TABLE billing.profile_download_event (
  id                          bigint GENERATED ALWAYS AS IDENTITY,
  candidate_profile_id        bigint      NOT NULL,
  downloader_app_user_id      bigint      NOT NULL,
  downloader_organisation_id  bigint,
  wallet_ledger_entry_id      bigint      NOT NULL,
  downloaded_at               timestamptz NOT NULL DEFAULT now(),
  created_at                  timestamptz NOT NULL DEFAULT now(),
  created_by                  bigint      NOT NULL DEFAULT public.current_actor_id(),
  CONSTRAINT pk_profile_download_event PRIMARY KEY (id),
  CONSTRAINT uq_profile_download_event_wallet_ledger_entry_id UNIQUE (wallet_ledger_entry_id),
  CONSTRAINT fk_profile_download_event_candidate_profile_id FOREIGN KEY (candidate_profile_id) REFERENCES profile.candidate_profile (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_profile_download_event_downloader_app_user_id FOREIGN KEY (downloader_app_user_id) REFERENCES admin.app_user (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_profile_download_event_downloader_organisation_id FOREIGN KEY (downloader_organisation_id) REFERENCES org.organisation (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  CONSTRAINT fk_profile_download_event_wallet_ledger_entry_id FOREIGN KEY (wallet_ledger_entry_id) REFERENCES billing.wallet_ledger_entry (id) ON UPDATE NO ACTION ON DELETE RESTRICT
);
CREATE INDEX idx_profile_download_event_candidate_profile_id ON billing.profile_download_event (candidate_profile_id, downloaded_at);
CREATE INDEX idx_profile_download_event_downloader_app_user_id ON billing.profile_download_event (downloader_app_user_id, downloaded_at);
CREATE INDEX idx_profile_download_event_downloader_organisation_id ON billing.profile_download_event (downloader_organisation_id) WHERE downloader_organisation_id IS NOT NULL;
COMMENT ON TABLE  billing.profile_download_event IS '[append-only] [api-write] Which recruiter or employer downloaded which profile, when, and the ledger debit that paid for it. Partition monthly at full scale (M21)';
COMMENT ON COLUMN billing.profile_download_event.candidate_profile_id IS '[Internal] Profile downloaded (subject)';
COMMENT ON COLUMN billing.profile_download_event.downloader_app_user_id IS '[Internal] User who downloaded (actor)';
COMMENT ON COLUMN billing.profile_download_event.downloader_organisation_id IS '[Internal] Organisation the downloader acted for; null: independent consultant';
COMMENT ON COLUMN billing.profile_download_event.wallet_ledger_entry_id IS '[Internal] Ledger debit for this download (required; one download per debit)';
COMMENT ON COLUMN billing.profile_download_event.downloaded_at IS '[Internal] Download instant (UTC)';

CREATE FUNCTION billing.check_download_debit() RETURNS trigger
LANGUAGE plpgsql AS
$$
BEGIN
  IF NEW.wallet_ledger_entry_id IS NULL THEN
    RETURN NEW;                               -- the NOT NULL constraint reports a missing debit by column name
  END IF;
  IF NOT EXISTS (SELECT 1 FROM billing.wallet_ledger_entry
                  WHERE id = NEW.wallet_ledger_entry_id AND ledger_entry_type_code = 'consumption' AND amount < 0) THEN
    RAISE EXCEPTION 'trg_profile_download_event_debit: ledger entry % is not a consumption debit', NEW.wallet_ledger_entry_id
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$;
CREATE TRIGGER trg_profile_download_event_debit BEFORE INSERT ON billing.profile_download_event
  FOR EACH ROW EXECUTE FUNCTION billing.check_download_debit();

-- Download API: debit + consumption + download event + audit in one transaction
CREATE FUNCTION billing.record_profile_download(p_candidate_profile_id bigint, p_wallet_id bigint, p_price numeric,
                                                p_idempotency_key text, p_downloader_organisation_id bigint DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, public AS
$$
DECLARE
  v_entry bigint;
  v_event bigint;
BEGIN
  v_entry := billing.post_ledger_entry(p_wallet_id, 'consumption', -abs(p_price), p_idempotency_key);
  SELECT id INTO v_event FROM billing.profile_download_event WHERE wallet_ledger_entry_id = v_entry;
  IF FOUND THEN
    RETURN v_event;                       -- retried call: same debit, same download
  END IF;
  INSERT INTO billing.credit_consumption (wallet_ledger_entry_id, consumption_purpose_code) VALUES (v_entry, 'profile_download');
  INSERT INTO billing.profile_download_event (candidate_profile_id, downloader_app_user_id, downloader_organisation_id, wallet_ledger_entry_id)
  VALUES (p_candidate_profile_id, public.current_actor_id(), p_downloader_organisation_id, v_entry)
  RETURNING id INTO v_event;
  PERFORM audit.log_event('profile_downloaded', 'profile.candidate_profile', p_candidate_profile_id,
                          jsonb_build_object('wallet_ledger_entry_id', v_entry, 'price', abs(p_price)));
  RETURN v_event;
END
$$;

REVOKE ALL ON FUNCTION billing.post_ledger_entry(bigint, text, numeric, text, bigint, bigint, bigint),
                       billing.record_profile_download(bigint, bigint, numeric, text, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION billing.post_ledger_entry(bigint, text, numeric, text, bigint, bigint, bigint),
                          billing.record_profile_download(bigint, bigint, numeric, text, bigint) TO talentra_app;

-- Paid profile views link their debit too (profile_view_event is Phase 1; the ledger exists from here)
ALTER TABLE profile.profile_view_event
  ADD COLUMN wallet_ledger_entry_id bigint,
  ADD CONSTRAINT fk_profile_view_event_wallet_ledger_entry_id FOREIGN KEY (wallet_ledger_entry_id)
    REFERENCES billing.wallet_ledger_entry (id) ON UPDATE NO ACTION ON DELETE RESTRICT,
  ADD CONSTRAINT uq_profile_view_event_wallet_ledger_entry_id UNIQUE (wallet_ledger_entry_id);
COMMENT ON COLUMN profile.profile_view_event.wallet_ledger_entry_id IS '[Internal] Ledger debit when the view was paid; null: free view (plan entitlement or own applicant)';

-- seed: two plans
INSERT INTO billing.plan (code, plan_name, label_key, billing_cycle_code, price_amount, price_currency_code, max_users, max_devices_per_user)
VALUES ('recruiter_starter', 'Recruiter Starter', ref.label_for('plan', 'Recruiter Starter'), 'monthly', 4999, 'INR', 3, 2),
       ('recruiter_pro',     'Recruiter Pro',     ref.label_for('plan', 'Recruiter Pro'),     'annual', 149999, 'INR', 25, 3);
INSERT INTO billing.plan_entitlement (plan_id, entitlement_type_code, quantity_per_cycle)
SELECT p.id, v.ent, v.qty
  FROM (VALUES ('recruiter_starter', 'job_post_credit', 5), ('recruiter_starter', 'profile_download', 50),
               ('recruiter_pro', 'job_post_credit', 100), ('recruiter_pro', 'profile_download', 2000),
               ('recruiter_pro', 'outreach_message', 10000)) v(plan_code, ent, qty)
  JOIN billing.plan p ON p.code = v.plan_code;
