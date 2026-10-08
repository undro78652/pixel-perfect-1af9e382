
-- ===== Core: profiles, houses, memberships, roles, permissions, audit, notifications =====
CREATE TYPE public.account_status AS ENUM ('pending_society','pending_household','active','rejected','suspended');
CREATE TYPE public.app_role AS ENUM ('society_admin','society_manager');

CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL DEFAULT '',
  mobile text NOT NULL UNIQUE,
  status public.account_status NOT NULL DEFAULT 'pending_society',
  must_change_password boolean NOT NULL DEFAULT false,
  status_reason text,
  is_demo boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.houses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  house_number text NOT NULL UNIQUE,
  block text,
  address text,
  occupancy text NOT NULL DEFAULT 'owner_occupied' CHECK (occupancy IN ('owner_occupied','tenant_occupied','vacant')),
  owner_name text,
  owner_mobile text,
  owner_since date,
  tenant_name text,
  tenant_mobile text,
  tenant_since date,
  primary_admin uuid,
  active boolean NOT NULL DEFAULT true,
  is_demo boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.house_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  house_id uuid NOT NULL REFERENCES public.houses(id),
  changed_by uuid,
  snapshot jsonb NOT NULL,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  house_id uuid NOT NULL REFERENCES public.houses(id),
  token text NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(18),'hex'),
  created_by uuid NOT NULL,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  house_id uuid NOT NULL REFERENCES public.houses(id),
  relation text NOT NULL DEFAULT 'family' CHECK (relation IN ('owner','tenant','family')),
  is_house_admin boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','ended','rejected')),
  invitation_id uuid REFERENCES public.invitations(id),
  started_at date,
  ended_at date,
  decided_by uuid,
  decision_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX one_active_membership ON public.memberships(user_id) WHERE status = 'active';
CREATE UNIQUE INDEX one_pending_membership ON public.memberships(user_id) WHERE status = 'pending';

CREATE TABLE public.house_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  house_number text NOT NULL,
  block text,
  address text,
  occupancy text NOT NULL DEFAULT 'owner_occupied',
  relation text NOT NULL DEFAULT 'owner',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  decided_by uuid,
  decision_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.user_roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  UNIQUE (user_id, role)
);

CREATE TABLE public.manager_permissions (
  user_id uuid NOT NULL,
  permission text NOT NULL,
  granted_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, permission)
);

