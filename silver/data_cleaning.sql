-- ============================================================================
-- CAR SALES DATA QUALITY HANDLING AND CLEANUP
-- ============================================================================
-- This script addresses the following data quality issues:
-- 1. NULL values in multiple columns (transmission, trim, body, condition, etc.)
-- 2. 8,515 duplicate VINs that should be unique identifiers
-- 3. saledate stored as STRING instead of proper DATE type
-- 4. 12 rows with NULLs in critical fields (mmr, sellingprice, saledate)
-- ============================================================================

-- Step 1: Create a cleaned table with proper data types
DROP TABLE IF EXISTS practice.bricks.car_sales_data_cleaned;

CREATE TABLE practice.bricks.car_sales_data_cleaned AS
SELECT 
    -- Keep original year
    year,
    
    -- Handle NULL categorical values by replacing with 'Unknown'
    COALESCE(make, 'Unknown') as make,
    COALESCE(model, 'Unknown') as model,
    COALESCE(trim, 'Unknown') as trim,
    COALESCE(body, 'Unknown') as body,
    COALESCE(transmission, 'Unknown') as transmission,
    
    -- Keep VIN as-is (we'll handle duplicates separately)
    vin,
    
    -- State is complete, no changes needed
    state,
    
    -- Condition: replace NULL with 0 (indicating unknown condition)
    COALESCE(condition, 0) as condition,
    
    -- Odometer: replace NULL with median value or 0
    COALESCE(odometer, 0) as odometer,
    
    -- Handle NULL colors and interior
    COALESCE(color, 'Unknown') as color,
    COALESCE(interior, 'Unknown') as interior,
    
    -- Seller is complete
    seller,
    
    -- Critical numeric fields: keep NULL if missing (for filtering later)
    mmr,
    sellingprice,
    
    -- Convert saledate from STRING to proper DATE format
    -- Format: "Tue Dec 16 2014 12:30:00" -> DATE
    -- Skip day-of-week (first 4 chars) and parse the rest with Spark 3.0+ pattern
    to_date(SUBSTRING(saledate, 5), 'MMM dd yyyy HH:mm:ss') as saledate,
    
    -- Add original saledate as timestamp string for reference
    saledate as saledate_original,
    
    -- Add data quality flags
    CASE 
        WHEN make IS NULL OR model IS NULL THEN 1 
        ELSE 0 
    END as missing_vehicle_info,
    
    CASE 
        WHEN transmission IS NULL THEN 1 
        ELSE 0 
    END as missing_transmission,
    
    CASE 
        WHEN mmr IS NULL OR sellingprice IS NULL OR saledate IS NULL THEN 1 
        ELSE 0 
    END as missing_critical_data,
    
    -- Calculate price difference for analysis
    sellingprice - mmr as price_difference

FROM practice.bricks.car_sales_data
-- Filter out rows with critical missing data
WHERE mmr IS NOT NULL 
  AND sellingprice IS NOT NULL 
  AND saledate IS NOT NULL;

-- ============================================================================
-- Step 2: Create a deduplicated table (remove duplicate VINs)
-- Keep the most recent sale for each VIN
-- ============================================================================

DROP TABLE IF EXISTS practice.bricks.car_sales_data_deduped;

CREATE TABLE practice.bricks.car_sales_data_deduped AS
WITH ranked_sales AS (
    SELECT 
        *,
        ROW_NUMBER() OVER (
            PARTITION BY vin 
            ORDER BY saledate DESC, sellingprice DESC
        ) as row_num
    FROM practice.bricks.car_sales_data_cleaned
)
SELECT 
    year,
    make,
    model,
    trim,
    body,
    transmission,
    vin,
    state,
    condition,
    odometer,
    color,
    interior,
    seller,
    mmr,
    sellingprice,
    saledate,
    saledate_original,
    missing_vehicle_info,
    missing_transmission,
    missing_critical_data,
    price_difference
FROM ranked_sales
WHERE row_num = 1;

-- ============================================================================
-- Step 3: Data Quality Summary Statistics
-- ============================================================================

SELECT 
    'Original Table' as table_name,
    COUNT(*) as total_rows,
    COUNT(DISTINCT vin) as unique_vins,
    COUNT(*) - COUNT(DISTINCT vin) as duplicate_vins
FROM practice.bricks.car_sales_data

UNION ALL

SELECT 
    'Cleaned Table',
    COUNT(*),
    COUNT(DISTINCT vin),
    COUNT(*) - COUNT(DISTINCT vin)
FROM practice.bricks.car_sales_data_cleaned

UNION ALL

SELECT 
    'Deduplicated Table',
    COUNT(*),
    COUNT(DISTINCT vin),
    COUNT(*) - COUNT(DISTINCT vin)
FROM practice.bricks.car_sales_data_deduped;

-- ============================================================================
-- Step 4: Quality Check - Verify cleaning results
-- ============================================================================

SELECT 
    'NULL Values After Cleaning' as check_type,
    SUM(CASE WHEN make = 'Unknown' THEN 1 ELSE 0 END) as unknown_make,
    SUM(CASE WHEN model = 'Unknown' THEN 1 ELSE 0 END) as unknown_model,
    SUM(CASE WHEN transmission = 'Unknown' THEN 1 ELSE 0 END) as unknown_transmission,
    SUM(CASE WHEN trim = 'Unknown' THEN 1 ELSE 0 END) as unknown_trim,
    SUM(CASE WHEN body = 'Unknown' THEN 1 ELSE 0 END) as unknown_body,
    SUM(CASE WHEN color = 'Unknown' THEN 1 ELSE 0 END) as unknown_color
FROM practice.bricks.car_sales_data_deduped;

-- ============================================================================
-- Step 5: Data Quality Metrics by Category
-- ============================================================================

SELECT 
    'Data Quality Summary' as metric_type,
    COUNT(*) as total_records,
    SUM(missing_vehicle_info) as records_missing_vehicle_info,
    SUM(missing_transmission) as records_missing_transmission,
    ROUND(AVG(CASE WHEN transmission = 'Unknown' THEN 0 ELSE 1 END) * 100, 2) as pct_with_transmission,
    ROUND(AVG(CASE WHEN odometer > 0 THEN 1 ELSE 0 END) * 100, 2) as pct_with_odometer,
    MIN(year) as min_year,
    MAX(year) as max_year,
    MIN(saledate) as earliest_sale,
    MAX(saledate) as latest_sale
FROM practice.bricks.car_sales_data_deduped;


