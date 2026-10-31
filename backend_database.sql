
-- =====================================================
-- MAKE A TON HACKATHON
-- SUBSCRIPTION MANAGEMENT SYSTEM
-- BACKEND DATABASE
-- Database: Supabase PostgreSQL
-- =====================================================


-- =====================================================
-- MODULE 1: USER PROFILES
-- =====================================================

CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role TEXT DEFAULT 'customer',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;


-- Automatically create profile after user registration
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, role)
    VALUES (
        NEW.id,
        NEW.raw_user_meta_data ->> 'full_name',
        'customer'
    );

    RETURN NEW;
END;
$$;

-- Original signup trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();


-- =====================================================
-- MODULE 2: PRODUCTS
-- =====================================================

CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    product_type TEXT,
    sales_price NUMERIC(12,2) NOT NULL DEFAULT 0,
    cost_price NUMERIC(12,2) NOT NULL DEFAULT 0,
    notes TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;


-- =====================================================
-- MODULE 3: PRODUCT VARIANTS
-- =====================================================

CREATE TABLE IF NOT EXISTS public.product_variants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    product_id UUID NOT NULL
        REFERENCES public.products(id) ON DELETE CASCADE,
    attribute_name TEXT NOT NULL,
    attribute_value TEXT NOT NULL,
    price_adjustment NUMERIC(12,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.product_variants ENABLE ROW LEVEL SECURITY;


-- =====================================================
-- MODULE 4: SUBSCRIPTION PLANS
-- =====================================================

CREATE TABLE IF NOT EXISTS public.subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,

    billing_interval TEXT NOT NULL
        CHECK (
            billing_interval IN (
                'daily', 'weekly', 'monthly', 'yearly'
            )
        ),

    min_quantity INTEGER DEFAULT 1,
    available_from DATE,
    available_until DATE,

    auto_close BOOLEAN DEFAULT FALSE,
    allow_early_close BOOLEAN DEFAULT FALSE,
    allow_pause BOOLEAN DEFAULT FALSE,
    allow_renewal BOOLEAN DEFAULT TRUE,

    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.subscription_plans ENABLE ROW LEVEL SECURITY;


-- =====================================================
-- MODULE 5: PLAN ITEMS
-- =====================================================

CREATE TABLE IF NOT EXISTS public.plan_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    plan_id UUID NOT NULL
        REFERENCES public.subscription_plans(id) ON DELETE CASCADE,

    product_id UUID NOT NULL
        REFERENCES public.products(id),

    variant_id UUID
        REFERENCES public.product_variants(id),

    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price NUMERIC(12,2) NOT NULL DEFAULT 0
);

ALTER TABLE public.plan_items ENABLE ROW LEVEL SECURITY;


-- =====================================================
-- MODULE 6: SUBSCRIPTIONS
-- =====================================================

CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    subscription_number TEXT UNIQUE NOT NULL,

    customer_id UUID NOT NULL
        REFERENCES public.profiles(id),

    plan_id UUID NOT NULL
        REFERENCES public.subscription_plans(id),

    start_date DATE NOT NULL,
    expiry_date DATE,
    payment_terms TEXT,

    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (
            status IN (
                'draft',
                'quotation',
                'confirmed',
                'active',
                'paused',
                'closed'
            )
        ),

    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;


-- =====================================================
-- MODULE 7: SUBSCRIPTION ITEMS
-- =====================================================

CREATE TABLE IF NOT EXISTS public.subscription_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    subscription_id UUID NOT NULL
        REFERENCES public.subscriptions(id) ON DELETE CASCADE,

    product_id UUID NOT NULL
        REFERENCES public.products(id),

    variant_id UUID
        REFERENCES public.product_variants(id),

    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price NUMERIC(12,2) NOT NULL DEFAULT 0,
    tax_amount NUMERIC(12,2) DEFAULT 0,
    subtotal NUMERIC(12,2) DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.subscription_items ENABLE ROW LEVEL SECURITY;


-- =====================================================
-- MODULE 8: INVOICES
-- =====================================================

