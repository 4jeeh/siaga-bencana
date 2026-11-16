-- Siaga Bencana v1.0.0 -- PLANNING LOCK 2026-11-16
-- PostgreSQL 15+ / Supabase. Apply ONCE to a clean database with a migration owner.
-- Pure schema: no seed, passwords, extensions, PostGIS, or Supabase-specific roles.
-- All business tables live in non-public schema siaga; do NOT expose it in PostgREST.
-- SQLModel must set schema='siaga'. Runtime uses a separate non-owner DB role.
BEGIN;
CREATE SCHEMA siaga;
REVOKE ALL ON SCHEMA siaga FROM PUBLIC;
SET LOCAL search_path = siaga, pg_catalog;
SET LOCAL TIME ZONE 'UTC';

CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text NOT NULL UNIQUE CHECK (email = lower(btrim(email)) AND char_length(email) BETWEEN 3 AND 254 AND position('@' IN email) > 1),
    display_name text NOT NULL CHECK (display_name = btrim(display_name) AND char_length(display_name) BETWEEN 1 AND 80),
    password_hash text NOT NULL CHECK (password_hash LIKE '$argon2%'),
    role text NOT NULL DEFAULT 'citizen' CHECK (role IN ('citizen', 'admin')),
    active boolean NOT NULL DEFAULT true,
    last_notification_sequence bigint NOT NULL DEFAULT 0 CHECK (last_notification_sequence >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now() CHECK (updated_at >= created_at)
);

CREATE TABLE alert_zones (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL UNIQUE REFERENCES users(id) ON DELETE RESTRICT,
    latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude double precision NOT NULL CHECK (longitude >= -180 AND longitude < 180),
    radius_km smallint NOT NULL DEFAULT 50 CHECK (radius_km IN (25, 50, 100)),
    notify_earthquake boolean NOT NULL DEFAULT true,
    notify_weather boolean NOT NULL DEFAULT true,
    zone_version bigint NOT NULL DEFAULT 1 CHECK (zone_version > 0),
    alert_eligible_since timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (updated_at >= created_at AND alert_eligible_since >= created_at)
);
CREATE INDEX alert_zones_coordinates_idx ON alert_zones(latitude, longitude);

CREATE TABLE disaster_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source text NOT NULL CHECK (source IN ('BMKG_TEWS', 'BMKG_NOWCAST')),
    source_key text NOT NULL CHECK (char_length(source_key) BETWEEN 1 AND 1024),
    category text NOT NULL CHECK (category IN ('earthquake', 'extreme_weather')),
    title text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 500),
    occurred_at timestamptz NOT NULL,
    latitude double precision CHECK (latitude BETWEEN -90 AND 90),
    longitude double precision CHECK (longitude >= -180 AND longitude < 180),
    magnitude double precision CHECK (magnitude >= 0 AND magnitude < 'Infinity'::double precision),
    depth_km double precision CHECK (depth_km >= 0 AND depth_km < 'Infinity'::double precision),
    region text,
    latitude_text text,
    longitude_text text,
    potential text,
    felt text,
    shakemap_url text,
    source_url text NOT NULL CHECK (char_length(source_url) BETWEEN 1 AND 2048),
    sender text,
    sent timestamptz,
    status text CHECK (status IN ('Actual', 'Exercise', 'System', 'Test', 'Draft')),
    msg_type text CHECK (msg_type IN ('Alert', 'Update', 'Cancel', 'Ack', 'Error')),
    language text,
    cap_event text,
    event_code text,
    severity text CHECK (severity IN ('Extreme', 'Severe', 'Moderate', 'Minor', 'Unknown')),
    urgency text CHECK (urgency IN ('Immediate', 'Expected', 'Future', 'Past', 'Unknown')),
    certainty text CHECK (certainty IN ('Observed', 'Likely', 'Possible', 'Unlikely', 'Unknown')),
    effective timestamptz,
    expires timestamptz,
    headline text,
    description text,
    web_url text,
    lifecycle_complete boolean NOT NULL DEFAULT true,
    cancelled_at timestamptz,
    superseded_at timestamptz,
    content_version bigint NOT NULL DEFAULT 1 CHECK (content_version > 0),
    content_hash text NOT NULL CHECK (content_hash ~ '^[0-9a-f]{64}$'),
    first_seen_at timestamptz NOT NULL DEFAULT now(),
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    is_simulated boolean NOT NULL DEFAULT false,
    provenance jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(provenance) = 'object'),
    UNIQUE (source, source_key),
    CHECK ((latitude IS NULL) = (longitude IS NULL)),
    CHECK (last_seen_at >= first_seen_at),
    CHECK ((source = 'BMKG_TEWS' AND category = 'earthquake' AND source_key ~ '^[0-9a-f]{64}$'
            AND latitude IS NOT NULL AND status IS NULL AND msg_type IS NULL AND sent IS NULL
            AND sender IS NULL AND effective IS NULL AND expires IS NULL AND severity IS NULL
            AND urgency IS NULL AND certainty IS NULL AND cancelled_at IS NULL AND superseded_at IS NULL)
        OR (source = 'BMKG_NOWCAST' AND category = 'extreme_weather' AND status IS NOT NULL
            AND msg_type IS NOT NULL AND sent IS NOT NULL AND sender IS NOT NULL
            AND effective IS NOT NULL AND occurred_at = sent AND magnitude IS NULL AND depth_km IS NULL
            AND potential IS NULL AND felt IS NULL AND shakemap_url IS NULL)),
    CHECK (source <> 'BMKG_NOWCAST' OR NOT lifecycle_complete OR
           (expires IS NOT NULL AND expires > effective))
);
CREATE INDEX disaster_events_feed_idx ON disaster_events(category, occurred_at DESC, id DESC);
CREATE INDEX disaster_events_time_idx ON disaster_events(occurred_at DESC, id DESC);
CREATE INDEX disaster_events_coordinates_idx ON disaster_events(latitude, longitude) WHERE latitude IS NOT NULL;
CREATE INDEX disaster_events_cap_window_idx ON disaster_events(effective, expires)
    WHERE source = 'BMKG_NOWCAST' AND status = 'Actual' AND cancelled_at IS NULL AND superseded_at IS NULL;

