import re

from argparse import ArgumentParser
from datetime import date

parser = ArgumentParser()
parser.add_argument("latest_release", help="Latest release info from `gh release view > {lastest_release}`.")
parser.add_argument("releases", help="File to write release info to.")
args = parser.parse_args()

BASE = "https://raw.githubusercontent.com/DiseaseOntology/SymptomOntology"
PATH = "src/ontology"

# parse release info
with open(args.latest_release, "r") as f:
    txt = f.read()
    m = re.search("tag:\t([^\n]+).*\n--\n(.*)", txt, re.DOTALL)
tag = m.group(1).strip()
description = m.group(2).strip()
this_year = int(tag.split("-")[0].lstrip("v"))

# add to releases
with open(args.releases, "r") as f:
    lines = f.readlines()

updated = False
new_year = False
md = []
for line in lines:
    line = line.strip()
    if not updated and line.startswith("## 202"):
        year = int(line.split(" ")[1])
        if this_year > year:
            new_year = True
            md.append(f"## {this_year} Releases")
        else:
            md.append(line)
        # release details including links to files as table
        md.append("")
        md.append(f"### [{tag}](https://github.com/DiseaseOntology/SymptomOntology/tree/{tag})")
        md.append("")
        md.append(description)
        md.append("")
        md.append("|  | OWL | OBO | JSON |")
        md.append("| --- | --- | --- | --- |")
        md.append(f"| Symptom Ontology | [symp.owl]({BASE}/{tag}/{PATH}/symp.owl) | [symp.obo]({BASE}/{tag}/{PATH}/symp.obo) | [symp.json]({BASE}/{tag}/{PATH}/symp.json) |")
        if new_year:
            md.append("")
            md.append(line)
        updated = True
    else:
        md.append(line)

lines = "\n".join(md)
with open(args.releases, "w") as f:
    f.write(lines)
