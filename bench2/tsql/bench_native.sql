-- Benchmark suite v2 - T-SQL natively compiled stored procedures (T-SQL -> C -> DLL, In-Memory OLTP).
-- Same algorithms as the C++/Java/Python suites. Run with sqlcmd against master. Creates database benchn.
-- Optional: sqlcmd variable LINESFILE = path (as seen by the server) to a "line i,i*7" file for the BULK INSERT test.
SET NOCOUNT ON;
IF DB_ID('benchn') IS NULL
BEGIN
    DECLARE @p NVARCHAR(400) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(400));
    EXEC('CREATE DATABASE benchn');
    EXEC('ALTER DATABASE benchn SET RECOVERY SIMPLE');
    EXEC('ALTER DATABASE benchn ADD FILEGROUP imoltp CONTAINS MEMORY_OPTIMIZED_DATA');
    EXEC('ALTER DATABASE benchn ADD FILE (NAME = ''imoltp'', FILENAME = ''' + @p + 'benchn_imoltp'') TO FILEGROUP imoltp');
END
GO
USE benchn;
GO
DROP PROCEDURE IF EXISTS dbo.p_int_lcg, dbo.p_collatz, dbo.p_leibniz, dbo.p_mandel, dbo.p_sin_sqrt, dbo.p_string,
    dbo.p_hashmap, dbo.p_hm_clear, dbo.p_rows_write, dbo.p_rows_read, dbo.p_rows_clear;
DROP TABLE IF EXISTS dbo.hm, dbo.rows_durable, dbo.bulk_lines;
GO
-- Hash map = memory-optimized table with a hash index, not logged (SCHEMA_ONLY) like an in-process map
CREATE TABLE dbo.hm (k BIGINT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 8388608), v BIGINT NOT NULL)
    WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_ONLY);
-- Durable rows = written to the transaction log on disk at commit
CREATE TABLE dbo.rows_durable (id BIGINT NOT NULL PRIMARY KEY NONCLUSTERED HASH WITH (BUCKET_COUNT = 8388608), txt VARCHAR(40) NOT NULL)
    WITH (MEMORY_OPTIMIZED = ON, DURABILITY = SCHEMA_AND_DATA);
CREATE TABLE dbo.bulk_lines (a VARCHAR(40) NOT NULL, b BIGINT NOT NULL);
GO
CREATE PROCEDURE dbo.p_int_lcg @n BIGINT, @acc BIGINT OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DECLARE @x BIGINT = 88172645, @i BIGINT = 0;
    SET @acc = 0;
    WHILE @i < @n
    BEGIN
        SET @x = (@x * 1103515245 + 12345) % 2147483648;
        SET @acc = @acc + @x % 65536;
        SET @i = @i + 1;
    END
END
GO
CREATE PROCEDURE dbo.p_collatz @n BIGINT, @steps BIGINT OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DECLARE @k BIGINT = 1, @v BIGINT;
    SET @steps = 0;
    WHILE @k <= @n
    BEGIN
        SET @v = @k;
        WHILE @v <> 1
        BEGIN
            IF @v % 2 = 1 SET @v = 3 * @v + 1; ELSE SET @v = @v / 2;
            SET @steps = @steps + 1;
        END
        SET @k = @k + 1;
    END
END
GO
CREATE PROCEDURE dbo.p_leibniz @n BIGINT, @r BIGINT OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DECLARE @s FLOAT = 0, @sign FLOAT = 1, @k BIGINT = 0;
    WHILE @k < @n
    BEGIN
        SET @s = @s + @sign / (2.0E0 * @k + 1.0E0);
        SET @sign = -@sign;
        SET @k = @k + 1;
    END
    SET @r = CAST(@s * 4.0E9 AS BIGINT);