CREATE TABLE event_areas (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL REFERENCES disaster_events(id) ON DELETE RESTRICT,
    position integer NOT NULL CHECK (position > 0),
    area_description text NOT NULL CHECK (char_length(area_description) > 0),
    UNIQUE (event_id, position)
);
CREATE TABLE area_polygons (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    area_id uuid NOT NULL REFERENCES event_areas(id) ON DELETE RESTRICT,
    position integer NOT NULL CHECK (position > 0),
    geometry_valid boolean NOT NULL,
    invalid_reason text,
    centroid_latitude double precision CHECK (centroid_latitude BETWEEN -90 AND 90),
    centroid_longitude double precision CHECK (centroid_longitude >= -180 AND centroid_longitude < 180),
    south double precision CHECK (south BETWEEN -90 AND 90),
    north double precision CHECK (north BETWEEN -90 AND 90),
    west double precision CHECK (west >= -180 AND west < 180),
    east double precision CHECK (east >= -180 AND east < 180),
    crosses_antimeridian boolean,
    UNIQUE (area_id, position),
    CHECK ((geometry_valid AND invalid_reason IS NULL AND centroid_latitude IS NOT NULL
            AND centroid_longitude IS NOT NULL AND south IS NOT NULL AND north IS NOT NULL
            AND west IS NOT NULL AND east IS NOT NULL AND crosses_antimeridian IS NOT NULL
            AND south <= north AND ((NOT crosses_antimeridian AND west <= east) OR (crosses_antimeridian AND west > east)))
        OR (NOT geometry_valid AND invalid_reason IS NOT NULL AND centroid_latitude IS NULL
            AND centroid_longitude IS NULL AND south IS NULL AND north IS NULL
            AND west IS NULL AND east IS NULL AND crosses_antimeridian IS NULL))
);
CREATE INDEX area_polygons_bbox_idx ON area_polygons(south, north) WHERE geometry_valid;
CREATE TABLE polygon_vertices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    polygon_id uuid NOT NULL REFERENCES area_polygons(id) ON DELETE RESTRICT,
    sequence integer NOT NULL CHECK (sequence > 0 AND sequence <= 10001),
    latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude double precision NOT NULL CHECK (longitude >= -180 AND longitude < 180),
    UNIQUE (polygon_id, sequence)
);

