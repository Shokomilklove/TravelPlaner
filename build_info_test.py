import sys
import os

file_path = os.environ.get("BUILD_INFO_FILE", "build-info.txt")

if not os.path.exists(file_path):
    print("FAIL: build-info.txt does not exist")
    sys.exit(1)

print("PASS: build-info.txt exists")

with open(file_path, "r") as file:
    content = file.read()

print("Build info:")
print(content)

sys.exit(0)