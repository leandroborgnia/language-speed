SET NOCOUNT ON;
DECLARE @t0 DATETIME2, @ms INT, @n BIGINT, @acc BIGINT, @str NVARCHAR(MAX), @k INT = 0;
WHILE @k < 3
BEGIN
    SET @n = 100000000; SET @t0 = SYSDATETIME();
    SELECT @acc = SUM((value * 2654435761) % 65536) FROM GENERATE_SERIES(CAST(1 AS BIGINT), @n) OPTION (MAXDOP 1);
    SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
    PRINT CONCAT('int_setbased,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/row');

    SET @n = 1000000; SET @t0 = SYSDATETIME();
    SELECT @str = STRING_AGG(CAST(value AS NVARCHAR(MAX)), ',') FROM GENERATE_SERIES(CAST(0 AS BIGINT), @n - 1) OPTION (MAXDOP 1);
    SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
    PRINT CONCAT('string_build(STRING_AGG),', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/item');
    SET @t0 = SYSDATETIME();
    SELECT @acc = SUM(CAST(value AS BIGINT)) FROM STRING_SPLIT(@str, ',') OPTION (MAXDOP 1);
    SET @ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
    PRINT CONCAT('string_split_parse,', @n, ',', @ms, 'ms,', @ms * 1e6 / @n, ' ns/item');
    SET @k += 1;
END
