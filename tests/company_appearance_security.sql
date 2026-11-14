-- Reversible checks only; no retained changes to accounts, sessions or appearance.
BEGIN;
CREATE TEMP TABLE appearance_check_results(test text,passed boolean);
DO $test$
DECLARE owner_id uuid; employee_id uuid; employee_company bigint; company bigint; sid uuid:=gen_random_uuid(); employee_sid uuid:=gen_random_uuid(); n int;
BEGIN
 SELECT user_id INTO STRICT owner_id FROM public.dlv_profiles WHERE active AND role='admin' AND workflow_role='admin';
 SELECT p.user_id,b.company_id INTO STRICT employee_id,employee_company FROM public.dlv_profiles p JOIN public.dlv_branches b ON b.id=p.branch_id WHERE p.active AND p.role='driver' LIMIT 1;
 SELECT company_id INTO STRICT company FROM public.dlv_company_branding LIMIT 1;
 INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(sid,owner_id,now(),now()),(employee_sid,employee_id,now(),now());
 PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'session_id',sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 UPDATE public.dlv_company_branding SET appearance='{"cards":{"size":20,"color":"#ffffff","background":"#211c1b"}}' WHERE company_id=company;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>0 THEN RAISE EXCEPTION 'Locked owner changed appearance';END IF;
 EXECUTE 'RESET ROLE';
 INSERT INTO public.dlv_owner_page_unlocks(user_id,session_id,expires_at) VALUES(owner_id,sid::text,now()+interval '10 minutes');
 EXECUTE 'SET LOCAL ROLE authenticated';
 UPDATE public.dlv_company_branding SET appearance='{"cards":{"size":20,"color":"#ffffff","background":"#211c1b"}}' WHERE company_id=company;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>1 THEN RAISE EXCEPTION 'Unlocked owner cannot save appearance';END IF;
 BEGIN
  UPDATE public.dlv_company_branding SET appearance='{"cards":{"color":"url(https://invalid.example)"}}' WHERE company_id=company;
  RAISE EXCEPTION 'Invalid CSS accepted';
 EXCEPTION WHEN check_violation THEN NULL; END;
 EXECUTE 'RESET ROLE';
 PERFORM set_config('request.jwt.claim.sub',employee_id::text,true);
 PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',employee_id,'session_id',employee_sid,'exp',extract(epoch from now()+interval '1 hour')::bigint,'aal','aal1')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 UPDATE public.dlv_company_branding SET appearance='{}' WHERE company_id=employee_company;
 GET DIAGNOSTICS n=ROW_COUNT;
 IF n<>0 THEN RAISE EXCEPTION 'Employee changed company appearance';END IF;
 SELECT count(*) INTO n FROM public.dlv_company_branding WHERE company_id<>employee_company;
 IF n<>0 THEN RAISE EXCEPTION 'Employee read foreign appearance';END IF;
 EXECUTE 'RESET ROLE';
 INSERT INTO appearance_check_results VALUES('locked_owner_denied',true),('unlocked_owner_can_save',true),('css_injection_denied',true),('employee_write_denied',true),('foreign_company_read_denied',true);
END $test$;
SELECT * FROM appearance_check_results;
ROLLBACK;
