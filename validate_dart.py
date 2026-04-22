import subprocess
import sys

dart_file = r"c:\Users\Wong Yan Thong\Documents\Demo\Swaply\lib\views\screens\profile\profile_screen_new.dart"

try:
    result = subprocess.run(
        ["dart", "analyze", dart_file],
        capture_output=True,
        text=True,
        timeout=30
    )
    print("STDOUT:", result.stdout)
    print("STDERR:", result.stderr)
    print("Return code:", result.returncode)
except Exception as e:
    print(f"Error running dart analyze: {e}")
