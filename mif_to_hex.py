import re
import os

def convert_mif_to_hex(mif_path):
    hex_path = os.path.splitext(mif_path)[0] + ".hex"

    with open(mif_path, "r") as f:
        lines = f.readlines()

    content_started = False
    hex_values = []

    for line in lines:
        line = line.strip()

        # Detect start of CONTENT block
        if line.upper().startswith("CONTENT"):
            content_started = True
            continue
        if not content_started:
            continue

        # Detect end of CONTENT
        if line.upper().startswith("END"):
            break

        # Match valid memory lines:  e.g.   0001 : 4;
        match = re.match(r"([0-9A-Fa-f]+)\s*:\s*([0-9A-Fa-f]+)\s*;", line)
        if match:
            addr, value = match.groups()
            hex_values.append(value)

    # Write as $readmemh-compatible hex file
    with open(hex_path, "w") as out:
        for v in hex_values:
            out.write(v + "\n")

    print(f"Converted {mif_path} → {hex_path}")


# Convert all .mif files in the current folder
for file in os.listdir("."):
    if file.lower().endswith(".mif"):
        convert_mif_to_hex(file)
