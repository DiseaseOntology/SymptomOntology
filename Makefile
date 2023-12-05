# config
MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:
.SECONDARY:
.NOTPARALLEL:

SYMP = src/ontology/symp
EDIT = src/ontology/symp-edit.owl
OBO = http://purl.obolibrary.org/obo/

# Set the ROBOT version to use
ROBOT_VRS = 1.9.5

.PHONY: release
release: version_edit test products verify post


##########################################
## SETUP
##########################################

.PHONY: clean
clean:
	rm -rf build

build build/update build/reports:
	mkdir -p $@

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
reason: build/edit-reasoned.owl

build/edit-reasoned.owl: $(EDIT) | check_robot build/update
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
## RELEASE PRODUCTS
##########################################

.PHONY: products
products: primary base data_export

# release vars
TS = $(shell date +'%d:%m:%Y %H:%M')
DATE := $(shell date +'%Y-%m-%d')
RELEASE_PREFIX := "$(OBO)symp/releases/$(DATE)/"

# standardized .obo creation;
#      args = output,input,version-iri,ontology-iri (optional)
#      Use "" for ontology-iri to retain the onotology IRI from the input file
define build_obo
	@ONT_IRI=$(4) ; \
	 ONT_IRI=$${ONT_IRI:+"--ontology-iri $(4)"} ; \
	$(ROBOT) query \
	 --input $(2) \
	 --update src/sparql/build/remove-ref-type.ru \
	remove \
	 --select "parents equivalents" \
	 --select "anonymous" \
	remove \
	 --select imports \
	 --trim true \
	annotate \
	 --version-iri $(3) \
	 $${ONT_IRI} \
	convert \
	 --output $(1)
    @grep -v ^owl-axioms $(1) | \
     grep -v ^date | \
     perl -lpe 'print "date: $(TS)" if $$. == 3' > $(1).tmp.obo && \
	 mv $(1).tmp.obo $(1)
endef

# ----------------------------------------
# IMPLICIT RULES
# ----------------------------------------

%.json: %.owl | check_robot
	@$(ROBOT) convert --input $< --output $@
	@echo "Created $@"

src/ontology/%.obo: src/ontology/%.owl | check_robot
	@VRS_IRI="$(RELEASE_PREFIX)$(subst src/ontology/,,$@)" ; \
	ONT_IRI="$(OBO)doid/$(subst src/ontology/,,$(basename $@))" ; \
	$(call build_obo,$@,$<,$${VRS_IRI},$${ONT_IRI})
	@echo "Created $@"

# ----------------------------------------
# PRIMARY
# ----------------------------------------

.PHONY: primary
primary: $(SYMP).owl $(SYMP).obo $(SYMP).json

$(SYMP).owl: $(EDIT) build/reports/report.tsv | check_robot
	@$(ROBOT) reason \
	 --input $< \
	 --create-new-ontology false \
	 --annotate-inferred-axioms false \
	 --exclude-duplicate-axioms true \
	annotate \
	 --version-iri "$(RELEASE_PREFIX)$(notdir $@)" \
	 --annotation oboInOwl:date "$(TS)" \
	 --annotation owl:versionInfo "$(DATE)" \
	 --output $@
	@echo "Created $@"

# implicit override - different ontology-iri pattern
$(SYMP).obo: $(SYMP).owl  | check_robot
	$(call build_obo,$@,$<,"$(RELEASE_PREFIX)$(notdir $@)","")

# ----------------------------------------
# BASE
# ----------------------------------------

.PHONY: base
base: $(SYMP)-base.owl $(SYMP)-base.obo $(SYMP)-base.json

$(SYMP)-base.owl: $(EDIT) | check_robot
	@$(ROBOT) remove \
	 --input $< \
	 --select imports \
	 --trim false \
	annotate \
	 --ontology-iri "$(OBO)symp/$(notdir $@)" \
	 --version-iri "$(RELEASE_PREFIX)$(notdir $@)" \
	 --annotation oboInOwl:date "$(TS)" \
	 --annotation owl:versionInfo "$(DATE)" \
	 --output $@
	@echo "Created $@"


# ----------------------------------------
# DATASETS (publicly available)
# ----------------------------------------

