SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/*
    Smoke tests for dbo.sp_GetNextGS1SSCC.
    Run after 00_setup.sql and 01_sp_GetNextGS1SSCC.sql.
*/

/* --- 1. First issue after seed 0 -> serial 000000001 --- */
UPDATE dbo.tbl_SSCC_Counter SET LastGS1SSCC = 0;

DECLARE @sscc NVARCHAR(22);
EXEC dbo.sp_GetNextGS1SSCC @SSCC = @sscc OUTPUT;

IF @sscc IS NULL
    OR LEN(@sscc) <> 22
    OR LEFT(@sscc, 12) <> N'(00)54602541'
    OR SUBSTRING(@sscc, 13, 9) <> N'000000001'
    THROW 51001, 'Test 1 failed: expected serial 000000001 with prefix 54602541.', 1;

PRINT N'Test 1 OK: ' + @sscc;
GO

/* --- 2. Wrap-around 999999999 -> 0, then 1 --- */
UPDATE dbo.tbl_SSCC_Counter SET LastGS1SSCC = 999999999;

DECLARE @sscc NVARCHAR(22);
EXEC dbo.sp_GetNextGS1SSCC @SSCC = @sscc OUTPUT;

IF SUBSTRING(@sscc, 13, 9) <> N'000000000'
    THROW 51002, 'Test 2 failed: expected wrap to serial 000000000.', 1;

PRINT N'Test 2 OK wrap to 0: ' + @sscc;

EXEC dbo.sp_GetNextGS1SSCC @SSCC = @sscc OUTPUT;

IF SUBSTRING(@sscc, 13, 9) <> N'000000001'
    THROW 51003, 'Test 2 failed: expected serial 000000001 after wrap.', 1;

PRINT N'Test 2 OK next after wrap: ' + @sscc;
GO

/* --- 3. Missing counter row --- */
DELETE FROM dbo.tbl_SSCC_Counter;

DECLARE @sscc NVARCHAR(22);
DECLARE @caught BIT = 0;

BEGIN TRY
    EXEC dbo.sp_GetNextGS1SSCC @SSCC = @sscc OUTPUT;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50001
        SET @caught = 1;
    ELSE
        THROW;
END CATCH;

IF @caught = 0
    THROW 51004, 'Test 3 failed: expected error 50001 on empty counter table.', 1;

IF @sscc IS NOT NULL
    THROW 51005, 'Test 3 failed: @SSCC must be NULL after an error.', 1;

PRINT N'Test 3 OK: empty table raises 50001';

INSERT INTO dbo.tbl_SSCC_Counter (LastGS1SSCC) VALUES (0);
GO

/* --- 4. Invalid counter value --- */
IF EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.tbl_SSCC_Counter')
      AND name = N'CK_tbl_SSCC_Counter_LastGS1SSCC'
)
    ALTER TABLE dbo.tbl_SSCC_Counter NOCHECK CONSTRAINT CK_tbl_SSCC_Counter_LastGS1SSCC;

UPDATE dbo.tbl_SSCC_Counter SET LastGS1SSCC = -1;

DECLARE @sscc NVARCHAR(22);
DECLARE @caught BIT = 0;

BEGIN TRY
    EXEC dbo.sp_GetNextGS1SSCC @SSCC = @sscc OUTPUT;
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50002
        SET @caught = 1;
    ELSE
        THROW;
END CATCH;

IF @caught = 0
    THROW 51006, 'Test 4 failed: expected error 50002 on invalid counter.', 1;

PRINT N'Test 4 OK: invalid counter raises 50002';

UPDATE dbo.tbl_SSCC_Counter SET LastGS1SSCC = 0;

IF EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.tbl_SSCC_Counter')
      AND name = N'CK_tbl_SSCC_Counter_LastGS1SSCC'
)
    ALTER TABLE dbo.tbl_SSCC_Counter WITH CHECK CHECK CONSTRAINT CK_tbl_SSCC_Counter_LastGS1SSCC;
GO

/* --- 5. Consecutive calls are unique and 22 chars --- */
UPDATE dbo.tbl_SSCC_Counter SET LastGS1SSCC = 0;

DECLARE @i INT = 0;
DECLARE @sscc NVARCHAR(22);
DECLARE @prev NVARCHAR(22);

WHILE @i < 5
BEGIN
    SET @sscc = NULL;
    EXEC dbo.sp_GetNextGS1SSCC @SSCC = @sscc OUTPUT;

    IF @sscc IS NULL
        OR LEN(@sscc) <> 22
        OR @sscc = @prev
        OR DATALENGTH(@sscc) <> 44 /* NVARCHAR: 22 chars * 2 bytes */
        THROW 51007, 'Test 5 failed: SSCC length or uniqueness.', 1;

    SET @prev = @sscc;
    SET @i += 1;
END;

PRINT N'Test 5 OK: five unique 22-character values';
GO

PRINT N'All tests passed.';
GO
