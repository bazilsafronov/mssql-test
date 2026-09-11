SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/*
    Supporting objects from the assignment.
    Deploy this script only if the objects do not already exist in the target database.
*/

IF OBJECT_ID(N'dbo.tbl_SSCC_Counter', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.tbl_SSCC_Counter
    (
        LastGS1SSCC BIGINT NOT NULL
            CONSTRAINT DF_tbl_SSCC_Counter_LastGS1SSCC DEFAULT (0)
            CONSTRAINT CK_tbl_SSCC_Counter_LastGS1SSCC
                CHECK (LastGS1SSCC >= 0 AND LastGS1SSCC <= 999999999)
    );
END
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.tbl_SSCC_Counter')
      AND name = N'CK_tbl_SSCC_Counter_LastGS1SSCC'
)
BEGIN
    ALTER TABLE dbo.tbl_SSCC_Counter WITH CHECK
        ADD CONSTRAINT CK_tbl_SSCC_Counter_LastGS1SSCC
        CHECK (LastGS1SSCC >= 0 AND LastGS1SSCC <= 999999999);
END
GO

/* Enforce a single-row counter (idempotent). */
IF COL_LENGTH(N'dbo.tbl_SSCC_Counter', N'Singleton') IS NULL
BEGIN
    ALTER TABLE dbo.tbl_SSCC_Counter ADD
        Singleton AS CONVERT(TINYINT, 1) PERSISTED
            CONSTRAINT UQ_tbl_SSCC_Counter_Singleton UNIQUE;
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.tbl_SSCC_Counter)
BEGIN
    INSERT INTO dbo.tbl_SSCC_Counter (LastGS1SSCC) VALUES (0);
END
GO

CREATE OR ALTER FUNCTION dbo.fn_GS1SSCC_CheckDigit
(
    @Digits NVARCHAR(20)
)
RETURNS INT
AS
BEGIN
    DECLARE @len INT;
    DECLARE @i INT;
    DECLARE @sum INT = 0;
    DECLARE @digit INT;
    DECLARE @weight INT;

    IF @Digits IS NULL
        OR LEN(@Digits) = 0
        OR @Digits LIKE N'%[^0-9]%'
        RETURN NULL;

    SET @len = LEN(@Digits);
    SET @i = @len;

    /* GS1 Mod 10: rightmost digit weight 3, then 1, 3, 1, ... */
    WHILE @i >= 1
    BEGIN
        SET @digit = CONVERT(INT, SUBSTRING(@Digits, @i, 1));
        SET @weight = CASE WHEN ((@len - @i) % 2) = 0 THEN 3 ELSE 1 END;
        SET @sum += @digit * @weight;
        SET @i -= 1;
    END;

    RETURN (10 - (@sum % 10)) % 10;
END
GO

CREATE OR ALTER FUNCTION dbo.fn_GenerateGS1SSCC
(
    @SSCC17 NVARCHAR(17)
)
RETURNS NVARCHAR(25)
AS
BEGIN
    DECLARE @checkDigit INT;

    IF @SSCC17 IS NULL
        OR LEN(@SSCC17) <> 17
        OR @SSCC17 LIKE N'%[^0-9]%'
        RETURN NULL;

    SET @checkDigit = dbo.fn_GS1SSCC_CheckDigit(@SSCC17);

    IF @checkDigit IS NULL
        RETURN NULL;

    RETURN N'(00)' + @SSCC17 + CONVERT(NVARCHAR(1), @checkDigit);
END
GO
