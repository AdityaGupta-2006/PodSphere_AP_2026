-- ============================================================================
-- PodSphere CP3: Application SQL Query Workload
-- Target Database: PostgreSQL 11+ (Validated on PostgreSQL 18.6)
--
-- This file provides every SQL query executed by the PodSphere application
-- to interact with the database across all 23 relational tables defined in
-- dbms/03_schema.sql.
--
-- Query Classification:
--   Every query is explicitly tagged with either:
--     -- READ   (SELECT queries for data retrieval and analytics)
--     -- WRITE  (INSERT, UPDATE, DELETE queries for data mutation)
--
-- Parameters:
--   PostgreSQL positional parameter placeholders ($1, $2, $3, ...) are used
--   throughout to ensure safe, prepared, parameterized execution.
-- ============================================================================


-- ============================================================================
-- SECTION 1: AUTHENTICATION & USER ACCOUNT OPERATIONS
-- Entities: users, profiles, user_roles, roles
-- ============================================================================

-- WRITE
-- Register a new user account with lowercase email and default status
INSERT INTO users (email, password_hash, account_status)
VALUES (lower($1), $2, $3)
RETURNING user_id, email, created_at, account_status;

-- READ
-- Authenticate user by canonical lowercase email to retrieve credentials
SELECT
    u.user_id,
    u.email,
    u.password_hash,
    u.account_status,
    u.created_at
FROM users u
WHERE u.email = lower($1);

-- READ
-- Fetch authenticated user account details along with profile and all assigned roles
SELECT
    u.user_id,
    u.email,
    u.account_status,
    u.created_at,
    p.profile_id,
    p.display_name,
    p.bio,
    p.avatar_url,
    p.website_url,
    p.updated_at AS profile_updated_at,
    COALESCE(ARRAY_AGG(r.role_name) FILTER (WHERE r.role_name IS NOT NULL), '{}') AS assigned_roles
FROM users u
LEFT JOIN profiles p ON u.user_id = p.user_id
LEFT JOIN user_roles ur ON u.user_id = ur.user_id
LEFT JOIN roles r ON ur.role_id = r.role_id
WHERE u.user_id = $1
GROUP BY u.user_id, u.email, u.account_status, u.created_at, p.profile_id, p.display_name, p.bio, p.avatar_url, p.website_url, p.updated_at;

-- WRITE
-- Update user account lifecycle status (e.g. pending, active, suspended, closed)
UPDATE users
SET account_status = $2
WHERE user_id = $1
RETURNING user_id, email, account_status;

-- WRITE
-- Update user password hash
UPDATE users
SET password_hash = $2
WHERE user_id = $1;


-- ============================================================================
-- SECTION 2: USER PROFILE OPERATIONS
-- Entities: profiles, users
-- ============================================================================

-- WRITE
-- Create an initial profile for a registered user
INSERT INTO profiles (user_id, display_name, bio, avatar_url, website_url)
VALUES ($1, $2, $3, $4, $5)
RETURNING profile_id, user_id, display_name, updated_at;

-- WRITE
-- Update profile details for a user
UPDATE profiles
SET
    display_name = $2,
    bio = $3,
    avatar_url = $4,
    website_url = $5,
    updated_at = CURRENT_TIMESTAMP
WHERE user_id = $1
RETURNING profile_id, user_id, display_name, bio, avatar_url, website_url, updated_at;

-- READ
-- Fetch public profile by user ID with account status check
SELECT
    p.profile_id,
    p.user_id,
    p.display_name,
    p.bio,
    p.avatar_url,
    p.website_url,
    p.updated_at,
    u.created_at AS member_since
FROM profiles p
JOIN users u ON p.user_id = u.user_id
WHERE p.user_id = $1
  AND u.account_status = 'active';


-- ============================================================================
-- SECTION 3: ROLE MANAGEMENT & AUTHORIZATION OPERATIONS
-- Entities: roles, user_roles, users
-- ============================================================================

-- WRITE
-- Assign a role to a user
INSERT INTO user_roles (user_id, role_id)
VALUES ($1, $2)
ON CONFLICT (user_id, role_id) DO NOTHING
RETURNING user_id, role_id, assigned_at;

-- WRITE
-- Revoke a role from a user
DELETE FROM user_roles
WHERE user_id = $1
  AND role_id = $2;

-- READ
-- List all available system roles
SELECT
    r.role_id,
    r.role_name,
    r.description
FROM roles r
ORDER BY r.role_id ASC;

-- READ
-- Verify if a user holds a specific named role (e.g. 'creator', 'provider', 'instructor')
SELECT EXISTS (
    SELECT 1
    FROM user_roles ur
    JOIN roles r ON ur.role_id = r.role_id
    WHERE ur.user_id = $1
      AND r.role_name = $2
) AS has_role;


-- ============================================================================
-- SECTION 4: PODCAST & EPISODE OPERATIONS
-- Entities: podcasts, episodes, users, profiles
-- ============================================================================

-- WRITE
-- Create a new podcast show
INSERT INTO podcasts (creator_id, title, description, category, language, status)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING podcast_id, creator_id, title, status, created_at;

-- WRITE
-- Update podcast show metadata
UPDATE podcasts
SET
    title = $2,
    description = $3,
    category = $4,
    language = $5,
    status = $6
WHERE podcast_id = $1
  AND creator_id = $7
RETURNING podcast_id, title, category, language, status;

-- WRITE
-- Archive a podcast show
UPDATE podcasts
SET status = 'archived'
WHERE podcast_id = $1
  AND creator_id = $2;

-- READ
-- Fetch podcast details by ID with creator profile and total episode count
SELECT
    p.podcast_id,
    p.creator_id,
    p.title,
    p.description,
    p.category,
    p.language,
    p.status,
    p.created_at,
    pr.display_name AS creator_name,
    pr.avatar_url AS creator_avatar,
    COUNT(e.episode_id) AS total_episodes,
    COUNT(e.episode_id) FILTER (WHERE e.status = 'published') AS published_episodes
FROM podcasts p
JOIN users u ON p.creator_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN episodes e ON p.podcast_id = e.podcast_id
WHERE p.podcast_id = $1
GROUP BY p.podcast_id, p.creator_id, p.title, p.description, p.category, p.language, p.status, p.created_at, pr.display_name, pr.avatar_url;

-- READ
-- List all podcasts owned by a creator with episode statistics
SELECT
    p.podcast_id,
    p.title,
    p.category,
    p.language,
    p.status,
    p.created_at,
    COUNT(e.episode_id) AS total_episodes,
    COUNT(e.episode_id) FILTER (WHERE e.status = 'published') AS published_episodes
