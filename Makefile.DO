# config
MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:
.SECONDARY:
.NOTPARALLEL:


.PHONY: release all
release: version_edit test version_imports products verify publish post

all: imports release


##########################################
## SETUP
##########################################

# Always run rules with this pre-req
FORCE:

.PHONY: clean
clean:
	rm -rf build

build build/update build/reports build/reports/temp:
	mkdir -p $@

# ----------------------------------------
# LOAD GENERAL FUNCTIONS & VARIABLES
# ----------------------------------------

include src/util/functions.mk
include metadata.mk

EDIT = src/ontology/$(ONTID)-edit.owl
NAMESPACE = http://purl.obolibrary.org/obo/$(ONT_ID)
ONT_ID_UC = $(shell echo '$(ONT_ID)' | tr '[:lower:]' '[:upper:]')

# ----------------------------------------
# ROBOT
# ----------------------------------------

# ROBOT is automatically updated
ROBOT := java -jar build/robot.jar

.PHONY: check_robot
check_robot:
	@if [[ -f build/robot.jar ]]; then \
		VRS=$$($(ROBOT) --version) ; \
		if [[ "$$VRS" != *"$(ROBOT_VRS)"* ]]; then \
			echo "Updating from $$VRS to $(ROBOT_VRS)..." ; \
			rm -rf build/robot.jar && $(MAKE) build/robot.jar ; \
		fi ; \
	else \
		echo "Downloading ROBOT version $(ROBOT_VRS)..." ; \
		$(MAKE) build/robot.jar ; \
	fi

# run `make refresh_robot` if ROBOT is not working correctly
.PHONY: refresh_robot
refresh_robot:
	rm -rf build/robot.jar && $(MAKE) build/robot.jar

build/robot.jar: | build
	@curl -L -o $@ https://github.com/ontodev/robot/releases/download/v$(ROBOT_VRS)/robot.jar

# ----------------------------------------
# FASTOBO
# ----------------------------------------

# fastobo is used to validate OBO structure
FASTOBO := build/fastobo-validator

build/fastobo-validator.zip: | build
	curl -Lk -o $@ https://github.com/fastobo/fastobo-validator/releases/latest/download/fastobo-validator_null_x86_64-apple-darwin.zip

$(FASTOBO): build/fastobo-validator.zip
	cd build && unzip -DD $(notdir $<) fastobo-validator


##########################################
## PRE-BUILD TESTS
##########################################

.PHONY: test report reason verify-edit quarterly_test

# `make test` is used for Github integration
test: reason report verify-edit

# Report for general issues in edit file
report: build/reports/report.tsv

.PRECIOUS: build/reports/report.tsv
build/reports/report.tsv: $(EDIT) src/sparql/report/report_profile.txt | check_robot build/reports
	@echo ""
	@$(ROBOT) report \
	 --input $< \
	 --profile $(word 2,$^) \
	 --labels true \
	 --output $@
	@echo "Edit file QC report available at $@"
	@echo ""

# Simple reasoning test
REASONED := build/reasoned.owl
reason: $(REASONED)

$(REASONED): $(EDIT) | check_robot build/update
	@$(ROBOT) reason \
	 --input $< \
	 --create-new-ontology false \
	 --annotate-inferred-axioms false \
	 --exclude-duplicate-axioms true \
	 --output $@
	@echo "Reasoning completed successfully!"

# Verify edit file
verify-edit: build/reports/verify-edit.csv
build/reports/verify-edit.csv: $(EDIT) $(wildcard src/sparql/verify/verify-edit-*.rq) | \
 check_robot build/reports/temp
	@echo "Verifying $< (see $@ on error)"
	@$(ROBOT) verify \
	 --input $< \
	 --queries $(filter-out $(firstword $^),$^) \
	 --output-dir $(word 2,$|)
# need to try to use --fail-on-violation false \ and rethrow errors if temp file created
	@$(call concat_files,$@,$(word 2,$|)/verify-edit-*.csv,true)

