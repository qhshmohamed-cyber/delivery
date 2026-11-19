-- Additive stage only: no existing login, RLS, or business rule is changed.
CREATE TABLE IF NOT EXISTS private.dlv_staff_session_lease (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id uuid NOT NULL,
  claimed_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE private.dlv_staff_session_lease ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.dlv_staff_session_lease FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.dlv_staff_session_claim()
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_sid uuid;
  v_claimed uuid;
  v_owner boolean := false;
BEGIN
  IF v_user IS NULL THEN
    RETURN pg_catalog.jsonb_build_object('allowed',false,'reason','unauthenticated');
  END IF;
  BEGIN
    v_sid := pg_catalog.nullif(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN pg_catalog.jsonb_build_object('allowed',false,'reason','bad_session');
  END;
  IF v_sid IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.sessions s JOIN auth.users u ON u.id=s.user_id
    WHERE s.id=v_sid AND s.user_id=v_user
      AND (s.not_after IS NULL OR s.not_after>now())
      AND u.deleted_at IS NULL
      AND (u.banned_until IS NULL OR u.banned_until<=now())
  ) THEN
    RETURN pg_catalog.jsonb_build_object('allowed',false,'reason','invalid_session');
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM private.dlv_platform_root_owner r
    JOIN public.dlv_profiles p ON p.user_id=r.user_id
    WHERE r.singleton=1 AND r.user_id=v_user AND p.active=true
      AND p.role='admin' AND p.workflow_role='admin'
  ) INTO v_owner;
  IF v_owner THEN
    RETURN pg_catalog.jsonb_build_object('allowed',true,'owner',true);
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.dlv_profiles p WHERE p.user_id=v_user AND p.active=true)
  THEN RETURN pg_catalog.jsonb_build_object('allowed',false,'reason','inactive');
  END IF;

  INSERT INTO private.dlv_staff_session_lease AS leases (user_id,session_id,claimed_at,last_seen_at)
    VALUES(v_user,v_sid,now(),now())
    ON CONFLICT (user_id) DO UPDATE
      SET session_id=EXCLUDED.session_id,
          claimed_at=CASE WHEN leases.session_id=EXCLUDED.session_id
                          THEN leases.claimed_at ELSE now() END,
          last_seen_at=now()
      WHERE leases.session_id=EXCLUDED.session_id
         OR leases.last_seen_at < now()-interval '15 minutes'
    RETURNING session_id INTO v_claimed;
  RETURN pg_catalog.jsonb_build_object(
    'allowed',v_claimed=v_sid,'owner',false,
    'reason',CASE WHEN v_claimed=v_sid THEN 'ok' ELSE 'already_active' END
  );
END $$;
REVOKE ALL ON FUNCTION public.dlv_staff_session_claim() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dlv_staff_session_claim() TO authenticated;

CREATE OR REPLACE FUNCTION public.dlv_staff_session_heartbeat()
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_sid uuid; v_ok uuid;
BEGIN
  BEGIN v_sid:=pg_catalog.nullif(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN RETURN false; END;
  IF auth.uid() IS NULL OR v_sid IS NULL THEN RETURN false; END IF;
  IF EXISTS(
    SELECT 1 FROM private.dlv_platform_root_owner r JOIN public.dlv_profiles p ON p.user_id=r.user_id
    WHERE r.singleton=1 AND r.user_id=auth.uid() AND p.active
      AND p.role='admin' AND p.workflow_role='admin'
  ) THEN RETURN true; END IF;
  IF NOT EXISTS(SELECT 1 FROM auth.sessions s WHERE s.id=v_sid AND s.user_id=auth.uid())
  THEN RETURN false; END IF;
  UPDATE private.dlv_staff_session_lease
  SET last_seen_at=now()
  WHERE user_id=auth.uid() AND session_id=v_sid
  RETURNING session_id INTO v_ok;
  RETURN v_ok=v_sid;
END $$;
REVOKE ALL ON FUNCTION public.dlv_staff_session_heartbeat() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dlv_staff_session_heartbeat() TO authenticated;

CREATE OR REPLACE FUNCTION public.dlv_staff_session_release()
RETURNS boolean LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_sid uuid;
BEGIN
  BEGIN v_sid:=pg_catalog.nullif(auth.jwt()->>'session_id','')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN RETURN false; END;
  IF auth.uid() IS NULL OR v_sid IS NULL THEN RETURN false; END IF;
  DELETE FROM private.dlv_staff_session_lease
  WHERE user_id=auth.uid() AND session_id=v_sid;
  RETURN found;
END $$;
REVOKE ALL ON FUNCTION public.dlv_staff_session_release() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dlv_staff_session_release() TO authenticated;

CREATE OR REPLACE FUNCTION public.dlv_staff_session_allowed()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
  SELECT
    EXISTS(SELECT 1 FROM private.dlv_platform_root_owner r JOIN public.dlv_profiles p
      ON p.user_id=r.user_id WHERE r.singleton=1 AND r.user_id=auth.uid()
      AND p.active AND p.role='admin' AND p.workflow_role='admin')
    OR EXISTS(
      SELECT 1 FROM private.dlv_staff_session_lease s
      WHERE s.user_id=auth.uid()
        AND s.session_id::text=auth.jwt()->>'session_id'
        AND s.last_seen_at > now()-interval '15 minutes'
    )
$$;
REVOKE ALL ON FUNCTION public.dlv_staff_session_allowed() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dlv_staff_session_allowed() TO authenticated;