FROM podcasts p
LEFT JOIN episodes e ON p.podcast_id = e.podcast_id
WHERE p.creator_id = $1
GROUP BY p.podcast_id, p.title, p.category, p.language, p.status, p.created_at
ORDER BY p.created_at DESC;

-- READ
-- Browse and search active podcasts with category, language filters, and pagination
SELECT
    p.podcast_id,
    p.creator_id,
    p.title,
    p.description,
    p.category,
    p.language,
    p.created_at,
    pr.display_name AS creator_name,
    pr.avatar_url AS creator_avatar,
    COUNT(e.episode_id) FILTER (WHERE e.status = 'published') AS published_episode_count
FROM podcasts p
JOIN users u ON p.creator_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN episodes e ON p.podcast_id = e.podcast_id
WHERE p.status = 'active'
  AND ($1::VARCHAR IS NULL OR p.category = $1)
  AND ($2::VARCHAR IS NULL OR p.language = $2)
  AND ($3::TEXT IS NULL OR p.title ILIKE '%' || $3 || '%')
GROUP BY p.podcast_id, p.creator_id, p.title, p.description, p.category, p.language, p.created_at, pr.display_name, pr.avatar_url
ORDER BY p.created_at DESC
LIMIT $4 OFFSET $5;

-- WRITE
-- Create a new episode in a podcast
INSERT INTO episodes (podcast_id, episode_number, title, description, media_url, duration_seconds, status, published_at)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING episode_id, podcast_id, episode_number, title, status, published_at;

-- WRITE
-- Update episode details and publication timestamp
UPDATE episodes
SET
    title = $2,
    description = $3,
    media_url = $4,
    duration_seconds = $5,
    status = $6,
    published_at = CASE
        WHEN $6 = 'published' AND published_at IS NULL THEN CURRENT_TIMESTAMP
        ELSE published_at
    END
WHERE episode_id = $1
RETURNING episode_id, podcast_id, episode_number, title, status, published_at;

-- WRITE
-- Delete an unpublished draft episode
DELETE FROM episodes
WHERE episode_id = $1
  AND status = 'draft';

-- READ
-- Fetch episode by ID with parent podcast and creator profile details
SELECT
    e.episode_id,
    e.podcast_id,
    e.episode_number,
    e.title AS episode_title,
    e.description AS episode_description,
    e.media_url,
    e.duration_seconds,
    e.status AS episode_status,
    e.published_at,
    p.title AS podcast_title,
    p.category AS podcast_category,
    p.creator_id,
    pr.display_name AS creator_name,
    pr.avatar_url AS creator_avatar
FROM episodes e
JOIN podcasts p ON e.podcast_id = p.podcast_id
JOIN users u ON p.creator_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE e.episode_id = $1;

-- READ
-- List published episodes for a podcast ordered by episode number
SELECT
    e.episode_id,
    e.podcast_id,
    e.episode_number,
    e.title,
    e.description,
    e.media_url,
    e.duration_seconds,
    e.published_at
FROM episodes e
WHERE e.podcast_id = $1
  AND e.status = 'published'
ORDER BY e.episode_number ASC;

-- READ
-- Calculate next available episode number for a podcast
SELECT
    COALESCE(MAX(e.episode_number), 0) + 1 AS next_episode_number
FROM episodes e
WHERE e.podcast_id = $1;


-- ============================================================================
-- SECTION 5: LEARNING, COURSES, LESSONS & PROGRESS OPERATIONS
-- Entities: courses, lessons, enrollments, lesson_progress, users, profiles, reviews
-- ============================================================================

-- WRITE
-- Create a new course listing
INSERT INTO courses (instructor_id, title, description, price, currency, status)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING course_id, instructor_id, title, price, currency, status, created_at;

-- WRITE
-- Update course details
UPDATE courses
SET
    title = $2,
    description = $3,
    price = $4,
    currency = $5,
    status = $6
WHERE course_id = $1
  AND instructor_id = $7
RETURNING course_id, title, price, currency, status;

-- WRITE
-- Delete an unpublished draft course
DELETE FROM courses
WHERE course_id = $1
  AND instructor_id = $2
  AND status = 'draft';

-- READ
-- Browse published courses with instructor details, lesson counts, and aggregate reviews
SELECT
    c.course_id,
    c.instructor_id,
    c.title,
    c.description,
    c.price,
    c.currency,
    c.created_at,
    pr.display_name AS instructor_name,
    pr.avatar_url AS instructor_avatar,
    COUNT(DISTINCT l.lesson_id) AS total_lessons,
    COALESCE(SUM(l.duration_seconds), 0) AS total_duration_seconds,
    COALESCE(ROUND(AVG(r.rating), 2), 0) AS average_rating,
    COUNT(DISTINCT r.review_id) AS review_count
FROM courses c
JOIN users u ON c.instructor_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN lessons l ON c.course_id = l.course_id
LEFT JOIN reviews r ON c.course_id = r.course_id
WHERE c.status = 'published'
  AND ($1::NUMERIC IS NULL OR c.price <= $1)
  AND ($2::TEXT IS NULL OR c.title ILIKE '%' || $2 || '%')
GROUP BY c.course_id, c.instructor_id, c.title, c.description, c.price, c.currency, c.created_at, pr.display_name, pr.avatar_url
ORDER BY c.created_at DESC
LIMIT $3 OFFSET $4;

-- READ
-- Fetch course details by ID with instructor profile and active enrollment count
SELECT
    c.course_id,
    c.instructor_id,
    c.title,
    c.description,
    c.price,
    c.currency,
    c.status,
    c.created_at,
    pr.display_name AS instructor_name,
    pr.bio AS instructor_bio,
    pr.avatar_url AS instructor_avatar,
    COUNT(DISTINCT l.lesson_id) AS total_lessons,
    COUNT(DISTINCT e.enrollment_id) FILTER (WHERE e.status = 'active') AS active_students,
    COALESCE(ROUND(AVG(r.rating), 2), 0) AS average_rating,
    COUNT(DISTINCT r.review_id) AS review_count
FROM courses c
JOIN users u ON c.instructor_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN lessons l ON c.course_id = l.course_id
LEFT JOIN enrollments e ON c.course_id = e.course_id
LEFT JOIN reviews r ON c.course_id = r.course_id
WHERE c.course_id = $1
GROUP BY c.course_id, c.instructor_id, c.title, c.description, c.price, c.currency, c.status, c.created_at, pr.display_name, pr.bio, pr.avatar_url;

-- WRITE
-- Add a lesson to a course
INSERT INTO lessons (course_id, lesson_order, title, content_url, duration_seconds)
VALUES ($1, $2, $3, $4, $5)
RETURNING lesson_id, course_id, lesson_order, title;

