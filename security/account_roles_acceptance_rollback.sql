-- Executes real account creation for every supported employee role in active branches.
-- All users, identities, sessions and audit entries are rolled back in a subtransaction.
CREATE TEMP TABLE qa_account_result(created_accounts integer,branches_tested integer,role_types integer,isolation_checks integer) ON COMMIT DROP;
DO $$
DECLARE owner_id uuid; owner_session uuid:=gen_random_uuid(); employee_session uuid;
 account_id uuid; job text; expected record; b record; other_branch integer;
 total integer:=0; branch_count integer:=0; checks integer:=0;
 code text; test_password text; new_company bigint; new_branch integer;
 original_users bigint; original_profiles bigint;
BEGIN
 SELECT user_id INTO STRICT owner_id FROM public.dlv_profiles WHERE active AND role='admin' AND workflow_role='admin' LIMIT 1;
 SELECT count(*) INTO original_users FROM auth.users;
 SELECT count(*) INTO original_profiles FROM public.dlv_profiles;
 BEGIN
  INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(owner_session,owner_id,now(),now());
  INSERT INTO public.dlv_owner_page_unlocks(user_id,session_id,expires_at) VALUES(owner_id,owner_session::text,now()+interval '15 minutes');
  INSERT INTO public.dlv_companies(name,slug,active,onboarding_status) VALUES('QA rollback only','qa-'||gen_random_uuid()::text,true,'active') RETURNING id INTO new_company;
  SELECT coalesce(max(id),0)+1 INTO new_branch FROM public.dlv_branches;
  INSERT INTO public.dlv_branches(id,name,company_id,active) VALUES(new_branch,'QA rollback branch A',new_company,true),(new_branch+1,'QA rollback branch B',new_company,true);
  FOR b IN SELECT br.id FROM public.dlv_branches br JOIN public.dlv_companies c ON c.id=br.company_id WHERE br.active AND c.active AND c.onboarding_status='active' ORDER BY br.id LOOP
   branch_count:=branch_count+1;
   FOREACH job IN ARRAY ARRAY['driver','supervisor','manager','callcenter','kitchen','complaints_officer','custom:كاشير اختبار'] LOOP
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'session_id',owner_session,'role','authenticated','exp',extract(epoch FROM now()+interval '1 hour')::bigint)::text,true);
    PERFORM set_config('request.jwt.claim.sub',owner_id::text,true);
    code:='QA-'||substr(gen_random_uuid()::text,1,20);test_password:='Qa!1'||gen_random_uuid()::text;
    account_id:=public.dlv_create_account(lower(code)||'@example.com',test_password,'QA rollback employee',code,job,b.id);
    SELECT * INTO expected FROM public.dlv_job_info(job);
    IF NOT EXISTS(SELECT 1 FROM public.dlv_profiles WHERE user_id=account_id AND branch_id=b.id AND allowed_branch_ids=ARRAY[b.id] AND workflow_role=expected.new_wf AND role=expected.new_role AND active) THEN RAISE EXCEPTION 'Account role/branch mapping failed: %',job; END IF;
    IF NOT EXISTS(SELECT 1 FROM auth.identities WHERE user_id=account_id AND provider='email') THEN RAISE EXCEPTION 'Missing login identity'; END IF;
    employee_session:=gen_random_uuid();INSERT INTO auth.sessions(id,user_id,created_at,updated_at) VALUES(employee_session,account_id,now(),now());
    PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',account_id,'session_id',employee_session,'role','authenticated','exp',extract(epoch FROM now()+interval '1 hour')::bigint)::text,true);
    PERFORM set_config('request.jwt.claim.sub',account_id::text,true);
    IF public.dlv_role() IS DISTINCT FROM expected.new_wf THEN RAISE EXCEPTION 'Runtime role failed: %',job; END IF;
    IF NOT public.dlv_can_access_branch(b.id) OR EXISTS(SELECT 1 FROM public.dlv_my_branches() x WHERE x.id<>b.id) THEN RAISE EXCEPTION 'Assigned branch scope failed'; END IF;
    FOR other_branch IN SELECT br.id FROM public.dlv_branches br WHERE br.id<>b.id LOOP
     IF public.dlv_can_access_branch(other_branch) THEN RAISE EXCEPTION 'Cross-branch access accepted'; END IF;checks:=checks+1;
    END LOOP;
    total:=total+1;
   END LOOP;
  END LOOP;
  RAISE EXCEPTION USING ERRCODE='ZQ002',MESSAGE='rollback successful acceptance fixtures';
 EXCEPTION WHEN SQLSTATE 'ZQ002' THEN NULL;
 END;
 IF (SELECT count(*) FROM auth.users)<>original_users OR (SELECT count(*) FROM public.dlv_profiles)<>original_profiles THEN RAISE EXCEPTION 'QA fixture rollback failed'; END IF;
 INSERT INTO qa_account_result VALUES(total,branch_count,7,checks);
END $$;
SELECT * FROM qa_account_result;
