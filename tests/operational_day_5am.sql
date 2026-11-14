-- Read-only assertions for 05:00 Cairo cutoff. Run in SQL editor.
DO $$
BEGIN
 IF public.dlv_operational_day('2026-11-14 02:59:59+00'::timestamptz) <> DATE '2026-11-13' THEN
   RAISE EXCEPTION 'Before 05:00 Cairo should belong to previous day';
 END IF;
 IF public.dlv_operational_day('2026-11-14 03:00:00+00'::timestamptz) <> DATE '2026-11-14' THEN
   RAISE EXCEPTION '05:00 Cairo should start new day';
 END IF;
 IF public.dlv_operational_day('2026-11-15 02:59:59+00'::timestamptz) <> DATE '2026-11-14' THEN
   RAISE EXCEPTION 'End of Nov 14 shift should belong to Nov 14';
 END IF;
END $$;
