# config
MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:
.SECONDARY:

SYMP = src/ontology/symp
EDIT = src/ontology/symp-edit.owl
OBO = http://purl.obolibrary.org/obo/

# to make a release, use `make release`

# Release process:
# 1. Verify symp-edit.owl
# 2. Build all products (symp.owl, symp.obo)
# 3. Verify structure of symp.owl with SPARQL queries
# 4. Validate syntax of OBO-format with fastobo-validator
# 5. Generate post-build reports (counts, etc.)
release: test products verify post


##########################################
## SOFTWARE SETUP
##########################################

build build/reports:
	mkdir -p $@

# ----------------------------------------
# ROBOT
# ----------------------------------------

# run `make update_robot` to get a new version of ROBOT
.PHONY: update_robot
update_robot:
	rm -rf build/robot.jar && make build/robot.jar

build/robot.jar: | build
	curl -L -o $@ https://github.com/ontodev/robot/releases/latest/download/robot.jar

ROBOT := java -jar build/robot.jar

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

.PHONY: test report reason verify-edit

# `make test` is used for Github integration
test: reason report verify-edit

# Report for general issues on symp-edit
report: build/reports/report.tsv

.PRECIOUS: build/reports/report.tsv
build/reports/report.tsv: $(EDIT) src/sparql/report/report_profile.txt | build/robot.jar build/reports
	@echo ""
	@$(ROBOT) report --input $< \
	 --profile $(word 2,$^) \
	 --labels true --output $@
	@echo "Full SYMP QC report available at $@"
	@echo ""

# Simple reasoning test
reason: $(EDIT) | build/robot.jar
	@$(ROBOT) reason --input $<
	@echo "Reasoning completed successfully!"

# Verify symp-edit.owl
EDIT_V_QUERIES := $(wildcard src/sparql/verify/edit-verify-*.rq)

verify-edit: $(EDIT) | build/robot.jar build/reports/report.tsv
	@echo "Verifying $<"
	@$(ROBOT) verify \
	 --input $< \
	 --queries $(EDIT_V_QUERIES) \
	 --output-dir build/reports


##########################################
## RELEASE PRODUCTS
##########################################

products: $(SYMP).owl $(SYMP).obo $(SYMP).json $(SYMP)-base.owl

# release vars
TS = $(shell date +'%d:%m:%Y %H:%M')
DATE = $(shell date +'%Y-%m-%d')

$(SYMP).owl: $(EDIT) build/reports/report.tsv | build/robot.jar
	@$(ROBOT) reason \
	 --input $< \
	 --create-new-ontology false \
	 --annotate-inferred-axioms false \
	 --exclude-duplicate-axioms true \
	annotate \
	 --version-iri "$(OBO)symp/releases/$(DATE)/$(notdir $@)" \
	 --annotation oboInOwl:date "$(TS)" \
	 --annotation owl:versionInfo "$(DATE)" \
	 --output $@
	@echo "Created $@"

$(SYMP).obo: $(SYMP).owl src/sparql/build/remove-ref-type.ru | build/robot.jar
	@$(ROBOT) remove \
	 --input $< \
	 --select "parents equivalents" \
	 --select "anonymous" \
	query \
	 --update $(word 2,$^) \
	annotate \
	 --version-iri "$(OBO)symp/releases/$(DATE)/$(notdir $@)" \
	 --output $(basename $@)-temp.obo
	@grep -v ^owl-axioms $(basename $@)-temp.obo | \
	grep -v ^date | \
	perl -lpe 'print "date: $(TS)" if $$. == 3'  > $@
	@rm $(basename $@)-temp.obo
	@echo "Created $@"

$(SYMP).json: $(SYMP).owl | build/robot.jar
	@$(ROBOT) convert --input $< --output $@
	@echo "Created $@"

$(SYMP)-base.owl: $(EDIT) | build/robot.jar
	@$(ROBOT) remove \
	 --input $< \
	 --select imports \
	 --trim false \
	annotate \
	 --ontology-iri "$(OBO)symp/$(notdir $@)" \
	 --version-iri "$(OBO)symp/releases/$(DATE)/$(notdir $@)" \
	 --annotation owl:versionInfo "$(DATE)" \
	 --output $@
	@echo "Created $@"


##########################################
## VERIFY PRODUCTS
##########################################

verify: verify-symp validate-obo

# Verify symp.owl
V_QUERIES := $(wildcard src/sparql/verify/verify-*.rq)

verify-symp: $(SYMP).owl | build/robot.jar build/reports/report.tsv
	@echo "Verifying $<"
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
build/symp-last.owl: | build/robot.jar
	@$(ROBOT) merge \
	 --input-iri http://purl.obolibrary.org/obo/symp.owl \
	 --collapse-import-closure true \
	 --output $@

build/reports/symp-diff.txt: build/symp-last.owl $(SYMP).owl | build/robot.jar build/reports
	@$(ROBOT) diff --left $< --right $(word 2, $^) --output $@
	@echo "Generated SYMP diff report at $@"

# all report queries
QUERIES := $(wildcard src/sparql/build/*-report.rq)

# target names for previous release reports
LAST_REPORTS := $(foreach Q,$(QUERIES), build/reports/$(basename $(notdir $(Q)))-last.tsv)
last-reports: $(LAST_REPORTS)
build/reports/%-last.tsv: src/sparql/build/%.rq build/symp-last.owl | build/robot.jar build/reports
	@echo "Counting: $(notdir $(basename $@))"
	@$(ROBOT) query \
	 --input $(word 2,$^) \
	 --query $< $@

# target names for current release reports
NEW_REPORTS := $(foreach Q,$(QUERIES), build/reports/$(basename $(notdir $(Q)))-new.tsv)
new-reports: $(NEW_REPORTS)
build/reports/%-new.tsv: src/sparql/build/%.rq $(SYMP).owl | build/robot.jar build/reports
	@echo "Counting: $(notdir $(basename $@))"
	@$(ROBOT) query \
	 --input $(word 2,$^) \
	 --query $< $@

# create a clean diff between last and current reports
build/reports/report-diff.txt: last-reports new-reports
	@python3 src/util/report-diff.py
	@echo "Diff report between current release and last release available at $@"

# the following targets are used to build a smaller diff with only removed axioms to review
build/robot.diff: build/symp-last.owl $(SYMP).owl | build/robot.jar
	@echo "Comparing axioms in previous release to current release"
	@$(ROBOT) diff \
	 --left $< \
	 --right $(word 2,$^) \
	 --labels true --output $@

build/reports/missing-axioms.txt: src/util/parse-diff.py build/robot.diff | build/reports
	@python3 $^ $@

