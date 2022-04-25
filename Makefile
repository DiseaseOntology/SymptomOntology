# config
MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:
.SECONDARY:

SYMP = src/ontology/symp
OBO = http://purl.obolibrary.org/obo/

# `make test` is used for Github actions CI
test: reason build/reports/report.tsv verify-edit

build build/reports:
	mkdir -p $@

# ----------------------------------------
# ROBOT & FASTOBO
# ----------------------------------------

# run `make update_robot` to get a new version of ROBOT
.PHONY: update_robot
update_robot:
	rm -rf build/robot.jar && make build/robot.jar

build/robot.jar: | build
	curl -L -o $@ https://github.com/ontodev/robot/releases/download/latest/robot.jar

ROBOT := java -jar build/robot.jar

# fastobo is used to validate OBO structure

FASTOBO := build/fastobo-validator

UNAME := $(shell uname)
ifeq ($(UNAME), Darwin)
	FASTOBO_URL := https://github.com/fastobo/fastobo-validator/releases/latest/download/fastobo_validator-x86_64-apple-darwin.tar.gz
else
	FASTOBO_URL := https://github.com/fastobo/fastobo-validator/releases/latest/download/fastobo_validator-x86_64-linux-musl.tar.gz
endif

build/fastobo.tar.gz: | build
	curl -Lk -o $@ $(FASTOBO_URL)

$(FASTOBO): build/fastobo.tar.gz
	cd build && tar -xvf $(notdir $<)


# ----------------------------------------
# CREATE OBO FILE
# ----------------------------------------

obo: $(SYMP).obo

$(SYMP).obo: $(SYMP).owl | build/robot.jar
	@$(ROBOT) convert --input $< --output $@
	@echo "Created $@"

# ----------------------------------------
# PRE-BUILD TESTS
# ----------------------------------------

.PHONY: report
report: build/reports/report.tsv

# Report for general issues on symp

.PRECIOUS: build/reports/report.tsv
build/reports/report.tsv: $(SYMP).owl | build/robot.jar build/reports
	@echo ""
	@$(ROBOT) report --input $< \
	 --profile src/sparql/report/report_profile.txt \
	 --labels true --output $@
	@echo "Full SYMP QC report available at $@"
	@echo ""


.PRECIOUS: build/reports/diff.


# Simple reasoning test
reason: $(SYMP).owl | build/robot.jar
	@$(ROBOT) reason --input $<
	@echo "Reasoning completed successfully!"


#-------------------------------
# Ensure proper OBO structure
#-------------------------------

validate-obo: validate-$(SYMP)

.PHONY: validate-$(SYMP)
validate-$(SYMP): $(SYMP).obo | $(FASTOBO)
	$(FASTOBO) $<

EDIT_V_QUERIES := $(wildcard src/sparql/verify/edit-verify-*.rq)
V_QUERIES := $(wildcard src/sparql/verify/verify-*.rq)

verify: verify-edit verify-symp

# Verify symp-edit.owl
verify-edit: $(SYMP).owl | build/robot.jar build/reports/report.tsv
	@echo "Verifying $< (see build/reports on error)"
	@$(ROBOT) verify \
	 --input $< \
	 --queries $(EDIT_V_QUERIES) \
	 --output-dir build/reports

# Verify symp.obo
verify-symp: $(SYMP).obo | build/robot.jar build/reports/report.tsv
	@echo "Verifying $< (see build/reports on error)"
	@$(ROBOT) verify \
	 --input $< \
	 --queries $(V_QUERIES) \
	 --output-dir build/reports
