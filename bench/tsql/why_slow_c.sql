SET NOCOUNT ON;
DECLARE @c1 INT, @c0 INT, @n BIGINT = 20000000, @acc BIGINT, @k INT = 0;
WHILE @k < 3
BEGIN
    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    SELECT @acc = SUM((value * 2654435761) % 65536) FROM GENERATE_SERIES(CAST(1 AS BIGINT), @n) OPTION (MAXDOP 1);
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; PRINT CONCAT('C literal = NUMERIC(10,0), ', (@c1 - @c0) * 1e6 / @n, ' ns/row (cpu)');
    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    SELECT @acc = SUM((value * CAST(2654435761 AS BIGINT)) % 65536) FROM GENERATE_SERIES(CAST(1 AS BIGINT), @n) OPTION (MAXDOP 1);
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; PRINT CONCAT('C literal = BIGINT,        ', (@c1 - @c0) * 1e6 / @n, ' ns/row (cpu)');
    SELECT @c0 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID;
    SELECT @acc = COUNT_BIG(*) FROM GENERATE_SERIES(CAST(1 AS BIGINT), @n) OPTION (MAXDOP 1);
    SELECT @c1 = cpu_time FROM sys.dm_exec_requests WHERE session_id = @@SPID; PRINT CONCAT('C generate + count only,   ', (@c1 - @c0) * 1e6 / @n, ' ns/row (cpu)');
    SET @k += 1;
END