-- WRITE
-- Update lesson details and sequence ordering
UPDATE lessons
SET
    title = $2,
    content_url = $3,
    duration_seconds = $4,
    lesson_order = $5
WHERE lesson_id = $1
RETURNING lesson_id, course_id, lesson_order, title, duration_seconds;

-- WRITE
-- Delete a lesson from a course
DELETE FROM lessons
WHERE lesson_id = $1;

-- READ
-- List lessons for a course with authenticated learner's completion status
SELECT
    l.lesson_id,
    l.course_id,
    l.lesson_order,
    l.title,
    l.content_url,
    l.duration_seconds,
    COALESCE(lp.is_completed, FALSE) AS is_completed,
    lp.completed_at
FROM lessons l
LEFT JOIN lesson_progress lp ON l.lesson_id = lp.lesson_id AND lp.user_id = $2
WHERE l.course_id = $1
ORDER BY l.lesson_order ASC;

-- WRITE
-- Enroll a user in a course
INSERT INTO enrollments (user_id, course_id, status)
VALUES ($1, $2, $3)
RETURNING enrollment_id, user_id, course_id, status, enrolled_at;

-- WRITE
-- Update course enrollment lifecycle status (e.g. active, completed, withdrawn)
UPDATE enrollments
SET status = $3
WHERE user_id = $1
  AND course_id = $2
RETURNING enrollment_id, user_id, course_id, status;

-- READ
-- Check learner enrollment status for a specific course
SELECT
    e.enrollment_id,
    e.user_id,
    e.course_id,
    e.status,
    e.enrolled_at
FROM enrollments e
WHERE e.user_id = $1
  AND e.course_id = $2;

-- WRITE
-- Record or update learner lesson completion progress
INSERT INTO lesson_progress (user_id, lesson_id, is_completed, completed_at, updated_at)
VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP)
ON CONFLICT (user_id, lesson_id)
DO UPDATE SET
    is_completed = EXCLUDED.is_completed,
    completed_at = EXCLUDED.completed_at,
    updated_at = CURRENT_TIMESTAMP
RETURNING user_id, lesson_id, is_completed, completed_at, updated_at;

-- READ
-- List all courses a learner is enrolled in along with progress completion percentage
SELECT
    e.enrollment_id,
    e.course_id,
    c.title AS course_title,
    c.price,
    c.currency,
    e.status AS enrollment_status,
    e.enrolled_at,
    pr.display_name AS instructor_name,
    COUNT(DISTINCT l.lesson_id) AS total_lessons,
    COUNT(DISTINCT lp.lesson_id) FILTER (WHERE lp.is_completed = TRUE) AS completed_lessons,
    ROUND(
        COUNT(DISTINCT lp.lesson_id) FILTER (WHERE lp.is_completed = TRUE)::NUMERIC
        / NULLIF(COUNT(DISTINCT l.lesson_id), 0) * 100,
        2
    ) AS progress_percentage
FROM enrollments e
JOIN courses c ON e.course_id = c.course_id
JOIN users u ON c.instructor_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN lessons l ON c.course_id = l.course_id
LEFT JOIN lesson_progress lp ON l.lesson_id = lp.lesson_id AND lp.user_id = e.user_id
WHERE e.user_id = $1
GROUP BY e.enrollment_id, e.course_id, c.title, c.price, c.currency, e.status, e.enrolled_at, pr.display_name
ORDER BY e.enrolled_at DESC;


-- ============================================================================
-- SECTION 6: EQUIPMENT MARKETPLACE & RENTAL OPERATIONS
-- Entities: equipment_categories, equipment, rentals, users, profiles, reviews
-- ============================================================================

-- READ
-- List all equipment categories
SELECT
    ec.category_id,
    ec.category_name,
    ec.description,
    COUNT(eq.equipment_id) AS listing_count
FROM equipment_categories ec
LEFT JOIN equipment eq ON ec.category_id = eq.category_id
GROUP BY ec.category_id, ec.category_name, ec.description
ORDER BY ec.category_name ASC;

-- WRITE
-- Create a new equipment category
INSERT INTO equipment_categories (category_name, description)
VALUES ($1, $2)
RETURNING category_id, category_name, description;

-- WRITE
-- Create a new equipment listing
INSERT INTO equipment (provider_id, category_id, equipment_name, description, daily_rate, currency, quantity, equipment_status)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING equipment_id, provider_id, equipment_name, daily_rate, currency, quantity, equipment_status;

-- WRITE
-- Update equipment listing details
UPDATE equipment
SET
    category_id = $2,
    equipment_name = $3,
    description = $4,
    daily_rate = $5,
    currency = $6,
    quantity = $7,
    equipment_status = $8
WHERE equipment_id = $1
  AND provider_id = $9
RETURNING equipment_id, equipment_name, daily_rate, currency, quantity, equipment_status;

-- WRITE
-- Delete an equipment listing
DELETE FROM equipment
WHERE equipment_id = $1
  AND provider_id = $2;

-- READ
-- Browse available equipment catalog with category, provider details, and review metrics
SELECT
    eq.equipment_id,
    eq.equipment_name,
    eq.description,
    eq.daily_rate,
    eq.currency,
    eq.quantity,
    eq.equipment_status,
    ec.category_name,
    pr.display_name AS provider_name,
    pr.avatar_url AS provider_avatar,
    COALESCE(ROUND(AVG(r.rating), 2), 0) AS average_rating,
    COUNT(DISTINCT r.review_id) AS review_count
FROM equipment eq
JOIN equipment_categories ec ON eq.category_id = ec.category_id
JOIN users u ON eq.provider_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN reviews r ON eq.equipment_id = r.equipment_id
WHERE eq.equipment_status = 'available'
  AND ($1::BIGINT IS NULL OR eq.category_id = $1)
  AND ($2::TEXT IS NULL OR eq.equipment_name ILIKE '%' || $2 || '%')
  AND ($3::NUMERIC IS NULL OR eq.daily_rate <= $3)
GROUP BY eq.equipment_id, eq.equipment_name, eq.description, eq.daily_rate, eq.currency, eq.quantity, eq.equipment_status, ec.category_name, pr.display_name, pr.avatar_url
ORDER BY eq.equipment_id DESC
LIMIT $4 OFFSET $5;

-- READ
-- Fetch single equipment listing by ID with full category and provider profile
SELECT
    eq.equipment_id,
    eq.provider_id,
    eq.category_id,
    eq.equipment_name,
    eq.description,
    eq.daily_rate,
    eq.currency,
    eq.quantity,
    eq.equipment_status,
    ec.category_name,
    ec.description AS category_description,
    pr.display_name AS provider_name,
    pr.bio AS provider_bio,
    pr.avatar_url AS provider_avatar