CREATE TABLE event_references (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id uuid NOT NULL REFERENCES disaster_events(id) ON DELETE RESTRICT,
    referenced_source_key text NOT NULL CHECK (char_length(referenced_source_key) BETWEEN 1 AND 1024),
    referenced_sender text NOT NULL,
    referenced_sent timestamptz NOT NULL,
    relation_type text NOT NULL CHECK (relation_type IN ('Update', 'Cancel')),
    referenced_event_id uuid REFERENCES disaster_events(id) ON DELETE RESTRICT,
    UNIQUE (event_id, referenced_sender, referenced_source_key, referenced_sent),
    CHECK (referenced_event_id IS NULL OR referenced_event_id <> event_id)
);
CREATE INDEX event_references_target_idx ON event_references(referenced_event_id);
CREATE INDEX event_references_unresolved_idx ON event_references(referenced_source_key) WHERE referenced_event_id IS NULL;

CREATE TABLE citizen_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    event_id uuid REFERENCES disaster_events(id) ON DELETE RESTRICT,
    client_request_id uuid NOT NULL,
    payload_hash text NOT NULL CHECK (payload_hash ~ '^[0-9a-f]{64}$'),
    payload_hash_algo text NOT NULL DEFAULT 'report-payload-v1' CHECK (payload_hash_algo = 'report-payload-v1'),
    category text NOT NULL CHECK (category IN ('earthquake', 'flood', 'eruption', 'extreme_weather', 'haze_other')),
    description text NOT NULL CHECK (description = btrim(description) AND char_length(description) BETWEEN 20 AND 1000),
    latitude double precision NOT NULL CHECK (latitude BETWEEN -90 AND 90),
    longitude double precision NOT NULL CHECK (longitude >= -180 AND longitude < 180),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_review', 'verified', 'rejected')),
    reviewer_id uuid REFERENCES users(id) ON DELETE RESTRICT,
    version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
    claimed_at timestamptz,
    decided_at timestamptz,
    photo_storage_backend text CHECK (photo_storage_backend IN ('local', 'supabase')),
    photo_object_key text UNIQUE,
    photo_sha256 text CHECK (photo_sha256 ~ '^[0-9a-f]{64}$'),
    photo_bytes integer CHECK (photo_bytes BETWEEN 1 AND 2097152),
    photo_width integer CHECK (photo_width BETWEEN 1 AND 1024),
    photo_height integer CHECK (photo_height BETWEEN 1 AND 1024),
    is_simulated boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (reporter_id, client_request_id),
    CHECK (reviewer_id IS NULL OR reviewer_id <> reporter_id),
    CHECK ((status = 'pending' AND reviewer_id IS NULL AND claimed_at IS NULL AND decided_at IS NULL AND version = 1)
        OR (status = 'in_review' AND reviewer_id IS NOT NULL AND claimed_at IS NOT NULL AND decided_at IS NULL AND version = 2)
        OR (status IN ('verified', 'rejected') AND reviewer_id IS NOT NULL AND claimed_at IS NOT NULL AND decided_at IS NOT NULL AND version = 3)),
    CHECK (updated_at >= created_at AND (claimed_at IS NULL OR claimed_at >= created_at)
           AND (decided_at IS NULL OR decided_at >= claimed_at)),
    CHECK (num_nonnulls(photo_storage_backend, photo_object_key, photo_sha256, photo_bytes, photo_width, photo_height) IN (0, 6)),
    CHECK (photo_object_key IS NULL OR photo_object_key ~ '^[0-9a-f-]{36}\.jpg$')
);
CREATE INDEX citizen_reports_moderation_idx ON citizen_reports(status, created_at, id) WHERE status IN ('pending', 'in_review');
CREATE INDEX citizen_reports_mine_idx ON citizen_reports(reporter_id, created_at DESC, id DESC);
CREATE INDEX citizen_reports_event_idx ON citizen_reports(event_id, created_at DESC, id DESC) WHERE status = 'verified';
CREATE INDEX citizen_reports_event_fk_idx ON citizen_reports(event_id);
CREATE INDEX citizen_reports_reviewer_idx ON citizen_reports(reviewer_id);
CREATE INDEX citizen_reports_public_idx ON citizen_reports(created_at DESC, id DESC) WHERE status = 'verified';
CREATE INDEX citizen_reports_coordinates_idx ON citizen_reports(latitude, longitude) WHERE status = 'verified';

