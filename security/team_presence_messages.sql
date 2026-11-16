-- Private staff presence and one-to-one management notices. No client table access.
CREATE TABLE private.dlv_team_presence(
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 session_id uuid NOT NULL REFERENCES auth.sessions(id) ON DELETE CASCADE,
 last_seen timestamptz NOT NULL DEFAULT now(),visible boolean NOT NULL DEFAULT true,
 PRIMARY KEY(user_id,session_id)
);
CREATE TABLE private.dlv_team_messages(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 sender_id uuid NOT NULL REFERENCES auth.users(id),recipient_id uuid NOT NULL REFERENCES auth.users(id),
 branch_id integer NOT NULL REFERENCES public.dlv_branches(id),
 body text NOT NULL CHECK(length(body) BETWEEN 1 AND 2000),
 request_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 delivered_at timestamptz,read_at timestamptz,
 UNIQUE(sender_id,request_id),CHECK(sender_id<>recipient_id)
);
CREATE INDEX dlv_team_messages_recipient ON private.dlv_team_messages(recipient_id,created_at DESC);
CREATE INDEX dlv_team_messages_sender ON private.dlv_team_messages(sender_id,created_at DESC);
ALTER TABLE private.dlv_team_presence ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.dlv_team_messages ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.dlv_team_presence,private.dlv_team_messages FROM PUBLIC,anon,authenticated;