FROM equipment eq
JOIN equipment_categories ec ON eq.category_id = ec.category_id
JOIN users u ON eq.provider_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE eq.equipment_id = $1;

-- READ
-- Calculate available inventory for an equipment listing across an overlapping date range [start_date, end_date)
SELECT
    eq.equipment_id,
    eq.quantity AS total_units,
    (eq.quantity - COALESCE(MAX(overlapping.peak_reserved), 0)) AS available_units
FROM equipment eq
LEFT JOIN LATERAL (
    SELECT
        b.check_date,
        SUM(existing.quantity) AS peak_reserved
    FROM (
        SELECT $2::DATE AS check_date
        UNION
        SELECT r.start_date
        FROM rentals r
        WHERE r.equipment_id = eq.equipment_id
          AND r.status IN ('confirmed', 'active')
          AND daterange(r.start_date, r.end_date, '[)') && daterange($2::DATE, $3::DATE, '[)')
          AND r.start_date >= $2::DATE
          AND r.start_date < $3::DATE
    ) b
    JOIN rentals existing ON existing.equipment_id = eq.equipment_id
      AND existing.status IN ('confirmed', 'active')
      AND existing.start_date <= b.check_date
      AND existing.end_date > b.check_date
    GROUP BY b.check_date
) overlapping ON TRUE
WHERE eq.equipment_id = $1
GROUP BY eq.equipment_id, eq.quantity;

-- WRITE
-- Submit an equipment rental request
INSERT INTO rentals (equipment_id, renter_id, start_date, end_date, quantity, agreed_rate, currency, status)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING rental_id, equipment_id, renter_id, start_date, end_date, quantity, agreed_rate, currency, status, created_at;

-- WRITE
-- Update rental status (e.g. confirmed, active, completed, cancelled)
UPDATE rentals
SET status = $2
WHERE rental_id = $1
RETURNING rental_id, equipment_id, renter_id, status;

-- READ
-- Fetch rental record by ID with equipment and party details
SELECT
    r.rental_id,
    r.equipment_id,
    r.renter_id,
    r.start_date,
    r.end_date,
    r.quantity,
    r.agreed_rate,
    r.currency,
    r.status AS rental_status,
    r.created_at,
    (r.end_date - r.start_date) AS rental_days,
    ((r.end_date - r.start_date) * r.quantity * r.agreed_rate) AS total_calculated_cost,
    eq.equipment_name,
    eq.provider_id,
    pr_renter.display_name AS renter_name,
    pr_prov.display_name AS provider_name
FROM rentals r
JOIN equipment eq ON r.equipment_id = eq.equipment_id
JOIN users renter ON r.renter_id = renter.user_id
LEFT JOIN profiles pr_renter ON renter.user_id = pr_renter.user_id
JOIN users prov ON eq.provider_id = prov.user_id
LEFT JOIN profiles pr_prov ON prov.user_id = pr_prov.user_id
WHERE r.rental_id = $1;

-- READ
-- List rental history for a renter
SELECT
    r.rental_id,
    r.equipment_id,
    eq.equipment_name,
    r.start_date,
    r.end_date,
    r.quantity,
    r.agreed_rate,
    r.currency,
    r.status AS rental_status,
    r.created_at,
    pr.display_name AS provider_name
FROM rentals r
JOIN equipment eq ON r.equipment_id = eq.equipment_id
JOIN users u ON eq.provider_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE r.renter_id = $1
ORDER BY r.created_at DESC;

-- READ
-- List rental requests received for provider's equipment
SELECT
    r.rental_id,
    r.equipment_id,
    eq.equipment_name,
    r.renter_id,
    pr.display_name AS renter_name,
    r.start_date,
    r.end_date,
    r.quantity,
    r.agreed_rate,
    r.currency,
    r.status AS rental_status,
    r.created_at
FROM rentals r
JOIN equipment eq ON r.equipment_id = eq.equipment_id
JOIN users u ON r.renter_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE eq.provider_id = $1
ORDER BY r.created_at DESC;


-- ============================================================================
-- SECTION 7: STUDIO LISTINGS & BOOKING OPERATIONS
-- Entities: studios, studio_bookings, users, profiles, reviews
-- ============================================================================

-- WRITE
-- Create a new recording studio listing
INSERT INTO studios (provider_id, studio_name, location, capacity, hourly_rate, currency, status)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING studio_id, provider_id, studio_name, hourly_rate, currency, status;

-- WRITE
-- Update studio listing details
UPDATE studios
SET
    studio_name = $2,
    location = $3,
    capacity = $4,
    hourly_rate = $5,
    currency = $6,
    status = $7
WHERE studio_id = $1
  AND provider_id = $8
RETURNING studio_id, studio_name, location, capacity, hourly_rate, currency, status;

-- WRITE
-- Delete a studio listing
DELETE FROM studios
WHERE studio_id = $1
  AND provider_id = $2;

-- READ
-- Browse available studios with provider profile and review rating
SELECT
    s.studio_id,
    s.provider_id,
    s.studio_name,
    s.location,
    s.capacity,
    s.hourly_rate,
    s.currency,
    s.status,
    pr.display_name AS provider_name,
    pr.avatar_url AS provider_avatar,
    COALESCE(ROUND(AVG(r.rating), 2), 0) AS average_rating,
    COUNT(DISTINCT r.review_id) AS review_count
FROM studios s
JOIN users u ON s.provider_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN reviews r ON s.studio_id = r.studio_id
WHERE s.status = 'available'
  AND ($1::INTEGER IS NULL OR s.capacity >= $1)
  AND ($2::NUMERIC IS NULL OR s.hourly_rate <= $2)
  AND ($3::TEXT IS NULL OR s.location ILIKE '%' || $3 || '%')
GROUP BY s.studio_id, s.provider_id, s.studio_name, s.location, s.capacity, s.hourly_rate, s.currency, s.status, pr.display_name, pr.avatar_url
ORDER BY s.studio_id DESC
LIMIT $4 OFFSET $5;

-- READ
-- Fetch studio listing by ID with full provider profile
SELECT
    s.studio_id,
    s.provider_id,
    s.studio_name,
    s.location,
    s.capacity,
    s.hourly_rate,
    s.currency,
    s.status,
    pr.display_name AS provider_name,
    pr.bio AS provider_bio,
    pr.avatar_url AS provider_avatar
FROM studios s
JOIN users u ON s.provider_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE s.studio_id = $1;

-- READ
-- Check studio slot availability for overlapping confirmed bookings [start_time, end_time)
SELECT
    sb.booking_id,
    sb.studio_id,
    sb.start_time,
    sb.end_time,
    sb.status
