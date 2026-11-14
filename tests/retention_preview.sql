-- Safe retention candidate preview: no DELETE, no data changes.
-- Do not schedule deletion without a verified backup/restore and retention approval.
SELECT 'read_notifications_30d' AS candidate, count(*) AS rows_eligible
FROM public.dlv_notifications WHERE read_at IS NOT NULL AND read_at < now()-interval '30 days'
UNION ALL
SELECT 'stale_locations_30d', count(*) FROM public.dlv_locations
WHERE updated_at < now()-interval '30 days'
UNION ALL
SELECT 'expired_rating_rate_limit_7d', count(*) FROM private.dlv_public_rating_rate_limits
WHERE window_started_at < now()-interval '7 days';
