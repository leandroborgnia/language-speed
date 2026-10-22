-- Single-threaded T-SQL equivalents (SQL Server 2022+ for GENERATE_SERIES / LEFT_SHIFT).
-- Run in SSMS / sqlcmd. OPTION (MAXDOP 1) keeps set-based queries single-threaded.
SET NOCOUNT ON;
DECLARE @t0 DATETIME2, @ms INT, @n BIGINT, @i BIGINT;

------------------------------------------------------------ 1. INT, procedural (WHILE)
DECLARE @x BIGINT = 88172645, @acc BIGINT = 0;
SET @n = 1000000; SET @i = 0; SET @t0 = SYSDATETIME();
WHILE @i < @n
BEGIN
    SET @x = (@x ^ LEFT_SHIFT(@x, 13)) & 0x7FFFFFFFFFFF;
    SET @x = @x ^ RIGHT_SHIFT(@x, 7);
    SET @acc = @acc + (@x & 0xFFFF);
    SET @i += 1;
END
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('int_while,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/op');

------------------------------------------------------------ 2. INT, set-based
SET @n = 100000000; SET @t0 = SYSDATETIME();
SELECT @acc = SUM((value * 2654435761) % 65536) FROM GENERATE_SERIES(CAST(1 AS BIGINT), @n) OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('int_setbased,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/row');

------------------------------------------------------------ 3. FLOAT Leibniz, procedural and set-based
DECLARE @s FLOAT = 0, @sign FLOAT = 1;
SET @n = 1000000; SET @i = 0; SET @t0 = SYSDATETIME();
WHILE @i < @n BEGIN SET @s += @sign / (2.0E0 * @i + 1.0E0); SET @sign = -@sign; SET @i += 1; END
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('float_leibniz_while,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/op  pi~', @s * 4);

SET @n = 100000000; SET @t0 = SYSDATETIME();
SELECT @s = SUM(CASE WHEN value % 2 = 0 THEN 1.0E0 ELSE -1.0E0 END / (2.0E0 * value + 1.0E0))
FROM GENERATE_SERIES(CAST(0 AS BIGINT), @n - 1) OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('float_leibniz_setbased,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/row  pi~', @s * 4);

------------------------------------------------------------ 4. DECIMAL(18,4) – same formula as the other languages
DECLARE @d DECIMAL(38,4) = 0, @rate DECIMAL(9,4) = 1.0375;
SET @n = 1000000; SET @i = 0; SET @t0 = SYSDATETIME();
WHILE @i < @n BEGIN SET @d += ROUND(CAST((@i % 10000) / 100.0 AS DECIMAL(18,2)) * @rate, 4); SET @i += 1; END
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('decimal_while,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/op');

SET @n = 5000000; SET @t0 = SYSDATETIME();
SELECT @d = SUM(ROUND(CAST((value % 10000) / 100.0 AS DECIMAL(18,2)) * @rate, 4))
FROM GENERATE_SERIES(CAST(0 AS BIGINT), @n - 1) OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('decimal_setbased,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/row  sum=', @d);

------------------------------------------------------------ 5. STRING build + split + parse
DECLARE @str NVARCHAR(MAX);
SET @n = 1000000; SET @t0 = SYSDATETIME();
SELECT @str = STRING_AGG(CAST(value AS NVARCHAR(MAX)), ',') FROM GENERATE_SERIES(CAST(0 AS BIGINT), @n - 1) OPTION (MAXDOP 1);
SELECT @acc = SUM(CAST(value AS BIGINT)) FROM STRING_SPLIT(@str, ',') OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('string_build_split_parse,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/item');

------------------------------------------------------------ 6. "IO": unstructured JSON as NVARCHAR(MAX) – write to table, read back, parse
DROP TABLE IF EXISTS #doc; CREATE TABLE #doc (id INT PRIMARY KEY, body NVARCHAR(MAX));
SET @n = 500000; SET @t0 = SYSDATETIME();
INSERT #doc (id, body)
SELECT 1, (SELECT value AS id, CONCAT('line ', value) AS name, value * 7 AS v
           FROM GENERATE_SERIES(CAST(0 AS BIGINT), @n - 1) FOR JSON PATH) OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
DECLARE @bytes BIGINT = (SELECT DATALENGTH(body) FROM #doc);
PRINT CONCAT('json_serialize_write,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/object, bytes=', @bytes);

SET @t0 = SYSDATETIME();
SELECT @acc = SUM(j.v) FROM #doc d CROSS APPLY OPENJSON(d.body) WITH (v BIGINT '$.v') j OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('json_read_parse,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/object, sum=', @acc);

------------------------------------------------------------ 7. Row IO: insert N narrow rows, read them back
DROP TABLE IF EXISTS #lines; CREATE TABLE #lines (id BIGINT PRIMARY KEY, txt VARCHAR(40));
SET @n = 5000000; SET @t0 = SYSDATETIME();
INSERT #lines WITH (TABLOCK) SELECT value, CONCAT('line ', value, ',', value * 7) FROM GENERATE_SERIES(CAST(0 AS BIGINT), @n - 1) OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('row_insert,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/row');
SET @t0 = SYSDATETIME();
SELECT @acc = SUM(CAST(SUBSTRING(txt, CHARINDEX(',', txt) + 1, 40) AS BIGINT)) FROM #lines OPTION (MAXDOP 1);
SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
PRINT CONCAT('row_read_parse,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/row, sum=', @acc);