# Verify edit file, to be run quarterly & not part of release
verify-quarterly: build/reports/verify-quarterly.csv
build/reports/verify-quarterly.csv: $(EDIT) $(wildcard src/sparql/verify/verify-quarterly-*.rq) | \
 check_robot build/reports/temp
	@echo "Verifying $< (see $@ on error)"
	@$(ROBOT) verify \
	 --input $< \
	 --queries $(filter-out $(firstword $^),$^) \
	 --fail-on-violation false \
	 --output-dir $(word 2,$|)
	@$(call concat_files,$@,$(word 2,$|)/$(notdir $(basename $@))-*.csv,true)


##########################################
## UPDATE DATA IN EDIT FILE
##########################################

# ----------------------------------------
# BRITISH SYNONYMS
# ----------------------------------------

# Add British synonyms from labels and exact synonyms
# This script requires `pandas` module: `python3 -m pip install pandas`

# Script and pipeline adapted from https://github.com/obophenotype/human-phenotype-ontology

build/update/british_english_dictionary.csv: | build/update
	curl -Lk -o $@ https://raw.githubusercontent.com/obophenotype/human-phenotype-ontology/master/src/ontology/hpo_british_english_dictionary.csv

build/update/synonyms.csv: $(EDIT) src/sparql/update/$(ONT_ID)_synonyms.rq | check_robot build/update
	@echo "Retrieving synonyms..."
	@$(ROBOT) query -i $< --query $(word 2,$^) $@

build/update/labels.csv: $(EDIT) src/sparql/update/$(ONT_ID)_labels.rq | check_robot build/update
	@echo "Retrieving labels..."
	@$(ROBOT) query -i $< --query $(word 2,$^) $@

build/be_synonyms.csv: src/util/compute_british_synonyms.py \
 build/update/labels.csv build/update/synonyms.csv \
 build/update/british_english_dictionary.csv
	@echo "Building synonyms template..."
	@python3 $^ $@

build/update/british_synonyms.owl: $(EDIT) build/update/be_synonyms.csv | check_robot
	@$(ROBOT) template --input $< --template $(word 2,$^) --output $@

add_british_synonyms: $(EDIT) build/update/british_synonyms.owl | check_robot
	@$(ROBOT) merge \
	 --input $< \
	 --input $(word 2,$^) \
	 --collapse-import-closure false \
	 --output TMP.ofn \
	&& mv TMP.ofn $^
	@echo "British synonyms added to $^"

# ----------------------------------------
# AUTO-UPDATE SUBSETS
# ----------------------------------------

