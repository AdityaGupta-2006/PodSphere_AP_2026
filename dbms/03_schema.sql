-- PodSphere CP2 PostgreSQL schema.
-- Relation names are lowercase snake_case mappings of the CP1 logical names.
-- Requires PostgreSQL 11+ for identity columns and
-- CREATE TRIGGER ... EXECUTE FUNCTION syntax.

BEGIN;

CREATE TABLE users (
    user_id BIGINT GENERATED ALWAYS AS IDENTITY,
    email VARCHAR(320) NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    account_status VARCHAR(20) NOT NULL,
    CONSTRAINT pk_users PRIMARY KEY (user_id),
    CONSTRAINT uq_users_email UNIQUE (email),
    CONSTRAINT ck_users_email_lower CHECK (email = lower(email)),
    CONSTRAINT ck_users_account_status
        CHECK (account_status IN ('pending', 'active', 'suspended', 'closed'))
);

CREATE TABLE roles (
    role_id BIGINT GENERATED ALWAYS AS IDENTITY,
    role_name VARCHAR(40) NOT NULL,
    description TEXT,
    CONSTRAINT pk_roles PRIMARY KEY (role_id),
    CONSTRAINT uq_roles_role_name UNIQUE (role_name)
);

CREATE TABLE user_roles (
    user_id BIGINT NOT NULL,
    role_id BIGINT NOT NULL,
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_user_roles PRIMARY KEY (user_id, role_id),
    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id)
        REFERENCES roles (role_id) ON DELETE RESTRICT
);

    -- Provider, creator, instructor, and administrator membership is represented
    -- only by user_roles. Cross-table role checks are an application/trigger rule.

CREATE TABLE profiles (
    profile_id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id BIGINT NOT NULL,
    display_name VARCHAR(120) NOT NULL,
    bio TEXT,
    avatar_url TEXT,
    website_url TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_profiles PRIMARY KEY (profile_id),
    CONSTRAINT uq_profiles_user_id UNIQUE (user_id),
    CONSTRAINT fk_profiles_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE RESTRICT
);

CREATE TABLE equipment_categories (
    category_id BIGINT GENERATED ALWAYS AS IDENTITY,
    category_name VARCHAR(100) NOT NULL,
    description TEXT,
    CONSTRAINT pk_equipment_categories PRIMARY KEY (category_id),
    CONSTRAINT uq_equipment_categories_name UNIQUE (category_name)
);

