$b   = 'D:\dev\learning\language-speed\bench2'
$py  = 'D:\dev\learning\language-speed\.venv\Scripts\python.exe'
$sql = 'D:\dev\programs\SQLServer-Native\tools\sqlcmd.exe'
$pw  = Get-Content 'D:\dev\programs\SQLServer-Native\sa-password.txt' -Raw
& $py "$b\python\bench_numba.py" 2>&1 | Set-Content "$b\results\python_numba.csv"
& $sql -S 'tcp:localhost,14330' -U sa -P $pw -C -h -1 -W -v "LINESFILE=D:\dev\programs\SQLServer-Native\bulk\lines.txt" `
      -i "$b\tsql\bench_native.sql" 2>&1 | Set-Content "$b\results\tsql_native_windows.csv"
# Same suite on the Linux/Docker instance (no BULK INSERT file there)
Stop-Service 'MSSQL$BENCH' -ErrorAction SilentlyContinue   # needs admin; ignored if it fails
docker start mssql | Out-Null
Copy-Item "$b\tsql\bench_native.sql" 'D:\dev\programs\SQLServer\scripts\' -Force
$dpw = Get-Content 'D:\dev\programs\SQLServer\sa-password.txt' -Raw
for ($i = 0; $i -lt 40; $i++) { docker exec mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $dpw -C -Q "SELECT 1" *> $null; if ($LASTEXITCODE -eq 0) { break }; Start-Sleep 3 }
docker exec mssql /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $dpw -C -h -1 -W -v LINESFILE=none -i /scripts/bench_native.sql 2>&1 |
    Set-Content "$b\results\tsql_native_docker_linux.csv"
docker stop mssql | Out-Null
'done'
