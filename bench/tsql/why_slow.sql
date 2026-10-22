-- Experiments isolating why T-SQL is slow. Run against master; creates database benchdb.
SET NOCOUNT ON;
IF DB_ID('benchdb') IS NULL
BEGIN
    CREATE DATABASE benchdb;
    ALTER DATABASE benchdb ADD FILEGROUP imoltp CONTAINS MEMORY_OPTIMIZED_DATA;
    ALTER DATABASE benchdb ADD FILE (NAME = 'imoltp', FILENAME = '/var/opt/mssql/data/benchdb_imoltp') TO FILEGROUP imoltp;
END
GO
USE benchdb;
GO
CREATE OR ALTER PROCEDURE dbo.native_loop @n BIGINT, @acc BIGINT OUTPUT, @s FLOAT OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DECLARE @i BIGINT = 0, @x BIGINT = 88172645, @sign FLOAT = 1;
    SET @acc = 0; SET @s = 0;
    WHILE @i < @n
    BEGIN
        SET @x = (@x * 1103515245 + 12345) % 2147483648;
        SET @acc = @acc + @x % 65536;
        SET @s = @s + @sign / (2.0E0 * @i + 1.0E0);
        SET @sign = -@sign;
        SET @i = @i + 1;
    END
END
GO
CREATE OR ALTER PROCEDURE dbo.interp_loop @n BIGINT, @acc BIGINT OUTPUT, @s FLOAT OUTPUT
AS BEGIN
    DECLARE @i BIGINT = 0, @x BIGINT = 88172645, @sign FLOAT = 1;
    SET @acc = 0; SET @s = 0;
    WHILE @i < @n
    BEGIN
        SET @x = (@x * 1103515245 + 12345) % 2147483648;
        SET @acc = @acc + @x % 65536;
        SET @s = @s + @sign / (2.0E0 * @i + 1.0E0);
        SET @sign = -@sign;
        SET @i = @i + 1;
    END
END
GO
DECLARE @t0 DATETIME2, @ms INT, @n BIGINT, @i BIGINT, @acc BIGINT, @s FLOAT;

-- A. Pure statement overhead: loop that does nothing but count
SET @n = 2000000; SET @i = 0; SET @t0 = SYSDATETIME();
WHILE @i < @n SET @i += 1;
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('A empty WHILE loop,                ', @ms * 1e6 / @n, ' ns/iteration');

-- B. Same loop body: interpreted vs natively compiled (T-SQL -> C -> DLL)
SET @n = 1000000; SET @t0 = SYSDATETIME();
EXEC dbo.interp_loop @n, @acc OUTPUT, @s OUTPUT;
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('B interpreted proc (5 SETs),       ', @ms * 1e6 / @n, ' ns/iteration  chk=', @acc);
SET @n = 20000000; SET @t0 = SYSDATETIME();
EXEC dbo.native_loop @n, @acc OUTPUT, @s OUTPUT;
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('B natively compiled proc,          ', @ms * 1e6 / @n, ' ns/iteration  pi~', @s * 4);

-- C. Literal typing: 2654435761 > INT max, so SQL types it NUMERIC(10,0) -> decimal math per row
SET @n = 20000000; SET @t0 = SYSDATETIME();
SELECT @acc = SUM((value * 2654435761) % 65536) FROM GENERATE_SERIES(CAST(1 AS BIGINT), @n) OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('C set-based, literal = NUMERIC,    ', @ms * 1e6 / @n, ' ns/row');
SET @t0 = SYSDATETIME();
SELECT @acc = SUM((value * CAST(2654435761 AS BIGINT)) % 65536) FROM GENERATE_SERIES(CAST(1 AS BIGINT), @n) OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('C set-based, literal = BIGINT,     ', @ms * 1e6 / @n, ' ns/row');
SET @t0 = SYSDATETIME();
SELECT @acc = COUNT_BIG(*) FROM GENERATE_SERIES(CAST(1 AS BIGINT), @n) OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('C just generating + counting rows, ', @ms * 1e6 / @n, ' ns/row');

-- D. Row mode vs batch mode on stored data (columnstore)
DROP TABLE IF EXISTS dbo.nums;
CREATE TABLE dbo.nums (k BIGINT NOT NULL, f FLOAT NOT NULL, d DECIMAL(18,2) NOT NULL);
INSERT dbo.nums WITH (TABLOCK) SELECT value, value, (value % 10000) / 100.0 FROM GENERATE_SERIES(CAST(0 AS BIGINT), @n - 1) OPTION (MAXDOP 1);
CREATE CLUSTERED COLUMNSTORE INDEX cci ON dbo.nums WITH (MAXDOP = 1);
DECLARE @d DECIMAL(38,4);
SET @t0 = SYSDATETIME();
SELECT @s = SUM(CASE WHEN k % 2 = 0 THEN 1.0E0 ELSE -1.0E0 END / (2.0E0 * f + 1.0E0)) FROM dbo.nums
OPTION (MAXDOP 1, USE HINT('DISALLOW_BATCH_MODE'));
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('D float sum, ROW mode,             ', @ms * 1e6 / @n, ' ns/row  pi~', @s * 4);
SET @t0 = SYSDATETIME();
SELECT @s = SUM(CASE WHEN k % 2 = 0 THEN 1.0E0 ELSE -1.0E0 END / (2.0E0 * f + 1.0E0)) FROM dbo.nums OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('D float sum, BATCH mode,           ', @ms * 1e6 / @n, ' ns/row  pi~', @s * 4);
SET @t0 = SYSDATETIME();
SELECT @d = SUM(ROUND(d * CAST(1.0375 AS DECIMAL(9,4)), 4)) FROM dbo.nums OPTION (MAXDOP 1, USE HINT('DISALLOW_BATCH_MODE'));
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('D decimal sum, ROW mode,           ', @ms * 1e6 / @n, ' ns/row');
SET @t0 = SYSDATETIME();
SELECT @d = SUM(ROUND(d * CAST(1.0375 AS DECIMAL(9,4)), 4)) FROM dbo.nums OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('D decimal sum, BATCH mode,         ', @ms * 1e6 / @n, ' ns/row');

-- E. VARCHAR(8000) vs NVARCHAR(MAX) string handling
DECLARE @v VARCHAR(8000), @m NVARCHAR(MAX), @k INT;
SET @n = 200000; SET @k = 0; SET @t0 = SYSDATETIME();
WHILE @k < @n BEGIN SET @v = CONCAT('line ', @k, ',', @k * 7); SET @k += 1; END
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('E CONCAT into VARCHAR(8000),       ', @ms * 1e6 / @n, ' ns/op');
SET @k = 0; SET @t0 = SYSDATETIME();
WHILE @k < @n BEGIN SET @m = CONCAT(N'line ', @k, N',', @k * 7); SET @k += 1; END
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('E CONCAT into NVARCHAR(MAX),       ', @ms * 1e6 / @n, ' ns/op');
GO
