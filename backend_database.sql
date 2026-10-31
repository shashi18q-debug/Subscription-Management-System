
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