END
GO
CREATE PROCEDURE dbo.p_mandel @w INT, @h INT, @maxi INT, @total BIGINT OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DECLARE @py INT = 0, @px INT, @it INT, @ci FLOAT, @cr FLOAT, @zr FLOAT, @zi FLOAT, @t FLOAT;
    SET @total = 0;
    WHILE @py < @h
    BEGIN
        SET @ci = -1.25E0 + 2.5E0 * @py / @h;
        SET @px = 0;
        WHILE @px < @w
        BEGIN
            SET @cr = -2.0E0 + 2.5E0 * @px / @w; SET @zr = 0; SET @zi = 0; SET @it = 0;
            WHILE @it < @maxi AND @zr * @zr + @zi * @zi <= 4.0E0
            BEGIN
                SET @t = @zr * @zr - @zi * @zi + @cr;
                SET @zi = 2.0E0 * @zr * @zi + @ci;
                SET @zr = @t;
                SET @it = @it + 1;
            END
            SET @total = @total + @it;
            SET @px = @px + 1;
        END
        SET @py = @py + 1;
    END
END
GO
CREATE PROCEDURE dbo.p_sin_sqrt @n BIGINT, @r BIGINT OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DECLARE @s FLOAT = 0, @i BIGINT = 0;
    WHILE @i < @n
    BEGIN
        SET @s = @s + SIN(@i * 0.001E0) * SQRT(CAST(@i AS FLOAT));
        SET @i = @i + 1;
    END
    SET @r = CAST(@s AS BIGINT);
END
GO
CREATE PROCEDURE dbo.p_string @n BIGINT, @acc BIGINT OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DECLARE @i BIGINT = 0, @s VARCHAR(48), @p INT;
    SET @acc = 0;
    WHILE @i < @n
    BEGIN
        -- CONCAT and CHARINDEX are not available in natively compiled modules: use + and a manual scan
        SET @s = 'line ' + CONVERT(VARCHAR(20), @i) + ',' + CONVERT(VARCHAR(20), @i * 7);
        SET @p = 1;
        WHILE SUBSTRING(@s, @p, 1) <> ',' SET @p = @p + 1;
        SET @acc = @acc + CONVERT(BIGINT, SUBSTRING(@s, @p + 1, 40)) + LEN(@s);
        SET @i = @i + 1;
    END
END
GO
CREATE PROCEDURE dbo.p_hashmap @n BIGINT, @hit BIGINT OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DECLARE @i BIGINT = 0, @v BIGINT;
    SET @hit = 0;
    WHILE @i < @n
    BEGIN
        INSERT dbo.hm (k, v) VALUES ((@i * 2654435761) % 4294967296, @i);
        SET @i = @i + 1;
    END
    SET @i = 0;
    WHILE @i < @n
    BEGIN
        SET @v = NULL;
        SELECT @v = v FROM dbo.hm WHERE k = (@i * 2654435761) % 4294967296;
        IF @v IS NOT NULL SET @hit = @hit + @v % 2;
        SET @i = @i + 1;
    END
END
GO
CREATE PROCEDURE dbo.p_hm_clear
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DELETE FROM dbo.hm;
END
GO
CREATE PROCEDURE dbo.p_rows_write @n BIGINT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DECLARE @i BIGINT = 0;
    WHILE @i < @n
    BEGIN
        INSERT dbo.rows_durable (id, txt) VALUES (@i, 'line ' + CONVERT(VARCHAR(20), @i) + ',' + CONVERT(VARCHAR(20), @i * 7));
        SET @i = @i + 1;
    END
END
GO
CREATE PROCEDURE dbo.p_rows_read @n BIGINT, @sum BIGINT OUTPUT
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    -- read every row back (point lookup by key) and parse the number after the comma
    DECLARE @i BIGINT = 0, @s VARCHAR(40), @p INT;
    SET @sum = 0;
    WHILE @i < @n
    BEGIN
        SELECT @s = txt FROM dbo.rows_durable WHERE id = @i;
        SET @p = 1;
        WHILE SUBSTRING(@s, @p, 1) <> ',' SET @p = @p + 1;
        SET @sum = @sum + CONVERT(BIGINT, SUBSTRING(@s, @p + 1, 40));
        SET @i = @i + 1;
    END
END
GO
CREATE PROCEDURE dbo.p_rows_clear
WITH NATIVE_COMPILATION, SCHEMABINDING
AS BEGIN ATOMIC WITH (TRANSACTION ISOLATION LEVEL = SNAPSHOT, LANGUAGE = N'us_english')
    DELETE FROM dbo.rows_durable;
