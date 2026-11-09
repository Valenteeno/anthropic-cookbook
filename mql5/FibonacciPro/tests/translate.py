"""Translate an MQL5 indicator into C++ against mql5_stubs.h for a g++ -fsyntax-only check."""
import re, sys

src = open(sys.argv[1], encoding="utf-8").read()
out = []
for line in src.split("\n"):
    if line.startswith("#property") or line.startswith("#include"):
        out.append("")
        continue
    if line.startswith("input "):
        line = line[len("input "):]
    out.append(line)
code = "\n".join(out)

# Array reference parameters and dynamic arrays.
code = re.sub(r"\b(const\s+)?(\w+)\s*&\s*(\w+)\[\]", r"\1MQLArr<\2> &\3", code)
code = re.sub(r"\b(string|MqlRates|double|int|long)\s+(\w+)\[\];", r"MQLArr<\1> \2;", code)

# Colours used anywhere become constants.
colors = sorted(set(re.findall(r"\bclr(?!NONE\b)\w+", code)))
header = ['#include "mql5_stubs.h"']
for i, c in enumerate(colors):
    header.append(f"const color {c}={i+1};")

# Prototypes for every top-level function (MQL5 needs no declaration order; C++ does).
func_re = re.compile(r"^((?:const\s+)?[A-Za-z_]\w*)\s+([A-Za-z_]\w*)\(([^()]*)\)\s*(\{.*)?$", re.M)
protos = []
def strip_defaults(params):
    return re.sub(r"=\s*[^,]+", "", params)
def repl(m):
    ret, name, params, rest = m.group(1), m.group(2), m.group(3), m.group(4) or ""
    if ret in ("return", "else", "struct", "typedef"):
        return m.group(0)
    protos.append(f"{ret} {name}({params});")
    return f"{ret} {name}({strip_defaults(params)}){rest}"
body = func_re.sub(repl, code)

# Prototypes must follow the struct definitions they mention.
marker = "// PURE_GEOMETRY_BEGIN"
idx = body.index(marker)
result = "\n".join(header) + "\n" + body[:idx] + "\n" + "\n".join(protos) + "\n" + body[idx:]
open(sys.argv[2], "w", encoding="utf-8").write(result)
print(f"{len(protos)} functions, {len(colors)} colours")