FROM studio_bookings sb
WHERE sb.studio_id = $1
  AND sb.status = 'confirmed'
  AND tstzrange(sb.start_time, sb.end_time, '[)') && tstzrange($2::TIMESTAMPTZ, $3::TIMESTAMPTZ, '[)');

-- WRITE
-- Submit a studio booking request
INSERT INTO studio_bookings (studio_id, customer_id, start_time, end_time, agreed_rate, currency, status)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING booking_id, studio_id, customer_id, start_time, end_time, agreed_rate, currency, status, created_at;

-- WRITE
-- Update studio booking status (e.g. confirmed, completed, cancelled)
UPDATE studio_bookings
SET status = $2
WHERE booking_id = $1
RETURNING booking_id, studio_id, customer_id, status;

-- READ
-- Fetch studio booking by ID with studio and customer/provider details
SELECT
    sb.booking_id,
    sb.studio_id,
    sb.customer_id,
    sb.start_time,
    sb.end_time,
    sb.agreed_rate,
    sb.currency,
    sb.status AS booking_status,
    sb.created_at,
    ROUND(EXTRACT(EPOCH FROM (sb.end_time - sb.start_time)) / 3600.0, 2) AS booked_hours,
    ROUND((EXTRACT(EPOCH FROM (sb.end_time - sb.start_time)) / 3600.0 * sb.agreed_rate)::NUMERIC, 2) AS total_agreed_amount,
    s.studio_name,
    s.location,
    s.provider_id,
    pr_cust.display_name AS customer_name,
    pr_prov.display_name AS provider_name
FROM studio_bookings sb
JOIN studios s ON sb.studio_id = s.studio_id
JOIN users cust ON sb.customer_id = cust.user_id
LEFT JOIN profiles pr_cust ON cust.user_id = pr_cust.user_id
JOIN users prov ON s.provider_id = prov.user_id
LEFT JOIN profiles pr_prov ON prov.user_id = pr_prov.user_id
WHERE sb.booking_id = $1;

-- READ
-- List booking history for a customer
SELECT
    sb.booking_id,
    sb.studio_id,
    s.studio_name,
    s.location,
    sb.start_time,
    sb.end_time,
    sb.agreed_rate,
    sb.currency,
    sb.status AS booking_status,
    sb.created_at,
    pr.display_name AS provider_name
FROM studio_bookings sb
JOIN studios s ON sb.studio_id = s.studio_id
JOIN users u ON s.provider_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE sb.customer_id = $1
ORDER BY sb.start_time DESC;

-- READ
-- List studio bookings received by provider
SELECT
    sb.booking_id,
    sb.studio_id,
    s.studio_name,
    sb.customer_id,
    pr.display_name AS customer_name,
    sb.start_time,
    sb.end_time,
    sb.agreed_rate,
    sb.currency,
    sb.status AS booking_status,
    sb.created_at
FROM studio_bookings sb
JOIN studios s ON sb.studio_id = s.studio_id
JOIN users u ON sb.customer_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE s.provider_id = $1
ORDER BY sb.start_time DESC;


-- ============================================================================
-- SECTION 8: CREATOR SERVICES & SERVICE ORDER OPERATIONS
-- Entities: services, service_orders, users, profiles, reviews
-- ============================================================================

-- WRITE
-- Create a new creator service offering (e.g. podcast editing, cover art)
INSERT INTO services (provider_id, service_name, description, price, currency, status)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING service_id, provider_id, service_name, price, currency, status;

-- WRITE
-- Update service offering details
UPDATE services
SET
    service_name = $2,
    description = $3,
    price = $4,
    currency = $5,
    status = $6
WHERE service_id = $1
  AND provider_id = $7
RETURNING service_id, service_name, price, currency, status;

-- WRITE
-- Delete a service offering
DELETE FROM services
WHERE service_id = $1
  AND provider_id = $2;

-- READ
-- Browse active creator services with provider details and reviews
SELECT
    s.service_id,
    s.provider_id,
    s.service_name,
    s.description,
    s.price,
    s.currency,
    s.status,
    pr.display_name AS provider_name,
    pr.avatar_url AS provider_avatar,
    COALESCE(ROUND(AVG(r.rating), 2), 0) AS average_rating,
    COUNT(DISTINCT r.review_id) AS review_count
FROM services s
JOIN users u ON s.provider_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN reviews r ON s.service_id = r.service_id
WHERE s.status = 'active'
  AND ($1::NUMERIC IS NULL OR s.price <= $1)
  AND ($2::TEXT IS NULL OR s.service_name ILIKE '%' || $2 || '%')
GROUP BY s.service_id, s.provider_id, s.service_name, s.description, s.price, s.currency, s.status, pr.display_name, pr.avatar_url
ORDER BY s.service_id DESC
LIMIT $3 OFFSET $4;

-- READ
-- Fetch service listing by ID with full provider profile
SELECT
    s.service_id,
    s.provider_id,
    s.service_name,
    s.description,
    s.price,
    s.currency,
    s.status,
    pr.display_name AS provider_name,
    pr.bio AS provider_bio,
    pr.avatar_url AS provider_avatar
FROM services s
JOIN users u ON s.provider_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE s.service_id = $1;

-- WRITE
-- Submit a creator service order
INSERT INTO service_orders (service_id, customer_id, agreed_price, currency, requirements, scheduled_at, status)
VALUES ($1, $2, $3, $4, $5, $6, $7)
RETURNING service_order_id, service_id, customer_id, agreed_price, currency, status, created_at;

-- WRITE
-- Update service order status, schedule, and completion timestamp
UPDATE service_orders
SET
    status = $2,
    scheduled_at = COALESCE($3, scheduled_at),
    completed_at = CASE
        WHEN $2 = 'completed' AND completed_at IS NULL THEN CURRENT_TIMESTAMP
        ELSE completed_at
    END
WHERE service_order_id = $1
RETURNING service_order_id, service_id, status, scheduled_at, completed_at;

-- READ
-- Fetch service order by ID with service and customer/provider details
SELECT
    so.service_order_id,
    so.service_id,
    so.customer_id,
    so.agreed_price,
    so.currency,
    so.requirements,
    so.scheduled_at,
    so.status AS order_status,
    so.created_at,
    so.completed_at,
    s.service_name,
    s.provider_id,
    pr_cust.display_name AS customer_name,
    pr_prov.display_name AS provider_name
FROM service_orders so
JOIN services s ON so.service_id = s.service_id
JOIN users cust ON so.customer_id = cust.user_id
LEFT JOIN profiles pr_cust ON cust.user_id = pr_cust.user_id
JOIN users prov ON s.provider_id = prov.user_id
LEFT JOIN profiles pr_prov ON prov.user_id = pr_prov.user_id
WHERE so.service_order_id = $1;

