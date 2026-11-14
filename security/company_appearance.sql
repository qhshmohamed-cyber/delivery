-- Presentation only. Existing branding RLS permits writes only by the unlocked owner.
CREATE OR REPLACE FUNCTION public.dlv_appearance_valid(p_value jsonb)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path TO '' AS $$
DECLARE k text; rule jsonb; prop text; val jsonb;
BEGIN
 IF p_value IS NULL OR jsonb_typeof(p_value)<>'object' OR octet_length(p_value::text)>60000 THEN RETURN false; END IF;
 IF (SELECT count(*) FROM jsonb_object_keys(p_value))>120 THEN RETURN false; END IF;
 FOR k,rule IN SELECT * FROM jsonb_each(p_value) LOOP
  IF k NOT IN ('text','headings','muted','cards','inputs','buttons','primary','gold','header') AND
   k !~ '^path:[a-z_]{1,32}:(div|section|header|nav|main|aside|article|form|details|summary|table|thead|tbody|tr|td|th|ul|ol|li|label|input|select|textarea|button|h1|h2|h3|p|small|span|strong|b|a):nth-of-type\([1-9][0-9]{0,2}\)(>(div|section|header|nav|main|aside|article|form|details|summary|table|thead|tbody|tr|td|th|ul|ol|li|label|input|select|textarea|button|h1|h2|h3|p|small|span|strong|b|a):nth-of-type\([1-9][0-9]{0,2}\)){0,11}$' THEN RETURN false; END IF;
  IF jsonb_typeof(rule)<>'object' THEN RETURN false; END IF;
  FOR prop,val IN SELECT * FROM jsonb_each(rule) LOOP
   IF prop IN ('color','background','border') THEN
    IF jsonb_typeof(val)<>'string' OR (val#>>'{}') !~ '^#[0-9a-fA-F]{6}$' THEN RETURN false; END IF;
   ELSIF prop IN ('size','padding','radius','weight') THEN
    IF jsonb_typeof(val)<>'number' THEN RETURN false; END IF;
    IF prop='size' AND NOT ((val::text)::numeric BETWEEN 14 AND 32) THEN RETURN false; END IF;
    IF prop='padding' AND NOT ((val::text)::numeric BETWEEN 8 AND 28) THEN RETURN false; END IF;
    IF prop='radius' AND NOT ((val::text)::numeric BETWEEN 0 AND 28) THEN RETURN false; END IF;
    IF prop='weight' AND (val::text)::numeric NOT IN (400,500,600,700) THEN RETURN false; END IF;
   ELSE RETURN false;
   END IF;
  END LOOP;
 END LOOP;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.dlv_appearance_valid(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.dlv_appearance_valid(jsonb) TO authenticated,service_role;
ALTER TABLE public.dlv_company_branding ADD COLUMN appearance jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE public.dlv_company_branding ADD CONSTRAINT dlv_company_appearance_safe CHECK (public.dlv_appearance_valid(appearance));
