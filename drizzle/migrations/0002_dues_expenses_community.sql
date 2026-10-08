
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
  INSERT INTO transactions(type, amount_paise, txn_date, purpose, source_account, dest_account, sender_kind, receiver_kind, house_id,
     sender_status, receiver_status, receiver_rev, receiver_by, receiver_at, admin_status, admin_by, admin_at, admin_reason, reverses_txn, created_by, posted_at)
  VALUES ('reversal', t.amount_paise, current_date, 'Reversal of ' || t.ref || ': ' || _reason, t.dest_account, t.source_account, 'none', 'bank_admin', t.house_id,
     'na','confirmed',1,auth.uid(),now(),'approved',auth.uid(),now(),_reason,_txn,auth.uid(),now())
  RETURNING id INTO rid;
  IF t.source_account IS NOT NULL THEN INSERT INTO ledger_entries(txn_id, account_id, amount_paise) VALUES (rid, t.source_account, t.amount_paise); END IF;
  IF t.dest_account IS NOT NULL THEN INSERT INTO ledger_entries(txn_id, account_id, amount_paise) VALUES (rid, t.dest_account, -t.amount_paise); END IF;
  UPDATE transactions SET reversed_at=now(), reversal_txn=rid, reverse_reason=_reason WHERE id=_txn;
  PERFORM _txn_event(_txn,'reversed',t.revision,_reason, jsonb_build_object('reversal',rid));
  PERFORM _notify(t.created_by,'approval','Transaction reversed: ' || t.ref,_reason,'/transactions/' || _txn);
  RETURN rid;
END $$;

CREATE OR REPLACE FUNCTION public._after_refund_post() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o transactions;
BEGIN
  IF NEW.type='refund' AND NEW.admin_status='approved' AND OLD.admin_status<>'approved' AND NEW.reverses_txn IS NOT NULL THEN
    SELECT * INTO o FROM transactions WHERE id=NEW.reverses_txn FOR UPDATE;
    IF o.type<>'collection' OR o.admin_status<>'approved' OR o.reversed_at IS NOT NULL THEN RAISE EXCEPTION 'Refunded collection is not a posted collection'; END IF;
    IF o.amount_paise <> NEW.amount_paise THEN RAISE EXCEPTION 'Refund must equal the full collection amount'; END IF;
    UPDATE transactions SET reversed_at=now(), reversal_txn=NEW.id, reverse_reason='Refunded by ' || NEW.ref WHERE id=o.id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER refund_post AFTER UPDATE ON public.transactions FOR EACH ROW EXECUTE FUNCTION public._after_refund_post();

CREATE OR REPLACE FUNCTION public.create_charge(_p jsonb, _house_ids uuid[]) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE cid uuid; amt bigint := (_p->>'amount_paise')::bigint; n int; idem text := nullif(_p->>'idempotency_key','');
BEGIN
  PERFORM _require_perm('charges.manage');
  IF idem IS NOT NULL THEN SELECT id INTO cid FROM charges WHERE idempotency_key=idem; IF cid IS NOT NULL THEN RETURN cid; END IF; END IF;
  IF coalesce(trim(_p->>'title'),'')='' THEN RAISE EXCEPTION 'Title is required'; END IF;
  IF amt IS NULL OR amt<=0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  SELECT count(*) INTO n FROM houses WHERE id = ANY(_house_ids) AND active;
  IF n = 0 OR n <> coalesce(array_length(_house_ids,1),0) THEN RAISE EXCEPTION 'Select at least one active house'; END IF;
  INSERT INTO charges(title, purpose, description, amount_paise, assessment_date, due_date, category, project_id, created_by, idempotency_key)
  VALUES (trim(_p->>'title'), _p->>'purpose', _p->>'description', amt, coalesce((_p->>'assessment_date')::date,current_date), nullif(_p->>'due_date','')::date,
          coalesce(_p->>'category','other'), nullif(_p->>'project_id','')::uuid, auth.uid(), idem) RETURNING id INTO cid;
  INSERT INTO charge_assessments(charge_id, house_id, amount_paise) SELECT cid, h, amt FROM unnest(_house_ids) h;
  INSERT INTO notifications(user_id, kind, title, body, link)
    SELECT m.user_id, 'charge', 'New charge: ' || trim(_p->>'title'), NULL, '/dues'
    FROM memberships m WHERE m.house_id = ANY(_house_ids) AND m.status='active';
  PERFORM _audit('charge.created','charge',cid::text, jsonb_build_object('title',_p->>'title','amount',amt,'houses',n,'total',amt*n), NULL, true);
  RETURN cid;