SUB_ADD := $(patsubst src/sparql/update/subsets/%.rq, update_%, \
	$(wildcard src/sparql/update/subsets/*.rq))
SUB_AUTO := $(patsubst src/sparql/update/subsets/%.ru, update_%, \
	$(wildcard src/sparql/update/subsets/*.ru))

.PHONY: update_slims $(SUB_ADD) $(SUB_AUTO)
update_slims: $(SUB_ADD) $(SUB_AUTO)

# so far only DO_infectious_disease_slim needs a reasoned edit file but it's
#	easier to keep one rule for all slim templates at the moment; may change
#	this if multiple slims don't need reasoned file.
build/update/template-%.tsv: build/edit-reasoned.owl \
 src/sparql/update/subsets/%.rq | check_robot build/update
	@echo "CHECKING $* subset for missing classes..."
	@$(ROBOT) query \
	 --input $< \
	 --query $(word 2,$^) build/update/$*-missing.tsv
	@sed '1s/.*/ID\tsubset\nID\tAI oboInOwl:inSubset/' build/update/$*-missing.tsv | \
	 sed -E 's|<(.+)>|\1\$(ONT_ID):$*|' > build/update/$*-template.tsv
	@rm build/update/$*-missing.tsv

$(SUB_ADD): update_%: $(EDIT) build/update/template-%.tsv | check_robot
	@if [ $$(awk 'END{print NR}' $(word 2,$^)) -gt "0" ]; then \
		echo "UPDATING in $<..." ; \
		$(ROBOT) template \
		 --prefix "$(ONT_ID): $(NAMESPACE)#" \
		 --input $< \
		 --template $(word 2,$^) \
		 --collapse-import-closure false \
		 --merge-before \
		convert \
		 --format ofn \
		 --output $< ; \
		echo " -> See $(word 2,$^) for additions" ; \
	else echo " -> Already up-to-date" ; \
	fi

$(SUB_AUTO): update_%: $(EDIT) src/sparql/update/subsets/%.ru | check_robot \
 build/update
	@echo "UPDATING $* subset in $<..."
	@NEW_DE=build/update/$*.owl ; \
	$(ROBOT) query \
	 --input $< \
	 --update $(word 2,$^) \
	 --output $$NEW_DE \
	&& $(ROBOT) diff \
	 --prefix "$(ONT_ID): $(NAMESPACE)#" \
	 --left $< \
	 --right $$NEW_DE \
	 --format pretty \
	 --output build/update/report-$*.txt \
	&& $(ROBOT) convert \
	 --input $$NEW_DE \
	 --format ofn \
	 --output $< \
	&& rm $$NEW_DE
	@echo " -> See build/update/report-$*.txt for changes"

# ----------------------------------------
# FIX DATA - TYPOS, PATTERNS, ETC. (use fix_help to list)
# ----------------------------------------

FIX_FILES := $(wildcard src/sparql/update/fix_*.ru)
FIX := $(basename $(notdir $(FIX_FILES)))

.PHONY: fix_help fix_data $(FIX)

# reports possible commands with description from first line of SPARQL update file
fix_help:
	@echo -e "\n\nThe following make rules can be used to 'fix' data:\n"
	@for f in $(FIX_FILES); do \
		printf -- '- %s:\t%s\n' $$(basename $$f .ru) "$$(sed '1s/# //;q' $$f )" ; \
	 done
	@echo -e "\nTo run all use: fix_data\n\n"

# run all fix commands
fix_data: $(FIX)

$(FIX): fix_%: $(EDIT) src/sparql/update/fix_%.ru | check_robot
	@$(ROBOT) query \
	 --input $< \
	 --update $(word 2,$^) \
	 --output tmp.owl \
	&& $(ROBOT) convert \
	 --input tmp.owl \
	 --format ofn \
	 --output $< \
	&& rm tmp.owl
	@echo "Fixed $* (review with: git diff --word-diff-regex='.' -- $<)"


##########################################
## BUILDING IMPORTS
##########################################

IMPS := $(IMP_OWL) $(IMP_OWL_GZ)

imports: | check_robot
	@echo "Checking import modules..."
	@cd src/ontology/imports && $(MAKE) imports

refresh_imports: | check_robot
	@echo "Refreshing import modules (this may take some time)..."
	@cd src/ontology/imports && $(MAKE) refresh_imports

$(IMPS): | check_robot
	@echo "Generating $@ import module..."
	@cd src/ontology/imports && $(MAKE) $@

# Refresh (clean & rebuild) *individual* imports with `refresh_{import}`
REFRESH_IMPS := $(foreach IMP,$(IMPS),refresh_$(IMP))
$(REFRESH_IMPS):
	@cd src/ontology/imports && $(MAKE) $@

.PHONY: imports refresh_imports $(IMPS) $(REFRESH_IMPS)


##########################################
## RELEASE PRODUCTS
##########################################

.PHONY: products
products: primary base full nonclassified subsets data_export

# ----------------------------------------
# RELEASE VARIABLES
# ----------------------------------------

PRIMARY = $(RELEASE_DIR)/$(ONT_ID)
BASE = $(PRIMARY)-base
FULL = $(PRIMARY)-$(FULL_NM)
NC = $(PRIMARY)-non-classified
SUBSET_DIR = $(RELEASE_DIR)/subsets

TS = $(shell date +'%d:%m:%Y %H:%M')
DATE := $(shell date +'%Y-%m-%d')
RELEASE_PFX := "$(NAMESPACE)/releases/$(DATE)/"

# ----------------------------------------
# IMPLICIT RULES
# ----------------------------------------

# Standardized .obo creation
$(RELEASE_DIR)/%.obo: $(RELEASE_DIR)/%.owl | check_robot
	@$(ROBOT) query \
	 --input $< \
	 --update src/sparql/build/remove-ref-type.ru \
	remove \
	 --select "parents equivalents" \
	 --select "anonymous" \
	remove \
	 --select imports \
	 --trim true \
	annotate \
	 --ontology-iri "$(NAMESPACE)/$(subst $(RELEASE_DIR)/,,$(basename $@))" \
	 --version-iri "$(RELEASE_PFX)$(subst $(RELEASE_DIR)/,,$@)" \
	convert \
	 --output $@
    @grep -v ^owl-axioms $@ | \
     grep -v ^date | \
     perl -lpe 'print "date: $(TS)" if $$. == 3' > $@.tmp.obo && \
	 mv $@.tmp.obo $@
	@echo "Created $@"

# Standardized .json creation
$(RELEASE_DIR)/%.json: $(RELEASE_DIR)/%.owl | check_robot
	@$(ROBOT) annotate \
	 --input $< \
	 --ontology-iri "$(NAMESPACE)/$(subst $(RELEASE_DIR)/,,$(basename $@))" \
	 --version-iri "$(RELEASE_PFX)$(subst $(RELEASE_DIR)/,,$@)" \
	convert \
	 --output $@
	@echo "Created $@"

# exclude sub-directories from implicit rules (not sure if needed or works)
SUBDIR_EXCLUDE = $(shell find $(RELEASE_DIR)/* -maxdepth 1 -type d)
TYPE_EXCLUDE = 
$(RELEASE_DIR)/imports/*.obo:

$(RELEASE_DIR)/imports/*.json:

$(RELEASE_DIR)/releases/*.obo:

$(RELEASE_DIR)/releases/*.json:


# ----------------------------------------
# DO-SPECIFIC ADJUSTMENTS
# ----------------------------------------

# for historic reasons full is called merged, this maintains the familiar command
.PHONY: merged
merged: full

# copies non-classified as HumanDO outputs
HumanDO.%: $(NC).%
	@cp $< $@
	@echo "Created $@"

# ----------------------------------------
# PRIMARY
# ----------------------------------------

.PHONY: primary
primary: $(PRIMARY).owl $(PRIMARY).obo $(PRIMARY).json

PRIMARY_IN := $(shell case $(DEFAULT_PRODUCT) in \
		(reasoned) echo $(REASONED) ;; \
		(base) echo $(BASE).owl ;; \
		(full) echo $(FULL).owl ;; \
		(non-classified) echo $(NC).owl ;; \
		esac)

$(PRIMARY).owl: $(PRIMARY_IN) build/reports/report.tsv | check_robot
	@$(ROBOT) annotate \
	 --ontology-iri "$(NAMESPACE).owl" \
	 --version-iri "$(RELEASE_PFX)$(notdir $@)" \
	 --annotation oboInOwl:date "$(TS)" \
	 --annotation owl:versionInfo "$(DATE)" \
	 --output $@
	@echo "Created $@"

# OBO & JSON specified to override implicit rules - different ontology-iri pattern
$(PRIMARY).obo: $(PRIMARY).owl | check_robot
	@$(ROBOT) query \
	 --input $< \
	 --update src/sparql/build/remove-ref-type.ru \
	remove \
	 --select "parents equivalents" \
	 --select "anonymous" \
	remove \
	 --select imports \
	 --trim true \
	annotate \
	 --ontology-iri "$(NAMESPACE).obo" \
	 --version-iri "$(RELEASE_PFX)$(notdir $@)" \
	convert \
	 --output $@
    @grep -v ^owl-axioms $@ | \
     grep -v ^date | \
     perl -lpe 'print "date: $(TS)" if $$. == 3' > $@.tmp.obo && \
	 mv $@.tmp.obo $@
	@echo "Created $@"

$(PRIMARY).json: $(PRIMARY).owl | check_robot
	@$(ROBOT) annotate \
	 --input $< \
	 --ontology-iri "$(NAMESPACE).json" \
	 --version-iri "$(RELEASE_PFX)$(notdir $@)" \
	convert \
	 --output $@
	@echo "Created $@"

# ----------------------------------------
# BASE
# ----------------------------------------

.PHONY: base
base: $(BASE).owl $(BASE).obo $(BASE).json

$(BASE).owl: $(EDIT) | check_robot
	@$(ROBOT) remove \
	 --input $< \
	 --select imports \
	 --trim false \
	annotate \
	 --ontology-iri "$(NAMESPACE)/$(notdir $@)" \
	 --version-iri "$(RELEASE_PFX)$(notdir $@)" \
	 --annotation oboInOwl:date "$(TS)" \
	 --annotation owl:versionInfo "$(DATE)" \
	 --output $@
	@echo "Created $@"

# ----------------------------------------
# FULL
# ----------------------------------------

.PHONY: full

full: $(FULL).owl $(FULL).obo $(FULL).json

$(FULL).owl: $(PRIMARY).owl | check_robot
	@$(ROBOT) merge \
	 --input $< \
	 --collapse-import-closure true \
	annotate \
	 --ontology-iri "$(NAMESPACE)/$(notdir $@)" \
	 --version-iri "$(RELEASE_PFX)$(notdir $@)" \
	 --output $@
	@echo "Created $@"

# ----------------------------------------
# NON-CLASSIFIED
# ----------------------------------------

.PHONY: nonclassified
nonclassified: $(NC).owl $(NC).obo $(NC).json

$(NC).owl: $(EDIT) | check_robot
	@$(ROBOT) remove \
	 --input $< \
	 --select imports \
	 --trim true \
	remove \
	 --select "parents equivalents" \
	 --select anonymous \
	annotate \
	 --ontology-iri "$(NAMESPACE)/$(notdir $@)" \
	 --version-iri "$(RELEASE_PFX)$(notdir $@)" \
	 --annotation owl:versionInfo "$(DATE)" \
	 --output $@
	@echo "Created $@"

# ----------------------------------------
# SUBSETS
# ----------------------------------------

SUBSET_IN := $(shell case $(SUBSET_INPUT) in \
		(primary) echo $(PRIMARY).owl ;; \
		(base) echo $(BASE).owl ;; \
		(full) echo $(FULL).owl ;; \
		(non-classified) echo $(NC).owl ;; \
		esac)
SUBS = $(foreach N,$(SUBSETS),$(addprefix $(RELEASE_DIR)/subsets/, $(N)))
OWL_SUBS = $(foreach N,$(SUBS),$(addsuffix .owl, $(N)))
OBO_SUBS = $(foreach N,$(SUBS),$(addsuffix .obo, $(N)))
JSON_SUBS = $(foreach N,$(SUBS),$(addsuffix .json, $(N)))

.PHONY: subsets
subsets: $(OWL_SUBS) $(OBO_SUBS) $(JSON_SUBS)

$(OWL_SUBS): $(SUBSET_IN) | check_robot
	$(ROBOT) filter \
	 --input $< \
	 --select "oboInOwl:inSubset=<$(NAMESPACE)#$(basename $(notdir $@))> annotations" \
	annotate \
	 --ontology-iri "$(NAMESPACE)/subsets/$(notdir $@)" \
	 --version-iri "$(RELEASE_PFX)subsets/$(notdir $@)" \
	 --output $@
	@echo "Created $@"

# Hopefully handled by implicit rules...
# $(RELEASE_DIR)/subsets/%.obo: $(RELEASE_DIR)/subsets/%.owl | check_robot
# 	$(call build_obo,$@,$<,"$(RELEASE_PFX)subsets/$(notdir $@)","$(NAMESPACE)/subsets/$(notdir $(basename $@))")
# 	@echo "Created $@"

# $(RELEASE_DIR)/subsets/%.json: $(RELEASE_DIR)/subsets/%.owl | check_robot
# 	@$(ROBOT) annotate \
# 	 --input $< \
# 	 --version-iri "$(RELEASE_PFX)subsets/$(notdir $@)" \
# 	 --ontology-iri "$(NAMESPACE)/subsets/$(notdir $@)" \
# 	convert \
# 	 --output $@
# 	@echo "Created $@"


# ----------------------------------------
# DATASETS (publicly available)
# ----------------------------------------

DATASETS := $(patsubst src/sparql/data_export/%.rq, $(DATASET_DIR)/%.tsv, \
	$(wildcard src/sparql/data_export/*.rq)) \

.PHONY: data_export
data_export: $(DATASETS) $(DATASET_DIR)/$(ONT_ID_UC)-subClassOf-anonymous.tsv \
 $(DATASET_DIR)/$(ONT_ID_UC)-equivalentClass.tsv

$(DATASET_DIR):
	mkdir -p $@

$(DATASET_DIR)/%.tsv: $(EDIT) src/sparql/data_export/%.rq | $(DATASET_DIR) check_robot
	@$(ROBOT) query --input $< --query $(word 2,$^) $@
	@sed '1 s/?//g' $@ > $@.tmp && mv $@.tmp $@
	@echo "Created $@"

$(DATASET_DIR)/$(ONT_ID_UC)-subClassOf-anonymous.tsv: $(EDIT) | $(DATASET_DIR) check_robot
	@robot export \
	 --input $< \
	 --header "ID|LABEL|SubClass Of [ANON]" \
	 --export $@
	@awk -F"\t" '$$3!=""' $@ > $@.tmp && mv $@.tmp $@
	@echo "Created $@"

$(DATASET_DIR)/$(ONT_ID_UC)-equivalentClass.tsv: $(EDIT) | $(DATASET_DIR) check_robot
	@robot export \
	 --input $< \
	 --header "ID|LABEL|Equivalent Class" \
	 --export $@
	@awk -F"\t" '$$3!=""' $@ > $@.tmp && mv $@.tmp $@
	@echo "Created $@"


# ----------------------------------------
# VERSION INPUT FILES (EDIT.OWL & IMPORTS)
# ----------------------------------------

# Set versionIRI for imports & ext.owl (whether updated or not)
VERSION_IMPS = $(foreach I,$(IMPS) $(MANUAL_IMPS),$(addprefix version_, $(I)))

.PHONY: version_edit version_imports version_ext $(VERSION_IMPS)
version_edit: | check_robot
	@$(ROBOT) annotate \
	 --input $(EDIT) \
	 --version-iri "$(RELEASE_PFX)$(ONT_ID).owl" \
	 --output $(EDIT).ofn \
	&& mv $(EDIT).ofn $(EDIT)
	@echo "Updated versionIRI of $(EDIT)"

version_imports: $(VERSION_IMPS) version_ext

version_ext: src/ontology/ext.owl | check_robot
	@$(ROBOT) annotate \
	 --input $< \
	 --version-iri "$(RELEASE_PFX)ext.owl" \
	 --output $<
	@echo "Updated versionIRI of $<"

$(VERSION_IMPS): version_%: src/ontology/imports/%_import.owl | check_robot
	@$(ROBOT) annotate \
	 --input $< \
	 --version-iri "$(RELEASE_PFX)imports/$(notdir $<)" \
	 --output $<
	@echo "Updated versionIRI of $<"

# ----------------------------------------
# RELEASE COPY
# ----------------------------------------

# Copy the latest release to the releases directory

.PHONY: publish
publish: $(wildcard $(PRIMARY).*) \
 $(wildcard $(FULL).*) \
 $(wildcard $(NC).*) \
 $(BASE).owl \
 subsets | $(RELEASE_DIR)
	@cp $(PRIMARY).* $|
	@cp $(FULL).* $|
	@cp $(NC).* $|
	@cp $(BASE).owl $|
	@cp -r $(RELEASE_DIR)/subsets $|
	@echo "Published to $|"
	@echo ""

$(RELEASE_DIR):
	mkdir -p $@


##########################################
## VERIFY PRODUCTS
##########################################

.PHONY: verify
verify: validate-obo verify-primary verify-nc

# ----------------------------------------
# OBO VALIDATION (with fastobo-validator)
# ----------------------------------------

OBO_V = $(patsubst $(VERIFY_DIR)/%.obo,validate-obo-%,$(wildcard $(VERIFY_DIR)/*.obo))

.PHONY: validate-obo $(OBO_V)
validate-obo: $(OBO_V)

$(OBO_V): validate-obo-%: $(RELEASE_DIR)/%.obo | $(FASTOBO)
	@$(FASTOBO) $<

# ----------------------------------------
# OWL VERIFICATION (with ROBOT)
# ----------------------------------------

# Verify primary OWL file
V_QUERIES := $(wildcard src/sparql/verify/verify-*.rq)
verify-primary: $(PRIMARY).owl | check_robot build/reports
	@echo "Verifying $< (see $(word 2,$|) on error)"
	@$(ROBOT) verify \
	 --input $< \
	 --queries $(V_QUERIES) \
	 --output-dir $(word 2,$|)

# Verify non-classified file
NC_V_QUERIES := $(wildcard src/sparql/verify-nc-*.rq)
verify-nc: $(NC).owl | check_robot build/reports
	@echo "Verifying $< (see $(word 2,$|) on error)"
	@$(ROBOT) verify \
	 --input $< \
	 --queries $(V_QUERIES) $(NC_V_QUERIES) \
	 --output-dir $(word 2,$|)


##########################################
## POST-BUILD REPORTS
##########################################

post: build/reports/report-diff.txt \
      build/reports/branch-count.tsv \
      build/reports/missing-axioms.txt \
      build/reports/hp-do-overlap.csv

# Show differences from the last FULL release of the ontology
LAST_IRI := $(NAMESPACE)/$(ONT_ID)-$(FULL_NM).owl
build/$(ONT_ID)-last.version: FORCE | build
	$(call which_latest,$@,$(LAST_IRI))

build/$(ONT_ID)-last.owl: build/$(ONT_ID)-last.version | check_robot build
	@LAST_VRS=$$(sed '1q' $<) ; \
	echo "DOWNLOADING $${LAST_VRS}..."
	curl -Lk $${LAST_VRS} > $@

build/reports/$(ONT_ID)-diff.html: build/$(ONT_ID)-last.owl $(FULL).owl | check_robot build/reports
	@$(ROBOT) diff --left $< --right $(word 2, $^) --format html --output $@
	@echo "Generated $(ONT_ID_UC) diff report at $@"

# all report queries
QUERIES := $(wildcard src/sparql/build/report-*.rq)

# target names for previous release reports
LAST_REPORTS := $(foreach Q,$(QUERIES), build/reports/$(basename $(notdir $(Q)))-last.tsv)
last-reports: $(LAST_REPORTS)
build/reports/%-last.tsv: src/sparql/build/%.rq build/$(ONT_ID)-last.owl | check_robot build/reports
	@echo "Counting: $(notdir $(basename $@))"
	@$(ROBOT) query \
	 --input $(word 2,$^) \
	 --query $< $@

# target names for current release reports
NEW_REPORTS := $(foreach Q,$(QUERIES), build/reports/$(basename $(notdir $(Q)))-new.tsv)
new-reports: $(NEW_REPORTS)
build/reports/%-new.tsv: src/sparql/build/%.rq $(FULL).owl | check_robot build/reports
	@echo "Counting: $(notdir $(basename $@))"
	@$(ROBOT) query \
	 --input $(word 2,$^) \
	 --query $< $@

# create a clean diff between last and current reports
build/reports/report-diff.txt: last-reports new-reports
	@python3 src/util/report-diff.py
	@echo "Diff report between current release and last release available at $@"

# create a count of asserted and total (asserted + inferred) classes in each branch
#	BASE file for asserted relationships (pre-reasoned)
branch_reports = $(foreach O,$(BASE).owl $(PRIMARY).owl,build/reports/temp/branch-count-$(O).tsv)

.INTERMEDIATE: $(branch_reports)
$(branch_reports): build/reports/temp/branch-count-%.tsv: $(RELEASE_DIR)/%.owl \
 src/sparql/build/branch-count.rq | check_robot build/reports/temp
	@echo "Counting all branches in $<..."
	@$(ROBOT) query \
	 --input $< \
	 --query $(word 2,$^) $@

build/reports/branch-count.tsv: $(branch_reports)
	@join -t $$'\t' -o $$'\t' <(sed '/^?/d' $< | sort -k1) <(sed '/^?/d' $(word 2,$^) | sort -k1) > $@
	@awk 'BEGIN{ FS=OFS="\t" ; print "branch\tasserted\tinferred\ttotal" } \
	 {print $$1, $$2, $$3-$$2, $$3}' $@ > $@.tmp && mv $@.tmp $@
	@echo "Branch counts available at $@"

# the following targets are used to build a smaller diff with only removed axioms to review
build/robot.diff: build/$(ONT_ID)-last.owl $(FULL).owl | check_robot
	@echo "Comparing axioms in previous release to current release"
	@$(ROBOT) diff \
	 --left $< \
	 --right $(word 2,$^) \
	 --labels true \
	 --output $@

build/reports/missing-axioms.txt: src/util/parse-diff.py build/robot.diff | build/reports
	@python3 $^ $@

build/hp-do-terms.tsv: $(FULL).owl src/sparql/build/hp-and-do-terms.rq | check_robot
	@echo "Finding overlap between HP and DO terms..."
	@$(ROBOT) query --input $< --query $(word 2,$^) $@

build/reports/hp-do-overlap.csv: src/util/get_hp_overlap.py build/hp-do-terms.tsv
	@python3 $^ $@


##########################################
## MAKE HELP
##########################################

.PHONY: help
help:
	@echo $(help_text)

define help_text
----------------------------------------
	Available Commands
----------------------------------------
*** NEVER run make commands in parallel (do NOT use the -j flag) ***

Core commands:
* help:			Print make commands.
* test:			Run all edit file validation tests.
* release:		Run the entire release pipeline.
* fix_data:		Run all automated fixes for the edit.owl file.
* fix_help:		Show fix command help.

Imports management:
* imports:				Generate all automated imports from the latest version.
* <import_id>:			Generate a single import, i.e. symp will generate 'imports/symp_import.owl'.
* refresh_imports:		(Advanced users) Regenerate all imports from newly downloaded source files.
* refresh_<import_id>:	(Advanced users) Regenerate specified import from newly downloaded source file.

Specialized commands:
* add_british_synonyms:		Add British synonyms from labels and exact synonyms.
* update_slims:				Update all auto-updating subsets.
* update_<subset_label>:	Update a single auto-updating subset, e.g. update_DO_rare_slim.

Additional build commands (advanced users)
* clean:			Delete all temporary files (build directory).
* all:				Run imports, followed by the release pipeline.
* products:			Create release products
	* primary:			Build primary release products.
	* base:				Build OBO-defined -base products (no imports).
	* nonclassified:	Build "non-classified" release products (i.e. base without logical axioms).
		* This differs from non-classified files of other OBO ontologies (https://oboacademy.github.io/obook/reference/release-artefacts/)
	* merged:			Build fully merged release products (may be named "-merged" or "-full").
	* subsets:			Build subset products.
	* data_export:		Generate AI/ML flat-file datasets.
* verify:
* validate-ob0:
* verify-primary:
* verify-nc:
* post:				Generate post-build release reports.

----------------------------------------
	Outline of Release Pipeline
----------------------------------------

* 1. Update edit.owl file versionIRI and validate.
* 2. Update versionIRIs of import modules.
* 3. Build release products.
* 4. Validate syntax of OBO-format products with fastobo-validator.
* 5. Verify logical structure of products with SPARQL queries.
* 6. Generate post-build reports (counts, etc.).
* 7. Publish to release directory.

endef