DATASETS := $(patsubst src/sparql/data_export/%.rq, $(DATASET_DIR)/%.tsv, \
	$(wildcard src/sparql/data_export/*.rq)) \

.PHONY: data_export
data_export: $(DATASETS) $(DATASET_DIR)/SYMP-subClassOf-anonymous.tsv \
 $(DATASET_DIR)/SYMP-equivalentClass.tsv

$(DATASET_DIR):
	mkdir -p $@

$(DATASET_DIR)/%.tsv: $(EDIT) src/sparql/data_export/%.rq | $(DATASET_DIR) check_robot
	@$(ROBOT) query --input $< --query $(word 2,$^) $@
	@sed '1 s/?//g' $@ > $@.tmp && mv $@.tmp $@
	@echo "Created $@"

$(DATASET_DIR)/SYMP-subClassOf-anonymous.tsv: $(EDIT) | $(DATASET_DIR) check_robot
	@robot export \
	 --input $< \
	 --header "ID|LABEL|SubClass Of [ANON]" \
	 --export $@
	@awk -F"\t" '$$3!=""' $@ > $@.tmp && mv $@.tmp $@
	@echo "Created $@"

$(DATASET_DIR)/SYMP-equivalentClass.tsv: $(EDIT) | $(DATASET_DIR) check_robot
	@robot export \
	 --input $< \
	 --header "ID|LABEL|Equivalent Class" \
	 --export $@
	@awk -F"\t" '$$3!=""' $@ > $@.tmp && mv $@.tmp $@
	@echo "Created $@"


# ----------------------------------------
# VERSION INPUT FILES (EDIT.OWL & IMPORTS)
# ----------------------------------------

.PHONY: version_edit
version_edit: | check_robot
	@$(ROBOT) annotate \
	 --input $(EDIT) \
	 --version-iri "$(RELEASE_PREFIX)doid.owl" \
	 --output $(EDIT).ofn \
	&& mv $(EDIT).ofn $(EDIT)
	@echo "Updated versionIRI of $(EDIT)"

# ----------------------------------------
# RELEASE COPY
# ----------------------------------------

# Copy the latest release to the releases directory

.PHONY: publish
publish: $(SYMP).owl $(SYMP).obo $(SYMP).json $(SYMP)-base.owl | $(RELEASE_DIR)
	@cp $(SYMP).* $|
	@cp $(SYMP)-base.owl $|
	@echo "Published to $|"
	@echo ""

$(RELEASE_DIR):
	mkdir -p $@


##########################################
## VERIFY PRODUCTS
##########################################

.PHONY: verify validate-obo
verify: verify-symp validate-obo

# ----------------------------------------
# OBO VALIDATION (with fastobo-validator)
# ----------------------------------------

OBO_V = $(patsubst src/ontology/%.obo,validate-obo-%,$(wildcard src/ontology/*.obo))

validate-obo: $(OBO_V)

$(OBO_V): validate-obo-%: src/ontology/%.obo | $(FASTOBO)
	@$(FASTOBO) $<

# ----------------------------------------
# OWL VERIFICATION (with ROBOT)
# ----------------------------------------

# Verify primary OWL file
V_QUERIES := $(wildcard src/sparql/verify/verify-*.rq)

verify-symp: $(SYMP).owl | check_robot
	@echo "Verifying $< (see build/reports on error)"
	@$(ROBOT) verify \
	 --input $< \
	 --queries $(V_QUERIES) \
	 --output-dir build/reports

# Ensure proper OBO structure
validate-obo: validate-$(SYMP)

.PHONY: validate-$(SYMP)
validate-$(SYMP): $(SYMP).obo | $(FASTOBO)
	$(FASTOBO) $<


##########################################
## POST-BUILD REPORT
##########################################

# Count classes, imports, and logical defs from old and new

post: build/reports/report-diff.txt \
      build/reports/missing-axioms.txt

# Get the last build of SYMP from IRI
# .PHONY: build/symp-last.owl
build/symp-last.owl: | check_robot
	@$(ROBOT) merge \
	 --input-iri http://purl.obolibrary.org/obo/symp.owl \
	 --collapse-import-closure true \
	 --output $@

build/reports/symp-diff.txt: build/symp-last.owl $(SYMP).owl | check_robot build/reports
	@$(ROBOT) diff --left $< --right $(word 2, $^) --output $@
	@echo "Generated SYMP diff report at $@"

# all report queries
QUERIES := $(wildcard src/sparql/build/*-report.rq)

# target names for previous release reports
LAST_REPORTS := $(foreach Q,$(QUERIES), build/reports/$(basename $(notdir $(Q)))-last.tsv)
last-reports: $(LAST_REPORTS)
build/reports/%-last.tsv: src/sparql/build/%.rq build/symp-last.owl | check_robot build/reports
	@echo "Counting: $(notdir $(basename $@))"
	@$(ROBOT) query \
	 --input $(word 2,$^) \
	 --query $< $@

# target names for current release reports
NEW_REPORTS := $(foreach Q,$(QUERIES), build/reports/$(basename $(notdir $(Q)))-new.tsv)
new-reports: $(NEW_REPORTS)
build/reports/%-new.tsv: src/sparql/build/%.rq $(SYMP).owl | check_robot build/reports
	@echo "Counting: $(notdir $(basename $@))"
	@$(ROBOT) query \
	 --input $(word 2,$^) \
	 --query $< $@

# create a clean diff between last and current reports
build/reports/report-diff.txt: last-reports new-reports
	@python3 src/util/report-diff.py
	@echo "Diff report between current release and last release available at $@"

# the following targets are used to build a smaller diff with only removed axioms to review
build/robot.diff: build/symp-last.owl $(SYMP).owl | check_robot
	@echo "Comparing axioms in previous release to current release"
	@$(ROBOT) diff \
	 --left $< \
	 --right $(word 2,$^) \
	 --labels true --output $@

build/reports/missing-axioms.txt: src/util/parse-diff.py build/robot.diff | build/reports
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
* help:			Print common make commands.
* test:			Run all edit.owl validation tests.
* release:		Run the entire release pipeline.

Additional build commands (advanced users)
* clean:		Delete all temporary files (build directory).

----------------------------------------
	Outline of Release Pipeline
----------------------------------------

* 1. Update edit.owl file versionIRI and validate.
* 2. Update versionIRIs of import modules.
* 3. Build release products.
* 4. Validate syntax of OBO-format products with fastobo-validator.
* 5. Verify logical structure of products with SPARQL queries.
* 6. Generate post-build reports (counts, etc.)

endef