import os
import sys


def main():
    if len(sys.argv) != 2:
        print("Usage: python search_word.py <word>")
        sys.exit(1)

    word = sys.argv[1]

    file_path = os.environ.get("FILE_TO_TEST")

    if not file_path:
        print("Error: FILE_TO_TEST environment variable is not set")
        sys.exit(1)

    if not os.path.isfile(file_path):
        print(f"Error: file does not exist: {file_path}")
        sys.exit(1)

    with open(file_path, "r", encoding="utf-8") as file:
        content = file.read()

    if word in content:
        print(f"Word '{word}' found in {file_path}")
        sys.exit(0)
    else:
        print(f"Word '{word}' not found in {file_path}")
        sys.exit(1)


if __name__ == "__main__":
    main()