CREATE TABLE IF NOT EXISTS public.invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_number TEXT UNIQUE NOT NULL,

    customer_id UUID NOT NULL
        REFERENCES public.profiles(id),

    subscription_id UUID
        REFERENCES public.subscriptions(id),

    invoice_date DATE NOT NULL DEFAULT CURRENT_DATE,
    due_date DATE,

    subtotal NUMERIC(12,2) DEFAULT 0,
    tax_total NUMERIC(12,2) DEFAULT 0,
    discount_total NUMERIC(12,2) DEFAULT 0,

    total_amount NUMERIC(12,2) DEFAULT 0,
    amount_paid NUMERIC(12,2) DEFAULT 0,

    status TEXT NOT NULL DEFAULT 'draft'
        CHECK (
            status IN (
                'draft',
                'confirmed',
                'sent',
                'paid',
                'cancelled'
            )
        ),

    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),

    CHECK (subtotal >= 0),
    CHECK (tax_total >= 0),
    CHECK (discount_total >= 0),
    CHECK (total_amount >= 0),
    CHECK (amount_paid >= 0)
);

ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_invoices_customer
ON public.invoices(customer_id);

CREATE INDEX IF NOT EXISTS idx_invoices_subscription
ON public.invoices(subscription_id);

CREATE INDEX IF NOT EXISTS idx_invoices_status
ON public.invoices(status);


-- =====================================================
-- MODULE 9: INVOICE ITEMS
-- =====================================================

CREATE TABLE IF NOT EXISTS public.invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_id UUID NOT NULL
        REFERENCES public.invoices(id) ON DELETE CASCADE,

    product_id UUID
        REFERENCES public.products(id),

    description TEXT,

    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price NUMERIC(12,2) NOT NULL DEFAULT 0,

    tax_rate NUMERIC(5,2) DEFAULT 0,
    tax_amount NUMERIC(12,2) DEFAULT 0,
    discount_amount NUMERIC(12,2) DEFAULT 0,
    line_total NUMERIC(12,2) DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice
ON public.invoice_items(invoice_id);


-- =====================================================
-- MODULE 10: PAYMENTS
-- =====================================================

CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    invoice_id UUID NOT NULL
        REFERENCES public.invoices(id) ON DELETE RESTRICT,

    payment_method TEXT NOT NULL
        CHECK (
            payment_method IN (
                'cash',
                'bank_transfer',
                'upi',
                'card',
                'other'
            )
        ),

    amount NUMERIC(12,2) NOT NULL CHECK (amount > 0),

    payment_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reference_number TEXT,
    notes TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_payments_invoice
ON public.payments(invoice_id);

CREATE INDEX IF NOT EXISTS idx_payments_date
ON public.payments(payment_date);


-- =====================================================
-- MODULE 11: DISCOUNT RULES
-- =====================================================

CREATE TABLE IF NOT EXISTS public.discount_rules (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL,

    discount_type TEXT NOT NULL
        CHECK (discount_type IN ('fixed', 'percentage')),

    discount_value NUMERIC(12,2) NOT NULL
        CHECK (discount_value > 0),

    min_purchase_amount NUMERIC(12,2)
        NOT NULL DEFAULT 0
        CHECK (min_purchase_amount >= 0),

    min_quantity INTEGER
        NOT NULL DEFAULT 1
        CHECK (min_quantity > 0),

    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,

    usage_limit INTEGER
        CHECK (usage_limit IS NULL OR usage_limit > 0),

    times_used INTEGER NOT NULL DEFAULT 0
        CHECK (times_used >= 0),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CHECK (
        discount_type <> 'percentage'
        OR discount_value <= 100
    ),

    CHECK (
        start_date IS NULL
        OR end_date IS NULL
        OR end_date > start_date
    )
);

ALTER TABLE public.discount_rules ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_discount_rules_active
ON public.discount_rules(is_active);

CREATE INDEX IF NOT EXISTS idx_discount_rules_dates
ON public.discount_rules(start_date, end_date);


-- =====================================================
-- MODULE 12: TAXES
-- =====================================================

CREATE TABLE IF NOT EXISTS public.taxes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    name TEXT NOT NULL UNIQUE,

    tax_rate NUMERIC(5,2) NOT NULL
        CHECK (tax_rate >= 0 AND tax_rate <= 100),

    description TEXT,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.taxes ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_taxes_active
ON public.taxes(is_active);


