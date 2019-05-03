
GETTING STARTED -- Setting up a Symptom Ontology Git remote repository


create a local DO git repository:

create a local directory: SymptomOntology_git

[in that directory]: run the command: create git directory by the command: git init

clone the HumanDiseaseOntology git repository: by the command: 

git clone https://github.com/DiseaseOntology/SymptomOntology.git

FILES:
  --> symp.obo
  --> symp.owl

EDITING:

--> Edit the symp.owl file, then run ROBOT to create the OBO file.
Push both files out when changes are made. 

working in the SymptomOntology directory

robot convert --input symp.owl --output results/symp.obo

NAMESPACE: 
SYMP:{7 #s}
SYMP:0000000

Editor: Lynn Schriml
SYMP:00191987



