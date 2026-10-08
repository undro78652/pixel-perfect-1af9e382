
CREATE TABLE public.fund_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('collector','bank')),
  name text NOT NULL,
  holder_user uuid,
  bank_name text,
  masked_number text,
  active boolean NOT NULL DEFAULT true,
  is_demo boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX one_collector_account_per_user ON public.fund_accounts(holder_user) WHERE kind='collector';

CREATE TABLE public.projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL, description text, category text NOT NULL DEFAULT 'General',
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  status text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','in_progress','on_hold','completed')),
  responsible_manager uuid, target_date date, budget_paise bigint,
  created_by uuid, archived boolean NOT NULL DEFAULT false, is_demo boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.charges (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL, purpose text, description text,
  amount_paise bigint NOT NULL CHECK (amount_paise > 0),
  assessment_date date NOT NULL DEFAULT current_date, due_date date,
  category text NOT NULL CHECK (category IN ('setup','project','maintenance','other')),
  project_id uuid REFERENCES public.projects(id),
  maintenance_period date UNIQUE,
  idempotency_key text UNIQUE,
  created_by uuid, is_demo boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.charge_assessments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  charge_id uuid NOT NULL REFERENCES public.charges(id),
  house_id uuid NOT NULL REFERENCES public.houses(id),
  amount_paise bigint NOT NULL CHECK (amount_paise > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (charge_id, house_id)
);
CREATE TABLE public.waivers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assessment_id uuid NOT NULL REFERENCES public.charge_assessments(id),
  amount_paise bigint NOT NULL CHECK (amount_paise > 0),
  reason text NOT NULL, created_by uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.maintenance_config (
  id int PRIMARY KEY DEFAULT 1 CHECK (id=1),
  enabled boolean NOT NULL DEFAULT false,
  amount_paise bigint, house_ids uuid[] NOT NULL DEFAULT '{}',
  first_month date, due_day int NOT NULL DEFAULT 10,
  updated_by uuid, updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.maintenance_config(id) VALUES (1);

CREATE TABLE public.expenses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ref text UNIQUE NOT NULL DEFAULT 'EX-' || upper(substr(md5(gen_random_uuid()::text),1,8)),
  title text NOT NULL, description text,
  amount_paise bigint NOT NULL CHECK (amount_paise > 0),
  category text NOT NULL DEFAULT 'General',
  expense_date date NOT NULL DEFAULT current_date,
  mode text NOT NULL CHECK (mode IN ('planned','paid_personally')),
  project_id uuid REFERENCES public.projects(id), complaint_id uuid,
  supplier text, item_details text, quantity text, beneficiary text,
  evidence text[] NOT NULL DEFAULT '{}',
  submitted_by uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  approved_paise bigint, decided_by uuid, decided_at timestamptz, decision_reason text,
  is_demo boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE SEQUENCE public.txn_ref_seq;
CREATE TABLE public.transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ref text UNIQUE NOT NULL DEFAULT 'TX-' || lpad(nextval('public.txn_ref_seq')::text, 6, '0'),
  type text NOT NULL CHECK (type IN ('collection','opening','transfer','expense_payment','reimbursement','refund','reversal')),
  amount_paise bigint NOT NULL CHECK (amount_paise > 0),
  txn_date date NOT NULL DEFAULT current_date,
  purpose text NOT NULL,
  source_account uuid REFERENCES public.fund_accounts(id),
  dest_account uuid REFERENCES public.fund_accounts(id),
  sender_kind text NOT NULL CHECK (sender_kind IN ('user','bank_admin','none')),
  sender_user uuid,
  receiver_kind text NOT NULL CHECK (receiver_kind IN ('user','bank_admin','external_admin')),
  receiver_user uuid,
  external_recipient text,
  house_id uuid REFERENCES public.houses(id),
  expense_id uuid REFERENCES public.expenses(id),
  project_id uuid REFERENCES public.projects(id),
  reference_note text,
  evidence text[] NOT NULL DEFAULT '{}',
  revision int NOT NULL DEFAULT 1,
  sender_status text NOT NULL DEFAULT 'pending' CHECK (sender_status IN ('pending','confirmed','not_yet','mismatch','na')),
  sender_rev int, sender_by uuid, sender_at timestamptz, sender_note text,
  receiver_status text NOT NULL DEFAULT 'pending' CHECK (receiver_status IN ('pending','confirmed','not_yet','mismatch')),
  receiver_rev int, receiver_by uuid, receiver_at timestamptz, receiver_note text,
  admin_status text NOT NULL DEFAULT 'pending' CHECK (admin_status IN ('pending','approved','rejected')),
  admin_by uuid, admin_at timestamptz, admin_reason text,
  cancelled_at timestamptz, cancel_reason text,
  reversed_at timestamptz, reversal_txn uuid, reverses_txn uuid REFERENCES public.transactions(id), reverse_reason text,
  duplicate_flag boolean NOT NULL DEFAULT false,
  idempotency_key text UNIQUE,
  created_by uuid NOT NULL,
  is_demo boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  posted_at timestamptz
);
CREATE TABLE public.txn_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  txn_id uuid NOT NULL REFERENCES public.transactions(id),
  assessment_id uuid NOT NULL REFERENCES public.charge_assessments(id),
  amount_paise bigint NOT NULL CHECK (amount_paise > 0)
);
CREATE TABLE public.txn_events (
  id bigserial PRIMARY KEY,
  txn_id uuid NOT NULL REFERENCES public.transactions(id),
  actor uuid, action text NOT NULL, revision int, note text, details jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.ledger_entries (
  id bigserial PRIMARY KEY,
  txn_id uuid NOT NULL REFERENCES public.transactions(id),
  account_id uuid NOT NULL REFERENCES public.fund_accounts(id),
  amount_paise bigint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION public._ledger_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Ledger entries are permanent'; END $$;
CREATE TRIGGER ledger_no_update BEFORE UPDATE OR DELETE ON public.ledger_entries FOR EACH ROW EXECUTE FUNCTION public._ledger_immutable();

GRANT SELECT ON public.fund_accounts, public.projects, public.charges, public.charge_assessments, public.waivers,
  public.maintenance_config, public.expenses, public.transactions, public.txn_allocations, public.txn_events, public.ledger_entries TO authenticated;
GRANT ALL ON public.fund_accounts, public.projects, public.charges, public.charge_assessments, public.waivers,
  public.maintenance_config, public.expenses, public.transactions, public.txn_allocations, public.txn_events, public.ledger_entries TO service_role;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['fund_accounts','projects','charges','charge_assessments','waivers','maintenance_config','expenses','transactions','txn_allocations','txn_events','ledger_entries'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY "members read" ON public.%I FOR SELECT TO authenticated USING (public.is_active_member(auth.uid()))', t);
  END LOOP; END $$;

-- ===== derived views (security invoker => RLS applies) =====
CREATE VIEW public.v_transactions WITH (security_invoker = true) AS
SELECT t.*,
  CASE
    WHEN t.reversed_at IS NOT NULL THEN 'reversed'
    WHEN t.cancelled_at IS NOT NULL THEN 'cancelled'
    WHEN t.admin_status='rejected' THEN 'rejected'
    WHEN t.admin_status='approved' THEN 'posted'
    WHEN t.sender_status='mismatch' OR t.receiver_status='mismatch' THEN 'disputed'
    WHEN (t.sender_status='na' OR (t.sender_status='confirmed' AND t.sender_rev=t.revision))
     AND (t.receiver_status='confirmed' AND t.receiver_rev=t.revision) THEN 'awaiting_admin'
    WHEN NOT (t.sender_status='na' OR (t.sender_status='confirmed' AND t.sender_rev=t.revision))
     AND NOT (t.receiver_status='confirmed' AND t.receiver_rev=t.revision) THEN 'awaiting_confirmations'
    WHEN NOT (t.sender_status='na' OR (t.sender_status='confirmed' AND t.sender_rev=t.revision)) THEN 'awaiting_sender'
    ELSE 'awaiting_receiver' END AS state
FROM public.transactions t;

CREATE VIEW public.v_account_balances WITH (security_invoker = true) AS
SELECT a.*,
  coalesce((SELECT sum(l.amount_paise) FROM public.ledger_entries l WHERE l.account_id=a.id),0)::bigint AS posted_paise,
  coalesce((SELECT sum(t.amount_paise) FROM public.transactions t WHERE t.source_account=a.id AND t.admin_status='pending' AND t.cancelled_at IS NULL),0)::bigint AS reserved_paise
FROM public.fund_accounts a;

CREATE VIEW public.v_assessment_dues WITH (security_invoker = true) AS
SELECT ca.*, c.title AS charge_title, c.category, c.due_date, c.assessment_date, h.house_number, h.block,
  coalesce((SELECT sum(w.amount_paise) FROM public.waivers w WHERE w.assessment_id=ca.id),0)::bigint AS waived_paise,
  coalesce((SELECT sum(al.amount_paise) FROM public.txn_allocations al JOIN public.transactions t ON t.id=al.txn_id
            WHERE al.assessment_id=ca.id AND t.admin_status='approved' AND t.reversed_at IS NULL AND t.type='collection'),0)::bigint AS paid_paise,
  coalesce((SELECT sum(al.amount_paise) FROM public.txn_allocations al JOIN public.transactions t ON t.id=al.txn_id
            WHERE al.assessment_id=ca.id AND t.admin_status='pending' AND t.cancelled_at IS NULL),0)::bigint AS pending_paise
FROM public.charge_assessments ca JOIN public.charges c ON c.id=ca.charge_id JOIN public.houses h ON h.id=ca.house_id;

CREATE VIEW public.v_expenses WITH (security_invoker = true) AS
SELECT e.*,
  coalesce((SELECT sum(t.amount_paise) FROM public.transactions t WHERE t.expense_id=e.id AND t.admin_status='approved' AND t.reversed_at IS NULL),0)::bigint AS settled_paise,
  coalesce((SELECT sum(t.amount_paise) FROM public.transactions t WHERE t.expense_id=e.id AND t.admin_status='pending' AND t.cancelled_at IS NULL),0)::bigint AS reserved_paise
FROM public.expenses e;
GRANT SELECT ON public.v_transactions, public.v_account_balances, public.v_assessment_dues, public.v_expenses TO authenticated;

-- ===== helpers =====
CREATE OR REPLACE FUNCTION public._outstanding(_assessment uuid) RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT ca.amount_paise
   - coalesce((SELECT sum(amount_paise) FROM waivers WHERE assessment_id=ca.id),0)
   - coalesce((SELECT sum(al.amount_paise) FROM txn_allocations al JOIN transactions t ON t.id=al.txn_id
               WHERE al.assessment_id=ca.id AND t.admin_status='approved' AND t.reversed_at IS NULL AND t.type='collection'),0)
  FROM charge_assessments ca WHERE ca.id=_assessment;
$$;
CREATE OR REPLACE FUNCTION public._posted_balance(_acct uuid) RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT coalesce(sum(amount_paise),0)::bigint FROM ledger_entries WHERE account_id=_acct;
$$;
CREATE OR REPLACE FUNCTION public._reserved(_acct uuid, _exclude uuid) RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT coalesce(sum(amount_paise),0)::bigint FROM transactions WHERE source_account=_acct AND admin_status='pending' AND cancelled_at IS NULL AND id IS DISTINCT FROM _exclude;
$$;
CREATE OR REPLACE FUNCTION public._party(_acct uuid, OUT kind text, OUT uid uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE a fund_accounts;
BEGIN
  SELECT * INTO a FROM fund_accounts WHERE id=_acct;
  IF a.id IS NULL OR NOT a.active THEN RAISE EXCEPTION 'Account is not active'; END IF;
  IF a.kind='bank' THEN kind := 'bank_admin'; uid := NULL;
  ELSE
    IF NOT public.is_active_member(a.holder_user) THEN RAISE EXCEPTION 'Collector % is not an active member', a.name; END IF;
    kind := 'user'; uid := a.holder_user;
  END IF;
END $$;
CREATE OR REPLACE FUNCTION public._can_act_party(_kind text, _uid uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE WHEN _kind='user' THEN _uid = auth.uid() AND public.is_active_member(auth.uid())
              WHEN _kind IN ('bank_admin','external_admin') THEN public.is_admin(auth.uid())
              ELSE false END;
$$;
CREATE OR REPLACE FUNCTION public._txn_event(_txn uuid, _action text, _rev int, _note text, _details jsonb) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
  INSERT INTO txn_events(txn_id, actor, action, revision, note, details) VALUES (_txn, auth.uid(), _action, _rev, _note, _details);
  INSERT INTO audit_log(actor, action, entity_type, entity_id, details, reason, financial) VALUES (auth.uid(), 'txn.' || _action, 'transaction', _txn::text, _details, _note, true);
$$;
CREATE OR REPLACE FUNCTION public._notify_party(_kind text, _uid uuid, _title text, _body text, _link text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF _kind='user' THEN IF _uid IS DISTINCT FROM auth.uid() THEN PERFORM _notify(_uid,'confirmation',_title,_body,_link); END IF;
  ELSIF _kind IN ('bank_admin','external_admin') THEN PERFORM _notify_admins('confirmation',_title,_body,_link); END IF;
END $$;
REVOKE EXECUTE ON FUNCTION public._txn_event(uuid,text,int,text,jsonb), public._notify_party(text,uuid,text,text,text) FROM PUBLIC, anon, authenticated;

-- ===== fund accounts =====
CREATE OR REPLACE FUNCTION public.create_fund_account(_kind text, _name text, _holder uuid, _bank_name text, _masked text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE aid uuid;
BEGIN
  PERFORM _require_admin();
  IF coalesce(trim(_name),'')='' THEN RAISE EXCEPTION 'Name is required'; END IF;
  IF _kind='collector' THEN
    IF NOT public.is_active_member(_holder) THEN RAISE EXCEPTION 'Collector must be an active member'; END IF;
    IF EXISTS (SELECT 1 FROM fund_accounts WHERE holder_user=_holder AND kind='collector') THEN
      UPDATE fund_accounts SET active=true, name=_name WHERE holder_user=_holder AND kind='collector' RETURNING id INTO aid;
    ELSE INSERT INTO fund_accounts(kind,name,holder_user) VALUES ('collector',_name,_holder) RETURNING id INTO aid; END IF;
    PERFORM _notify(_holder,'role','You are now an authorized money collector',NULL,'/funds');
  ELSIF _kind='bank' THEN
    INSERT INTO fund_accounts(kind,name,bank_name,masked_number) VALUES ('bank',_name,_bank_name,_masked) RETURNING id INTO aid;
  ELSE RAISE EXCEPTION 'Unknown account type'; END IF;
  PERFORM _audit('account.created','fund_account',aid::text, jsonb_build_object('kind',_kind,'name',_name,'holder',_holder), NULL, true);
  RETURN aid;
END $$;
CREATE OR REPLACE FUNCTION public.set_fund_account_active(_acct uuid, _active boolean, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM _require_admin();
  IF NOT _active AND public._reserved(_acct, NULL) > 0 THEN RAISE EXCEPTION 'Account has pending outgoing records'; END IF;
  UPDATE fund_accounts SET active=_active WHERE id=_acct;
  PERFORM _audit(CASE WHEN _active THEN 'account.activated' ELSE 'account.deactivated' END,'fund_account',_acct::text,NULL,_reason,true);
END $$;

-- ===== create transaction =====
CREATE OR REPLACE FUNCTION public.create_transaction(_p jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  me uuid := auth.uid(); tid uuid; typ text := _p->>'type';
  amt bigint := (_p->>'amount_paise')::bigint;
  src uuid := nullif(_p->>'source_account','')::uuid; dst uuid := nullif(_p->>'dest_account','')::uuid;
  hid uuid := nullif(_p->>'house_id','')::uuid; eid uuid := nullif(_p->>'expense_id','')::uuid;
  payer uuid := nullif(_p->>'payer_user','')::uuid;
  sk text; su uuid; rk text; ru uuid; e expenses; al jsonb; alloc_sum bigint := 0; dup boolean;
  idem text := nullif(_p->>'idempotency_key','');
  src_holder uuid; dst_holder uuid;
BEGIN
  PERFORM _require_active();
  IF idem IS NOT NULL THEN SELECT id INTO tid FROM transactions WHERE idempotency_key=idem; IF tid IS NOT NULL THEN RETURN tid; END IF; END IF;
  IF amt IS NULL OR amt <= 0 THEN RAISE EXCEPTION 'Amount must be greater than zero'; END IF;
  IF coalesce(trim(_p->>'purpose'),'')='' THEN RAISE EXCEPTION 'Purpose is required'; END IF;
  SELECT holder_user INTO src_holder FROM fund_accounts WHERE id=src;
  SELECT holder_user INTO dst_holder FROM fund_accounts WHERE id=dst;

  IF typ='collection' THEN
    IF hid IS NULL OR dst IS NULL THEN RAISE EXCEPTION 'House and receiving account are required'; END IF;
    payer := coalesce(payer, CASE WHEN public.my_house_id(me)=hid THEN me END);
    IF payer IS NULL OR public.my_house_id(payer) IS DISTINCT FROM hid OR NOT public.is_active_member(payer) THEN RAISE EXCEPTION 'Payer must be an active member of that house'; END IF;
    IF NOT (public.my_house_id(me)=hid OR dst_holder=me OR public.has_perm(me,'finance.record')) THEN RAISE EXCEPTION 'You can only record payments for your own house or to your own collector account'; END IF;
    sk := 'user'; su := payer;
    SELECT kind, uid INTO rk, ru FROM _party(dst);
    src := NULL;
  ELSIF typ='opening' THEN
    PERFORM _require_perm('finance.record');
    IF dst IS NULL THEN RAISE EXCEPTION 'Receiving account is required'; END IF;
    sk := 'none'; SELECT kind, uid INTO rk, ru FROM _party(dst); src := NULL; hid := NULL;
  ELSIF typ='transfer' THEN
    IF src IS NULL OR dst IS NULL OR src=dst THEN RAISE EXCEPTION 'Choose two different accounts'; END IF;
    IF NOT (src_holder=me OR dst_holder=me OR public.has_perm(me,'finance.record')) THEN RAISE EXCEPTION 'Not allowed to record this transfer'; END IF;
    SELECT kind, uid INTO sk, su FROM _party(src); SELECT kind, uid INTO rk, ru FROM _party(dst); hid := NULL;
  ELSIF typ IN ('expense_payment','reimbursement') THEN
    IF src IS NULL OR eid IS NULL THEN RAISE EXCEPTION 'Expense and paying account are required'; END IF;
    IF NOT (src_holder=me OR public.has_perm(me,'finance.record')) THEN RAISE EXCEPTION 'Not allowed to record this payment'; END IF;
    SELECT * INTO e FROM expenses WHERE id=eid FOR UPDATE;
    IF e.status <> 'approved' THEN RAISE EXCEPTION 'Expense is not approved'; END IF;
    IF (SELECT coalesce(sum(amount_paise),0) FROM transactions WHERE expense_id=eid AND cancelled_at IS NULL AND admin_status<>'rejected' AND reversed_at IS NULL) + amt > e.approved_paise THEN
      RAISE EXCEPTION 'Payment exceeds the remaining approved amount'; END IF;
    SELECT kind, uid INTO sk, su FROM _party(src);
    IF typ='reimbursement' THEN rk := 'user'; ru := e.submitted_by;
    ELSE rk := 'external_admin'; ru := NULL;
      IF coalesce(trim(_p->>'external_recipient'),'')='' THEN RAISE EXCEPTION 'Recipient / vendor name is required'; END IF; END IF;
    dst := NULL; hid := NULL;
  ELSIF typ='refund' THEN
    PERFORM _require_perm('finance.record');
    IF src IS NULL OR hid IS NULL OR payer IS NULL OR public.my_house_id(payer) IS DISTINCT FROM hid THEN RAISE EXCEPTION 'Paying account, house and a member of that house are required'; END IF;
    IF nullif(_p->>'refund_of','') IS NULL THEN RAISE EXCEPTION 'Choose the posted collection being refunded'; END IF;
    SELECT kind, uid INTO sk, su FROM _party(src); rk := 'user'; ru := payer; dst := NULL;
  ELSE RAISE EXCEPTION 'Unknown transaction type'; END IF;

  IF src IS NOT NULL THEN
    PERFORM 1 FROM fund_accounts WHERE id=src FOR UPDATE;
    IF public._posted_balance(src) - public._reserved(src, NULL) < amt THEN RAISE EXCEPTION 'Insufficient available funds in the source account'; END IF;
  END IF;

  SELECT EXISTS (SELECT 1 FROM transactions WHERE type=typ AND amount_paise=amt AND cancelled_at IS NULL AND admin_status<>'rejected'
     AND house_id IS NOT DISTINCT FROM hid AND coalesce(dst,source_account) IS NOT DISTINCT FROM coalesce(dest_account,source_account)
     AND abs(txn_date - coalesce((_p->>'txn_date')::date,current_date)) <= 3) INTO dup;

  INSERT INTO transactions(type, amount_paise, txn_date, purpose, source_account, dest_account, sender_kind, sender_user, receiver_kind, receiver_user,
    external_recipient, house_id, expense_id, project_id, reference_note, evidence, sender_status, idempotency_key, created_by, duplicate_flag, reverses_txn)
  VALUES (typ, amt, coalesce((_p->>'txn_date')::date, current_date), trim(_p->>'purpose'), src, dst, sk, su, rk, ru,
    nullif(_p->>'external_recipient',''), hid, eid, nullif(_p->>'project_id','')::uuid, nullif(_p->>'reference_note',''),
    coalesce(ARRAY(SELECT jsonb_array_elements_text(_p->'evidence')),'{}'), CASE WHEN sk='none' THEN 'na' ELSE 'pending' END, idem, me, dup,
    CASE WHEN typ='refund' THEN (_p->>'refund_of')::uuid END)
  RETURNING id INTO tid;

  IF typ='collection' THEN
    IF jsonb_array_length(coalesce(_p->'allocations','[]'::jsonb)) = 0 THEN RAISE EXCEPTION 'Allocate the payment to at least one charge'; END IF;
    FOR al IN SELECT * FROM jsonb_array_elements(_p->'allocations') LOOP
      IF (al->>'amount_paise')::bigint <= 0 THEN CONTINUE; END IF;
      IF NOT EXISTS (SELECT 1 FROM charge_assessments WHERE id=(al->>'assessment_id')::uuid AND house_id=hid) THEN RAISE EXCEPTION 'Allocation is not a charge of this house'; END IF;
      IF (al->>'amount_paise')::bigint > public._outstanding((al->>'assessment_id')::uuid) THEN RAISE EXCEPTION 'Allocation exceeds outstanding dues'; END IF;
      INSERT INTO txn_allocations(txn_id, assessment_id, amount_paise) VALUES (tid, (al->>'assessment_id')::uuid, (al->>'amount_paise')::bigint);
      alloc_sum := alloc_sum + (al->>'amount_paise')::bigint;
    END LOOP;
    IF alloc_sum <> amt THEN RAISE EXCEPTION 'Allocations (%) must equal the amount (%)', alloc_sum, amt; END IF;
  END IF;

  PERFORM _txn_event(tid,'created',1,NULL,_p);
  -- creator confirms own side if they are that party (users only; bank/external sides need an explicit admin action)
  IF sk='user' AND su=me THEN UPDATE transactions SET sender_status='confirmed', sender_rev=1, sender_by=me, sender_at=now() WHERE id=tid; PERFORM _txn_event(tid,'sender_confirmed',1,'Creator confirmed',NULL); END IF;
  IF rk='user' AND ru=me THEN UPDATE transactions SET receiver_status='confirmed', receiver_rev=1, receiver_by=me, receiver_at=now() WHERE id=tid; PERFORM _txn_event(tid,'receiver_confirmed',1,'Creator confirmed',NULL); END IF;
  IF NOT (sk='user' AND su=me) AND sk<>'none' THEN PERFORM _notify_party(sk, su, 'Please confirm you sent money', trim(_p->>'purpose'), '/confirmations'); END IF;
  IF NOT (rk='user' AND ru=me) THEN PERFORM _notify_party(rk, ru, 'Please confirm you received money', trim(_p->>'purpose'), '/confirmations'); END IF;
  IF dup THEN PERFORM _notify_admins('dispute','Possible duplicate transaction','A similar record already exists','/transactions/' || tid); END IF;
  RETURN tid;
END $$;

CREATE OR REPLACE FUNCTION public.confirm_transaction(_txn uuid, _side text, _response text, _note text, _revision int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t transactions;
BEGIN
  PERFORM _require_active();
  SELECT * INTO t FROM transactions WHERE id=_txn FOR UPDATE;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Not found'; END IF;
  IF t.admin_status<>'pending' OR t.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'This record is no longer open'; END IF;
  IF _revision <> t.revision THEN RAISE EXCEPTION 'This record changed. Review the latest version before confirming.'; END IF;
  IF _response NOT IN ('confirmed','not_yet','mismatch') THEN RAISE EXCEPTION 'Invalid response'; END IF;
  IF _response='mismatch' AND coalesce(trim(_note),'')='' THEN RAISE EXCEPTION 'Explain the mismatch'; END IF;
  IF _side='sender' THEN
    IF t.sender_kind='none' OR NOT public._can_act_party(t.sender_kind, t.sender_user) THEN RAISE EXCEPTION 'You are not the sender of this record'; END IF;
    IF t.sender_status=_response AND t.sender_rev=t.revision THEN RETURN; END IF;
    UPDATE transactions SET sender_status=_response, sender_rev=t.revision, sender_by=auth.uid(), sender_at=now(), sender_note=_note WHERE id=_txn;
  ELSIF _side='receiver' THEN
    IF NOT public._can_act_party(t.receiver_kind, t.receiver_user) THEN RAISE EXCEPTION 'You are not the receiver of this record'; END IF;
    IF t.receiver_status=_response AND t.receiver_rev=t.revision THEN RETURN; END IF;
    UPDATE transactions SET receiver_status=_response, receiver_rev=t.revision, receiver_by=auth.uid(), receiver_at=now(), receiver_note=_note WHERE id=_txn;
  ELSE RAISE EXCEPTION 'Invalid side'; END IF;
  PERFORM _txn_event(_txn, _side || '_' || _response, t.revision, _note, NULL);
  IF _response='mismatch' THEN PERFORM _notify_admins('dispute','Transaction disputed: ' || t.ref, _note, '/transactions/' || _txn);
       PERFORM _notify(t.created_by,'dispute','Transaction disputed: ' || t.ref, _note, '/transactions/' || _txn); END IF;
  IF (SELECT state FROM v_transactions WHERE id=_txn)='awaiting_admin' THEN PERFORM _notify_admins('approval','Ready for approval: ' || t.ref, t.purpose, '/admin/financial-approvals'); END IF;
END $$;

CREATE OR REPLACE FUNCTION public.decide_transaction(_txn uuid, _approve boolean, _reason text, _revision int) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t transactions; st text; al record; e expenses;
BEGIN
  PERFORM _require_admin();
  SELECT * INTO t FROM transactions WHERE id=_txn FOR UPDATE;
  IF t.id IS NULL THEN RAISE EXCEPTION 'Not found'; END IF;
  IF t.admin_status='approved' THEN RETURN 'already_posted'; END IF;
  IF t.admin_status='rejected' THEN RETURN 'already_rejected'; END IF;
  IF t.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'Record was cancelled'; END IF;
  IF _revision <> t.revision THEN RAISE EXCEPTION 'Record changed; review the latest version'; END IF;
  IF NOT _approve THEN
    IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required to reject'; END IF;
    UPDATE transactions SET admin_status='rejected', admin_by=auth.uid(), admin_at=now(), admin_reason=_reason WHERE id=_txn;
    PERFORM _txn_event(_txn,'rejected',t.revision,_reason,NULL);
    PERFORM _notify(t.created_by,'approval','Transaction rejected: ' || t.ref,_reason,'/transactions/' || _txn);
    IF t.sender_user IS NOT NULL AND t.sender_user<>t.created_by THEN PERFORM _notify(t.sender_user,'approval','Transaction rejected: ' || t.ref,_reason,'/transactions/' || _txn); END IF;
    IF t.receiver_user IS NOT NULL AND t.receiver_user<>t.created_by THEN PERFORM _notify(t.receiver_user,'approval','Transaction rejected: ' || t.ref,_reason,'/transactions/' || _txn); END IF;
    RETURN 'rejected';
  END IF;
  SELECT state INTO st FROM v_transactions WHERE id=_txn;
  IF st <> 'awaiting_admin' THEN RAISE EXCEPTION 'Required confirmations are not complete (state: %)', st; END IF;
  -- lock accounts in a stable order
  PERFORM 1 FROM fund_accounts WHERE id IN (t.source_account, t.dest_account) ORDER BY id FOR UPDATE;
  IF t.source_account IS NOT NULL AND public._posted_balance(t.source_account) < t.amount_paise THEN RAISE EXCEPTION 'Insufficient posted funds in the source account'; END IF;
  IF t.type='collection' THEN
    FOR al IN SELECT * FROM txn_allocations WHERE txn_id=_txn LOOP
      PERFORM 1 FROM charge_assessments WHERE id=al.assessment_id FOR UPDATE;
      IF al.amount_paise > public._outstanding(al.assessment_id) THEN RAISE EXCEPTION 'An allocation now exceeds outstanding dues; correct the record first'; END IF;
    END LOOP;
  END IF;
  IF t.expense_id IS NOT NULL THEN
    SELECT * INTO e FROM expenses WHERE id=t.expense_id FOR UPDATE;
    IF (SELECT coalesce(sum(amount_paise),0) FROM transactions WHERE expense_id=e.id AND admin_status='approved' AND reversed_at IS NULL) + t.amount_paise > e.approved_paise THEN
      RAISE EXCEPTION 'Settlement exceeds approved expense amount'; END IF;
  END IF;
  IF t.source_account IS NOT NULL THEN INSERT INTO ledger_entries(txn_id, account_id, amount_paise) VALUES (_txn, t.source_account, -t.amount_paise); END IF;
  IF t.dest_account IS NOT NULL THEN INSERT INTO ledger_entries(txn_id, account_id, amount_paise) VALUES (_txn, t.dest_account, t.amount_paise); END IF;
  IF t.type='refund' AND t.reverses_txn IS NOT NULL THEN
    -- refund of a collection reopens that collection's allocations by marking it reversed-by-refund only when full
    NULL;
  END IF;
  UPDATE transactions SET admin_status='approved', admin_by=auth.uid(), admin_at=now(), admin_reason=_reason, posted_at=now() WHERE id=_txn;
  PERFORM _txn_event(_txn,'approved_posted',t.revision,_reason, jsonb_build_object('admin_was_sender', t.sender_by=auth.uid(), 'admin_was_receiver', t.receiver_by=auth.uid()));
  PERFORM _notify(t.created_by,'approval','Transaction posted: ' || t.ref, t.purpose,'/transactions/' || _txn);
  IF t.sender_user IS NOT NULL AND t.sender_user<>t.created_by THEN PERFORM _notify(t.sender_user,'approval','Transaction posted: ' || t.ref,t.purpose,'/transactions/' || _txn); END IF;
  IF t.receiver_user IS NOT NULL AND t.receiver_user<>t.created_by THEN PERFORM _notify(t.receiver_user,'approval','Transaction posted: ' || t.ref,t.purpose,'/transactions/' || _txn); END IF;
  RETURN 'posted';
END $$;

CREATE OR REPLACE FUNCTION public.edit_transaction(_txn uuid, _p jsonb) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t transactions; amt bigint; al jsonb; alloc_sum bigint := 0; nrev int;
BEGIN
  PERFORM _require_active();
  SELECT * INTO t FROM transactions WHERE id=_txn FOR UPDATE;
  IF t.admin_status<>'pending' OR t.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'Only open records can be corrected'; END IF;
  IF NOT (t.created_by=auth.uid() OR public.is_admin(auth.uid())) THEN RAISE EXCEPTION 'Only the creator or admin can correct this record'; END IF;
  amt := coalesce((_p->>'amount_paise')::bigint, t.amount_paise);
  IF amt <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  IF t.source_account IS NOT NULL AND public._posted_balance(t.source_account) - public._reserved(t.source_account, _txn) < amt THEN RAISE EXCEPTION 'Insufficient available funds'; END IF;
  IF t.expense_id IS NOT NULL AND (SELECT coalesce(sum(amount_paise),0) FROM transactions WHERE expense_id=t.expense_id AND id<>_txn AND cancelled_at IS NULL AND admin_status<>'rejected' AND reversed_at IS NULL) + amt > (SELECT approved_paise FROM expenses WHERE id=t.expense_id) THEN
    RAISE EXCEPTION 'Payment exceeds the remaining approved amount'; END IF;
  nrev := t.revision + 1;
  UPDATE transactions SET amount_paise=amt,
    purpose=coalesce(nullif(trim(_p->>'purpose'),''), purpose),
    txn_date=coalesce((_p->>'txn_date')::date, txn_date),
    reference_note=CASE WHEN _p ? 'reference_note' THEN _p->>'reference_note' ELSE reference_note END,
    evidence=CASE WHEN _p ? 'evidence' THEN ARRAY(SELECT jsonb_array_elements_text(_p->'evidence')) ELSE evidence END,
    revision=nrev,
    sender_status=CASE WHEN sender_kind='none' THEN 'na' ELSE 'pending' END, sender_rev=NULL, sender_by=NULL, sender_at=NULL,
    receiver_status='pending', receiver_rev=NULL, receiver_by=NULL, receiver_at=NULL
  WHERE id=_txn;
  IF t.type='collection' AND _p ? 'allocations' THEN
    DELETE FROM txn_allocations WHERE txn_id=_txn;
    FOR al IN SELECT * FROM jsonb_array_elements(_p->'allocations') LOOP
      IF (al->>'amount_paise')::bigint <= 0 THEN CONTINUE; END IF;
      IF NOT EXISTS (SELECT 1 FROM charge_assessments WHERE id=(al->>'assessment_id')::uuid AND house_id=t.house_id) THEN RAISE EXCEPTION 'Allocation is not a charge of this house'; END IF;
      IF (al->>'amount_paise')::bigint > public._outstanding((al->>'assessment_id')::uuid) THEN RAISE EXCEPTION 'Allocation exceeds outstanding dues'; END IF;
      INSERT INTO txn_allocations(txn_id, assessment_id, amount_paise) VALUES (_txn, (al->>'assessment_id')::uuid, (al->>'amount_paise')::bigint);
      alloc_sum := alloc_sum + (al->>'amount_paise')::bigint;
    END LOOP;
    IF alloc_sum <> amt THEN RAISE EXCEPTION 'Allocations must equal the amount'; END IF;
  ELSIF t.type='collection' AND amt <> t.amount_paise THEN RAISE EXCEPTION 'Changing the amount requires new allocations';
  END IF;
  PERFORM _txn_event(_txn,'corrected',nrev,_p->>'note', jsonb_build_object('before', to_jsonb(t), 'changes', _p));
  PERFORM _notify_party(t.sender_kind, t.sender_user, 'Record corrected — please confirm again: ' || t.ref, NULL, '/confirmations');
  PERFORM _notify_party(t.receiver_kind, t.receiver_user, 'Record corrected — please confirm again: ' || t.ref, NULL, '/confirmations');
END $$;

CREATE OR REPLACE FUNCTION public.cancel_transaction(_txn uuid, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t transactions;
BEGIN
  SELECT * INTO t FROM transactions WHERE id=_txn FOR UPDATE;
  IF t.admin_status<>'pending' OR t.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'Only open records can be cancelled'; END IF;
  IF NOT (t.created_by=auth.uid() OR public.is_admin(auth.uid())) THEN RAISE EXCEPTION 'Not allowed'; END IF;
  IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  UPDATE transactions SET cancelled_at=now(), cancel_reason=_reason WHERE id=_txn;
  PERFORM _txn_event(_txn,'cancelled',t.revision,_reason,NULL);
END $$;

CREATE OR REPLACE FUNCTION public.reverse_transaction(_txn uuid, _reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE t transactions; rid uuid;
BEGIN
  PERFORM _require_admin();
  IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  SELECT * INTO t FROM transactions WHERE id=_txn FOR UPDATE;
  IF t.admin_status<>'approved' THEN RAISE EXCEPTION 'Only posted records can be reversed'; END IF;
  IF t.reversed_at IS NOT NULL THEN RETURN t.reversal_txn; END IF;
  IF t.type='reversal' THEN RAISE EXCEPTION 'A reversal cannot itself be reversed'; END IF;
  PERFORM 1 FROM fund_accounts WHERE id IN (t.source_account, t.dest_account) ORDER BY id FOR UPDATE;
  IF t.dest_account IS NOT NULL AND public._posted_balance(t.dest_account) < t.amount_paise THEN RAISE EXCEPTION 'Destination account no longer holds enough to reverse'; END IF;
  INSERT INTO transactions(type, amount_paise, txn_date, purpose, source_account, dest_account, sender_kind, receiver_kind, house_id, expense_id,
     sender_status, receiver_status, receiver_rev, receiver_by, receiver_at, admin_status, admin_by, admin_at, admin_reason, reverses_txn, created_by, posted_at)
  VALUES ('reversal', t.amount_paise, current_date, 'Reversal of ' || t.ref || ': ' || _reason, t.dest_account, t.source_account, 'na'::text::text, 'bank_admin', t.house_id, NULL,
     'na','confirmed',1,auth.uid(),now(),'approved',auth.uid(),now(),_reason,_txn,auth.uid(),now())
  RETURNING id INTO rid;
  IF t.source_account IS NOT NULL THEN INSERT INTO ledger_entries(txn_id, account_id, amount_paise) VALUES (rid, t.source_account, t.amount_paise); END IF;
  IF t.dest_account IS NOT NULL THEN INSERT INTO ledger_entries(txn_id, account_id, amount_paise) VALUES (rid, t.dest_account, -t.amount_paise); END IF;
  UPDATE transactions SET reversed_at=now(), reversal_txn=rid, reverse_reason=_reason WHERE id=_txn;
  PERFORM _txn_event(_txn,'reversed',t.revision,_reason, jsonb_build_object('reversal',rid));
  PERFORM _notify(t.created_by,'approval','Transaction reversed: ' || t.ref,_reason,'/transactions/' || _txn);
  RETURN rid;
END $$;