CREATE TABLE report_verifications (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id uuid NOT NULL REFERENCES citizen_reports(id) ON DELETE RESTRICT,
    moderator_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    from_status text NOT NULL CHECK (from_status IN ('pending', 'in_review')),
    to_status text NOT NULL CHECK (to_status IN ('in_review', 'verified', 'rejected')),
    reason text NOT NULL CHECK (reason = btrim(reason) AND char_length(reason) BETWEEN 10 AND 500),
    resulting_version bigint NOT NULL CHECK (resulting_version > 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (report_id, resulting_version),
    CHECK ((from_status = 'pending' AND to_status = 'in_review' AND resulting_version = 2)
        OR (from_status = 'in_review' AND to_status IN ('verified', 'rejected') AND resulting_version = 3))
);
CREATE INDEX report_verifications_history_idx ON report_verifications(report_id, created_at, id);
CREATE INDEX report_verifications_moderator_idx ON report_verifications(moderator_id);

CREATE TABLE notification_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    event_id uuid NOT NULL REFERENCES disaster_events(id) ON DELETE RESTRICT,
    kind text NOT NULL DEFAULT 'official_new' CHECK (kind = 'official_new'),
    sequence bigint NOT NULL CHECK (sequence > 0),
    zone_version bigint NOT NULL CHECK (zone_version > 0),
    priority_algo text NOT NULL CHECK (priority_algo IN ('eq-priority-v1', 'cap-priority-v1')),
    priority_score double precision CHECK (priority_score BETWEEN 0 AND 100),
    priority_label text NOT NULL CHECK (priority_label IN ('ordinary', 'attention', 'high', 'information', 'unavailable')),
    priority_reasons jsonb NOT NULL CHECK (jsonb_typeof(priority_reasons) = 'array'),
    priority_components jsonb CHECK (jsonb_typeof(priority_components) = 'object'),
    match_method text NOT NULL CHECK (match_method IN ('point_distance', 'inside_polygon', 'near_polygon_sample')),
    match_distance_km double precision NOT NULL CHECK (match_distance_km >= 0 AND match_distance_km <= 100 + 0.000001),
    evaluated_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    read_at timestamptz,
    is_simulated boolean NOT NULL DEFAULT false,
    UNIQUE (user_id, event_id, kind),
    UNIQUE (user_id, sequence),
    CHECK (read_at IS NULL OR read_at >= created_at),
    CHECK ((priority_algo = 'cap-priority-v1' AND priority_score IS NULL AND priority_components IS NULL
            AND match_method IN ('inside_polygon', 'near_polygon_sample'))
        OR (priority_algo = 'eq-priority-v1' AND match_method = 'point_distance'
            AND ((priority_score IS NULL AND priority_label = 'unavailable' AND priority_components IS NULL)
              OR (priority_score IS NOT NULL AND priority_components IS NOT NULL AND
                ((priority_score < 35 AND priority_label = 'ordinary') OR
                 (priority_score >= 35 AND priority_score < 65 AND priority_label = 'attention') OR
                 (priority_score >= 65 AND priority_label = 'high'))))))
);
CREATE INDEX notification_logs_history_idx ON notification_logs(user_id, created_at DESC, id DESC);
CREATE INDEX notification_logs_unread_idx ON notification_logs(user_id, sequence) WHERE read_at IS NULL;
CREATE INDEX notification_logs_event_idx ON notification_logs(event_id);

CREATE TABLE sync_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    source text NOT NULL CHECK (source IN ('BMKG_TEWS', 'BMKG_NOWCAST')),
    status text NOT NULL CHECK (status IN ('running', 'success', 'partial', 'failed', 'abandoned')),
    lease_token uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
    lease_until timestamptz NOT NULL,
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    last_success_at timestamptz,
    bootstrap_completed boolean NOT NULL DEFAULT false,
    checkpoint jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(checkpoint) = 'object'),
    valid_count integer NOT NULL DEFAULT 0 CHECK (valid_count >= 0),
    invalid_count integer NOT NULL DEFAULT 0 CHECK (invalid_count >= 0),
    changed_count integer NOT NULL DEFAULT 0 CHECK (changed_count >= 0 AND changed_count <= valid_count),
    error_code text,
    error_summary text CHECK (char_length(error_summary) <= 500),
    CHECK (lease_until > started_at),
    CHECK ((status = 'running' AND finished_at IS NULL) OR (status <> 'running' AND finished_at IS NOT NULL AND finished_at >= started_at)),
    CHECK (status <> 'success' OR (last_success_at IS NOT NULL AND bootstrap_completed))
);
CREATE UNIQUE INDEX sync_runs_one_active_source_idx ON sync_runs(source) WHERE status = 'running';
CREATE INDEX sync_runs_latest_idx ON sync_runs(source, started_at DESC, id DESC);
CREATE INDEX sync_runs_lease_idx ON sync_runs(lease_until) WHERE status = 'running';

