# Runs every v2 suite sequentially (nothing else competing for the CPU). Results -> bench2\results\*.csv
$b   = 'D:\dev\learning\language-speed\bench2'
$tmp = $env:TEMP
$py  = 'D:\dev\learning\language-speed\.venv\Scripts\python.exe'
$sql = 'D:\dev\programs\SQLServer-Native\tools\sqlcmd.exe'
$pw  = Get-Content 'D:\dev\programs\SQLServer-Native\sa-password.txt' -Raw
New-Item -ItemType Directory -Force "$b\results" | Out-Null

& "$b\cpp\bench.exe" $tmp                                  | Set-Content "$b\results\cpp.csv"
& java -Xmx8g -cp "$b\java" Bench $tmp                    | Set-Content "$b\results\java.csv"
& $py "$b\python\bench_numba.py"                     2>&1 | Set-Content "$b\results\python_numba.csv"
Push-Location "$b\python"; & $py bench_cython.py $tmp 2>&1 | Set-Content "$b\results\python_cython.csv"; Pop-Location
& $sql -S 'tcp:localhost,14330' -U sa -P $pw -C -h -1 -W -v "LINESFILE=D:\dev\programs\SQLServer-Native\bulk\lines.txt" `
      -i "$b\tsql\bench_native.sql" 2>&1 | Set-Content "$b\results\tsql_native_windows.csv"
'done'

