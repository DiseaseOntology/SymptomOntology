# README -- For Editors

This README provides information necessary for editors of the Symptom Ontology to make edits and releases.

For more information refer to the Disease Ontology's [README-editors.md](https://github.com/DiseaseOntology/HumanDiseaseOntology/blob/main/src/ontology/README-editors.md).


## GETTING STARTED

Set up a local copy of the SymptomOntology git repository with the official SymptomOntology as a remote with the command:

`git clone https://github.com/DiseaseOntology/SymptomOntology.git`

Refer to the [Install Software](#install-software) section for information about installing git, Protege, or ROBOT.


## NAMESPACE INFO

The Symptom Ontology's [base URI & redirects](https://github.com/OBOFoundry/purl.obolibrary.org/blob/master/config/symp.yml) are defined in the OBO Foundry's [purl.obolibrary.org](https://github.com/OBOFoundry/purl.obolibrary.org) repository.

- Base URI: `http://purl.obolibrary.org/symp`
- Namespace: `SYMP`
- ID format: `SYMP:{7 #s}`
    - Example: `SYMP:0000000`

The following ID ranges are assigned for Symptom Ontology curators:

```
SYMP:$sequence(7,0000000,0019999)$  Lynn Schriml (UMSOM)
SYMP:$sequence(7,0020000,0020999)$  James Munro (UMSOM)
```

Assignments Last Updated: 2022-05-18


## EDITING

Follow this procedure to edit the Symptom Ontology:

1. Pull changes from Github to your local repository clone.
2. Edit symp-edit.owl in the src/ontology directory using [Protégé](https://protege.stanford.edu/) or [ROBOT template](http://robot.obolibrary.org/template.
2. Review changes to symp-edit.owl (`git diff`).
    - NOTE: It's fairly common for Protégé to make unexpected changes. Some of these are innocuous (example: rearranging the position of header lines), while others may indicate problems (example: the addition of unexpected classes). `git diff` provides a good opportunity to review changes that have been made before committing (it only requires that you be familiar with OWL functional syntax).
3. Commit changes directly to the 'main' branch.
4. Push changes to the Github repository.

_ALL_ edits to the Symptom Ontology should be made in the **src/ontology/symp-edit.owl** file. _No_ other files should be edited.


## RELEASES

The Symptom Ontology does not have a set or expected release schedule. Instead, releases should be created whenever updates are substantive or needed for use in the Human Disease Ontology (DO).

The production files produced during a release (in the src/ontology directory) include:

- symp.owl
- symp.obo
- symp.json

Statistical, error, and diff reports produced during a release can be found in the build/reports directory. Diff reports compare the updates of this release to the last official release.

**Differences with DO releases:**  
The Symptom Ontology is simpler than the Human Disease Ontology with no imports or subsets. As such, the number of production files is drastically reduced. Also, production files are _ONLY_ saved in the src/ontology directory (there is no src/release directory for SYMP).


### To create a new release:

1. Run `make release` from the SymptomOntology top-level directory.
    - This creates production files, conducts tests, and generates reports.
2. Ensure the release is error free and fix warnings/informational messages as necessary.
    - **If _ANY_ errors are found**, they should be corrected in the symp-edit.owl file (committed and pushed to Github, as well) and the release should be repeated.
    - Some tests are listed directly in the terminal during execution. These tests are listed below the file they are being executed against. Example:
        ```
        Verifying src/ontology/symp-edit.owl
        PASS Rule src/sparql/verify/edit-verify-definition_xref.rq: 0 violation(s)
        ```
        - Any errors in these tests _MUST_ be corrected.
        - There are currently tests for symp-edit.owl, symp.owl, and symp.obo.
        - For the owl file tests, the term(s) causing an error will be listed in the terminal after the line with the test name and number of violations.
        - For the symp.obo test, the error and its context in the obo file will be displayed. 'Completed validation of `src/ontology/symp.obo`' means the test has passed.
    - Other tests are executed by ROBOT against the symp-edit.owl file and will be listed in `build/reports/report.tsv` along with one of 3 levels: ERROR, WARNING, INFO.
        - ERRORs _MUST_ be corrected.
        - If possible, WARNINGs and INFOs should also be fixed prior to release. Note that INFO particularly does not necessarily indicate a problem.
3. Commit the production files (symp.owl, symp.obo, symp.json) and push to Github.
    - This commit should _ONLY_ include production files and have a message that is distinguishable from other, recent releases ending with the word 'release'. Using a timeframe is fine (example: 'early May release' or 'May 10 release').
4. In [SymptomOntology](https://github.com/DiseaseOntology/SymptomOntology) on Github, navigate to [Releases](https://github.com/DiseaseOntology/SymptomOntology/releases) and choose to 'Draft a New Release'. Then complete the release as follows:
    1. Select 'Choose a Tag'. Type 'v' followed by the 'YYYY-MM-DD' of this release (example: v2022-05-10) and then select '+ Create new tag: <tag name> on publish'.
        - **NOTE**: The creation of a new tag and the format of its name are **_critical_**. The tag name should always match the date _when the production files were created_ in the described format, including the dashes and 'v' prefix. Double check that it has been added correctly prior to publishing the release.
    2. Give the release a brief title.
    3. Add text to 'Describe this release'.
        - This should describe significant updates and may include statistics of interest (example: total number of terms and/or percentage of terms defined).
        - NOTE: Descriptions are formatted for Github and utilize Github's markdown formatting. Select 'Preview' to view the text as it will appear on Github.
    4. Once everything is satisfactory, select 'Publish release'.
        - Alternatively, a release in progress can be saved for review by a team member or later completion by selecting 'Save draft'.


## Install Software

git and Protege are required to edit the Symptom Ontology. ROBOT is _not_.

Note that ROBOT is required for releases but `make release` does not use a system-wide ROBOT installation, instead downloading the latest version of ROBOT to the local repository and using that file as part of the release process.

### Git

Refer to git's [install instructions](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git).


#### Protégé

Install [Protégé Desktop](https://protege.stanford.edu/products.php) 5.1 or higher and ensure it has ELK reasoner 0.4.3 or higher (check the 'Reasoner' menu).


#### ROBOT

Follow the 'getting started' instructions to install [ROBOT](http://robot.obolibrary.org/).