END $$;
CREATE OR REPLACE FUNCTION public.add_house_to_charge(_charge uuid, _house uuid, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c charges;
BEGIN
  PERFORM _require_admin();
  IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  SELECT * INTO c FROM charges WHERE id=_charge;
  INSERT INTO charge_assessments(charge_id, house_id, amount_paise) VALUES (_charge, _house, c.amount_paise) ON CONFLICT DO NOTHING;
  PERFORM _audit('charge.house_added','charge',_charge::text, jsonb_build_object('house',_house), _reason, true);
END $$;
CREATE OR REPLACE FUNCTION public.waive_assessment(_assessment uuid, _amount bigint, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM _require_admin();
  IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  PERFORM 1 FROM charge_assessments WHERE id=_assessment FOR UPDATE;
  IF _amount <= 0 OR _amount > public._outstanding(_assessment) THEN RAISE EXCEPTION 'Waiver must be positive and not above the outstanding due'; END IF;
  INSERT INTO waivers(assessment_id, amount_paise, reason, created_by) VALUES (_assessment, _amount, _reason, auth.uid());
  PERFORM _audit('charge.waived','assessment',_assessment::text, jsonb_build_object('amount',_amount), _reason, true);
END $$;

CREATE OR REPLACE FUNCTION public.generate_maintenance() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE cfg maintenance_config; cur date := date_trunc('month', (now() AT TIME ZONE 'Asia/Kolkata'))::date; cid uuid; made int := 0;
BEGIN
  SELECT * INTO cfg FROM maintenance_config WHERE id=1 FOR UPDATE;
  IF NOT cfg.enabled OR cfg.first_month IS NULL OR cfg.first_month > cur THEN RETURN 0; END IF;
  IF EXISTS (SELECT 1 FROM charges WHERE maintenance_period=cur) THEN RETURN 0; END IF;
  INSERT INTO charges(title, purpose, amount_paise, assessment_date, due_date, category, maintenance_period, created_by)
  VALUES ('Maintenance ' || to_char(cur,'Mon YYYY'), 'Monthly maintenance', cfg.amount_paise, cur, cur + (cfg.due_day-1), 'maintenance', cur, cfg.updated_by)
  ON CONFLICT (maintenance_period) DO NOTHING RETURNING id INTO cid;
  IF cid IS NULL THEN RETURN 0; END IF;
  INSERT INTO charge_assessments(charge_id, house_id, amount_paise)
    SELECT cid, h.id, cfg.amount_paise FROM houses h WHERE h.id = ANY(cfg.house_ids) AND h.active ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS made = ROW_COUNT;
  INSERT INTO notifications(user_id, kind, title, body, link)
    SELECT m.user_id, 'charge', 'Maintenance ' || to_char(cur,'Mon YYYY') || ' issued', NULL, '/dues' FROM memberships m WHERE m.house_id = ANY(cfg.house_ids) AND m.status='active';
  INSERT INTO audit_log(actor, action, entity_type, entity_id, details, financial) VALUES (NULL,'maintenance.generated','charge',cid::text, jsonb_build_object('period',cur,'houses',made), true);
  RETURN made;
END $$;
REVOKE EXECUTE ON FUNCTION public.generate_maintenance() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_maintenance(_enabled boolean, _amount bigint, _house_ids uuid[], _first_month date, _due_day int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE cur date := date_trunc('month', (now() AT TIME ZONE 'Asia/Kolkata'))::date; old maintenance_config;
BEGIN
  PERFORM _require_perm('charges.manage');
  SELECT * INTO old FROM maintenance_config WHERE id=1;
  IF _enabled THEN
    IF _amount IS NULL OR _amount<=0 THEN RAISE EXCEPTION 'Set an amount'; END IF;
    IF coalesce(array_length(_house_ids,1),0)=0 THEN RAISE EXCEPTION 'Select houses'; END IF;
    IF _first_month IS NULL THEN RAISE EXCEPTION 'Choose the first billing month'; END IF;
    IF date_trunc('month',_first_month)::date < cur AND (old.first_month IS NULL OR date_trunc('month',_first_month)::date <> old.first_month) THEN
      RAISE EXCEPTION 'First billing month cannot be in the past (no backdating)'; END IF;
  END IF;
  UPDATE maintenance_config SET enabled=_enabled, amount_paise=_amount, house_ids=coalesce(_house_ids,'{}'),
    first_month=date_trunc('month',_first_month)::date, due_day=greatest(1,least(coalesce(_due_day,10),28)), updated_by=auth.uid(), updated_at=now() WHERE id=1;
  PERFORM _audit('maintenance.configured','maintenance','1', jsonb_build_object('enabled',_enabled,'amount',_amount,'houses',array_length(_house_ids,1),'first_month',_first_month,'due_day',_due_day), NULL, true);
  IF _enabled THEN PERFORM public.generate_maintenance(); END IF;
END $$;

CREATE OR REPLACE FUNCTION public.create_expense(_p jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE eid uuid; amt bigint := (_p->>'amount_paise')::bigint;
BEGIN
  PERFORM _require_active();
  IF coalesce(trim(_p->>'title'),'')='' THEN RAISE EXCEPTION 'Title is required'; END IF;
  IF amt IS NULL OR amt<=0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;
  IF coalesce(_p->>'mode','') NOT IN ('planned','paid_personally') THEN RAISE EXCEPTION 'Choose Planned or Already paid personally'; END IF;
  INSERT INTO expenses(title, description, amount_paise, category, expense_date, mode, project_id, complaint_id, supplier, item_details, quantity, beneficiary, evidence, submitted_by)
  VALUES (trim(_p->>'title'), _p->>'description', amt, coalesce(nullif(_p->>'category',''),'General'), coalesce((_p->>'expense_date')::date,current_date), _p->>'mode',
    nullif(_p->>'project_id','')::uuid, nullif(_p->>'complaint_id','')::uuid, _p->>'supplier', _p->>'item_details', _p->>'quantity', _p->>'beneficiary',
    coalesce(ARRAY(SELECT jsonb_array_elements_text(_p->'evidence')),'{}'), auth.uid()) RETURNING id INTO eid;
  PERFORM _notify_admins('expense','New expense request: ' || trim(_p->>'title'), NULL, '/expenses/' || eid);
  PERFORM _audit('expense.submitted','expense',eid::text,_p,NULL,true);
  RETURN eid;
END $$;
CREATE OR REPLACE FUNCTION public.decide_expense(_exp uuid, _approve boolean, _approved bigint, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE e expenses;
BEGIN
  PERFORM _require_admin();
  SELECT * INTO e FROM expenses WHERE id=_exp FOR UPDATE;
  IF e.status<>'pending' THEN RAISE EXCEPTION 'Expense already decided'; END IF;
  IF _approve THEN
    IF coalesce(_approved, e.amount_paise) <= 0 OR coalesce(_approved,e.amount_paise) > e.amount_paise THEN RAISE EXCEPTION 'Approved amount must be positive and not above the requested amount'; END IF;
    UPDATE expenses SET status='approved', approved_paise=coalesce(_approved,e.amount_paise), decided_by=auth.uid(), decided_at=now(), decision_reason=_reason WHERE id=_exp;
  ELSE
    IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required to reject'; END IF;
    UPDATE expenses SET status='rejected', decided_by=auth.uid(), decided_at=now(), decision_reason=_reason WHERE id=_exp;
  END IF;
  PERFORM _notify(e.submitted_by,'expense', CASE WHEN _approve THEN 'Expense approved: ' ELSE 'Expense rejected: ' END || e.title, _reason, '/expenses/' || _exp);
  PERFORM _audit(CASE WHEN _approve THEN 'expense.approved' ELSE 'expense.rejected' END,'expense',_exp::text, jsonb_build_object('approved',_approved), _reason, true);
END $$;

CREATE TABLE public.updates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id uuid REFERENCES public.projects(id),
  title text NOT NULL, body text NOT NULL,
  published_by uuid NOT NULL, edited_at timestamptz, archived_at timestamptz,
  is_demo boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.update_revisions (
  id bigserial PRIMARY KEY, update_id uuid NOT NULL REFERENCES public.updates(id),
  title text, body text, edited_by uuid, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.issues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ref text UNIQUE NOT NULL DEFAULT 'IS-' || upper(substr(md5(gen_random_uuid()::text),1,6)),
  kind text NOT NULL CHECK (kind IN ('complaint','suggestion')),
  title text NOT NULL, description text NOT NULL, category text NOT NULL DEFAULT 'General', location text,
  photos text[] NOT NULL DEFAULT '{}', project_id uuid REFERENCES public.projects(id),
  author uuid NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','closed')),
  priority text NOT NULL DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
  assignee uuid, closure_note text, reopen_requested_at timestamptz, reopen_request_note text,
  is_demo boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.issue_history (
  id bigserial PRIMARY KEY, issue_id uuid NOT NULL REFERENCES public.issues(id),
  actor uuid, action text NOT NULL, from_value text, to_value text, reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type text NOT NULL CHECK (target_type IN ('project','update','issue')),
  target_id uuid NOT NULL, parent_id uuid REFERENCES public.comments(id),
  author uuid NOT NULL, body text NOT NULL,
  edited_at timestamptz, deleted_at timestamptz, moderated_reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON public.comments(target_type, target_id, created_at);
CREATE TABLE public.reactions (
  target_type text NOT NULL CHECK (target_type IN ('project','update','comment')),
  target_id uuid NOT NULL, user_id uuid NOT NULL, value smallint NOT NULL CHECK (value IN (-1,1)),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (target_type, target_id, user_id)
);
CREATE TABLE public.project_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), project_id uuid NOT NULL REFERENCES public.projects(id),
  path text NOT NULL, caption text, added_by uuid, created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.updates, public.update_revisions, public.issues, public.issue_history, public.comments, public.reactions, public.project_photos TO authenticated;
GRANT ALL ON public.updates, public.update_revisions, public.issues, public.issue_history, public.comments, public.reactions, public.project_photos TO service_role;
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['updates','update_revisions','issues','issue_history','comments','reactions','project_photos'] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY "members read" ON public.%I FOR SELECT TO authenticated USING (public.is_active_member(auth.uid()))', t);
  END LOOP; END $$;

CREATE OR REPLACE FUNCTION public.save_project(_id uuid, _p jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE pid uuid := _id;
BEGIN
  PERFORM _require_perm('projects.manage');
  IF coalesce(trim(_p->>'title'),'')='' THEN RAISE EXCEPTION 'Title is required'; END IF;
  IF pid IS NULL THEN
    INSERT INTO projects(title, description, category, priority, status, responsible_manager, target_date, budget_paise, created_by)
    VALUES (trim(_p->>'title'), _p->>'description', coalesce(nullif(_p->>'category',''),'General'), coalesce(_p->>'priority','normal'), coalesce(_p->>'status','planned'),
      nullif(_p->>'responsible_manager','')::uuid, nullif(_p->>'target_date','')::date, nullif(_p->>'budget_paise','')::bigint, auth.uid()) RETURNING id INTO pid;
    PERFORM _audit('project.created','project',pid::text,_p,NULL);
  ELSE
    PERFORM _audit('project.updated','project',pid::text, jsonb_build_object('before',(SELECT to_jsonb(p) FROM projects p WHERE id=pid),'changes',_p), NULL);
    UPDATE projects SET title=trim(_p->>'title'), description=_p->>'description', category=coalesce(nullif(_p->>'category',''),'General'),
      priority=coalesce(_p->>'priority',priority), status=coalesce(_p->>'status',status), responsible_manager=nullif(_p->>'responsible_manager','')::uuid,
      target_date=nullif(_p->>'target_date','')::date, budget_paise=nullif(_p->>'budget_paise','')::bigint,
      archived=coalesce((_p->>'archived')::boolean, archived) WHERE id=pid;
  END IF;
  RETURN pid;
END $$;
CREATE OR REPLACE FUNCTION public.add_project_photo(_project uuid, _path text, _caption text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN PERFORM _require_perm('projects.manage');
  INSERT INTO project_photos(project_id, path, caption, added_by) VALUES (_project,_path,_caption,auth.uid()); END $$;

CREATE OR REPLACE FUNCTION public.publish_update(_project uuid, _title text, _body text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE uid uuid;
BEGIN
  PERFORM _require_perm('updates.publish');
  IF coalesce(trim(_title),'')='' OR coalesce(trim(_body),'')='' THEN RAISE EXCEPTION 'Title and text are required'; END IF;
  INSERT INTO updates(project_id, title, body, published_by) VALUES (_project, trim(_title), _body, auth.uid()) RETURNING id INTO uid;
  PERFORM _notify_all('update','Official update: ' || trim(_title), NULL, CASE WHEN _project IS NULL THEN '/updates' ELSE '/projects/' || _project END);
  PERFORM _audit('update.published','update',uid::text, jsonb_build_object('title',_title,'project',_project), NULL);
  RETURN uid;
END $$;
CREATE OR REPLACE FUNCTION public.edit_update(_id uuid, _title text, _body text, _archive boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE u updates;
BEGIN
  PERFORM _require_perm('updates.publish');
  SELECT * INTO u FROM updates WHERE id=_id FOR UPDATE;
  INSERT INTO update_revisions(update_id, title, body, edited_by) VALUES (_id, u.title, u.body, auth.uid());
  UPDATE updates SET title=coalesce(nullif(trim(_title),''),title), body=coalesce(nullif(_body,''),body), edited_at=now(),
    archived_at=CASE WHEN _archive THEN coalesce(archived_at,now()) WHEN _archive=false THEN NULL ELSE archived_at END WHERE id=_id;
  PERFORM _audit(CASE WHEN _archive THEN 'update.archived' ELSE 'update.edited' END,'update',_id::text,NULL,NULL);
END $$;

CREATE OR REPLACE FUNCTION public.add_comment(_type text, _target uuid, _parent uuid, _body text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE cid uuid; pa uuid;
BEGIN
  PERFORM _require_active();
  IF coalesce(trim(_body),'')='' OR length(_body)>5000 THEN RAISE EXCEPTION 'Comment must be 1 to 5000 characters'; END IF;
  IF _parent IS NOT NULL THEN
    SELECT author INTO pa FROM comments WHERE id=_parent AND target_type=_type AND target_id=_target;
    IF pa IS NULL THEN RAISE EXCEPTION 'Parent comment not found'; END IF;
  END IF;
  INSERT INTO comments(target_type, target_id, parent_id, author, body) VALUES (_type,_target,_parent,auth.uid(),trim(_body)) RETURNING id INTO cid;
  IF pa IS NOT NULL AND pa<>auth.uid() THEN
    PERFORM _notify(pa,'reply','Someone replied to your comment', left(trim(_body),120),
      CASE _type WHEN 'project' THEN '/projects/' || _target WHEN 'update' THEN '/updates' ELSE '/issues/' || _target END);
  END IF;
  IF _type='issue' THEN
    PERFORM _notify(i.author,'reply','New comment on ' || i.ref, left(trim(_body),120), '/issues/' || i.id) FROM issues i WHERE i.id=_target AND i.author<>auth.uid();
  END IF;
  RETURN cid;
END $$;
CREATE OR REPLACE FUNCTION public.edit_comment(_id uuid, _body text, _delete boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM comments WHERE id=_id AND author=auth.uid() AND deleted_at IS NULL) THEN RAISE EXCEPTION 'You can only change your own comments'; END IF;
  IF _delete THEN UPDATE comments SET deleted_at=now() WHERE id=_id;
  ELSE IF coalesce(trim(_body),'')='' THEN RAISE EXCEPTION 'Comment cannot be empty'; END IF;
       UPDATE comments SET body=trim(_body), edited_at=now() WHERE id=_id; END IF;
END $$;
CREATE OR REPLACE FUNCTION public.moderate_comment(_id uuid, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE a uuid;
BEGIN
  PERFORM _require_perm('moderation');
  IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required'; END IF;
  UPDATE comments SET deleted_at=now(), moderated_reason=_reason WHERE id=_id RETURNING author INTO a;
  PERFORM _notify(a,'moderation','A comment of yours was removed by a moderator',_reason,NULL);
  PERFORM _audit('comment.moderated','comment',_id::text,NULL,_reason);
END $$;
CREATE OR REPLACE FUNCTION public.set_reaction(_type text, _target uuid, _value int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM _require_active();
  IF _value = 0 THEN DELETE FROM reactions WHERE target_type=_type AND target_id=_target AND user_id=auth.uid();
  ELSIF _value IN (-1,1) THEN
    INSERT INTO reactions(target_type, target_id, user_id, value) VALUES (_type,_target,auth.uid(),_value)
    ON CONFLICT (target_type, target_id, user_id) DO UPDATE SET value=EXCLUDED.value, created_at=now();
  ELSE RAISE EXCEPTION 'Invalid reaction'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public._issue_perm(_kind text, _action text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE WHEN _kind='suggestion' THEN public.has_perm(auth.uid(),'suggestions.manage')
              WHEN _action='priority' THEN public.has_perm(auth.uid(),'complaints.priority')
              WHEN _action='self_assign' THEN public.has_perm(auth.uid(),'complaints.self_assign')
              ELSE public.has_perm(auth.uid(),'complaints.manage') END;
$$;
CREATE OR REPLACE FUNCTION public.create_issue(_p jsonb) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE iid uuid;
BEGIN
  PERFORM _require_active();
  IF coalesce(_p->>'kind','') NOT IN ('complaint','suggestion') THEN RAISE EXCEPTION 'Invalid type'; END IF;
  IF coalesce(trim(_p->>'title'),'')='' OR coalesce(trim(_p->>'description'),'')='' THEN RAISE EXCEPTION 'Title and description are required'; END IF;
  INSERT INTO issues(kind, title, description, category, location, photos, project_id, author)
  VALUES (_p->>'kind', trim(_p->>'title'), trim(_p->>'description'), coalesce(nullif(_p->>'category',''),'General'), _p->>'location',
    coalesce(ARRAY(SELECT jsonb_array_elements_text(_p->'photos')),'{}'), nullif(_p->>'project_id','')::uuid, auth.uid()) RETURNING id INTO iid;
  INSERT INTO issue_history(issue_id, actor, action, to_value) VALUES (iid, auth.uid(), 'created', 'open');
  PERFORM _notify_perm(CASE WHEN _p->>'kind'='complaint' THEN 'complaints.manage' ELSE 'suggestions.manage' END,'issue','New ' || (_p->>'kind') || ': ' || trim(_p->>'title'),NULL,'/issues/' || iid);
  RETURN iid;
END $$;
CREATE OR REPLACE FUNCTION public.issue_action(_id uuid, _action text, _value text, _reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE i issues; me uuid := auth.uid(); n int;
BEGIN
  PERFORM _require_active();
  SELECT * INTO i FROM issues WHERE id=_id FOR UPDATE;
  IF i.id IS NULL THEN RAISE EXCEPTION 'Not found'; END IF;
  IF _action='status' THEN
    IF NOT (_issue_perm(i.kind,'status') OR i.assignee=me) THEN RAISE EXCEPTION 'Not allowed to change status'; END IF;
    IF _value NOT IN ('open','in_progress','closed') THEN RAISE EXCEPTION 'Invalid status'; END IF;
    IF _value='closed' AND coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A closing explanation is required'; END IF;
    IF i.status='closed' AND _value<>'closed' AND coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required to reopen'; END IF;
    UPDATE issues SET status=_value, closure_note=CASE WHEN _value='closed' THEN _reason ELSE closure_note END,
      reopen_requested_at=CASE WHEN _value<>'closed' THEN NULL ELSE reopen_requested_at END WHERE id=_id;
    INSERT INTO issue_history(issue_id, actor, action, from_value, to_value, reason) VALUES (_id, me, 'status', i.status, _value, _reason);
    PERFORM _notify(i.author,'issue',i.ref || ' is now ' || replace(_value,'_',' '),_reason,'/issues/' || _id);
  ELSIF _action='priority' THEN
    IF NOT _issue_perm(i.kind,'priority') THEN RAISE EXCEPTION 'Not allowed to change priority'; END IF;
    IF _value NOT IN ('low','normal','high','urgent') THEN RAISE EXCEPTION 'Invalid priority'; END IF;
    UPDATE issues SET priority=_value WHERE id=_id;
    INSERT INTO issue_history(issue_id, actor, action, from_value, to_value, reason) VALUES (_id, me, 'priority', i.priority, _value, _reason);
    PERFORM _notify(i.author,'issue',i.ref || ' priority: ' || _value,NULL,'/issues/' || _id);
  ELSIF _action='take' THEN
    IF NOT _issue_perm(i.kind,'self_assign') THEN RAISE EXCEPTION 'You do not have permission to take responsibility'; END IF;
    UPDATE issues SET assignee=me WHERE id=_id AND assignee IS NULL; GET DIAGNOSTICS n = ROW_COUNT;
    IF n=0 THEN RAISE EXCEPTION 'Someone else already took responsibility'; END IF;
    INSERT INTO issue_history(issue_id, actor, action, to_value) VALUES (_id, me, 'took_responsibility', me::text);
    PERFORM _notify(i.author,'issue','Someone is now responsible for ' || i.ref,NULL,'/issues/' || _id);
  ELSIF _action='assign' THEN
    IF NOT public.is_admin(me) AND NOT _issue_perm(i.kind,'assign') THEN RAISE EXCEPTION 'Not allowed to assign'; END IF;
    IF i.assignee IS NOT NULL AND coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required to reassign'; END IF;
    IF nullif(_value,'') IS NOT NULL AND NOT (public.has_role(_value::uuid,'society_manager') OR public.is_admin(_value::uuid)) THEN RAISE EXCEPTION 'Assignee must be a manager or admin'; END IF;
    UPDATE issues SET assignee=nullif(_value,'')::uuid WHERE id=_id;
    INSERT INTO issue_history(issue_id, actor, action, from_value, to_value, reason) VALUES (_id, me, 'assigned', i.assignee::text, _value, _reason);
    PERFORM _notify(nullif(_value,'')::uuid,'issue','You were assigned ' || i.ref,_reason,'/issues/' || _id);
  ELSIF _action='release' THEN
    IF i.assignee IS DISTINCT FROM me THEN RAISE EXCEPTION 'Only the assignee can release'; END IF;
    IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'A reason is required'; END IF;
    UPDATE issues SET assignee=NULL WHERE id=_id;
    INSERT INTO issue_history(issue_id, actor, action, from_value, reason) VALUES (_id, me, 'released', me::text, _reason);
  ELSIF _action='request_reopen' THEN
    IF i.status<>'closed' THEN RAISE EXCEPTION 'Only closed items can be reopened'; END IF;
    IF coalesce(trim(_reason),'')='' THEN RAISE EXCEPTION 'Explain why it should be reopened'; END IF;
    UPDATE issues SET reopen_requested_at=now(), reopen_request_note=_reason WHERE id=_id;
    INSERT INTO issue_history(issue_id, actor, action, reason) VALUES (_id, me, 'reopen_requested', _reason);
    PERFORM _notify_perm(CASE WHEN i.kind='complaint' THEN 'complaints.manage' ELSE 'suggestions.manage' END,'issue','Reopen requested: ' || i.ref,_reason,'/issues/' || _id);
  ELSIF _action='link_project' THEN
    IF NOT (public.has_perm(me,'projects.manage') OR _issue_perm(i.kind,'status')) THEN RAISE EXCEPTION 'Not allowed'; END IF;
    UPDATE issues SET project_id=nullif(_value,'')::uuid WHERE id=_id;
    INSERT INTO issue_history(issue_id, actor, action, from_value, to_value) VALUES (_id, me, 'linked_project', i.project_id::text, _value);
  ELSE RAISE EXCEPTION 'Unknown action'; END IF;
END $$;

CREATE POLICY "members read evidence" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id='evidence' AND public.is_active_member(auth.uid()));
CREATE POLICY "members upload own evidence" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id='evidence' AND public.is_active_member(auth.uid()) AND (storage.foldername(name))[1] = auth.uid()::text);