-- READ
-- List service orders placed by customer
SELECT
    so.service_order_id,
    so.service_id,
    s.service_name,
    so.agreed_price,
    so.currency,
    so.status AS order_status,
    so.scheduled_at,
    so.created_at,
    so.completed_at,
    pr.display_name AS provider_name
FROM service_orders so
JOIN services s ON so.service_id = s.service_id
JOIN users u ON s.provider_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE so.customer_id = $1
ORDER BY so.created_at DESC;

-- READ
-- List service orders received by provider
SELECT
    so.service_order_id,
    so.service_id,
    s.service_name,
    so.customer_id,
    pr.display_name AS customer_name,
    so.agreed_price,
    so.currency,
    so.requirements,
    so.scheduled_at,
    so.status AS order_status,
    so.created_at,
    so.completed_at
FROM service_orders so
JOIN services s ON so.service_id = s.service_id
JOIN users u ON so.customer_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE s.provider_id = $1
ORDER BY so.created_at DESC;


-- ============================================================================
-- SECTION 9: FINANCE OPERATIONS (PAYMENTS, TRANSACTIONS & PAYOUTS)
-- Entities: payments, transactions, payouts, users, profiles
-- ============================================================================

-- WRITE
-- Create a new payment record
INSERT INTO payments (payer_id, amount, currency, payment_method, payment_status, payment_reference)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING payment_id, payer_id, amount, currency, payment_method, payment_status, created_at;

-- WRITE
-- Update payment status, external gateway reference, and settlement timestamp
UPDATE payments
SET
    payment_status = $2,
    payment_reference = COALESCE($3, payment_reference),
    paid_at = CASE
        WHEN $2 = 'paid' AND paid_at IS NULL THEN CURRENT_TIMESTAMP
        ELSE paid_at
    END
WHERE payment_id = $1
RETURNING payment_id, payment_status, payment_reference, paid_at;

-- WRITE
-- Record a financial transaction event associated with a payment
INSERT INTO transactions (payment_id, transaction_type, amount, transaction_status, provider_reference)
VALUES ($1, $2, $3, $4, $5)
RETURNING transaction_id, payment_id, transaction_type, amount, transaction_status, created_at;

-- WRITE
-- Update transaction event status and provider reference
UPDATE transactions
SET
    transaction_status = $2,
    provider_reference = COALESCE($3, provider_reference)
WHERE transaction_id = $1
RETURNING transaction_id, transaction_status, provider_reference;

-- READ
-- Fetch payment by ID with payer information and associated transaction events
SELECT
    p.payment_id,
    p.payer_id,
    p.amount AS payment_amount,
    p.currency,
    p.payment_method,
    p.payment_status,
    p.payment_reference,
    p.created_at AS payment_created_at,
    p.paid_at,
    t.transaction_id,
    t.transaction_type,
    t.amount AS transaction_amount,
    t.transaction_status,
    t.provider_reference AS tx_provider_reference,
    t.created_at AS transaction_created_at
FROM payments p
LEFT JOIN transactions t ON p.payment_id = t.payment_id
WHERE p.payment_id = $1
ORDER BY t.created_at ASC;

-- READ
-- List payment history for a customer
SELECT
    p.payment_id,
    p.amount,
    p.currency,
    p.payment_method,
    p.payment_status,
    p.payment_reference,
    p.created_at,
    p.paid_at
FROM payments p
WHERE p.payer_id = $1
ORDER BY p.created_at DESC;

-- WRITE
-- Initiate a provider payout record
INSERT INTO payouts (provider_id, amount, currency, status, payout_reference)
VALUES ($1, $2, $3, $4, $5)
RETURNING payout_id, provider_id, amount, currency, status, created_at;

-- WRITE
-- Update payout status, transfer reference, and paid timestamp
UPDATE payouts
SET
    status = $2,
    payout_reference = COALESCE($3, payout_reference),
    paid_at = CASE
        WHEN $2 = 'paid' AND paid_at IS NULL THEN CURRENT_TIMESTAMP
        ELSE paid_at
    END
WHERE payout_id = $1
RETURNING payout_id, provider_id, amount, status, payout_reference, paid_at;

-- READ
-- List payouts for a provider
SELECT
    po.payout_id,
    po.provider_id,
    po.amount,
    po.currency,
    po.status AS payout_status,
    po.payout_reference,
    po.created_at,
    po.paid_at
FROM payouts po
WHERE po.provider_id = $1
ORDER BY po.created_at DESC;

-- READ
-- Calculate provider payout summary: total paid out vs currently processing/pending
SELECT
    po.provider_id,
    po.currency,
    COALESCE(SUM(po.amount) FILTER (WHERE po.status = 'paid'), 0) AS total_paid_out,
    COALESCE(SUM(po.amount) FILTER (WHERE po.status IN ('pending', 'processing')), 0) AS total_pending_payouts,
    COUNT(po.payout_id) AS total_payout_requests
FROM payouts po
WHERE po.provider_id = $1
GROUP BY po.provider_id, po.currency;


-- ============================================================================
-- SECTION 10: REVIEW & FEEDBACK OPERATIONS
-- Entities: reviews, users, profiles, equipment, studios, services, courses
-- ============================================================================

-- WRITE
-- Submit a review for exactly one target entity (user, equipment, studio, service, or course)
INSERT INTO reviews (
    reviewer_id,
    reviewed_user_id,
    equipment_id,
    studio_id,
    service_id,
    course_id,
    rating,
    review_text
)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
RETURNING review_id, reviewer_id, rating, created_at;

-- WRITE
-- Update an existing review rating and commentary
UPDATE reviews
SET
    rating = $2,
    review_text = $3
WHERE review_id = $1
  AND reviewer_id = $4
RETURNING review_id, rating, review_text;

-- WRITE
-- Delete a review
DELETE FROM reviews
WHERE review_id = $1
  AND reviewer_id = $2;

-- READ
-- Fetch reviews for a reviewed user target with reviewer profile
SELECT
    r.review_id,
    r.reviewer_id,
    r.rating,
    r.review_text,
    r.created_at,
    pr.display_name AS reviewer_name,
    pr.avatar_url AS reviewer_avatar
FROM reviews r
JOIN users u ON r.reviewer_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE r.reviewed_user_id = $1
ORDER BY r.created_at DESC;

-- READ
-- Fetch reviews for an equipment target with reviewer profile
SELECT
    r.review_id,
    r.reviewer_id,
    r.rating,
    r.review_text,
    r.created_at,
    pr.display_name AS reviewer_name,
    pr.avatar_url AS reviewer_avatar
FROM reviews r
JOIN users u ON r.reviewer_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE r.equipment_id = $1
ORDER BY r.created_at DESC;

