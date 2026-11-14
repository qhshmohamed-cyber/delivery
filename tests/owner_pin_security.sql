-- Authorization simulation only. No real owner PIN is read or changed.
-- All fixtures and credential writes are rolled back.
BEGIN;
CREATE TEMP TABLE pin_test_actor AS
 SELECT p.user_id,gen_random_uuid() AS sid,gen_random_uuid() AS sid2
 FROM public.dlv_profiles p WHERE p.active AND p.role='admin' AND p.workflow_role='admin' LIMIT 1;
CREATE TEMP TABLE pin_test_results(test text,passed boolean);
INSERT INTO auth.sessions(id,user_id,created_at,updated_at) SELECT sid,user_id,now(),now() FROM pin_test_actor;
INSERT INTO auth.sessions(id,user_id,created_at,updated_at) SELECT sid2,user_id,now(),now() FROM pin_test_actor;
DO $tests$
DECLARE u record; s jsonb; i integer; other_user uuid;
BEGIN
 SELECT * INTO STRICT u FROM pin_test_actor;
 PERFORM set_config('request.jwt.claim.sub',u.user_id::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 DELETE FROM public.dlv_owner_page_unlocks WHERE user_id=u.user_id;
 DELETE FROM public.dlv_owner_page_security WHERE user_id=u.user_id;
 DELETE FROM private.dlv_owner_unlock_attempts WHERE user_id=u.user_id;
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF public.dlv_owner_page_check() THEN RAISE EXCEPTION 'Unconfigured page bypass'; END IF;
 s:=public.dlv_owner_page_status();
 IF (s->>'configured')::boolean THEN RAISE EXCEPTION 'Incorrect setup status'; END IF;
 IF public.dlv_owner_page_set_password('12345',null) OR public.dlv_owner_page_set_password('abcdef',null) OR public.dlv_owner_page_set_password('1234567',null) THEN RAISE EXCEPTION 'Invalid PIN accepted'; END IF;
 IF NOT public.dlv_owner_page_set_password('012345',null) THEN RAISE EXCEPTION 'Six digit PIN with leading zero rejected'; END IF;
 IF NOT public.dlv_owner_page_check() OR NOT (public.dlv_owner_page_status()->>'pin_configured')::boolean THEN RAISE EXCEPTION 'Configured current session not unlocked'; END IF;
 EXECUTE 'RESET ROLE';
 IF EXISTS(SELECT 1 FROM public.dlv_owner_page_security WHERE user_id=u.user_id AND (password_hash='012345' OR extensions.crypt('012345',password_hash)<>password_hash)) THEN RAISE EXCEPTION 'Hash storage failed'; END IF;
 DELETE FROM public.dlv_owner_page_unlocks WHERE user_id=u.user_id;
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOR i IN 1..5 LOOP
  IF public.dlv_owner_page_unlock('999999') THEN RAISE EXCEPTION 'Wrong PIN accepted'; END IF;
 END LOOP;
 IF public.dlv_owner_page_unlock('012345') THEN RAISE EXCEPTION 'Correct PIN accepted while blocked'; END IF;
 IF public.dlv_owner_page_set_password('654321','012345') THEN RAISE EXCEPTION 'PIN change bypassed lockout'; END IF;
 EXECUTE 'RESET ROLE';
 IF NOT EXISTS(SELECT 1 FROM private.dlv_owner_unlock_attempts WHERE user_id=u.user_id AND attempts=7) THEN RAISE EXCEPTION 'Attempt counter not persisted'; END IF;
 UPDATE private.dlv_owner_unlock_attempts SET window_started_at=now()-interval '16 minutes' WHERE user_id=u.user_id;
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF NOT public.dlv_owner_page_unlock('012345') THEN RAISE EXCEPTION 'Valid PIN rejected after window expiry'; END IF;
 IF NOT public.dlv_owner_page_check() THEN RAISE EXCEPTION 'Unlocked session not accepted'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid2,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 IF public.dlv_owner_page_check() THEN RAISE EXCEPTION 'Unlock leaked into second session'; END IF;
 IF NOT public.dlv_owner_page_unlock('012345') THEN RAISE EXCEPTION 'Second session valid unlock failed'; END IF;
 IF public.dlv_owner_page_set_password('654321','000000') THEN RAISE EXCEPTION 'Wrong current PIN changed lock'; END IF;
 IF NOT public.dlv_owner_page_set_password('654321','012345') THEN RAISE EXCEPTION 'PIN rotation failed'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 IF public.dlv_owner_page_check() THEN RAISE EXCEPTION 'PIN change retained older unlock'; END IF;
 EXECUTE 'RESET ROLE';
 UPDATE public.dlv_owner_page_security SET password_hash=extensions.crypt('Legacy-page-Test!123',extensions.gen_salt('bf',12)),credential_kind='legacy' WHERE user_id=u.user_id;
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF NOT public.dlv_owner_page_unlock('Legacy-page-Test!123') THEN RAISE EXCEPTION 'Existing credential stopped working'; END IF;
 IF NOT public.dlv_owner_page_set_password('001234','Legacy-page-Test!123') THEN RAISE EXCEPTION 'Legacy migration failed'; END IF;
 EXECUTE 'RESET ROLE';
 UPDATE public.dlv_owner_page_unlocks SET expires_at=now()-interval '1 minute' WHERE user_id=u.user_id;
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF public.dlv_owner_page_check() THEN RAISE EXCEPTION 'Expired unlock accepted'; END IF;
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u.user_id,'session_id',gen_random_uuid(),'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 IF public.dlv_owner_page_unlock('001234') OR public.dlv_owner_page_check() THEN RAISE EXCEPTION 'Revoked session accepted'; END IF;
 EXECUTE 'RESET ROLE';
 SELECT user_id INTO other_user FROM public.dlv_profiles WHERE active AND role<>'admin' LIMIT 1;
 IF other_user IS NULL THEN RAISE EXCEPTION 'Employee fixture missing'; END IF;
 INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(gen_random_uuid(),other_user,now(),now()) RETURNING id INTO u.sid;
 PERFORM set_config('request.jwt.claim.sub',other_user::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',other_user,'session_id',u.sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 IF public.dlv_owner_page_check() OR public.dlv_owner_page_unlock('001234') THEN RAISE EXCEPTION 'Employee bypass'; END IF;
 BEGIN
  PERFORM public.dlv_owner_page_set_password('333333',null);RAISE EXCEPTION 'Employee configured owner lock';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  PERFORM public.dlv_owner_page_status();RAISE EXCEPTION 'Employee obtained lock status';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 EXECUTE 'SET LOCAL ROLE anon';
 BEGIN
  PERFORM public.dlv_owner_page_unlock('001234');RAISE EXCEPTION 'Anonymous call accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 EXECUTE 'RESET ROLE';
 INSERT INTO pin_test_results VALUES
 ('unconfigured_owner_fails_closed',true),
 ('six_digits_only_and_leading_zero',true),
 ('bcrypt_hash_storage',true),
 ('five_wrong_attempts_block_unlock_and_rotation',true),
 ('lockout_window_expiry',true),
 ('unlock_bound_to_session',true),
 ('rotation_requires_current_secret_revokes_other_unlocks',true),
 ('legacy_lock_preserved_and_convertible',true),
 ('expired_unlock_and_revoked_session_denied',true),
 ('employees_and_anonymous_denied',true);
END;
$tests$;
SELECT * FROM pin_test_results;
ROLLBACK;