CREATE TABLE podcasts (
    podcast_id BIGINT GENERATED ALWAYS AS IDENTITY,
    creator_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    category VARCHAR(100),
    language VARCHAR(35),
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_podcasts PRIMARY KEY (podcast_id),
    CONSTRAINT fk_podcasts_creator FOREIGN KEY (creator_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_podcasts_status
        CHECK (status IN ('draft', 'active', 'archived'))
);

CREATE TABLE episodes (
    episode_id BIGINT GENERATED ALWAYS AS IDENTITY,
    podcast_id BIGINT NOT NULL,
    episode_number INTEGER NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    media_url TEXT,
    duration_seconds INTEGER,
    status VARCHAR(20) NOT NULL,
    published_at TIMESTAMPTZ,
    CONSTRAINT pk_episodes PRIMARY KEY (episode_id),
    CONSTRAINT uq_episodes_podcast_number UNIQUE (podcast_id, episode_number),
    CONSTRAINT fk_episodes_podcast FOREIGN KEY (podcast_id)
        REFERENCES podcasts (podcast_id) ON DELETE RESTRICT,
    CONSTRAINT ck_episodes_number_positive CHECK (episode_number > 0),
    CONSTRAINT ck_episodes_duration_nonnegative
        CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
    CONSTRAINT ck_episodes_status
        CHECK (status IN ('draft', 'scheduled', 'published'))
);

CREATE TABLE courses (
    course_id BIGINT GENERATED ALWAYS AS IDENTITY,
    instructor_id BIGINT NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    price NUMERIC(12,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_courses PRIMARY KEY (course_id),
    CONSTRAINT fk_courses_instructor FOREIGN KEY (instructor_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_courses_price_nonnegative CHECK (price >= 0),
    CONSTRAINT ck_courses_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_courses_status CHECK (status IN ('draft', 'published'))
);

CREATE TABLE lessons (
    lesson_id BIGINT GENERATED ALWAYS AS IDENTITY,
    course_id BIGINT NOT NULL,
    lesson_order INTEGER NOT NULL,
    title VARCHAR(200) NOT NULL,
    content_url TEXT,
    duration_seconds INTEGER,
    CONSTRAINT pk_lessons PRIMARY KEY (lesson_id),
    CONSTRAINT uq_lessons_course_order UNIQUE (course_id, lesson_order),
    CONSTRAINT fk_lessons_course FOREIGN KEY (course_id)
        REFERENCES courses (course_id) ON DELETE RESTRICT,
    CONSTRAINT ck_lessons_order_positive CHECK (lesson_order > 0),
    CONSTRAINT ck_lessons_duration_nonnegative
        CHECK (duration_seconds IS NULL OR duration_seconds >= 0)
);

CREATE TABLE enrollments (
    enrollment_id BIGINT GENERATED ALWAYS AS IDENTITY,
    user_id BIGINT NOT NULL,
    course_id BIGINT NOT NULL,
    enrolled_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL,
    CONSTRAINT pk_enrollments PRIMARY KEY (enrollment_id),
    CONSTRAINT uq_enrollments_user_course UNIQUE (user_id, course_id),
    CONSTRAINT fk_enrollments_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_enrollments_course FOREIGN KEY (course_id)
        REFERENCES courses (course_id) ON DELETE RESTRICT,
    CONSTRAINT ck_enrollments_status
        CHECK (status IN ('active', 'completed', 'withdrawn'))
);

CREATE TABLE lesson_progress (
    user_id BIGINT NOT NULL,
    lesson_id BIGINT NOT NULL,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_lesson_progress PRIMARY KEY (user_id, lesson_id),
    CONSTRAINT fk_lesson_progress_user FOREIGN KEY (user_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_lesson_progress_lesson FOREIGN KEY (lesson_id)
        REFERENCES lessons (lesson_id) ON DELETE RESTRICT,
    CONSTRAINT ck_lesson_progress_completion_time CHECK (
        (is_completed AND completed_at IS NOT NULL)
        OR (NOT is_completed AND completed_at IS NULL)
    )
);

CREATE TABLE equipment (
    equipment_id BIGINT GENERATED ALWAYS AS IDENTITY,
    provider_id BIGINT NOT NULL,
    category_id BIGINT NOT NULL,
    equipment_name VARCHAR(200) NOT NULL,
    description TEXT,
    daily_rate NUMERIC(12,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    quantity INTEGER NOT NULL,
    equipment_status VARCHAR(20) NOT NULL,
    CONSTRAINT pk_equipment PRIMARY KEY (equipment_id),
    CONSTRAINT fk_equipment_provider FOREIGN KEY (provider_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_equipment_category FOREIGN KEY (category_id)
        REFERENCES equipment_categories (category_id) ON DELETE RESTRICT,
    CONSTRAINT ck_equipment_rate_nonnegative CHECK (daily_rate >= 0),
    CONSTRAINT ck_equipment_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_equipment_quantity_positive CHECK (quantity > 0),
    CONSTRAINT ck_equipment_status
        CHECK (equipment_status IN ('available', 'unavailable'))
);

CREATE TABLE rentals (
    rental_id BIGINT GENERATED ALWAYS AS IDENTITY,
    equipment_id BIGINT NOT NULL,
    renter_id BIGINT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    quantity INTEGER NOT NULL,
    agreed_rate NUMERIC(12,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_rentals PRIMARY KEY (rental_id),
    CONSTRAINT fk_rentals_equipment FOREIGN KEY (equipment_id)
        REFERENCES equipment (equipment_id) ON DELETE RESTRICT,
    CONSTRAINT fk_rentals_renter FOREIGN KEY (renter_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_rentals_date_range CHECK (end_date > start_date),
    CONSTRAINT ck_rentals_quantity_positive CHECK (quantity > 0),
    CONSTRAINT ck_rentals_rate_nonnegative CHECK (agreed_rate >= 0),
    CONSTRAINT ck_rentals_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_rentals_status
        CHECK (status IN ('requested', 'confirmed', 'active', 'completed', 'cancelled'))
);

CREATE TABLE studios (
    studio_id BIGINT GENERATED ALWAYS AS IDENTITY,
    provider_id BIGINT NOT NULL,
    studio_name VARCHAR(200) NOT NULL,
    location TEXT NOT NULL,
    capacity INTEGER NOT NULL,
    hourly_rate NUMERIC(12,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    status VARCHAR(20) NOT NULL,
    CONSTRAINT pk_studios PRIMARY KEY (studio_id),
    CONSTRAINT fk_studios_provider FOREIGN KEY (provider_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_studios_capacity_positive CHECK (capacity > 0),
    CONSTRAINT ck_studios_rate_nonnegative CHECK (hourly_rate >= 0),
    CONSTRAINT ck_studios_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_studios_status CHECK (status IN ('available', 'unavailable'))
);

CREATE TABLE studio_bookings (
    booking_id BIGINT GENERATED ALWAYS AS IDENTITY,
    studio_id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    agreed_rate NUMERIC(12,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_studio_bookings PRIMARY KEY (booking_id),
    CONSTRAINT fk_studio_bookings_studio FOREIGN KEY (studio_id)
        REFERENCES studios (studio_id) ON DELETE RESTRICT,
    CONSTRAINT fk_studio_bookings_customer FOREIGN KEY (customer_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_studio_bookings_time_range CHECK (end_time > start_time),
    CONSTRAINT ck_studio_bookings_rate_nonnegative CHECK (agreed_rate >= 0),
    CONSTRAINT ck_studio_bookings_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_studio_bookings_status
        CHECK (status IN ('requested', 'confirmed', 'completed', 'cancelled')),
    CONSTRAINT ex_studio_bookings_no_confirmed_overlap
        EXCLUDE USING gist (
            (int8range(studio_id, studio_id, '[]')) WITH &&,
            (tstzrange(start_time, end_time, '[)')) WITH &&
        ) WHERE (status = 'confirmed')
);

CREATE TABLE services (
    service_id BIGINT GENERATED ALWAYS AS IDENTITY,
    provider_id BIGINT NOT NULL,
    service_name VARCHAR(200) NOT NULL,
    description TEXT,
    price NUMERIC(12,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    status VARCHAR(20) NOT NULL,
    CONSTRAINT pk_services PRIMARY KEY (service_id),
    CONSTRAINT fk_services_provider FOREIGN KEY (provider_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_services_price_nonnegative CHECK (price >= 0),
    CONSTRAINT ck_services_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_services_status CHECK (status IN ('active', 'inactive'))
);

CREATE TABLE service_orders (
    service_order_id BIGINT GENERATED ALWAYS AS IDENTITY,
    service_id BIGINT NOT NULL,
    customer_id BIGINT NOT NULL,
    agreed_price NUMERIC(12,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    requirements TEXT,
    scheduled_at TIMESTAMPTZ,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMPTZ,
    CONSTRAINT pk_service_orders PRIMARY KEY (service_order_id),
    CONSTRAINT fk_service_orders_service FOREIGN KEY (service_id)
        REFERENCES services (service_id) ON DELETE RESTRICT,
    CONSTRAINT fk_service_orders_customer FOREIGN KEY (customer_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_service_orders_price_nonnegative CHECK (agreed_price >= 0),
    CONSTRAINT ck_service_orders_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_service_orders_status
        CHECK (status IN ('requested', 'accepted', 'in_progress', 'completed', 'cancelled'))
);

CREATE TABLE payments (
    payment_id BIGINT GENERATED ALWAYS AS IDENTITY,
    payer_id BIGINT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    payment_method VARCHAR(40) NOT NULL,
    payment_status VARCHAR(20) NOT NULL,
    payment_reference VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    paid_at TIMESTAMPTZ,
    CONSTRAINT pk_payments PRIMARY KEY (payment_id),
    CONSTRAINT fk_payments_payer FOREIGN KEY (payer_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_payments_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT ck_payments_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_payments_status
        CHECK (payment_status IN ('pending', 'authorized', 'paid', 'failed', 'refunded'))
);

CREATE TABLE transactions (
    transaction_id BIGINT GENERATED ALWAYS AS IDENTITY,
    payment_id BIGINT NOT NULL,
    transaction_type VARCHAR(30) NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    transaction_status VARCHAR(20) NOT NULL,
    provider_reference VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_transactions PRIMARY KEY (transaction_id),
    CONSTRAINT fk_transactions_payment FOREIGN KEY (payment_id)
        REFERENCES payments (payment_id) ON DELETE RESTRICT,
    CONSTRAINT ck_transactions_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT ck_transactions_type
        CHECK (transaction_type IN ('authorization', 'capture', 'refund', 'fee')),
    CONSTRAINT ck_transactions_status
        CHECK (transaction_status IN ('pending', 'succeeded', 'failed'))
);

CREATE TABLE payouts (
    payout_id BIGINT GENERATED ALWAYS AS IDENTITY,
    provider_id BIGINT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    currency CHAR(3) NOT NULL,
    status VARCHAR(20) NOT NULL,
    payout_reference VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    paid_at TIMESTAMPTZ,
    CONSTRAINT pk_payouts PRIMARY KEY (payout_id),
    CONSTRAINT fk_payouts_provider FOREIGN KEY (provider_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_payouts_amount_nonnegative CHECK (amount >= 0),
    CONSTRAINT ck_payouts_currency CHECK (currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_payouts_status
        CHECK (status IN ('pending', 'processing', 'paid', 'failed'))
);

CREATE TABLE reviews (
    review_id BIGINT GENERATED ALWAYS AS IDENTITY,
    reviewer_id BIGINT NOT NULL,
    reviewed_user_id BIGINT,
    equipment_id BIGINT,
    studio_id BIGINT,
    service_id BIGINT,
    course_id BIGINT,
    rating SMALLINT NOT NULL,
    review_text TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_reviews PRIMARY KEY (review_id),
    CONSTRAINT fk_reviews_reviewer FOREIGN KEY (reviewer_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reviews_user_target FOREIGN KEY (reviewed_user_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reviews_equipment_target FOREIGN KEY (equipment_id)
        REFERENCES equipment (equipment_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reviews_studio_target FOREIGN KEY (studio_id)
        REFERENCES studios (studio_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reviews_service_target FOREIGN KEY (service_id)
        REFERENCES services (service_id) ON DELETE RESTRICT,
    CONSTRAINT fk_reviews_course_target FOREIGN KEY (course_id)
        REFERENCES courses (course_id) ON DELETE RESTRICT,
    CONSTRAINT ck_reviews_exactly_one_target CHECK (
        num_nonnulls(reviewed_user_id, equipment_id, studio_id, service_id, course_id) = 1
    ),
    CONSTRAINT ck_reviews_rating CHECK (rating BETWEEN 1 AND 5)
);

CREATE TABLE creator_plans (
    plan_id BIGINT GENERATED ALWAYS AS IDENTITY,
    creator_id BIGINT NOT NULL,
    plan_title VARCHAR(200) NOT NULL,
    podcast_idea TEXT,
    target_launch_date DATE,
    plan_status VARCHAR(20) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_creator_plans PRIMARY KEY (plan_id),
    CONSTRAINT fk_creator_plans_creator FOREIGN KEY (creator_id)
        REFERENCES users (user_id) ON DELETE RESTRICT,
    CONSTRAINT ck_creator_plans_status
        CHECK (plan_status IN ('draft', 'active', 'completed', 'archived'))
);

CREATE TABLE plan_tasks (
    task_id BIGINT GENERATED ALWAYS AS IDENTITY,
    plan_id BIGINT NOT NULL,
    task_title VARCHAR(200) NOT NULL,
    task_category VARCHAR(80),
    due_date DATE,
    task_status VARCHAR(20) NOT NULL,
    task_order INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_plan_tasks PRIMARY KEY (task_id),
    CONSTRAINT uq_plan_tasks_plan_order UNIQUE (plan_id, task_order),
    CONSTRAINT fk_plan_tasks_plan FOREIGN KEY (plan_id)
        REFERENCES creator_plans (plan_id) ON DELETE RESTRICT,
    CONSTRAINT ck_plan_tasks_order_positive CHECK (task_order > 0),
    CONSTRAINT ck_plan_tasks_status
        CHECK (task_status IN ('not_started', 'in_progress', 'completed'))
);

-- A nullable external reference is unique only for rows that have a value.
CREATE UNIQUE INDEX uq_payments_reference_nonnull
    ON payments (payment_reference)
    WHERE payment_reference IS NOT NULL;

CREATE UNIQUE INDEX uq_transactions_provider_reference_nonnull
    ON transactions (provider_reference)
    WHERE provider_reference IS NOT NULL;

CREATE UNIQUE INDEX uq_payouts_reference_nonnull
    ON payouts (payout_reference)
    WHERE payout_reference IS NOT NULL;

-- Foreign-key and common relationship lookup indexes not already covered by a key.
CREATE INDEX ix_user_roles_role_id ON user_roles (role_id);
CREATE INDEX ix_podcasts_creator_id ON podcasts (creator_id);
CREATE INDEX ix_courses_instructor_id ON courses (instructor_id);
CREATE INDEX ix_enrollments_course_id ON enrollments (course_id);
CREATE INDEX ix_lesson_progress_lesson_id ON lesson_progress (lesson_id);
CREATE INDEX ix_equipment_provider_id ON equipment (provider_id);
CREATE INDEX ix_equipment_category_id ON equipment (category_id);
CREATE INDEX ix_rentals_equipment_id ON rentals (equipment_id);
CREATE INDEX ix_rentals_renter_id ON rentals (renter_id);
CREATE INDEX ix_rentals_inventory_window
    ON rentals (equipment_id, start_date, end_date)
    WHERE status IN ('confirmed', 'active');
CREATE INDEX ix_studios_provider_id ON studios (provider_id);
CREATE INDEX ix_studio_bookings_studio_id ON studio_bookings (studio_id);
CREATE INDEX ix_studio_bookings_customer_id ON studio_bookings (customer_id);
CREATE INDEX ix_services_provider_id ON services (provider_id);
CREATE INDEX ix_service_orders_service_id ON service_orders (service_id);
CREATE INDEX ix_service_orders_customer_id ON service_orders (customer_id);
CREATE INDEX ix_payments_payer_id ON payments (payer_id);
CREATE INDEX ix_transactions_payment_id ON transactions (payment_id);
CREATE INDEX ix_payouts_provider_id ON payouts (provider_id);
CREATE INDEX ix_reviews_reviewer_id ON reviews (reviewer_id);
CREATE INDEX ix_creator_plans_creator_id ON creator_plans (creator_id);

-- These partial indexes also support lookups by each review target.
CREATE UNIQUE INDEX uq_reviews_user_target_reviewer
    ON reviews (reviewed_user_id, reviewer_id)
    WHERE reviewed_user_id IS NOT NULL;

CREATE UNIQUE INDEX uq_reviews_equipment_target_reviewer
    ON reviews (equipment_id, reviewer_id)
    WHERE equipment_id IS NOT NULL;

CREATE UNIQUE INDEX uq_reviews_studio_target_reviewer
    ON reviews (studio_id, reviewer_id)
    WHERE studio_id IS NOT NULL;

CREATE UNIQUE INDEX uq_reviews_service_target_reviewer
    ON reviews (service_id, reviewer_id)
    WHERE service_id IS NOT NULL;

CREATE UNIQUE INDEX uq_reviews_course_target_reviewer
    ON reviews (course_id, reviewer_id)
    WHERE course_id IS NOT NULL;

COMMENT ON CONSTRAINT ex_studio_bookings_no_confirmed_overlap ON studio_bookings IS
    'Uses built-in GiST range operators; int8range equality encodes studio identity and [) timestamps allow adjacent bookings.';

-- Active reservations use half-open DATE ranges [start_date, end_date), so a
-- rental ending on a date does not overlap another beginning on that date.
-- The equipment row lock serializes reservation checks for the same listing.
CREATE FUNCTION enforce_rental_inventory()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_available_quantity INTEGER;
BEGIN
    IF NEW.status NOT IN ('confirmed', 'active') THEN
        RETURN NEW;
    END IF;

    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'reservation inventory changes require READ COMMITTED isolation or external serialization'
            USING ERRCODE = '25001';
    END IF;

    SELECT equipment.quantity
    INTO v_available_quantity
    FROM equipment
    WHERE equipment.equipment_id = NEW.equipment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            SELECT NEW.start_date AS check_date
            UNION
            SELECT existing.start_date
            FROM rentals AS existing
            WHERE existing.equipment_id = NEW.equipment_id
              AND existing.status IN ('confirmed', 'active')
              AND existing.rental_id IS DISTINCT FROM NEW.rental_id
              AND daterange(existing.start_date, existing.end_date, '[)')
                  && daterange(NEW.start_date, NEW.end_date, '[)')
              AND existing.start_date >= NEW.start_date
              AND existing.start_date < NEW.end_date
        ) AS boundaries
        WHERE (
            SELECT COALESCE(SUM(existing.quantity), 0)
            FROM rentals AS existing
            WHERE existing.equipment_id = NEW.equipment_id
              AND existing.status IN ('confirmed', 'active')
              AND existing.rental_id IS DISTINCT FROM NEW.rental_id
              AND existing.start_date <= boundaries.check_date
              AND existing.end_date > boundaries.check_date
        ) + NEW.quantity > v_available_quantity
    ) THEN
        RAISE EXCEPTION 'rental quantity exceeds available equipment inventory for an overlapping period'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_rentals_inventory
    BEFORE INSERT OR UPDATE OF equipment_id, start_date, end_date, quantity, status
    ON rentals
    FOR EACH ROW
    EXECUTE FUNCTION enforce_rental_inventory();

-- Prevent lowering the listed quantity below any already-reserved peak. The row
-- update lock serializes this check with enforce_rental_inventory().
CREATE FUNCTION enforce_equipment_quantity_not_below_reservations()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.quantity < OLD.quantity THEN
        IF current_setting('transaction_isolation') <> 'read committed' THEN
            RAISE EXCEPTION 'equipment quantity reductions require READ COMMITTED isolation or external serialization'
                USING ERRCODE = '25001';
        END IF;

                IF EXISTS (
                        SELECT 1
                        FROM (
                                SELECT rental.start_date AS check_date
                                FROM rentals AS rental
                                WHERE rental.equipment_id = OLD.equipment_id
                                    AND rental.status IN ('confirmed', 'active')
                        ) AS boundaries
                        WHERE (
                                SELECT COALESCE(SUM(rental.quantity), 0)
                                FROM rentals AS rental
                                WHERE rental.equipment_id = OLD.equipment_id
                                    AND rental.status IN ('confirmed', 'active')
                                    AND rental.start_date <= boundaries.check_date
                                    AND rental.end_date > boundaries.check_date
                        ) > NEW.quantity
                ) THEN
            RAISE EXCEPTION 'equipment quantity cannot be lower than overlapping confirmed or active rentals'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_equipment_quantity_reservations
    BEFORE UPDATE OF quantity
    ON equipment
    FOR EACH ROW
    EXECUTE FUNCTION enforce_equipment_quantity_not_below_reservations();

COMMENT ON FUNCTION enforce_rental_inventory() IS
    'Checks peak overlapping confirmed/active rental quantities at interval start boundaries while holding the equipment row lock. Requested rentals do not reserve inventory.';

-- Progress writes lock the matching enrollment row. Enrollment deletion or key
-- changes are rejected while progress exists, preserving the enrollment rule.
CREATE FUNCTION require_enrollment_for_lesson_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id BIGINT;
BEGIN
    SELECT lesson.course_id
    INTO v_course_id
    FROM lessons AS lesson
    WHERE lesson.lesson_id = NEW.lesson_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    PERFORM enrollment.enrollment_id
    FROM enrollments AS enrollment
    WHERE enrollment.user_id = NEW.user_id
      AND enrollment.course_id = v_course_id
    FOR KEY SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'lesson progress requires enrollment in the lesson course'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_lesson_progress_requires_enrollment
    BEFORE INSERT OR UPDATE OF user_id, lesson_id
    ON lesson_progress
    FOR EACH ROW
    EXECUTE FUNCTION require_enrollment_for_lesson_progress();

CREATE FUNCTION prevent_lesson_course_change_with_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.course_id IS DISTINCT FROM OLD.course_id
       AND EXISTS (
           SELECT 1
           FROM lesson_progress AS progress
           WHERE progress.lesson_id = OLD.lesson_id
       ) THEN
        RAISE EXCEPTION 'lesson cannot be reassigned while learner progress exists'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_lessons_preserve_progress_course
    BEFORE UPDATE OF course_id
    ON lessons
    FOR EACH ROW
    EXECUTE FUNCTION prevent_lesson_course_change_with_progress();

CREATE FUNCTION protect_enrollment_with_lesson_progress()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.user_id IS NOT DISTINCT FROM OLD.user_id
           AND NEW.course_id IS NOT DISTINCT FROM OLD.course_id THEN
            RETURN NEW;
        END IF;
    END IF;

    IF EXISTS (
        SELECT 1
        FROM lesson_progress AS progress
        JOIN lessons AS lesson ON lesson.lesson_id = progress.lesson_id
        WHERE progress.user_id = OLD.user_id
          AND lesson.course_id = OLD.course_id
    ) THEN
        RAISE EXCEPTION 'enrollment cannot be deleted or reassigned while lesson progress exists'
            USING ERRCODE = '23503';
    END IF;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_enrollments_preserve_progress
    BEFORE DELETE OR UPDATE OF user_id, course_id
    ON enrollments
    FOR EACH ROW
    EXECUTE FUNCTION protect_enrollment_with_lesson_progress();

COMMENT ON FUNCTION require_enrollment_for_lesson_progress() IS
    'Requires an enrollment for the course containing the lesson and locks that enrollment against concurrent deletion or reassignment.';

COMMENT ON FUNCTION prevent_lesson_course_change_with_progress() IS
    'Prevents moving a lesson to another course after progress has been recorded; progress writes lock the lesson row during course lookup.';

COMMIT;
