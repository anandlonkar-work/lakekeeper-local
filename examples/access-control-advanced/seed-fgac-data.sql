-- ============================================================================
-- FGAC Seed Data Script
-- ============================================================================
-- This script populates column_permissions and row_policies tables with
-- policies that match the test data from the 05-FGAC-Testing.ipynb notebook
--
-- Test Data from Notebook:
-- 8 employees across Engineering, HR, Finance, Sales, and Executive departments
-- Classifications: Public, Internal, Confidential, Restricted
-- 
-- Expected Behavior:
-- - Peter (admin): Sees ALL 8 employees with ALL columns
-- - Anna (restricted): Sees only 5 employees (filtered by dept/classification)
--                      with salary/email/phone columns MASKED (NULL)
-- ============================================================================

DO $$
DECLARE
    demo_warehouse_id UUID;
    peter_user_id UUID := 'cfb55bf6-fcbb-4a1e-bfec-30c6649b52f8';  -- Peter's UUID from notebook
    anna_user_id UUID := 'd223d88c-85b6-4859-b5c5-27f3825e47f6';   -- Anna's UUID from notebook
BEGIN
    -- ========================================================================
    -- 1. Get warehouse_id for 'demo' warehouse
    -- ========================================================================
    SELECT warehouse_id INTO demo_warehouse_id
    FROM warehouse
    WHERE warehouse_name = 'demo'
    LIMIT 1;

    IF demo_warehouse_id IS NULL THEN
        RAISE EXCEPTION 'Demo warehouse not found. Please run bootstrap and create warehouse first.';
    END IF;

    RAISE NOTICE '✓ Found demo warehouse: %', demo_warehouse_id;

    -- ========================================================================
    -- 2. Column Permissions - Mask sensitive columns for Anna
    -- ========================================================================
    -- From notebook: Anna should NOT see salary, email, phone columns
    -- These will appear as NULL in query results
    
    RAISE NOTICE '';
    RAISE NOTICE '=== Inserting Column Permissions ===';
    
    INSERT INTO column_permissions (
        column_permission_id,
        warehouse_id,
        namespace_name,
        table_name,
        column_name,
        principal_type,
        principal_id,
        permission_type,
        masking_method,
        masking_expression,
        granted_by,
        granted_at,
        expires_at
    ) VALUES
    -- Mask salary column for Anna
    (
        gen_random_uuid(),
        demo_warehouse_id,
        'fgac_test',
        'employees',
        'salary',
        'user',
        anna_user_id,
        'mask',
        'null',
        'NULL',
        peter_user_id,  -- Granted by Peter (admin)
        now(),
        NULL  -- No expiration
    ),
    -- Mask email column for Anna
    (
        gen_random_uuid(),
        demo_warehouse_id,
        'fgac_test',
        'employees',
        'email',
        'user',
        anna_user_id,
        'mask',
        'null',
        'NULL',
        peter_user_id,
        now(),
        NULL
    ),
    -- Mask phone column for Anna
    (
        gen_random_uuid(),
        demo_warehouse_id,
        'fgac_test',
        'employees',
        'phone',
        'user',
        anna_user_id,
        'mask',
        'null',
        'NULL',
        peter_user_id,
        now(),
        NULL
    )
    ON CONFLICT DO NOTHING;

    RAISE NOTICE '✓ Inserted 3 column permissions for Anna';
    RAISE NOTICE '  - salary → NULL';
    RAISE NOTICE '  - email → NULL';
    RAISE NOTICE '  - phone → NULL';

    -- ========================================================================
    -- 3. Row Policies - Filter rows for Anna
    -- ========================================================================
    -- From notebook test data, Anna should see:
    -- ✓ John Doe (Engineering, Public)
    -- ✓ Jane Smith (Engineering, Public)
    -- ✓ Charlie Wilson (Engineering, Public)
    -- ✓ Diana Lee (Sales, Public) - IF we allow Sales department
    -- ✓ Eve Davis (HR, Internal)
    --
    -- Anna should NOT see:
    -- ✗ Bob Johnson (HR, Confidential) - Confidential classification
    -- ✗ Alice Brown (Finance, Confidential) - Confidential classification
    -- ✗ Frank Miller (Executive, Restricted) - Executive dept + Restricted
    
    RAISE NOTICE '';
    RAISE NOTICE '=== Inserting Row Policies ===';
    
    INSERT INTO row_policies (
        row_policy_id,
        warehouse_id,
        namespace_name,
        table_name,
        policy_name,
        principal_type,
        principal_id,
        policy_expression,
        policy_type,
        is_active,
        priority,
        granted_by,
        granted_at,
        expires_at
    ) VALUES
    -- Policy 1: Only show Public and Internal classification for Anna
    -- This blocks: Bob Johnson (Confidential), Alice Brown (Confidential), Frank Miller (Restricted)
    (
        gen_random_uuid(),
        demo_warehouse_id,
        'fgac_test',
        'employees',
        'public_internal_only',
        'user',
        anna_user_id,
        'classification IN (''Public'', ''Internal'')',
        'filter',
        true,
        10,  -- Highest priority
        peter_user_id,
        now(),
        NULL
    ),
    -- Policy 2: Exclude Executive department for Anna
    -- This blocks: Frank Miller (Executive, CEO)
    (
        gen_random_uuid(),
        demo_warehouse_id,
        'fgac_test',
        'employees',
        'no_executive_dept',
        'user',
        anna_user_id,
        'department != ''Executive''',
        'filter',
        true,
        9,  -- High priority
        peter_user_id,
        now(),
        NULL
    ),
    -- Policy 3: Anna can only see Engineering department
    -- This is the most restrictive - only Engineering employees
    -- Comment this out if you want Anna to see more departments
    (
        gen_random_uuid(),
        demo_warehouse_id,
        'fgac_test',
        'employees',
        'engineering_only',
        'user',
        anna_user_id,
        'department = ''Engineering''',
        'filter',
        true,
        8,  -- Lower priority (most specific)
        peter_user_id,
        now(),
        NULL
    )
    ON CONFLICT DO NOTHING;

    RAISE NOTICE '✓ Inserted 3 row policies for Anna';
    RAISE NOTICE '  - Classification: Public/Internal only';
    RAISE NOTICE '  - Department: No Executive';
    RAISE NOTICE '  - Department: Engineering only';

    -- ========================================================================
    -- 4. Summary
    -- ========================================================================
    RAISE NOTICE '';
    RAISE NOTICE '=== FGAC Seed Data Summary ===';
    RAISE NOTICE '✓ Column Permissions: 3 (mask salary, email, phone for Anna)';
    RAISE NOTICE '✓ Row Policies: 3 (classification + department filters for Anna)';
    RAISE NOTICE '';
    RAISE NOTICE 'Expected Query Results:';
    RAISE NOTICE '  Peter (admin): 8 employees, all columns visible';
    RAISE NOTICE '  Anna (restricted): 3 Engineering employees (John, Jane, Charlie)';
    RAISE NOTICE '                     salary/email/phone columns show NULL';
    RAISE NOTICE '';
    RAISE NOTICE 'To modify Anna''s access:';
    RAISE NOTICE '  - Remove "engineering_only" policy to show more departments';
    RAISE NOTICE '  - Adjust classification filter to show Confidential data';
    RAISE NOTICE '';
    
END $$;

-- Verify the data was inserted
SELECT 
    'Column Permissions' as type,
    COUNT(*) as count
FROM column_permissions

UNION ALL

SELECT 
    'Row Policies' as type,
    COUNT(*) as count
FROM row_policies;

-- Show the actual policies
SELECT 
    'Column Permission' as type,
    cp.column_name,
    cp.principal_type,
    cp.principal_id::text,
    cp.masking_method,
    cp.masking_expression
FROM column_permissions cp
JOIN warehouse w ON cp.warehouse_id = w.warehouse_id
WHERE w.warehouse_name = 'demo'
    AND cp.namespace_name = 'fgac_test'
    AND cp.table_name = 'employees'

UNION ALL

SELECT 
    'Row Policy' as type,
    rp.policy_name,
    rp.principal_type,
    rp.principal_id::text,
    rp.policy_type,
    rp.policy_expression
FROM row_policies rp
JOIN warehouse w ON rp.warehouse_id = w.warehouse_id
WHERE w.warehouse_name = 'demo'
    AND rp.namespace_name = 'fgac_test'
    AND rp.table_name = 'employees'
ORDER BY type, column_name, policy_name;
