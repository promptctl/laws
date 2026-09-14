# Task: write the clean-room specification of `stamp`

Below is the complete source of a small command-line program. Write its clean-room
behavioral specification as one Markdown file: everything an independent team needs to
reimplement its externally observable behavior without ever seeing this source. Output
only the specification. Describe only behavior this source actually has. Do not add
behavior, and do not describe implementation internals.

## Source: `stamp.py`

```python
#!/usr/bin/env python3
import os, sys, time

USAGE = "usage: stamp [-u] [-f FORMAT] FILE"

def main(argv):
    utc = False
    fmt = os.environ.get("STAMP_FORMAT", "%Y-%m-%dT%H:%M:%S")
    args = argv[1:]
    while args and args[0].startswith("-"):
        flag = args.pop(0)
        if flag == "-u":
            utc = True
        elif flag == "-f":
            if not args:
                print(USAGE, file=sys.stderr)
                return 2
            fmt = args.pop(0)
        else:
            print(f"stamp: unknown option {flag}", file=sys.stderr)
            return 2
    if len(args) != 1:
        print(USAGE, file=sys.stderr)
        return 2
    path = args[0]
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError as e:
        print(f"stamp: {path}: {e.strerror}", file=sys.stderr)
        return 1
    now = time.gmtime() if utc else time.localtime()
    prefix = time.strftime(fmt, now)
    for line in lines:
        print(f"{prefix} {line}")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

## Reader

A team that will rebuild `stamp` in another language and will never see this source.
