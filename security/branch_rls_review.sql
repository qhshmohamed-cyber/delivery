-- SECURITY REVIEW REQUIRED BEFORE PRODUCTION EXECUTION
-- Existing dlv_branches b_sel policy USING(true) exposes all branch rows to any authenticated user.
-- Replace only after testing owner, manager, supervisor, employee and multi-branch accounts.
BEGIN;
DROP POLICY IF EXISTS b_sel ON public.dlv_branches;
CREATE POLICY b_sel ON public.dlv_branches FOR SELECT TO authenticated
USING (
  (select public.dlv_role()) = 'admin'
  OR public.dlv_can_access_branch(id)
);
COMMIT;
-- Validation cases: owner can see all; staff sees only permitted branches;
-- disabled accounts see none; tenant A cannot enumerate tenant B.
-- Rollback (only if validated to be necessary; temporarily restores old behavior):
-- DROP POLICY b_sel ON public.dlv_branches;
-- CREATE POLICY b_sel ON public.dlv_branches FOR SELECT TO authenticated USING (true);
