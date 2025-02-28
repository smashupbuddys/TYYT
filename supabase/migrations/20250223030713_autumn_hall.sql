-- Delete pending dispatch data
DELETE FROM quotations
WHERE status = 'accepted'
AND workflow_status->>'dispatch' = 'pending';

-- Delete upcoming video call data
DELETE FROM video_calls 
WHERE status = 'scheduled'
AND workflow_status->>'video_call' = 'pending';

-- Delete any orphaned workflow assignments
DELETE FROM workflow_assignments wa
WHERE NOT EXISTS (
  SELECT 1 FROM video_calls vc
  WHERE vc.id = wa.video_call_id
);

-- Delete any orphaned workflow history
DELETE FROM workflow_history wh
WHERE NOT EXISTS (
  SELECT 1 FROM video_calls vc
  WHERE vc.id = wh.video_call_id
);

-- Delete any orphaned workflow notes
DELETE FROM workflow_notes wn
WHERE NOT EXISTS (
  SELECT 1 FROM video_calls vc
  WHERE vc.id = wn.video_call_id
);

-- Delete any orphaned notifications related to these
DELETE FROM notifications
WHERE type LIKE 'video_call_%'
OR type LIKE 'dispatch_%';