END
GO
------------------------------------------------------------------ driver (best of 3, wall clock + CPU time)
CREATE TABLE #r (name VARCHAR(40), units BIGINT, us BIGINT, cpu_ms BIGINT, chk BIGINT);
DECLARE @k INT = 0, @t0 DATETIME2(7), @c0 INT, @c1 INT, @chk BIGINT;
WHILE @k < 3
BEGIN
    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; SET @t0 = SYSDATETIME();
    EXEC dbo.p_int_lcg 100000000, @chk OUTPUT;
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    INSERT #r VALUES ('int_lcg', 100000000, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()), @c1 - @c0, @chk);

    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; SET @t0 = SYSDATETIME();
    EXEC dbo.p_collatz 1000000, @chk OUTPUT;
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    INSERT #r VALUES ('int_collatz', 131434424, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()), @c1 - @c0, @chk);

    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; SET @t0 = SYSDATETIME();
    EXEC dbo.p_leibniz 100000000, @chk OUTPUT;
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    INSERT #r VALUES ('float_leibniz', 100000000, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()), @c1 - @c0, @chk);

    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; SET @t0 = SYSDATETIME();
    EXEC dbo.p_mandel 1000, 1000, 200, @chk OUTPUT;
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    INSERT #r VALUES ('float_mandelbrot', @chk, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()), @c1 - @c0, @chk);

    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; SET @t0 = SYSDATETIME();
    EXEC dbo.p_sin_sqrt 20000000, @chk OUTPUT;
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    INSERT #r VALUES ('float_sin_sqrt', 20000000, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()), @c1 - @c0, @chk);

    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; SET @t0 = SYSDATETIME();
    EXEC dbo.p_string 5000000, @chk OUTPUT;
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    INSERT #r VALUES ('string_format_parse', 5000000, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()), @c1 - @c0, @chk);

    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; SET @t0 = SYSDATETIME();
    EXEC dbo.p_hashmap 5000000, @chk OUTPUT;
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    INSERT #r VALUES ('hashmap_insert_lookup', 5000000, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()), @c1 - @c0, @chk);
    EXEC dbo.p_hm_clear;

    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; SET @t0 = SYSDATETIME();
    EXEC dbo.p_rows_write 5000000;
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    INSERT #r VALUES ('rows_write_durable', 5000000, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()), @c1 - @c0, 5000000);

    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; SET @t0 = SYSDATETIME();
    EXEC dbo.p_rows_read 5000000, @chk OUTPUT;
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    INSERT #r VALUES ('rows_read_parse', 5000000, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()), @c1 - @c0, @chk);
    EXEC dbo.p_rows_clear;

    IF N'$(LINESFILE)' <> N'none'
    BEGIN
        TRUNCATE TABLE dbo.bulk_lines;
        SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; SET @t0 = SYSDATETIME();
        BULK INSERT dbo.bulk_lines FROM '$(LINESFILE)' WITH (FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', TABLOCK);
        SELECT @chk = SUM(b) FROM dbo.bulk_lines OPTION (MAXDOP 1);
        SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
        INSERT #r VALUES ('io_read_parse_lines(BULK INSERT)', 5000000, DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()), @c1 - @c0, @chk);
    END
    SET @k += 1;
END
SELECT CONCAT(name, ',', MIN(units), ',', FORMAT(MIN(us) / 1e6, '0.0000'), ',', FORMAT(MIN(us) * 1000.0 / MIN(units), '0.000'), ',', MIN(chk),
              ',cpu_ns=', FORMAT(MIN(cpu_ms) * 1e6 / MIN(units), '0.000'))
FROM #r GROUP BY name ORDER BY MIN(CASE name WHEN 'int_lcg' THEN 1 WHEN 'int_collatz' THEN 2 WHEN 'float_leibniz' THEN 3 WHEN 'float_mandelbrot' THEN 4
    WHEN 'float_sin_sqrt' THEN 5 WHEN 'string_format_parse' THEN 6 WHEN 'hashmap_insert_lookup' THEN 7 WHEN 'rows_write_durable' THEN 8 ELSE 9 END);