-- =====================================================
-- MODULE 13: TAX AND DISCOUNT LINKS
-- =====================================================

ALTER TABLE public.invoice_items
ADD COLUMN IF NOT EXISTS tax_id UUID
REFERENCES public.taxes(id) ON DELETE SET NULL;

ALTER TABLE public.invoices
ADD COLUMN IF NOT EXISTS discount_rule_id UUID
REFERENCES public.discount_rules(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_invoice_items_tax
ON public.invoice_items(tax_id);

CREATE INDEX IF NOT EXISTS idx_invoices_discount_rule
ON public.invoices(discount_rule_id);


-- =====================================================
-- END OF DATABASE SCHEMA
-- NOTE: RLS POLICIES STILL NEED TO BE CONFIGURED.
-- =====================================================



-- =========================================
-- MODULE 14: PROFILE SECURITY AND RLS
-- =========================================

-- 14.1 Allow users to view their own profile
DROP POLICY IF EXISTS "Users view own profile"
ON public.profiles;

CREATE POLICY "Users view own profile"
ON public.profiles
FOR SELECT
TO authenticated
USING (id = (SELECT auth.uid()));


-- 14.2 Allow admins to view all profiles
DROP POLICY IF EXISTS "Admins view all profiles"
ON public.profiles;

CREATE POLICY "Admins view all profiles"
ON public.profiles
FOR SELECT
TO authenticated
USING (public.is_admin());


-- 14.3 Allow admins to manage profiles through RLS
DROP POLICY IF EXISTS "Admins manage profiles"
ON public.profiles;

CREATE POLICY "Admins manage profiles"
ON public.profiles
FOR ALL
TO authenticated
USING (public.is_admin())
WITH CHECK (public.is_admin());


-- 14.4 Restrict direct profile modifications
-- Users cannot directly insert, update, or delete profiles.
-- Role changes will be handled through a secure admin function later.

REVOKE INSERT, UPDATE, DELETE
ON public.profiles
FROM authenticated;

GRANT SELECT
ON public.profiles
TO authenticated;


-- =========================================
-- END OF MODULE 14
-- =========================================



-- =========================================
-- MODULE 15: SECURE ADMIN ROLE MANAGEMENT
-- =========================================

-- 15.1 Create secure function to assign user roles

CREATE OR REPLACE FUNCTION public.set_user_role(
    p_user_id UUID,
    p_role TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN

    -- Only existing admins can change roles
    IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Access denied: Admin permission required';
    END IF;

    -- Validate user ID
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'User ID cannot be empty';
    END IF;

    -- Validate allowed roles
    IF p_role IS NULL OR p_role NOT IN ('admin', 'staff', 'customer') THEN
        RAISE EXCEPTION 'Invalid role. Allowed: admin, staff, customer';
    END IF;

    -- Prevent admins from changing their own role
    IF p_user_id = (SELECT auth.uid()) THEN
        RAISE EXCEPTION 'You cannot change your own role';
    END IF;

    -- Update the selected user's role
    UPDATE public.profiles
    SET role = p_role
    WHERE id = p_user_id;

    -- Check whether the user exists
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User profile not found';
    END IF;

END;
$$;


-- 15.2 Restrict function execution

REVOKE ALL ON FUNCTION public.set_user_role(UUID, TEXT)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.set_user_role(UUID, TEXT)
TO authenticated;


-- =========================================
-- END OF MODULE 15
-- =========================================



-- =========================================
-- MODULE 16: QUOTE TEMPLATES AND QUOTATION MANAGEMENT
-- =========================================

-- 16.1 Create quotation templates

CREATE TABLE IF NOT EXISTS public.quote_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    template_name TEXT NOT NULL,
    description TEXT,

    default_payment_terms TEXT,
    validity_days INTEGER NOT NULL DEFAULT 30
        CHECK (validity_days > 0),

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_by UUID REFERENCES public.profiles(id)
        ON DELETE SET NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- 16.2 Create quotation template items

CREATE TABLE IF NOT EXISTS public.quote_template_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    template_id UUID NOT NULL
        REFERENCES public.quote_templates(id)
        ON DELETE CASCADE,

    product_id UUID NOT NULL
        REFERENCES public.products(id)
        ON DELETE RESTRICT,

    variant_id UUID
        REFERENCES public.product_variants(id)
        ON DELETE SET NULL,

    quantity INTEGER NOT NULL DEFAULT 1
        CHECK (quantity > 0),

    unit_price NUMERIC(12,2) NOT NULL
        CHECK (unit_price >= 0),

    tax_rate NUMERIC(5,2) NOT NULL DEFAULT 0
        CHECK (tax_rate >= 0 AND tax_rate <= 100),

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- 16.3 Add quotation details to subscriptions

ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS quote_template_id UUID
    REFERENCES public.quote_templates(id)
    ON DELETE SET NULL;

ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS quotation_valid_until DATE;

ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS quotation_notes TEXT;


-- 16.4 Create indexes

CREATE INDEX IF NOT EXISTS idx_quote_templates_active
ON public.quote_templates(is_active);

CREATE INDEX IF NOT EXISTS idx_quote_template_items_template
ON public.quote_template_items(template_id);

CREATE INDEX IF NOT EXISTS idx_quote_template_items_product
ON public.quote_template_items(product_id);

CREATE INDEX IF NOT EXISTS idx_subscriptions_quote_template
ON public.subscriptions(quote_template_id);


-- 16.5 Enable Row Level Security

ALTER TABLE public.quote_templates
ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.quote_template_items
ENABLE ROW LEVEL SECURITY;


-- 16.6 Admin and Staff policies for quotation templates

DROP POLICY IF EXISTS "Admin staff manage quote templates"
ON public.quote_templates;

CREATE POLICY "Admin staff manage quote templates"
ON public.quote_templates
FOR ALL
TO authenticated
USING (public.is_admin_or_staff())
WITH CHECK (public.is_admin_or_staff());


-- 16.7 Admin and Staff policies for template items

DROP POLICY IF EXISTS "Admin staff manage quote template items"
ON public.quote_template_items;

CREATE POLICY "Admin staff manage quote template items"
ON public.quote_template_items
FOR ALL
TO authenticated
USING (public.is_admin_or_staff())
WITH CHECK (public.is_admin_or_staff());


-- =========================================
-- END OF MODULE 16
-- =========================================



-- =========================================
-- MODULE 17: SUBSCRIPTION LIFECYCLE AND RENEWAL
-- =========================================

-- 17.1 Add renewal tracking fields

ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS renewed_from UUID
    REFERENCES public.subscriptions(id)
    ON DELETE SET NULL;

ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS renewal_count INTEGER NOT NULL DEFAULT 0
    CHECK (renewal_count >= 0);

ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS paused_at TIMESTAMPTZ;

ALTER TABLE public.subscriptions
ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ;


-- 17.2 Create index for renewal tracking

CREATE INDEX IF NOT EXISTS idx_subscriptions_renewed_from
ON public.subscriptions(renewed_from);

CREATE INDEX IF NOT EXISTS idx_subscriptions_status_expiry
ON public.subscriptions(status, expiry_date);


-- 17.3 Validate subscription status changes

CREATE OR REPLACE FUNCTION public.validate_subscription_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN

    IF NEW.status IS DISTINCT FROM OLD.status THEN

        -- Draft can become quotation or confirmed
        IF OLD.status = 'draft'
           AND NEW.status NOT IN ('quotation', 'confirmed') THEN
            RAISE EXCEPTION 'Invalid status change from draft';
        END IF;

        -- Quotation can become confirmed or closed
        IF OLD.status = 'quotation'
           AND NEW.status NOT IN ('confirmed', 'closed') THEN
            RAISE EXCEPTION 'Invalid status change from quotation';
        END IF;

        -- Confirmed can become active or closed
        IF OLD.status = 'confirmed'
           AND NEW.status NOT IN ('active', 'closed') THEN
            RAISE EXCEPTION 'Invalid status change from confirmed';
        END IF;

        -- Active can become paused or closed
        IF OLD.status = 'active'
           AND NEW.status NOT IN ('paused', 'closed') THEN
            RAISE EXCEPTION 'Invalid status change from active';
        END IF;

        -- Paused can become active or closed
        IF OLD.status = 'paused'
           AND NEW.status NOT IN ('active', 'closed') THEN
            RAISE EXCEPTION 'Invalid status change from paused';
        END IF;

        -- Closed subscriptions cannot be reopened
        IF OLD.status = 'closed' THEN
            RAISE EXCEPTION 'Closed subscriptions cannot be changed';
        END IF;

    END IF;

    -- Record pause date
    IF NEW.status = 'paused' AND OLD.status <> 'paused' THEN
        NEW.paused_at = NOW();
    END IF;

    -- Clear pause date when reactivated
    IF NEW.status = 'active' AND OLD.status = 'paused' THEN
        NEW.paused_at = NULL;
    END IF;

    -- Record closing date
    IF NEW.status = 'closed' AND OLD.status <> 'closed' THEN
        NEW.closed_at = NOW();
    END IF;

    RETURN NEW;

END;
$$;


-- 17.4 Create subscription status trigger

DROP TRIGGER IF EXISTS trg_validate_subscription_status
ON public.subscriptions;

CREATE TRIGGER trg_validate_subscription_status
BEFORE UPDATE OF status
ON public.subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.validate_subscription_status();


-- 17.5 Create secure subscription renewal function

CREATE OR REPLACE FUNCTION public.renew_subscription(
    p_subscription_id UUID,
    p_new_start_date DATE,
    p_new_expiry_date DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_original public.subscriptions%ROWTYPE;
    v_new_subscription_id UUID;
    v_new_number TEXT;
BEGIN

    -- Only Admin and Staff can renew subscriptions
    IF NOT public.is_admin_or_staff() THEN
        RAISE EXCEPTION 'Access denied: Admin or Staff permission required';
    END IF;

    IF p_new_start_date IS NULL
       OR p_new_expiry_date IS NULL
       OR p_new_expiry_date < p_new_start_date THEN
        RAISE EXCEPTION 'Invalid renewal dates';
    END IF;

    -- Lock and retrieve original subscription
    SELECT *
    INTO v_original
    FROM public.subscriptions
    WHERE id = p_subscription_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Subscription not found';
    END IF;

    IF v_original.status NOT IN ('active', 'closed') THEN
        RAISE EXCEPTION 'Only active or closed subscriptions can be renewed';
    END IF;

    IF v_original.status = 'closed' THEN
        RAISE EXCEPTION 'Closed subscriptions cannot be renewed';
    END IF;

    -- Check plan renewal permission
    IF NOT EXISTS (
        SELECT 1
        FROM public.subscription_plans
        WHERE id = v_original.plan_id
          AND allow_renewal = TRUE
          AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'This plan does not allow renewal';
    END IF;

    -- Generate a unique subscription number
    v_new_number := 'SUB-' ||
        upper(substr(replace(gen_random_uuid()::TEXT, '-', ''), 1, 12));

    -- Create renewed subscription
    INSERT INTO public.subscriptions (
        subscription_number,
        customer_id,
        plan_id,
        start_date,
        expiry_date,
        payment_terms,
        status,
        renewed_from,
        renewal_count
    )
    VALUES (
        v_new_number,
        v_original.customer_id,
        v_original.plan_id,
        p_new_start_date,
        p_new_expiry_date,
        v_original.payment_terms,
        'confirmed',
        v_original.id,
        v_original.renewal_count + 1
    )
    RETURNING id INTO v_new_subscription_id;

    -- Copy subscription items
    INSERT INTO public.subscription_items (
        subscription_id,
        product_id,
        variant_id,
        quantity,
        unit_price,
        tax_amount,
        subtotal
    )
    SELECT
        v_new_subscription_id,
        product_id,
        variant_id,
        quantity,
        unit_price,
        tax_amount,
        subtotal
    FROM public.subscription_items
    WHERE subscription_id = v_original.id;

    -- Update original renewal count
    UPDATE public.subscriptions
    SET renewal_count = renewal_count + 1
    WHERE id = v_original.id;

    RETURN v_new_subscription_id;

END;
$$;


-- 17.6 Restrict renewal function execution

REVOKE ALL ON FUNCTION public.renew_subscription(UUID, DATE, DATE)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.renew_subscription(UUID, DATE, DATE)
TO authenticated;


-- =========================================
-- END OF MODULE 17
-- =========================================



-- =========================================
-- MODULE 18: AUTOMATED INVOICE GENERATION
-- =========================================

-- 18.1 Add billing period tracking to invoices

ALTER TABLE public.invoices
ADD COLUMN IF NOT EXISTS billing_period_start DATE;

ALTER TABLE public.invoices
ADD COLUMN IF NOT EXISTS billing_period_end DATE;


-- 18.2 Prevent duplicate invoices for the same
-- subscription and billing period

CREATE UNIQUE INDEX IF NOT EXISTS
idx_unique_subscription_billing_period
ON public.invoices (
    subscription_id,
    billing_period_start,
    billing_period_end
)
WHERE subscription_id IS NOT NULL
  AND billing_period_start IS NOT NULL
  AND billing_period_end IS NOT NULL;


-- 18.3 Create invoice generation function

CREATE OR REPLACE FUNCTION public.generate_subscription_invoice(
    p_subscription_id UUID,
    p_period_start DATE,
    p_period_end DATE,
    p_invoice_date DATE,
    p_due_date DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_subscription public.subscriptions%ROWTYPE;
    v_invoice_id UUID;
    v_invoice_number TEXT;
    v_subtotal NUMERIC(12,2);
    v_tax_total NUMERIC(12,2);
    v_total NUMERIC(12,2);
    v_item_count INTEGER;
BEGIN

    -- Only Admin and Staff can generate invoices
    IF NOT public.is_admin_or_staff() THEN
        RAISE EXCEPTION
            'Access denied: Admin or Staff permission required';
    END IF;

    -- Validate dates
    IF p_period_start IS NULL
       OR p_period_end IS NULL
       OR p_invoice_date IS NULL
       OR p_due_date IS NULL
       OR p_period_end < p_period_start
       OR p_due_date < p_invoice_date THEN
        RAISE EXCEPTION 'Invalid invoice or billing dates';
    END IF;

    -- Lock subscription to prevent simultaneous generation
    SELECT *
    INTO v_subscription
    FROM public.subscriptions
    WHERE id = p_subscription_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Subscription not found';
    END IF;

    -- Only active subscriptions can be billed
    IF v_subscription.status <> 'active' THEN
        RAISE EXCEPTION 'Only active subscriptions can be billed';
    END IF;

    -- Validate billing period against subscription dates
    IF p_period_start < v_subscription.start_date
       OR p_period_end > v_subscription.expiry_date THEN
        RAISE EXCEPTION
            'Billing period must fall within subscription dates';
    END IF;

    -- Check for an existing invoice
    IF EXISTS (
        SELECT 1
        FROM public.invoices
        WHERE subscription_id = p_subscription_id
          AND billing_period_start = p_period_start
          AND billing_period_end = p_period_end
    ) THEN
        RAISE EXCEPTION
            'An invoice already exists for this billing period';
    END IF;

    -- Calculate invoice amounts from subscription items
    SELECT
        COALESCE(SUM(subtotal), 0),
        COALESCE(SUM(tax_amount), 0),
        COUNT(*)
    INTO
        v_subtotal,
        v_tax_total,
        v_item_count
    FROM public.subscription_items
    WHERE subscription_id = p_subscription_id;

    IF v_item_count = 0 THEN
        RAISE EXCEPTION 'Subscription has no items to invoice';
    END IF;

    v_total := v_subtotal + v_tax_total;

    -- Generate unique invoice number
    v_invoice_number := 'INV-' ||
        upper(substr(
            replace(gen_random_uuid()::TEXT, '-', ''),
            1,
            12
        ));

    -- Create invoice
    INSERT INTO public.invoices (
        invoice_number,
        customer_id,
        subscription_id,
        invoice_date,
        due_date,
        billing_period_start,
        billing_period_end,
        subtotal,
        tax_total,
        discount_total,
        total_amount,
        amount_paid,
        status
    )
    VALUES (
        v_invoice_number,
        v_subscription.customer_id,
        p_subscription_id,
        p_invoice_date,
        p_due_date,
        p_period_start,
        p_period_end,
        v_subtotal,
        v_tax_total,
        0,
        v_total,
        0,
        'draft'
    )
    RETURNING id INTO v_invoice_id;

    -- Copy subscription items into invoice items
    INSERT INTO public.invoice_items (
        invoice_id,
        product_id,
        description,
        quantity,
        unit_price,
        tax_rate,
        tax_amount,
        discount_amount,
        line_total
    )
    SELECT
        v_invoice_id,
        si.product_id,
        p.name,
        si.quantity,
        si.unit_price,
        CASE
            WHEN si.subtotal > 0
            THEN ROUND(
                (si.tax_amount / si.subtotal) * 100,
                2
            )
            ELSE 0
        END,
        si.tax_amount,
        0,
        si.subtotal + si.tax_amount
    FROM public.subscription_items si
    JOIN public.products p
        ON p.id = si.product_id
    WHERE si.subscription_id = p_subscription_id;

    RETURN v_invoice_id;

END;
$$;


-- 18.4 Restrict invoice generation function execution

REVOKE ALL ON FUNCTION
public.generate_subscription_invoice(
    UUID, DATE, DATE, DATE, DATE
)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
public.generate_subscription_invoice(
    UUID, DATE, DATE, DATE, DATE
)
TO authenticated;


-- 18.5 Create billing lookup index

CREATE INDEX IF NOT EXISTS idx_invoices_billing_dates
ON public.invoices (
    billing_period_start,
    billing_period_end
);


-- =========================================
-- END OF MODULE 18
-- =========================================



-- =========================================
-- MODULE 19: PAYMENT PROCESSING AND BALANCE MANAGEMENT
-- =========================================

-- 19.1 Add outstanding balance column

ALTER TABLE public.invoices
ADD COLUMN IF NOT EXISTS outstanding_amount NUMERIC(12,2)
GENERATED ALWAYS AS (
    GREATEST(total_amount - amount_paid, 0)
) STORED;


-- 19.2 Create index for payment history

CREATE INDEX IF NOT EXISTS idx_payments_invoice_date
ON public.payments(invoice_id, payment_date);


-- 19.3 Validate and process payment automatically

CREATE OR REPLACE FUNCTION public.process_invoice_payment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_invoice public.invoices%ROWTYPE;
BEGIN

    -- Only Admin and Staff can record payments
    IF NOT public.is_admin_or_staff() THEN
        RAISE EXCEPTION
            'Access denied: Admin or Staff permission required';
    END IF;

    -- Lock invoice row
    SELECT *
    INTO v_invoice
    FROM public.invoices
    WHERE id = NEW.invoice_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice not found';
    END IF;

    -- Prevent payments on invalid invoice statuses
    IF v_invoice.status NOT IN ('confirmed', 'sent') THEN
        RAISE EXCEPTION
            'Payments can only be recorded for confirmed or sent invoices';
    END IF;

    -- Prevent overpayment
    IF NEW.amount > (v_invoice.total_amount - v_invoice.amount_paid) THEN
        RAISE EXCEPTION
            'Payment exceeds the outstanding invoice balance';
    END IF;

    -- Update invoice paid amount and status
    UPDATE public.invoices
    SET
        amount_paid = amount_paid + NEW.amount,
        status = CASE
            WHEN amount_paid + NEW.amount >= total_amount
            THEN 'paid'
            ELSE status
        END
    WHERE id = NEW.invoice_id;

    RETURN NEW;

END;
$$;


-- 19.4 Create payment trigger

DROP TRIGGER IF EXISTS trg_process_invoice_payment
ON public.payments;

CREATE TRIGGER trg_process_invoice_payment
BEFORE INSERT ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.process_invoice_payment();


-- 19.5 Prevent direct payment editing or deletion

CREATE OR REPLACE FUNCTION public.prevent_payment_modification()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
    RAISE EXCEPTION
        'Payment records cannot be edited or deleted. Record corrections separately.';
END;
$$;


DROP TRIGGER IF EXISTS trg_prevent_payment_update
ON public.payments;

CREATE TRIGGER trg_prevent_payment_update
BEFORE UPDATE OR DELETE ON public.payments
FOR EACH ROW
EXECUTE FUNCTION public.prevent_payment_modification();


-- 19.6 Restrict payment table permissions

REVOKE UPDATE, DELETE
ON public.payments
FROM authenticated;


-- 19.7 Secure payment trigger execution

REVOKE ALL ON FUNCTION public.process_invoice_payment()
FROM PUBLIC, anon, authenticated;


-- =========================================
-- END OF MODULE 19
-- =========================================

