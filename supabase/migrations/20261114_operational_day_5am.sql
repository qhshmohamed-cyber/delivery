-- Your Staff Delivery operational day boundary, Africa/Cairo 05:00.
-- Safe additive migration: no data deletion, no table changes.
CREATE OR REPLACE FUNCTION public.dlv_operational_day(p_at timestamptz)
RETURNS date
LANGUAGE sql
STABLE
SET search_path = pg_catalog
AS $$
 SELECT ((p_at AT TIME ZONE 'Africa/Cairo') - interval '5 hours')::date;
$$;
REVOKE ALL ON FUNCTION public.dlv_operational_day(timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dlv_operational_day(timestamptz) TO authenticated;
COMMENT ON FUNCTION public.dlv_operational_day(timestamptz) IS
 'Operational day runs from 05:00 Africa/Cairo until immediately before 05:00 next calendar day. Does not delete records.';
