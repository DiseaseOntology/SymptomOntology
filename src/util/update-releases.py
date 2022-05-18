import subprocess

from argparse import ArgumentParser
from datetime import date

BASE = "https://raw.githubusercontent.com/DiseaseOntology/SymptomOntology"
PATH = "src/ontology"

parser = ArgumentParser()
parser.add_argument("releases")
args = parser.parse_args()

result = subprocess.run(["gh", "release", "list", "-L", "1"], stdout=subprocess.PIPE)
releases = result.stdout.decode("utf-8")
for line in releases.split("\n"):
    if line.strip() == "":
        continue
    tag = line.split("\t")[2]
this_year = int(tag.split("-")[0].lstrip("v"))

result = subprocess.run(["gh", "release", "view", tag], stdout=subprocess.PIPE)
view = result.stdout.decode("utf-8")
description = view.split("\n--\n")[1].strip()

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
        start = True
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