-- name: Start a session (device-limit check with seat lock)
-- kind: transactional
-- mode: dml
SELECT * FROM app.start_session(:rec_user, digest('bench-device-' || clock_timestamp()::text, 'sha256'),
                                digest('bench-token-' || clock_timestamp()::text, 'sha256'));
