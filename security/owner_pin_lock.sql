-- Replace mandatory TOTP gate with an account-bound, server-verified page PIN.
-- Existing credentials remain valid until the owner explicitly changes them.
ALTER TABLE public.dlv_owner_page_security
 ADD COLUMN IF NOT EXISTS credential_kind text NOT NULL DEFAULT 'legacy';

CREATE OR REPLACE FUNCTION public.dlv_owner_page_check()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO '' AS $$
 SELECT public.dlv_session_valid()
 AND EXISTS(SELECT 1 FROM public.dlv_profiles p WHERE p.user_id=(SELECT auth.uid()) AND p.active AND p.role='admin' AND p.workflow_role='admin')
 AND EXISTS(SELECT 1 FROM public.dlv_owner_page_security p WHERE p.user_id=(SELECT auth.uid()))
 AND EXISTS(SELECT 1 FROM public.dlv_owner_page_unlocks u WHERE u.user_id=(SELECT auth.uid()) AND u.session_id=auth.jwt()->>'session_id' AND u.expires_at>now());
$$;

CREATE OR REPLACE FUNCTION public.dlv_owner_page_status()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE configured boolean; kind text; until_at timestamptz;
BEGIN
 IF NOT public.dlv_session_valid() OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=auth.uid() AND active AND role='admin' AND workflow_role='admin')
 THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 SELECT true,credential_kind INTO configured,kind FROM public.dlv_owner_page_security WHERE user_id=auth.uid();
 SELECT window_started_at+interval '15 minutes' INTO until_at FROM private.dlv_owner_unlock_attempts WHERE user_id=auth.uid() AND attempts>=5 AND window_started_at>now()-interval '15 minutes';
 RETURN jsonb_build_object('configured',coalesce(configured,false),'pin_configured',kind='pin6','unlocked',public.dlv_owner_page_check(),'locked_until',until_at);
END;
$$;

CREATE OR REPLACE FUNCTION public.dlv_owner_page_unlock(p_password text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE h text; sid text:=auth.jwt()->>'session_id'; n integer; kind text;
BEGIN
 IF NOT public.dlv_session_valid() OR sid IS NULL OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=auth.uid() AND active AND role='admin' AND workflow_role='admin') THEN RETURN false; END IF;
 IF octet_length(coalesce(p_password,''))>72 THEN RETURN false; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('owner-page-'||auth.uid()::text,0));
 INSERT INTO private.dlv_owner_unlock_attempts(user_id,attempts) VALUES(auth.uid(),1)
 ON CONFLICT(user_id) DO UPDATE SET
 attempts=CASE WHEN dlv_owner_unlock_attempts.window_started_at<=now()-interval '15 minutes' THEN 1 ELSE dlv_owner_unlock_attempts.attempts+1 END,
 window_started_at=CASE WHEN dlv_owner_unlock_attempts.window_started_at<=now()-interval '15 minutes' THEN now() ELSE dlv_owner_unlock_attempts.window_started_at END
 RETURNING attempts INTO n;
 IF n>5 THEN RETURN false; END IF;
 SELECT password_hash,credential_kind INTO h,kind FROM public.dlv_owner_page_security WHERE user_id=auth.uid();
 IF h IS NULL OR (kind='pin6' AND coalesce(p_password,'') !~ '^[0-9]{6}$') OR extensions.crypt(coalesce(p_password,''),h)<>h THEN RETURN false; END IF;
 DELETE FROM private.dlv_owner_unlock_attempts WHERE user_id=auth.uid();
 INSERT INTO public.dlv_owner_page_unlocks(user_id,session_id,expires_at) VALUES(auth.uid(),sid,now()+interval '30 minutes')
 ON CONFLICT(user_id,session_id) DO UPDATE SET expires_at=excluded.expires_at;
 RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.dlv_owner_page_set_password(p_new text,p_old text DEFAULT NULL::text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path TO '' AS $$
DECLARE h text; n integer; sid text:=auth.jwt()->>'session_id';
BEGIN
 IF NOT public.dlv_session_valid() OR sid IS NULL OR NOT EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=auth.uid() AND active AND role='admin' AND workflow_role='admin')
 THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF coalesce(p_new,'') !~ '^[0-9]{6}$' OR octet_length(coalesce(p_old,''))>72 THEN RETURN false; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('owner-page-'||auth.uid()::text,0));
 SELECT password_hash INTO h FROM public.dlv_owner_page_security WHERE user_id=auth.uid() FOR UPDATE;
 IF h IS NOT NULL THEN
  INSERT INTO private.dlv_owner_unlock_attempts(user_id,attempts) VALUES(auth.uid(),1)
  ON CONFLICT(user_id) DO UPDATE SET
  attempts=CASE WHEN dlv_owner_unlock_attempts.window_started_at<=now()-interval '15 minutes' THEN 1 ELSE dlv_owner_unlock_attempts.attempts+1 END,
  window_started_at=CASE WHEN dlv_owner_unlock_attempts.window_started_at<=now()-interval '15 minutes' THEN now() ELSE dlv_owner_unlock_attempts.window_started_at END
  RETURNING attempts INTO n;
  IF n>5 THEN RETURN false; END IF;
  IF p_old IS NULL OR extensions.crypt(p_old,h)<>h THEN RETURN false; END IF;
 END IF;
 INSERT INTO public.dlv_owner_page_security(user_id,password_hash,credential_kind)
 VALUES(auth.uid(),extensions.crypt(p_new,extensions.gen_salt('bf',12)),'pin6')
 ON CONFLICT(user_id) DO UPDATE SET password_hash=excluded.password_hash,credential_kind='pin6',updated_at=now();
 DELETE FROM private.dlv_owner_unlock_attempts WHERE user_id=auth.uid();
 DELETE FROM public.dlv_owner_page_unlocks WHERE user_id=auth.uid();
 INSERT INTO public.dlv_owner_page_unlocks(user_id,session_id,expires_at) VALUES(auth.uid(),sid,now()+interval '30 minutes');
 RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.dlv_owner_page_status(),public.dlv_owner_page_unlock(text),public.dlv_owner_page_set_password(text,text),public.dlv_owner_page_check() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_owner_page_status(),public.dlv_owner_page_unlock(text),public.dlv_owner_page_set_password(text,text),public.dlv_owner_page_check() TO authenticated;
NOTIFY pgrst,'reload schema';