CREATE TABLE media_cleanup_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    storage_backend text NOT NULL CHECK (storage_backend IN ('local', 'supabase')),
    object_key text NOT NULL UNIQUE CHECK (object_key ~ '^[0-9a-f-]{36}\.jpg$'),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'done', 'cancelled')),
    attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    next_attempt_at timestamptz NOT NULL DEFAULT now(),
    lease_token uuid,
    lease_until timestamptz,
    object_created_at timestamptz NOT NULL,
    last_error text CHECK (char_length(last_error) <= 500),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (updated_at >= created_at),
    CHECK ((status = 'running' AND lease_token IS NOT NULL AND lease_until IS NOT NULL)
        OR (status <> 'running' AND lease_token IS NULL AND lease_until IS NULL))
);
CREATE INDEX media_cleanup_jobs_due_idx ON media_cleanup_jobs(next_attempt_at, id) WHERE status = 'pending';
CREATE INDEX media_cleanup_jobs_lease_idx ON media_cleanup_jobs(lease_until) WHERE status = 'running';

-- In-row CHECK cannot query another table. These triggers protect report state/audit;
-- authentication, actor binding and conditional expected_version remain service duties.
CREATE FUNCTION siaga.guard_report_transition() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, siaga AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF NEW.status <> 'pending' OR NEW.version <> 1 THEN
            RAISE EXCEPTION 'Reports must start pending' USING ERRCODE = '23514';
        END IF;
        RETURN NEW;
    END IF;
    IF (to_jsonb(NEW) - ARRAY['status','reviewer_id','version','claimed_at','decided_at','updated_at'])
       IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['status','reviewer_id','version','claimed_at','decided_at','updated_at']) THEN
        RAISE EXCEPTION 'Submitted report is immutable' USING ERRCODE = '23514';
    END IF;
    IF NOT ((OLD.status = 'pending' AND NEW.status = 'in_review' AND NEW.version = OLD.version + 1)
         OR (OLD.status = 'in_review' AND NEW.status IN ('verified','rejected') AND NEW.version = OLD.version + 1
             AND NEW.reviewer_id = OLD.reviewer_id AND NEW.claimed_at = OLD.claimed_at)) THEN
        RAISE EXCEPTION 'Invalid report transition' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM siaga.users WHERE id = NEW.reviewer_id AND role = 'admin' AND active) THEN
        RAISE EXCEPTION 'Reviewer must be active admin' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER report_transition_guard BEFORE INSERT OR UPDATE ON citizen_reports
    FOR EACH ROW EXECUTE FUNCTION siaga.guard_report_transition();

CREATE FUNCTION siaga.guard_verification() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, siaga AS $$
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'Audit is append-only' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM siaga.citizen_reports r JOIN siaga.users u ON u.id = NEW.moderator_id
        WHERE r.id = NEW.report_id AND r.reviewer_id = NEW.moderator_id AND r.reporter_id <> NEW.moderator_id
          AND r.version = NEW.resulting_version AND r.status = NEW.to_status AND u.role = 'admin' AND u.active) THEN
        RAISE EXCEPTION 'Audit must match report and moderator' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER verification_guard BEFORE INSERT OR UPDATE OR DELETE ON report_verifications
    FOR EACH ROW EXECUTE FUNCTION siaga.guard_verification();
CREATE FUNCTION siaga.require_report_audit() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, siaga AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM siaga.report_verifications
        WHERE report_id = NEW.id AND resulting_version = NEW.version
          AND from_status = OLD.status AND to_status = NEW.status AND moderator_id = NEW.reviewer_id) THEN
        RAISE EXCEPTION 'Report transition requires audit in same transaction' USING ERRCODE = '23514';
    END IF;
    RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER report_requires_audit AFTER UPDATE ON citizen_reports
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION siaga.require_report_audit();