CREATE FUNCTION private.dlv_team_can_manage(p_target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT public.dlv_session_valid() AND public.dlv_role() IN ('admin','manager')
 AND (public.dlv_role()<>'admin' OR public.dlv_owner_page_check())
 AND EXISTS(SELECT 1 FROM public.dlv_profiles p JOIN auth.users u ON u.id=p.user_id JOIN public.dlv_branches b ON b.id=p.branch_id
 JOIN public.dlv_companies c ON c.id=b.company_id
 WHERE p.user_id=p_target AND p.active AND u.deleted_at IS NULL AND (u.banned_until IS NULL OR u.banned_until<=now()) AND b.active AND c.active AND c.onboarding_status='active'
 AND public.dlv_can_access_branch(b.id) AND (p.role<>'admin' OR public.dlv_role()='admin'));
$$;
REVOKE ALL ON FUNCTION private.dlv_team_can_manage(uuid) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.dlv_team_ping(p_visible boolean DEFAULT true) RETURNS timestamptz
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid:=(SELECT auth.uid());sid uuid; at_time timestamptz:=now();
BEGIN
 IF NOT public.dlv_session_valid() OR public.dlv_role() IS NULL THEN RAISE EXCEPTION 'Session unavailable' USING ERRCODE='42501';END IF;
 IF public.dlv_role()='admin' AND NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION 'Owner verification required' USING ERRCODE='42501';END IF;
 sid:=(auth.jwt()->>'session_id')::uuid;
 INSERT INTO private.dlv_team_presence(user_id,session_id,last_seen,visible) VALUES(uid,sid,at_time,coalesce(p_visible,false))
 ON CONFLICT(user_id,session_id) DO UPDATE SET last_seen=excluded.last_seen,visible=excluded.visible;
 DELETE FROM private.dlv_team_presence WHERE user_id=uid AND last_seen<now()-interval '7 days';
 RETURN at_time;
END $$;

CREATE FUNCTION public.dlv_team_members(p_search text DEFAULT '',p_offset integer DEFAULT 0,p_limit integer DEFAULT 100)
RETURNS TABLE(user_id uuid,full_name text,job_title text,branch_id integer,branch_name text,company_name text,last_seen timestamptz,online boolean,visible boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.dlv_session_valid() OR public.dlv_role() NOT IN ('admin','manager') OR public.dlv_role() IS NULL
 OR (public.dlv_role()='admin' AND NOT public.dlv_owner_page_check()) THEN RAISE EXCEPTION 'Management only' USING ERRCODE='42501';END IF;
 RETURN QUERY SELECT p.user_id,p.full_name,coalesce(p.job_title,p.workflow_role),b.id,b.name,c.name,
 presence.last_seen,coalesce(presence.last_seen>now()-interval '90 seconds',false),coalesce(presence.visible,false)
 FROM public.dlv_profiles p JOIN public.dlv_branches b ON b.id=p.branch_id JOIN public.dlv_companies c ON c.id=b.company_id
 LEFT JOIN LATERAL(SELECT max(h.last_seen) AS last_seen,bool_or(h.visible AND h.last_seen>now()-interval '90 seconds') AS visible
 FROM private.dlv_team_presence h JOIN auth.sessions s ON s.id=h.session_id AND s.user_id=h.user_id
 WHERE h.user_id=p.user_id AND (s.not_after IS NULL OR s.not_after>now()))presence ON true
 WHERE private.dlv_team_can_manage(p.user_id) AND p.user_id<>(SELECT auth.uid())
 AND (coalesce(btrim(p_search),'')='' OR position(lower(left(btrim(p_search),100)) IN lower(p.full_name||' '||b.name||' '||c.name))>0)
 ORDER BY (presence.last_seen>now()-interval '90 seconds') DESC NULLS LAST,p.full_name,p.user_id
 LIMIT least(greatest(coalesce(p_limit,100),1),100) OFFSET greatest(coalesce(p_offset,0),0);
END $$;

CREATE FUNCTION public.dlv_team_send(p_recipient uuid,p_body text,p_request uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE uid uuid:=(SELECT auth.uid());v_body text:=btrim(coalesce(p_body,''));prior private.dlv_team_messages;mid uuid;bid integer;
BEGIN
 IF p_request IS NULL OR p_recipient IS NULL OR p_recipient=uid OR private.dlv_team_can_manage(p_recipient) IS NOT TRUE THEN RAISE EXCEPTION 'Recipient unavailable or unauthorized' USING ERRCODE='42501';END IF;
 IF length(v_body) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Message must contain 1 to 2000 characters' USING ERRCODE='22023';END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('team-send:'||uid::text,0));
 SELECT * INTO prior FROM private.dlv_team_messages WHERE sender_id=uid AND request_id=p_request;
 IF FOUND THEN
  IF prior.recipient_id<>p_recipient OR prior.body<>v_body THEN RAISE EXCEPTION 'Request already used with different content' USING ERRCODE='22023';END IF;
  RETURN prior.id;
 END IF;
 IF (SELECT count(*) FROM private.dlv_team_messages WHERE sender_id=uid AND created_at>now()-interval '1 minute')>=30 THEN RAISE EXCEPTION 'Message rate limit reached; retry shortly' USING ERRCODE='54000';END IF;
 SELECT p.branch_id INTO STRICT bid FROM public.dlv_profiles p WHERE p.user_id=p_recipient AND p.active FOR SHARE;
 IF private.dlv_team_can_manage(p_recipient) IS NOT TRUE THEN RAISE EXCEPTION 'Recipient changed' USING ERRCODE='42501';END IF;
 INSERT INTO private.dlv_team_messages(sender_id,recipient_id,branch_id,body,request_id) VALUES(uid,p_recipient,bid,v_body,p_request) RETURNING id INTO mid;
 RETURN mid;
END $$;

CREATE FUNCTION public.dlv_team_inbox(p_limit integer DEFAULT 50)
RETURNS TABLE(id uuid,sender_name text,body text,created_at timestamptz,delivered_at timestamptz,read_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.dlv_session_valid() OR public.dlv_role() IS NULL OR (public.dlv_role()='admin' AND NOT public.dlv_owner_page_check()) THEN RAISE EXCEPTION 'Session unavailable' USING ERRCODE='42501';END IF;
 RETURN QUERY SELECT m.id,p.full_name,m.body,m.created_at,m.delivered_at,m.read_at
 FROM private.dlv_team_messages m JOIN public.dlv_profiles p ON p.user_id=m.sender_id
 WHERE m.recipient_id=(SELECT auth.uid()) AND m.branch_id=public.dlv_branch()
 AND public.dlv_can_access_branch(m.branch_id)
 ORDER BY (m.read_at IS NULL) DESC,m.created_at DESC,m.id LIMIT least(greatest(coalesce(p_limit,50),1),100);
END $$;

CREATE FUNCTION public.dlv_team_thread(p_recipient uuid,p_limit integer DEFAULT 50)
RETURNS TABLE(id uuid,body text,created_at timestamptz,delivered_at timestamptz,read_at timestamptz)
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF private.dlv_team_can_manage(p_recipient) IS NOT TRUE THEN RAISE EXCEPTION 'Recipient unavailable or unauthorized' USING ERRCODE='42501';END IF;
 RETURN QUERY SELECT m.id,m.body,m.created_at,m.delivered_at,m.read_at FROM private.dlv_team_messages m
 WHERE m.sender_id=(SELECT auth.uid()) AND m.recipient_id=p_recipient AND public.dlv_can_access_branch(m.branch_id)
 ORDER BY m.created_at DESC,m.id LIMIT least(greatest(coalesce(p_limit,50),1),100);
END $$;

CREATE FUNCTION public.dlv_team_ack(p_id uuid,p_read boolean DEFAULT false) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT public.dlv_session_valid() OR public.dlv_role() IS NULL OR (public.dlv_role()='admin' AND NOT public.dlv_owner_page_check()) THEN RAISE EXCEPTION 'Session unavailable' USING ERRCODE='42501';END IF;
 UPDATE private.dlv_team_messages m SET delivered_at=coalesce(m.delivered_at,now()),read_at=CASE WHEN p_read THEN coalesce(m.read_at,now()) ELSE m.read_at END
 WHERE m.id=p_id AND m.recipient_id=(SELECT auth.uid()) AND m.branch_id=public.dlv_branch() AND public.dlv_can_access_branch(m.branch_id)
 AND (m.delivered_at IS NULL OR (p_read AND m.read_at IS NULL));
 RETURN FOUND;
END $$;

CREATE FUNCTION private.dlv_team_notify() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 -- Only an opaque ID is broadcast; authenticated recipients fetch text through guarded RPCs.
 BEGIN
  IF TG_OP='INSERT' THEN PERFORM realtime.send(jsonb_build_object('id',NEW.id),'staff_message','profile:user:'||NEW.recipient_id::text,true);
  ELSE PERFORM realtime.send(jsonb_build_object('id',NEW.id),'staff_message','profile:user:'||NEW.sender_id::text,true);END IF;
 EXCEPTION WHEN OTHERS THEN NULL; -- durable inbox polling remains available if realtime is down
 END;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION private.dlv_team_notify() FROM PUBLIC,anon,authenticated;
CREATE TRIGGER dlv_team_notify AFTER INSERT OR UPDATE OF delivered_at,read_at ON private.dlv_team_messages FOR EACH ROW EXECUTE FUNCTION private.dlv_team_notify();
REVOKE ALL ON FUNCTION public.dlv_team_ping(boolean),public.dlv_team_members(text,integer,integer),public.dlv_team_send(uuid,text,uuid),public.dlv_team_inbox(integer),public.dlv_team_thread(uuid,integer),public.dlv_team_ack(uuid,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_team_ping(boolean),public.dlv_team_members(text,integer,integer),public.dlv_team_send(uuid,text,uuid),public.dlv_team_inbox(integer),public.dlv_team_thread(uuid,integer),public.dlv_team_ack(uuid,boolean) TO authenticated;
NOTIFY pgrst,'reload schema';