-- READ
-- Fetch reviews for a studio target with reviewer profile
SELECT
    r.review_id,
    r.reviewer_id,
    r.rating,
    r.review_text,
    r.created_at,
    pr.display_name AS reviewer_name,
    pr.avatar_url AS reviewer_avatar
FROM reviews r
JOIN users u ON r.reviewer_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE r.studio_id = $1
ORDER BY r.created_at DESC;

-- READ
-- Fetch reviews for a creator service target with reviewer profile
SELECT
    r.review_id,
    r.reviewer_id,
    r.rating,
    r.review_text,
    r.created_at,
    pr.display_name AS reviewer_name,
    pr.avatar_url AS reviewer_avatar
FROM reviews r
JOIN users u ON r.reviewer_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE r.service_id = $1
ORDER BY r.created_at DESC;

-- READ
-- Fetch reviews for a course target with reviewer profile
SELECT
    r.review_id,
    r.reviewer_id,
    r.rating,
    r.review_text,
    r.created_at,
    pr.display_name AS reviewer_name,
    pr.avatar_url AS reviewer_avatar
FROM reviews r
JOIN users u ON r.reviewer_id = u.user_id
LEFT JOIN profiles pr ON u.user_id = pr.user_id
WHERE r.course_id = $1
ORDER BY r.created_at DESC;

-- READ
-- Calculate aggregate rating score and star distribution breakdown for an entity
SELECT
    COUNT(*) AS total_reviews,
    ROUND(AVG(r.rating), 2) AS average_rating,
    COUNT(*) FILTER (WHERE r.rating = 5) AS five_star_count,
    COUNT(*) FILTER (WHERE r.rating = 4) AS four_star_count,
    COUNT(*) FILTER (WHERE r.rating = 3) AS three_star_count,
    COUNT(*) FILTER (WHERE r.rating = 2) AS two_star_count,
    COUNT(*) FILTER (WHERE r.rating = 1) AS one_star_count
FROM reviews r
WHERE (r.reviewed_user_id = $1 AND $2 = 'user')
   OR (r.equipment_id = $1 AND $2 = 'equipment')
   OR (r.studio_id = $1 AND $2 = 'studio')
   OR (r.service_id = $1 AND $2 = 'service')
   OR (r.course_id = $1 AND $2 = 'course');


-- ============================================================================
-- SECTION 11: CREATOR PLANNING & TASK MANAGEMENT OPERATIONS
-- Entities: creator_plans, plan_tasks, users
-- ============================================================================

-- WRITE
-- Create a new creator production plan
INSERT INTO creator_plans (creator_id, plan_title, podcast_idea, target_launch_date, plan_status)
VALUES ($1, $2, $3, $4, $5)
RETURNING plan_id, creator_id, plan_title, plan_status, created_at;

-- WRITE
-- Update creator plan details
UPDATE creator_plans
SET
    plan_title = $2,
    podcast_idea = $3,
    target_launch_date = $4,
    plan_status = $5,
    updated_at = CURRENT_TIMESTAMP
WHERE plan_id = $1
  AND creator_id = $6
RETURNING plan_id, plan_title, plan_status, target_launch_date, updated_at;

-- WRITE
-- Delete a creator plan
DELETE FROM creator_plans
WHERE plan_id = $1
  AND creator_id = $2;

-- READ
-- Fetch creator plan by ID with ordered tasks
SELECT
    cp.plan_id,
    cp.creator_id,
    cp.plan_title,
    cp.podcast_idea,
    cp.target_launch_date,
    cp.plan_status,
    cp.created_at,
    cp.updated_at,
    pt.task_id,
    pt.task_title,
    pt.task_category,
    pt.due_date,
    pt.task_status,
    pt.task_order
FROM creator_plans cp
LEFT JOIN plan_tasks pt ON cp.plan_id = pt.plan_id
WHERE cp.plan_id = $1
ORDER BY pt.task_order ASC;

-- READ
-- List all creator plans with task completion metrics
SELECT
    cp.plan_id,
    cp.creator_id,
    cp.plan_title,
    cp.target_launch_date,
    cp.plan_status,
    cp.created_at,
    COUNT(pt.task_id) AS total_tasks,
    COUNT(pt.task_id) FILTER (WHERE pt.task_status = 'completed') AS completed_tasks,
    COUNT(pt.task_id) FILTER (WHERE pt.task_status = 'in_progress') AS in_progress_tasks
FROM creator_plans cp
LEFT JOIN plan_tasks pt ON cp.plan_id = pt.plan_id
WHERE cp.creator_id = $1
GROUP BY cp.plan_id, cp.creator_id, cp.plan_title, cp.target_launch_date, cp.plan_status, cp.created_at
ORDER BY cp.created_at DESC;

-- WRITE
-- Add a task to a creator plan
INSERT INTO plan_tasks (plan_id, task_title, task_category, due_date, task_status, task_order)
VALUES ($1, $2, $3, $4, $5, $6)
RETURNING task_id, plan_id, task_title, task_status, task_order;

-- WRITE
-- Update task details, status, and sequence ordering
UPDATE plan_tasks
SET
    task_title = $2,
    task_category = $3,
    due_date = $4,
    task_status = $5,
    task_order = $6
WHERE task_id = $1
RETURNING task_id, plan_id, task_title, task_status, task_order;

-- WRITE
-- Delete a task from a plan
DELETE FROM plan_tasks
WHERE task_id = $1;

-- READ
-- Calculate next task sequence order for a creator plan
SELECT
    COALESCE(MAX(pt.task_order), 0) + 1 AS next_task_order
FROM plan_tasks pt
WHERE pt.plan_id = $1;


-- ============================================================================
-- SECTION 12: BUSINESS INTELLIGENCE, ANALYTICS & DASHBOARD REPORTING
-- Complex multi-table reporting queries across PodSphere domains
-- ============================================================================

-- READ
-- Creator 360 overview dashboard: podcasts, episodes, courses, enrolled students, and planning status
SELECT
    u.user_id,
    pr.display_name AS creator_name,
    COUNT(DISTINCT p.podcast_id) AS total_podcasts,
    COUNT(DISTINCT e.episode_id) AS total_episodes,
    COUNT(DISTINCT e.episode_id) FILTER (WHERE e.status = 'published') AS published_episodes,
    COUNT(DISTINCT c.course_id) AS total_courses_created,
    COUNT(DISTINCT enr.enrollment_id) AS total_students_enrolled,
    COUNT(DISTINCT cp.plan_id) AS total_production_plans,
    COUNT(DISTINCT pt.task_id) FILTER (WHERE pt.task_status = 'completed') AS completed_planning_tasks
