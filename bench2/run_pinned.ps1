# All suites pinned to the 8 P-cores (CPUs 0,1,6-9,18,19 = mask C03C3) so every language runs on the same core type.
$b   = 'D:\dev\learning\language-speed\bench2'
$tmp = $env:TEMP
$py  = 'D:\dev\learning\language-speed\.venv\Scripts\python.exe'
$sql = 'D:\dev\programs\SQLServer-Native\tools\sqlcmd.exe'
$pw  = Get-Content 'D:\dev\programs\SQLServer-Native\sa-password.txt' -Raw
$r   = "$b\results_pinned"; New-Item -ItemType Directory -Force $r | Out-Null

cmd /c "start /affinity C03C3 /b /wait `"`" `"$b\cpp\bench.exe`" `"$tmp`" > `"$r\cpp.csv`""
cmd /c "start /affinity C03C3 /b /wait `"`" java -Xmx8g -cp `"$b\java`" Bench `"$tmp`" > `"$r\java.csv`""
cmd /c "start /affinity C03C3 /b /wait `"`" `"$py`" `"$b\python\bench_numba.py`" > `"$r\python_numba.csv`" 2>&1"
Push-Location "$b\python"
cmd /c "start /affinity C03C3 /b /wait `"`" `"$py`" bench_cython.py `"$tmp`" > `"$r\python_cython.csv`" 2>&1"
Pop-Location

& $sql -S 'tcp:localhost,14330' -U sa -P $pw -C -Q "ALTER SERVER CONFIGURATION SET PROCESS AFFINITY CPU = 0, 1, 6 TO 9, 18, 19;"
foreach ($run in 1, 2) {
    & $sql -S 'tcp:localhost,14330' -U sa -P $pw -C -h -1 -W -v "LINESFILE=D:\dev\programs\SQLServer-Native\bulk\lines.txt" `
          -i "$b\tsql\bench_native.sql" 2>&1 | Set-Content "$r\tsql_native_windows_run$run.csv"
}
'done'