CREATE TABLE public.audit_log (
  id bigserial PRIMARY KEY,
  actor uuid,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text,
  details jsonb,
  reason text,
  financial boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  kind text NOT NULL,
  title text NOT NULL,
  body text,
  link text,
  read_at timestamptz,
  dismissed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON public.notifications(user_id, created_at DESC);

CREATE TABLE public.society_settings (
  id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  society_name text NOT NULL DEFAULT 'XYZ Society',
  address text,
  invite_days int NOT NULL DEFAULT 7,
  show_demo boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.society_settings (id) VALUES (1);

-- grants
GRANT SELECT ON public.profiles, public.houses, public.house_history, public.invitations, public.memberships,
  public.house_requests, public.user_roles, public.manager_permissions, public.audit_log, public.notifications,
  public.society_settings TO authenticated;
GRANT ALL ON public.profiles, public.houses, public.house_history, public.invitations, public.memberships,
  public.house_requests, public.user_roles, public.manager_permissions, public.audit_log, public.notifications,
  public.society_settings TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.audit_log_id_seq TO service_role;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.houses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.house_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.house_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.manager_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.society_settings ENABLE ROW LEVEL SECURITY;

-- ===== helper functions =====
CREATE OR REPLACE FUNCTION public.is_active_member(_uid uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM profiles p JOIN memberships m ON m.user_id = p.id AND m.status='active'
                 WHERE p.id = _uid AND p.status = 'active');
$$;
CREATE OR REPLACE FUNCTION public.has_role(_uid uuid, _role public.app_role) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_active_member(_uid) AND EXISTS (SELECT 1 FROM user_roles WHERE user_id=_uid AND role=_role);
$$;
CREATE OR REPLACE FUNCTION public.is_admin(_uid uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$ SELECT public.has_role(_uid,'society_admin'); $$;
CREATE OR REPLACE FUNCTION public.has_perm(_uid uuid, _perm text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_admin(_uid) OR (public.has_role(_uid,'society_manager')
     AND EXISTS (SELECT 1 FROM manager_permissions WHERE user_id=_uid AND permission=_perm));
$$;
CREATE OR REPLACE FUNCTION public.my_house_id(_uid uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT house_id FROM memberships WHERE user_id=_uid AND status='active' LIMIT 1;
$$;
CREATE OR REPLACE FUNCTION public.is_house_admin_of(_uid uuid, _house uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_active_member(_uid) AND EXISTS (SELECT 1 FROM memberships WHERE user_id=_uid AND house_id=_house AND status='active' AND is_house_admin);
$$;

CREATE OR REPLACE FUNCTION public._require_active() RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN IF NOT public.is_active_member(auth.uid()) THEN RAISE EXCEPTION 'Only approved active members can do this'; END IF; END $$;
CREATE OR REPLACE FUNCTION public._require_perm(_perm text) RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN IF NOT public.has_perm(auth.uid(), _perm) THEN RAISE EXCEPTION 'You do not have permission: %', _perm; END IF; END $$;
CREATE OR REPLACE FUNCTION public._require_admin() RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'Only the Society admin can do this'; END IF; END $$;

CREATE OR REPLACE FUNCTION public._audit(_action text, _etype text, _eid text, _details jsonb, _reason text, _fin boolean DEFAULT false) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO audit_log(actor, action, entity_type, entity_id, details, reason, financial) VALUES (auth.uid(), _action, _etype, _eid, _details, _reason, _fin);
$$;
CREATE OR REPLACE FUNCTION public._notify(_uid uuid, _kind text, _title text, _body text, _link text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO notifications(user_id, kind, title, body, link) SELECT _uid, _kind, _title, _body, _link WHERE _uid IS NOT NULL;
$$;
CREATE OR REPLACE FUNCTION public._notify_admins(_kind text, _title text, _body text, _link text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO notifications(user_id, kind, title, body, link)
  SELECT ur.user_id, _kind, _title, _body, _link FROM user_roles ur WHERE ur.role='society_admin' AND public.is_active_member(ur.user_id);
$$;
CREATE OR REPLACE FUNCTION public._notify_perm(_perm text, _kind text, _title text, _body text, _link text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO notifications(user_id, kind, title, body, link)
  SELECT p.id, _kind, _title, _body, _link FROM profiles p WHERE p.status='active' AND public.has_perm(p.id, _perm);
$$;
CREATE OR REPLACE FUNCTION public._notify_all(_kind text, _title text, _body text, _link text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  INSERT INTO notifications(user_id, kind, title, body, link)
  SELECT p.id, _kind, _title, _body, _link FROM profiles p WHERE public.is_active_member(p.id);
$$;
REVOKE EXECUTE ON FUNCTION public._audit(text,text,text,jsonb,text,boolean), public._notify(uuid,text,text,text,text),
  public._notify_admins(text,text,text,text), public._notify_perm(text,text,text,text,text), public._notify_all(text,text,text,text)
  FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.normalize_mobile(_m text) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE d text := regexp_replace(coalesce(_m,''), '\D', '', 'g');
BEGIN
  IF length(d) = 10 THEN d := '91' || d;
  ELSIF length(d) = 11 AND left(d,1) = '0' THEN d := '91' || substr(d,2); END IF;
  IF length(d) <> 12 OR left(d,2) <> '91' THEN RAISE EXCEPTION 'Enter a valid 10-digit Indian mobile number'; END IF;
  RETURN '+' || d;
END $$;

-- ===== RLS policies =====
CREATE POLICY "own or members read profiles" ON public.profiles FOR SELECT TO authenticated
  USING (id = auth.uid() OR public.is_active_member(auth.uid()));
CREATE POLICY "members read houses" ON public.houses FOR SELECT TO authenticated USING (public.is_active_member(auth.uid()));
CREATE POLICY "members read house history" ON public.house_history FOR SELECT TO authenticated USING (public.is_active_member(auth.uid()));
CREATE POLICY "house admins read invitations" ON public.invitations FOR SELECT TO authenticated
  USING (public.is_house_admin_of(auth.uid(), house_id) OR public.is_admin(auth.uid()));
CREATE POLICY "own or members read memberships" ON public.memberships FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_active_member(auth.uid()));
CREATE POLICY "own or reviewers read house requests" ON public.house_requests FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_perm(auth.uid(),'membership.review'));
CREATE POLICY "members read roles" ON public.user_roles FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_active_member(auth.uid()));
CREATE POLICY "members read perms" ON public.manager_permissions FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_active_member(auth.uid()));
CREATE POLICY "members read audit" ON public.audit_log FOR SELECT TO authenticated USING (public.is_active_member(auth.uid()));
CREATE POLICY "own notifications" ON public.notifications FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY "members read settings" ON public.society_settings FOR SELECT TO authenticated USING (public.is_active_member(auth.uid()));

-- ===== signup trigger =====
CREATE OR REPLACE FUNCTION public.handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, mobile, must_change_password)
  VALUES (NEW.id, coalesce(NEW.raw_user_meta_data->>'full_name',''),
          public.normalize_mobile(NEW.raw_user_meta_data->>'mobile'),
          coalesce((NEW.raw_user_meta_data->>'must_change_password')::boolean, false));
  RETURN NEW;
END $$;
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ===== membership & onboarding RPCs =====
CREATE OR REPLACE FUNCTION public.request_house_membership(_house_number text, _relation text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE h houses; mid uuid; st account_status;
BEGIN
  SELECT status INTO st FROM profiles WHERE id = auth.uid();
  IF st IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  IF st IN ('active','suspended') THEN RAISE EXCEPTION 'Your account cannot submit a joining request right now'; END IF;
  IF EXISTS (SELECT 1 FROM memberships WHERE user_id=auth.uid() AND status='pending') OR EXISTS (SELECT 1 FROM house_requests WHERE user_id=auth.uid() AND status='pending') THEN
    RAISE EXCEPTION 'You already have a pending request'; END IF;
  SELECT * INTO h FROM houses WHERE lower(house_number) = lower(trim(_house_number)) AND active;
  IF h.id IS NULL THEN RAISE EXCEPTION 'No active house with that number. Ask your house admin, or request a new house.'; END IF;
  INSERT INTO memberships(user_id, house_id, relation, status) VALUES (auth.uid(), h.id, coalesce(_relation,'family'), 'pending') RETURNING id INTO mid;
  UPDATE profiles SET status='pending_household', status_reason=NULL WHERE id=auth.uid();
  INSERT INTO notifications(user_id, kind, title, body, link)
    SELECT m.user_id, 'membership', 'New membership request', 'Someone asked to join house ' || h.house_number, '/admin/membership'
    FROM memberships m WHERE m.house_id = h.id AND m.status='active' AND m.is_house_admin;
  PERFORM _audit('membership.requested','membership',mid::text, jsonb_build_object('house',h.house_number), NULL);
  RETURN mid;
END $$;

CREATE OR REPLACE FUNCTION public.accept_invitation(_token text, _relation text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE inv invitations; mid uuid; st account_status;
BEGIN
  SELECT status INTO st FROM profiles WHERE id = auth.uid();
  IF st IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  IF st IN ('active','suspended') THEN RAISE EXCEPTION 'Your account cannot accept this invitation'; END IF;
  SELECT * INTO inv FROM invitations WHERE token = _token;
  IF inv.id IS NULL OR inv.revoked_at IS NOT NULL OR inv.expires_at < now() THEN RAISE EXCEPTION 'This invitation link is invalid, expired or revoked'; END IF;
  IF EXISTS (SELECT 1 FROM memberships WHERE user_id=auth.uid() AND status='pending') THEN RAISE EXCEPTION 'You already have a pending request'; END IF;
  INSERT INTO memberships(user_id, house_id, relation, status, invitation_id) VALUES (auth.uid(), inv.house_id, coalesce(_relation,'family'), 'pending', inv.id) RETURNING id INTO mid;
  UPDATE profiles SET status='pending_household', status_reason=NULL WHERE id=auth.uid();
  INSERT INTO notifications(user_id, kind, title, body, link)
    SELECT m.user_id, 'membership', 'Invitation accepted', 'A family member registered through your invitation and awaits approval', '/admin/membership'
    FROM memberships m WHERE m.house_id = inv.house_id AND m.status='active' AND m.is_house_admin;
  PERFORM _audit('membership.invitation_used','membership',mid::text, jsonb_build_object('invitation',inv.id), NULL);
  RETURN mid;
END $$;

CREATE OR REPLACE FUNCTION public.invitation_info(_token text) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object('house_number', h.house_number, 'valid', (i.revoked_at IS NULL AND i.expires_at > now()), 'expires_at', i.expires_at)
  FROM invitations i JOIN houses h ON h.id = i.house_id WHERE i.token = _token;
$$;

CREATE OR REPLACE FUNCTION public.request_new_house(_house_number text, _block text, _address text, _occupancy text, _relation text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE rid uuid; st account_status;
BEGIN
  SELECT status INTO st FROM profiles WHERE id = auth.uid();
  IF st IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  IF st IN ('active','suspended') THEN RAISE EXCEPTION 'Your account cannot submit this request'; END IF;
  IF EXISTS (SELECT 1 FROM memberships WHERE user_id=auth.uid() AND status='pending') OR EXISTS (SELECT 1 FROM house_requests WHERE user_id=auth.uid() AND status='pending') THEN
    RAISE EXCEPTION 'You already have a pending request'; END IF;
  IF coalesce(trim(_house_number),'') = '' THEN RAISE EXCEPTION 'House number is required'; END IF;
  IF EXISTS (SELECT 1 FROM houses WHERE lower(house_number)=lower(trim(_house_number))) THEN RAISE EXCEPTION 'That house already exists. Request membership in it instead.'; END IF;
  INSERT INTO house_requests(user_id, house_number, block, address, occupancy, relation)
  VALUES (auth.uid(), trim(_house_number), nullif(trim(_block),''), _address, coalesce(_occupancy,'owner_occupied'), coalesce(_relation,'owner')) RETURNING id INTO rid;
  UPDATE profiles SET status='pending_society', status_reason=NULL WHERE id=auth.uid();
  PERFORM _notify_perm('membership.review','membership','New house request','House ' || _house_number || ' was requested','/admin/membership');
  PERFORM _audit('house.requested','house_request',rid::text, jsonb_build_object('house',_house_number), NULL);
  RETURN rid;
END $$;

CREATE OR REPLACE FUNCTION public.decide_membership(_membership uuid, _approve boolean, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m memberships;
BEGIN
  SELECT * INTO m FROM memberships WHERE id=_membership FOR UPDATE;
  IF m.id IS NULL OR m.status <> 'pending' THEN RAISE EXCEPTION 'Request is not pending'; END IF;
  IF NOT (public.is_house_admin_of(auth.uid(), m.house_id) OR public.is_admin(auth.uid())) THEN RAISE EXCEPTION 'Only this house''s admin can decide'; END IF;
  IF _approve THEN
    UPDATE memberships SET status='ended', ended_at=current_date WHERE user_id=m.user_id AND status='active';
    UPDATE memberships SET status='active', started_at=current_date, decided_by=auth.uid(), decision_reason=_reason, is_house_admin=false WHERE id=m.id;
    UPDATE profiles SET status='active', status_reason=NULL WHERE id=m.user_id AND status <> 'suspended';
    PERFORM _notify(m.user_id,'membership','Membership approved','You can now use XYZ Society','/');
  ELSE
    IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required to reject'; END IF;
    UPDATE memberships SET status='rejected', decided_by=auth.uid(), decision_reason=_reason WHERE id=m.id;
    UPDATE profiles SET status='rejected', status_reason=_reason WHERE id=m.user_id AND status <> 'active';
    PERFORM _notify(m.user_id,'membership','Membership request rejected',_reason,'/status');
  END IF;
  PERFORM _audit(CASE WHEN _approve THEN 'membership.approved' ELSE 'membership.rejected' END,'membership',m.id::text, jsonb_build_object('user',m.user_id,'house',m.house_id), _reason);
END $$;

CREATE OR REPLACE FUNCTION public.decide_house_request(_req uuid, _approve boolean, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r house_requests; hid uuid;
BEGIN
  PERFORM _require_perm('membership.review');
  SELECT * INTO r FROM house_requests WHERE id=_req FOR UPDATE;
  IF r.id IS NULL OR r.status <> 'pending' THEN RAISE EXCEPTION 'Request is not pending'; END IF;
  IF _approve THEN
    INSERT INTO houses(house_number, block, address, occupancy, primary_admin) VALUES (r.house_number, r.block, r.address, r.occupancy, r.user_id) RETURNING id INTO hid;
    UPDATE memberships SET status='ended', ended_at=current_date WHERE user_id=r.user_id AND status='active';
    INSERT INTO memberships(user_id, house_id, relation, is_house_admin, status, started_at, decided_by) VALUES (r.user_id, hid, r.relation, true, 'active', current_date, auth.uid());
    UPDATE house_requests SET status='approved', decided_by=auth.uid(), decision_reason=_reason WHERE id=r.id;
    UPDATE profiles SET status='active', status_reason=NULL WHERE id=r.user_id AND status <> 'suspended';
    PERFORM _notify(r.user_id,'membership','House approved','House ' || r.house_number || ' was created with you as house admin','/my-house');
  ELSE
    IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required to reject'; END IF;
    UPDATE house_requests SET status='rejected', decided_by=auth.uid(), decision_reason=_reason WHERE id=r.id;
    UPDATE profiles SET status='rejected', status_reason=_reason WHERE id=r.user_id AND status <> 'active';
    PERFORM _notify(r.user_id,'membership','House request rejected',_reason,'/status');
  END IF;
  PERFORM _audit(CASE WHEN _approve THEN 'house_request.approved' ELSE 'house_request.rejected' END,'house_request',r.id::text, jsonb_build_object('house',r.house_number), _reason);
END $$;

CREATE OR REPLACE FUNCTION public.create_invitation(_house uuid, _days int) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t text;
BEGIN
  IF NOT public.is_house_admin_of(auth.uid(), _house) THEN RAISE EXCEPTION 'Only the house admin can invite'; END IF;
  INSERT INTO invitations(house_id, created_by, expires_at) VALUES (_house, auth.uid(), now() + make_interval(days => greatest(1, least(coalesce(_days,7),30)))) RETURNING token INTO t;
  PERFORM _audit('invitation.created','house',_house::text, NULL, NULL);
  RETURN t;
END $$;
CREATE OR REPLACE FUNCTION public.revoke_invitation(_inv uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE hid uuid;
BEGIN
  SELECT house_id INTO hid FROM invitations WHERE id=_inv;
  IF NOT (public.is_house_admin_of(auth.uid(), hid) OR public.is_admin(auth.uid())) THEN RAISE EXCEPTION 'Not allowed'; END IF;
  UPDATE invitations SET revoked_at = now() WHERE id=_inv AND revoked_at IS NULL;
  PERFORM _audit('invitation.revoked','house',hid::text, jsonb_build_object('invitation',_inv), NULL);
END $$;

CREATE OR REPLACE FUNCTION public.create_house(_number text, _block text, _address text, _occupancy text, _owner_name text, _owner_mobile text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE hid uuid;
BEGIN
  PERFORM _require_perm('houses.manage');
  IF coalesce(trim(_number),'')='' THEN RAISE EXCEPTION 'House number is required'; END IF;
  INSERT INTO houses(house_number, block, address, occupancy, owner_name, owner_mobile, owner_since)
  VALUES (trim(_number), nullif(trim(_block),''), _address, coalesce(_occupancy,'owner_occupied'), _owner_name, _owner_mobile, current_date) RETURNING id INTO hid;
  PERFORM _audit('house.created','house',hid::text, jsonb_build_object('number',_number), NULL);
  RETURN hid;
END $$;

CREATE OR REPLACE FUNCTION public.update_house(_house uuid, _data jsonb, _note text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE old houses;
BEGIN
  IF NOT (public.is_house_admin_of(auth.uid(), _house) OR public.has_perm(auth.uid(),'houses.manage')) THEN RAISE EXCEPTION 'Not allowed to edit this house'; END IF;
  SELECT * INTO old FROM houses WHERE id=_house FOR UPDATE;
  INSERT INTO house_history(house_id, changed_by, snapshot, note) VALUES (_house, auth.uid(), to_jsonb(old), _note);
  UPDATE houses SET
    block = CASE WHEN _data ? 'block' THEN nullif(_data->>'block','') ELSE block END,
    address = CASE WHEN _data ? 'address' THEN _data->>'address' ELSE address END,
    occupancy = coalesce(_data->>'occupancy', occupancy),
    owner_name = CASE WHEN _data ? 'owner_name' THEN _data->>'owner_name' ELSE owner_name END,
    owner_mobile = CASE WHEN _data ? 'owner_mobile' THEN _data->>'owner_mobile' ELSE owner_mobile END,
    owner_since = CASE WHEN _data ? 'owner_since' THEN nullif(_data->>'owner_since','')::date ELSE owner_since END,
    tenant_name = CASE WHEN _data ? 'tenant_name' THEN nullif(_data->>'tenant_name','') ELSE tenant_name END,
    tenant_mobile = CASE WHEN _data ? 'tenant_mobile' THEN nullif(_data->>'tenant_mobile','') ELSE tenant_mobile END,
    tenant_since = CASE WHEN _data ? 'tenant_since' THEN nullif(_data->>'tenant_since','')::date ELSE tenant_since END,
    active = CASE WHEN _data ? 'active' AND public.has_perm(auth.uid(),'houses.manage') THEN (_data->>'active')::boolean ELSE active END
  WHERE id=_house;
  PERFORM _audit('house.updated','house',_house::text, jsonb_build_object('before',to_jsonb(old),'changes',_data), _note);
END $$;

CREATE OR REPLACE FUNCTION public.set_house_admin(_membership uuid, _is_admin boolean, _primary boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m memberships;
BEGIN
  SELECT * INTO m FROM memberships WHERE id=_membership;
  IF m.status <> 'active' THEN RAISE EXCEPTION 'Membership is not active'; END IF;
  IF NOT (public.is_house_admin_of(auth.uid(), m.house_id) OR public.has_perm(auth.uid(),'houses.manage')) THEN RAISE EXCEPTION 'Not allowed'; END IF;
  IF NOT _is_admin AND (SELECT count(*) FROM memberships WHERE house_id=m.house_id AND status='active' AND is_house_admin AND id<>m.id)=0 THEN
    RAISE EXCEPTION 'A house needs at least one house admin'; END IF;
  UPDATE memberships SET is_house_admin=_is_admin WHERE id=m.id;
  IF _primary AND _is_admin THEN UPDATE houses SET primary_admin=m.user_id WHERE id=m.house_id; END IF;
  PERFORM _notify(m.user_id,'membership', CASE WHEN _is_admin THEN 'You are now a house admin' ELSE 'House admin responsibility removed' END, NULL, '/my-house');
  PERFORM _audit('house_admin.changed','membership',m.id::text, jsonb_build_object('is_house_admin',_is_admin,'primary',_primary), NULL);
END $$;

CREATE OR REPLACE FUNCTION public.end_membership(_membership uuid, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m memberships;
BEGIN
  SELECT * INTO m FROM memberships WHERE id=_membership FOR UPDATE;
  IF m.status <> 'active' THEN RAISE EXCEPTION 'Membership is not active'; END IF;
  IF NOT (public.is_house_admin_of(auth.uid(), m.house_id) OR public.is_admin(auth.uid())) THEN RAISE EXCEPTION 'Not allowed'; END IF;
  IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  IF m.user_id = auth.uid() THEN RAISE EXCEPTION 'You cannot end your own membership here'; END IF;
  UPDATE memberships SET status='ended', ended_at=current_date, decision_reason=_reason WHERE id=m.id;
  UPDATE profiles SET status='pending_society', status_reason='Membership ended: ' || _reason WHERE id=m.user_id;
  PERFORM _notify(m.user_id,'membership','Your house membership ended',_reason,'/status');
  PERFORM _audit('membership.ended','membership',m.id::text, NULL, _reason);
END $$;

CREATE OR REPLACE FUNCTION public.set_account_status(_user uuid, _status public.account_status, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM _require_admin();
  IF _status NOT IN ('active','suspended') THEN RAISE EXCEPTION 'Only suspend or reactivate here'; END IF;
  IF _user = auth.uid() THEN RAISE EXCEPTION 'You cannot change your own status'; END IF;
  IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  IF _status='active' AND NOT EXISTS (SELECT 1 FROM memberships WHERE user_id=_user AND status='active') THEN RAISE EXCEPTION 'User has no active house membership'; END IF;
  UPDATE profiles SET status=_status, status_reason=_reason WHERE id=_user;
  PERFORM _notify(_user,'membership', CASE WHEN _status='suspended' THEN 'Account suspended' ELSE 'Account reactivated' END, _reason, '/status');
  PERFORM _audit('account.status','profile',_user::text, jsonb_build_object('status',_status), _reason);
END $$;

CREATE OR REPLACE FUNCTION public.set_role(_user uuid, _role public.app_role, _grant boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM _require_admin();
  IF NOT public.is_active_member(_user) THEN RAISE EXCEPTION 'Roles can only be given to active members'; END IF;
  IF NOT _grant AND _role='society_admin' AND (SELECT count(*) FROM user_roles WHERE role='society_admin' AND user_id<>_user)=0 THEN
    RAISE EXCEPTION 'The society needs at least one Society admin'; END IF;
  IF _grant THEN INSERT INTO user_roles(user_id, role) VALUES (_user,_role) ON CONFLICT DO NOTHING;
  ELSE DELETE FROM user_roles WHERE user_id=_user AND role=_role;
       IF _role='society_manager' THEN DELETE FROM manager_permissions WHERE user_id=_user; END IF; END IF;
  PERFORM _notify(_user,'role', CASE WHEN _grant THEN 'Role granted: ' ELSE 'Role removed: ' END || replace(_role::text,'_',' '), NULL, '/profile');
  PERFORM _audit('role.changed','profile',_user::text, jsonb_build_object('role',_role,'grant',_grant), NULL);
END $$;

CREATE OR REPLACE FUNCTION public.set_manager_permissions(_user uuid, _perms text[]) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE allowed text[] := ARRAY['membership.review','houses.manage','charges.manage','projects.manage','updates.publish',
  'complaints.priority','complaints.self_assign','complaints.manage','suggestions.manage','finance.record','reports.export','moderation'];
BEGIN
  PERFORM _require_admin();
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id=_user AND role='society_manager') THEN RAISE EXCEPTION 'User is not a Society manager'; END IF;
  IF EXISTS (SELECT 1 FROM unnest(_perms) p WHERE p <> ALL(allowed)) THEN RAISE EXCEPTION 'Unknown permission'; END IF;
  DELETE FROM manager_permissions WHERE user_id=_user;
  INSERT INTO manager_permissions(user_id, permission, granted_by) SELECT _user, p, auth.uid() FROM unnest(_perms) p;
  PERFORM _notify(_user,'role','Your manager permissions changed', NULL, '/profile');
  PERFORM _audit('permissions.changed','profile',_user::text, jsonb_build_object('permissions',_perms), NULL);
END $$;

CREATE OR REPLACE FUNCTION public.update_my_profile(_full_name text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF coalesce(trim(_full_name),'')='' OR length(_full_name) > 100 THEN RAISE EXCEPTION 'Enter a name up to 100 characters'; END IF;
  UPDATE profiles SET full_name=trim(_full_name) WHERE id=auth.uid();
END $$;
CREATE OR REPLACE FUNCTION public.clear_must_change_password() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE profiles SET must_change_password=false WHERE id=auth.uid();
$$;

CREATE OR REPLACE FUNCTION public.update_settings(_name text, _address text, _invite_days int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM _require_admin();
  UPDATE society_settings SET society_name=coalesce(nullif(trim(_name),''),society_name), address=_address, invite_days=greatest(1,least(coalesce(_invite_days,7),30)), updated_at=now() WHERE id=1;
  PERFORM _audit('settings.updated','settings','1', jsonb_build_object('name',_name,'address',_address,'invite_days',_invite_days), NULL);
END $$;

CREATE OR REPLACE FUNCTION public.mark_notification(_id uuid, _action text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF _action = 'read' THEN UPDATE notifications SET read_at = coalesce(read_at, now()) WHERE id=_id AND user_id=auth.uid();
  ELSIF _action = 'dismiss' THEN UPDATE notifications SET dismissed_at = now(), read_at = coalesce(read_at, now()) WHERE id=_id AND user_id=auth.uid();
  ELSIF _action = 'read_all' THEN UPDATE notifications SET read_at = now() WHERE user_id=auth.uid() AND read_at IS NULL;
  END IF;
END $$;

-- used by server function for admin-provisioned accounts (caller must be allowed)
CREATE OR REPLACE FUNCTION public.attach_provisioned_member(_user uuid, _house uuid, _relation text, _is_house_admin boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM _require_perm('membership.review');
  IF EXISTS (SELECT 1 FROM memberships WHERE user_id=_user AND status='active') THEN RAISE EXCEPTION 'User already has a house'; END IF;
  INSERT INTO memberships(user_id, house_id, relation, is_house_admin, status, started_at, decided_by) VALUES (_user, _house, coalesce(_relation,'family'), coalesce(_is_house_admin,false), 'active', current_date, auth.uid());
  IF _is_house_admin THEN UPDATE houses SET primary_admin = coalesce(primary_admin, _user) WHERE id=_house; END IF;
  UPDATE profiles SET status='active', must_change_password=true WHERE id=_user;
  PERFORM _audit('account.provisioned','profile',_user::text, jsonb_build_object('house',_house,'house_admin',_is_house_admin), NULL);
END $$;
CREATE OR REPLACE FUNCTION public.log_password_reset(_user uuid, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM _require_admin();
  UPDATE profiles SET must_change_password=true WHERE id=_user;
  PERFORM _notify(_user,'security','Your password was reset by the Society admin','Use the temporary password you were given and choose a new one.','/profile');
  PERFORM _audit('password.reset_issued','profile',_user::text, NULL, _reason);
END $$;