FROM users u
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN podcasts p ON u.user_id = p.creator_id
LEFT JOIN episodes e ON p.podcast_id = e.podcast_id
LEFT JOIN courses c ON u.user_id = c.instructor_id
LEFT JOIN enrollments enr ON c.course_id = enr.course_id
LEFT JOIN creator_plans cp ON u.user_id = cp.creator_id
LEFT JOIN plan_tasks pt ON cp.plan_id = pt.plan_id
WHERE u.user_id = $1
GROUP BY u.user_id, pr.display_name;

-- READ
-- Marketplace provider revenue summary across equipment rentals, studio bookings, and creator services
SELECT
    u.user_id AS provider_id,
    pr.display_name AS provider_name,
    COALESCE(rentals_summary.rental_revenue, 0) AS total_rental_revenue,
    COALESCE(rentals_summary.rental_orders, 0) AS total_rental_orders,
    COALESCE(studio_summary.studio_revenue, 0) AS total_studio_revenue,
    COALESCE(studio_summary.studio_bookings_count, 0) AS total_studio_bookings,
    COALESCE(services_summary.service_revenue, 0) AS total_service_revenue,
    COALESCE(services_summary.service_orders_count, 0) AS total_service_orders,
    (
        COALESCE(rentals_summary.rental_revenue, 0) +
        COALESCE(studio_summary.studio_revenue, 0) +
        COALESCE(services_summary.service_revenue, 0)
    ) AS gross_marketplace_revenue
FROM users u
LEFT JOIN profiles pr ON u.user_id = pr.user_id
LEFT JOIN (
    SELECT
        eq.provider_id,
        SUM((r.end_date - r.start_date) * r.quantity * r.agreed_rate) AS rental_revenue,
        COUNT(r.rental_id) AS rental_orders
    FROM equipment eq
    JOIN rentals r ON eq.equipment_id = r.equipment_id
    WHERE r.status IN ('confirmed', 'active', 'completed')
    GROUP BY eq.provider_id
) rentals_summary ON u.user_id = rentals_summary.provider_id
LEFT JOIN (
    SELECT
        s.provider_id,
        SUM(ROUND((EXTRACT(EPOCH FROM (sb.end_time - sb.start_time)) / 3600.0 * sb.agreed_rate)::NUMERIC, 2)) AS studio_revenue,
        COUNT(sb.booking_id) AS studio_bookings_count
    FROM studios s
    JOIN studio_bookings sb ON s.studio_id = sb.studio_id
    WHERE sb.status IN ('confirmed', 'completed')
    GROUP BY s.provider_id
) studio_summary ON u.user_id = studio_summary.provider_id
LEFT JOIN (
    SELECT
        srv.provider_id,
        SUM(so.agreed_price) AS service_revenue,
        COUNT(so.service_order_id) AS service_orders_count
    FROM services srv
    JOIN service_orders so ON srv.service_id = so.service_id
    WHERE so.status IN ('accepted', 'in_progress', 'completed')
    GROUP BY srv.provider_id
) services_summary ON u.user_id = services_summary.provider_id
WHERE u.user_id = $1;

-- READ
-- Course curriculum funnel and learner completion rate by lesson
SELECT
    c.course_id,
    c.title AS course_title,
    l.lesson_id,
    l.lesson_order,
    l.title AS lesson_title,
    COUNT(DISTINCT e.user_id) AS total_enrolled_learners,
    COUNT(DISTINCT lp.user_id) FILTER (WHERE lp.is_completed = TRUE) AS completed_learners,
    ROUND(
        COUNT(DISTINCT lp.user_id) FILTER (WHERE lp.is_completed = TRUE)::NUMERIC
        / NULLIF(COUNT(DISTINCT e.user_id), 0) * 100,
        2
    ) AS lesson_completion_rate
FROM courses c
JOIN lessons l ON c.course_id = l.course_id
LEFT JOIN enrollments e ON c.course_id = e.course_id AND e.status = 'active'
LEFT JOIN lesson_progress lp ON l.lesson_id = lp.lesson_id AND lp.user_id = e.user_id
WHERE c.course_id = $1
GROUP BY c.course_id, c.title, l.lesson_id, l.lesson_order, l.title
ORDER BY l.lesson_order ASC;

-- READ
-- Studio booking utilization and revenue metrics
SELECT
    s.studio_id,
    s.studio_name,
    s.location,
    s.hourly_rate,
    s.currency,
    s.status AS studio_status,
    COUNT(sb.booking_id) AS total_bookings,
    COUNT(sb.booking_id) FILTER (WHERE sb.status = 'confirmed') AS confirmed_bookings,
    COUNT(sb.booking_id) FILTER (WHERE sb.status = 'completed') AS completed_bookings,
    COALESCE(
        SUM(EXTRACT(EPOCH FROM (sb.end_time - sb.start_time)) / 3600.0)
        FILTER (WHERE sb.status IN ('confirmed', 'completed')),
        0
    ) AS total_booked_hours,
    COALESCE(
        SUM(ROUND((EXTRACT(EPOCH FROM (sb.end_time - sb.start_time)) / 3600.0 * sb.agreed_rate)::NUMERIC, 2))
        FILTER (WHERE sb.status IN ('confirmed', 'completed')),
        0
    ) AS total_earned_revenue
FROM studios s
LEFT JOIN studio_bookings sb ON s.studio_id = sb.studio_id
WHERE s.provider_id = $1
GROUP BY s.studio_id, s.studio_name, s.location, s.hourly_rate, s.currency, s.status
ORDER BY total_earned_revenue DESC;

-- READ
-- Equipment fleet utilization and rental activity report
SELECT
    eq.equipment_id,
    eq.equipment_name,
    ec.category_name,
    eq.quantity AS inventory_units,
    eq.daily_rate,
    eq.currency,
    eq.equipment_status,
    COUNT(r.rental_id) AS total_rentals,
    COUNT(r.rental_id) FILTER (WHERE r.status IN ('confirmed', 'active')) AS active_or_confirmed_rentals,
    COALESCE(
        SUM((r.end_date - r.start_date) * r.quantity)
        FILTER (WHERE r.status IN ('confirmed', 'active', 'completed')),
        0
    ) AS total_unit_days_rented,
    COALESCE(
        SUM((r.end_date - r.start_date) * r.quantity * r.agreed_rate)
        FILTER (WHERE r.status IN ('confirmed', 'active', 'completed')),
        0
    ) AS total_rental_revenue
FROM equipment eq
JOIN equipment_categories ec ON eq.category_id = ec.category_id
LEFT JOIN rentals r ON eq.equipment_id = r.equipment_id
WHERE eq.provider_id = $1
GROUP BY eq.equipment_id, eq.equipment_name, ec.category_name, eq.quantity, eq.daily_rate, eq.currency, eq.equipment_status
ORDER BY total_rental_revenue DESC;