COMMENT ON TABLE users IS 'Backend accounts only; no Supabase Auth client access; admin provisioned by operator.';
COMMENT ON COLUMN users.last_notification_sequence IS 'Increment under user row lock and insert log in same transaction; retain lock to commit. Never use global serial for replay.';
COMMENT ON TABLE alert_zones IS 'One zone/user. Lock users then zones, sorted user UUID, on all writers; changed PUT increments zone_version and resets eligibility cutoff.';
COMMENT ON COLUMN alert_zones.longitude IS 'Earth range, 180 canonicalized to -180; no Indonesia-only CHECK because antimeridian/polar fixtures are required.';
COMMENT ON TABLE disaster_events IS 'Official events only. TEWS SHA256 identity; Nowcast CAP identifier. Areas/references are relational. Event+notification+checkpoint batch commits atomically.';
COMMENT ON COLUMN disaster_events.status IS 'CAP status, NOT report status or computed lifecycle_status; NULL for TEWS.';
COMMENT ON COLUMN disaster_events.lifecycle_complete IS 'Parser validates references and interval. Invalid/missing expiry retained as incomplete, never alert eligible.';
COMMENT ON COLUMN disaster_events.provenance IS 'Supporting source endpoint/RSS/raw unknown enum metadata only. Never public ORM dump.';
COMMENT ON TABLE event_areas IS 'All areas from selected CAP info block; service enforces Nowcast parent.';
COMMENT ON TABLE area_polygons IS 'Normalized closed rings. Service validates topology, supported shape, 3 unique vertices and conservative bbox before geometry_valid=true.';
COMMENT ON TABLE polygon_vertices IS 'Positive contiguous order per ring, closure repeats first vertex. Input total <=10000 vertices/CAP; generated closure may add one per polygon.';
COMMENT ON TABLE event_references IS 'Service resolves CAP sender/identifier/sent, same source and relation_type matching parent msg_type; unresolved references never fabricated.';
COMMENT ON TABLE citizen_reports IS 'report-payload-v1 hash computed server over canonical fields and deterministic sanitized photo digest; same key/same hash replay, mismatch 409.';
COMMENT ON COLUMN citizen_reports.photo_object_key IS 'Private JPEG only; no original filename, EXIF or permanent signed URL. Service checks decode and byte/dimension limits.';
COMMENT ON TABLE report_verifications IS 'Append-only. Conditional report update and audit INSERT in one transaction; deferred trigger rejects missing audit.';
COMMENT ON TABLE notification_logs IS 'Immutable delivery snapshot except read_at (first-read wins). Service validates event kind/algo/mode and current zone eligibility. No automatic pruning MVP.';
COMMENT ON TABLE sync_runs IS 'Partial unique running/source. Claim uses pg_try_advisory_xact_lock per source; abandon expired lease then insert. Fence token+expiry under row lock before batch write.';
COMMENT ON COLUMN sync_runs.checkpoint IS 'Copy latest committed checkpoint/bootstrap/last_success to next run; batch updates with events/logs. Partial does not advance last_success. Bootstrap completed only after full initial source traversal.';
COMMENT ON TABLE media_cleanup_jobs IS 'No FK to report: orphan objects deliberately have no report. Check DB references and active uploads again before deleting; reconciliation only DB-healthy and objects >24h old.';

REVOKE ALL ON ALL TABLES IN SCHEMA siaga FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA siaga FROM PUBLIC;
COMMIT;

-- MIGRATION / RUNTIME CONTRACT (operator implements grants; no role creation here):
-- Runtime role: non-owner, no schema CREATE, no table DELETE/TRUNCATE, no audit UPDATE/DELETE.
-- Grant schema USAGE, table SELECT/INSERT and UPDATE only required columns/tables;
-- notification_logs UPDATE(read_at) only, report_verifications SELECT/INSERT only.
-- No anon/authenticated PostgREST grants. If exposing siaga accidentally, disable exposure
-- before deployment; Flutter business access is JWT -> FastAPI -> restricted SQL role.
-- Tables have no auto updated_at trigger: services supply server time in each transaction.
-- Numeric bounds reject NaN/Infinity via upper/lower comparisons. All times finite UTC
-- ISO8601 at API boundary; database stores timestamptz. Mode/source rules enforced by service.
-- Haversine R=6371.0088 km; inclusive distance <= radius+0.000001. No GIS extension.
-- Geometry update: explicit child deletion (vertices -> polygons -> areas) by a dedicated
-- ingestion role if needed, inside fenced batch; core event/report/user/log/audit not deleted.
-- Dedicated ingestion role may DELETE geometry/reference rows only, never runtime mobile role.
-- SIMULASI SEED IS NOT PART OF THIS DDL. Build a separate guarded backend seed later:
-- APP_MODE=simulation; isolated DB/folder; citizen+2 admins; is_simulated=true on event,
-- report and notification; normal claim/decision pipeline builds audit, no trigger bypass.
-- No fabricated production events, credentials, or photo assets are inserted here.
-- Reference: https://www.postgresql.org/docs/15/functions-uuid.html (core gen_random_uuid)
-- https://www.postgresql.org/docs/15/ddl-constraints.html
-- https://www.postgresql.org/docs/15/sql-createtrigger.html
