# README -- For Editors

This README provides information necessary for editors of the Symptom Ontology to make edits and releases.

More information may be available at the Disease Ontology's [README-editors.md](https://github.com/DiseaseOntology/HumanDiseaseOntology/blob/main/src/ontology/README-editors.md).


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

The following ID ranges are assigned to Symptom Ontology curators:

```
SYMP:$sequence(7,0000000,0019999)$  Lynn Schriml (UMSOM)
SYMP:$sequence(7,0020000,0020999)$  James Munro (UMSOM)
```
_Assignments Last Updated: 2022-05-18_


## EDITING

Procedure for editing the Symptom Ontology:

1. Pull changes from Github to your local repository clone.
2. Edit symp-edit.owl in the src/ontology directory using [Protege](https://protege.stanford.edu/) or [ROBOT template](http://robot.obolibrary.org/template).
2. _[OPTIONAL]_ Review changes to symp-edit.owl (`git diff`).
    - NOTE: It's common for Protege to make unexpected changes. Some of these are innocuous (example: rearranging the position of header lines), while others may indicate problems (example: the addition of unexpected classes). `git diff` provides a good opportunity to review changes that have been made before committing (it only requires that you be familiar with OWL functional syntax).
3. Commit changes directly to your local 'main' branch.
4. Push changes to the Github repository.

_ALL_ edits to the Symptom Ontology should be made in the **src/ontology/symp-edit.owl** file. _No_ other files should be edited.


## RELEASES

Releases of the Symptom Ontology should be generated **at least quarterly** and may need to be generated more frequently if changes are substantive or are needed by downstream users, including the Human Disease Ontology (DO).

<section id="production-files">

The production files produced during a release (in the `src/ontology` directory) include:

- symp.owl
- symp.obo
- symp.json

</section>

Creating a release also generates reports (statistical, error, and diff) which are saved to the `build/reports` directory. Diff reports compare the updates of this release to the last official release.

**Differences with DO releases:**  
The Symptom Ontology is simpler than the Human Disease Ontology with no imports or subsets. As such, the number of production files is drastically reduced. Also, production files are _ONLY_ saved in the `src/ontology` directory (there is no `src/release` directory for SYMP).


### To Create a New Release:

#### Summarized Instructions

1. Update the IRI date to the current date in the symp-edit.owl file.
2. Run `make test` from the SymptomOntology top-level directory.
3. Address any warnings or errors identified.
    - Repeat steps 2-3 until all errors are fixed and `make test` no longer identifies errors.
4. Run `make release` from the SymptomOntology top-level directory.
5. Review the generated **build/reports** and address any warnings or errors.
    - Repeat steps 4-5 until all errors are fixed and `make release` no longer identifies errors.
6. Record the following in the Release log:
    1. All major updates since the previous release
    2. Information from ROBOT-generated release reports (in build/reports).
7. Commit the production files and push them to the Github repository.
8. On Github, create a new release from the pushed commit.


#### Detailed Instructions

1. Update the IRI date to the current date in the symp-edit.owl file.
    - This can be done by changing the date in the "Ontology Version IRI" on the Active ontology tab in Protege.
    - The date should be in the format "YYYY-MM-DD".
    - Note that this date is _not_ propagated to production files and is intended only for SYMP editor reference.
2. Run `make test` from the SymptomOntology top-level directory.
    - There are 3 sets of tests executed to identify errors in symp-edit.owl, each described below. Errors in any test will cause a failure but tests list these errors differently.
        1. A test for ontology "incoherency" via [ROBOT reason](http://robot.obolibrary.org/reason#logical-validation) that prints _directly in the console_ error-causing classes on failure or a completion message on success.
        2. A suite of tests via [ROBOT report](http://robot.obolibrary.org/report) that prints a summary of "Violations" in the console and saves _error details to **build/reports/report.tsv**_. These "violations" occur with one of 3 levels of severity:
            - ERROR: These are critical violations that _MUST_ be corrected immediately.
            - WARNING: These violations are not critical but do not conform to good ontology practice or OBO Foundry principles and should be corrected as soon as possible, if possible before a release.
            - INFO: These violations are informative and may or may not indicate a problem.
            - The suite of ROBOT report tests executed against the symp-edit.owl file are defined in `src/sparql/report/report_profile.txt`.
        3. A suite of SPARQL query tests via [ROBOT verify](http://robot.obolibrary.org/verify) that prints the name for each query with the number of errors, followed by the error-causing elements _directly in the console_, if any.
            - These tests are defined in `src/sparql/verify/` and begin with `edit-verify-`.
            - Example, showing a test for the symp-edit.owl file:
                ```
                Verifying src/ontology/symp-edit.owl
                PASS Rule src/sparql/verify/edit-verify-definition_xref.rq: 0 violation(s)
                ```
3. Address any warnings or errors identified.
    - Repeat steps 2-3 until all errors are fixed and `make test` no longer identifies errors.
4. Run `make release` from the SymptomOntology top-level directory.
    - This creates [production files](#production-files), conducts tests, and generates reports.
    - TESTS: `make release` re-executes the tests of `make test` along with additional tests to ensure the validity of the production files symp.owl and symp.obo.
        - **If _ANY_ errors are found**, they should be corrected in the symp-edit.owl file and `make release` re-executed.
        1. symp.owl tests are SPARQL queries executed via [ROBOT verify](http://robot.obolibrary.org/verify) that prints the name for each query with the number of errors, followed by the error-causing elements _directly in the console_, if any.
            - These tests are defined in `src/sparql/verify/` and begin with `verify-`.
        2. symp.obo tests are executed by [fastobo-validator](https://github.com/fastobo/fastobo-validator), [v0.4.0](https://github.com/fastobo/fastobo-validator/releases/tag/v0.4.0), which prints errors in their file context on failure or 'Completed validation of src/ontology/symp.obo' on success, _directly to the console_.
5. Review the generated **build/reports** and address any warnings or errors.
    - Repeat steps 4-5 until all errors are fixed and `make release` no longer identifies errors.
6. Record the following in the Release log:
    1. All major updates since the previous release.
    2. Information from ROBOT-generated release reports (in build/reports).
        - This would include the class, definition, branch and axiom (logical definition) counts.
7. Commit the production files and push them to the Github repository.
    - Add the production files to be committed with `git add .` from the src/ontology directory.
    - Commit the added files with `git commit -m ‘{include a release message}’`
        - A release message should briefly identify this commit as a 'release'. Using a timeframe is fine (example: 'early May release' or 'May 10 release').
    - Push the commit to the Github repository with `git push`.
        - If this does not work, it's probably because there were updates on Github that were not pulled. This may necessitate running `git pull` and repeating steps 4-7.
8. On Github, create a new release from the pushed commit.
    1. In the [SymptomOntology](https://github.com/DiseaseOntology/SymptomOntology) repo on Github, navigate to [Releases](https://github.com/DiseaseOntology/SymptomOntology/releases) and choose to 'Draft a New Release'.
    2. Select 'Choose a Tag'. Type 'v' followed by the 'YYYY-MM-DD' of this release (example: v2022-05-10) and then select '+ Create new tag: <tag name> on publish'.
        - **NOTE**: The creation of a new tag and the format of its name are **_critical_**. The tag name should always match the date _when the production files were created_ and be in the described format, including the dashes and 'v' prefix. Double check that it has been added correctly prior to publishing the release.
    3. Give the release a brief title.
    4. Add text to 'Describe this release'.
        - This should describe significant updates and may include statistics of interest (example: total number of terms and/or percentage of terms defined).
        - NOTE: Descriptions are formatted for Github and utilize Github's markdown formatting. Select 'Preview' to view the text as it will appear on Github.
    5. Once everything is satisfactory, select 'Publish release'.
        - Alternatively, a release in progress can be saved for review by a team member or later completion by selecting 'Save draft'.


## Install Software

git and Protege are required to edit the Symptom Ontology. ROBOT is _not_.

Note that ROBOT is required for releases but `make release` does not use a system-wide ROBOT installation, instead downloading the latest version of ROBOT to the local repository and using that file as part of the release process.

### Git

Refer to git's [install instructions](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git).


#### Protege

Install [Protege Desktop](https://protege.stanford.edu/products.php) 5.1 or higher and ensure it has ELK reasoner 0.4.3 or higher (check the 'Reasoner' menu).


#### ROBOT

Follow the 'getting started' instructions to install [ROBOT](http://robot.obolibrary.org/).


<style type="text/css">
    ol { list-style-type: decimal; }
    ol ol { list-style-type: lower-roman; }
    ul { list-style-type: disc; }
    ul ul { list-style-type: square; }
</style>
