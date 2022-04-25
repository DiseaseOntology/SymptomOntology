
GETTING STARTED -- Setting up a Symptom Ontology Git remote repository


Create a local copy of the SymptomOntology git repository with the command:

`git clone https://github.com/DiseaseOntology/SymptomOntology.git`


**FILES:**

The following ontology files can be found in the src/ontology folder:
  --> symp.obo
  --> symp.owl


**EDITING & RELEASES:**

--> Edit the symp.owl file, then run ROBOT to create the OBO file.
Push both files out when changes are made.

working in the SymptomOntology directory

robot convert --input symp.owl --output symp.obo


**NAMESPACE:**

SYMP:{7 #s}
SYMP:0000000

Editor: Lynn Schriml
SYMP:00191987
