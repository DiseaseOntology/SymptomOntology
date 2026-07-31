# config
MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := all
.DELETE_ON_ERROR:
.SUFFIXES:
.SECONDARY:
.NOTPARALLEL:

ONT := symp
OBO := http://purl.obolibrary.org/obo/
EDIT := src/ontology/$(ONT)-edit.owl

# define the release directory
REL_DIR := src/ontology

# Set the software version(s) to use
ROBOT_VRS = 1.9.10
FASTOBO_VRS = 0.4.6

# ***NEVER run make commands in parallel (do NOT use the -j flag)***

# to make a release, use `make release`
# to run QC tests on *-edit.owl, use `make test`

# Release process:
# 1. Build product(s)
# 2. Validate syntax of OBO-format products with fastobo-validator
# 3. Verify logical structure of products with SPARQL queries
# 4. Generate post-build reports (counts, etc.)

.PHONY: release all
release: test products verify post
	@echo "Release complete!"

all: release

.PHONY: FORCE
FORCE:


##########################################
## SETUP
##########################################

.PHONY: clean
clean:
	rm -rf build

build build/update build/reports build/reports/temp build/translations:
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
			printf "\e[1;37mUpdating\e[0m from $$VRS to $(ROBOT_VRS)...\n" ; \
			rm -rf build/robot.jar && $(MAKE) build/robot.jar ; \
		fi ; \
	else \
		echo "Downloading ROBOT version $(ROBOT_VRS)..." ; \
		$(MAKE) build/robot.jar ; \
	fi

build/robot.jar: | build
	@curl -L -o $@ https://github.com/ontodev/robot/releases/download/v$(ROBOT_VRS)/robot.jar

# ----------------------------------------
# FASTOBO
# ----------------------------------------

# fastobo is used to validate OBO structure
FASTOBO := build/fastobo-validator

.PHONY: check_fastobo
check_fastobo:
	@if [[ -f $(FASTOBO) ]]; then \
		VRS=$$($(FASTOBO) --version) ; \
		if [[ "$$VRS" != *"$(FASTOBO_VRS)"* ]]; then \
			printf "\e[1;37mUpdating\e[0m from $$VRS to $(FASTOBO_VRS)...\n" ; \
			rm -rf build/fastobo-validator && $(MAKE) $(FASTOBO) ; \
		fi ; \
	else \
		printf "\e[1;37mDownloading\e[0m fastobo-validator version $(FASTOBO_VRS)...\n" ; \
		$(MAKE) $(FASTOBO) ; \
	fi

$(FASTOBO): | build
	@if [[ $$(uname -m) == 'x86_64' ]]; then \
		curl -Lk -o build/fastobo-validator.zip https://github.com/fastobo/fastobo-validator/releases/download/v$(FASTOBO_VRS)/fastobo-validator_null_x86_64-apple-darwin.zip ; \
		cd build && unzip -DD fastobo-validator.zip fastobo-validator && rm fastobo-validator.zip ; \
	else \
		if [[ $$(command -v cargo) != *"cargo" ]]; then \
			printf "\e[1;33mWARNING:\e[0m fastobo-validator must be built from source on ARM64 machines\n" ; \
			printf " --> Install the Rust programming language, then repeat desired make command\n" ; \
			printf "\e[1;33mSKIPPING\e[0m fastobo-validator install\n\n" ; \
		else \
			echo "fastobo-validator must be built from source on ARM64 machines, one moment..." ; \
			cargo install --quiet --root $(dir $@) \
				--git "https://github.com/fastobo/fastobo-validator/" \
				--tag "v$(FASTOBO_VRS)" fastobo-validator && \
			mv build/bin/fastobo-validator $@ && rm -d build/bin ; \
		fi ; \
	fi


##########################################
## CI TESTS & DIFF
##########################################

.PHONY: ci_test report reason verify-edit

# Continuous Integration (CI) testing
ci_test: reason report verify-edit
	@echo ""

test: ci_test diff

# Simple reasoning test
reason: build/$(ONT)-edit-reasoned.owl

build/$(ONT)-edit-reasoned.owl: $(EDIT) | check_robot build
	@$(ROBOT) reason \
	 --input $< \
	 --create-new-ontology false \
	 --annotate-inferred-axioms false \
	 --exclude-duplicate-axioms true \
	 --output $@
	@echo -e "\n## Reasoning completed successfully!"

# QC reports for *-edit.owl (.ok files ensure errors are blocking)
report: build/reports/report-obo.tsv build/reports/report.tsv

.PHONY: build/reports/report-obo.tsv build/reports/report.tsv
build/reports/report-obo.tsv: build/reports/temp/report-obo.tsv.ok
build/reports/report.tsv: build/reports/temp/report.tsv.ok

build/reports/temp/report-obo.tsv.ok: $(EDIT) | check_robot build/reports/temp
	@REPORT=build/reports/$(notdir $(basename $@)); \
	 echo -e "\n## OBO QC report ##\nFull report at $$REPORT" ; \
	$(ROBOT) report \
	 --input $< \
	 --labels false \
	 --output $$REPORT && \
	touch $@

build/reports/temp/report.tsv.ok: $(EDIT) src/sparql/report/report_profile.txt | \
  check_robot build/reports/temp
	@REPORT=build/reports/$(notdir $(basename $@)); \
	 echo -e "\n## $(ONT)-edit QC report ##\nFull report at $$REPORT\n" ; \
	$(ROBOT) report \
	 --input $< \
	 --profile $(word 2,$^) \
	 --labels false \
	 --output $$REPORT && \
	touch $@

# Verify *-edit.owl
EDIT_V_QUERIES := $(wildcard src/sparql/verify/edit-verify-*.rq src/sparql/verify/verify-*.rq)
EDIT_V_RES := $(patsubst src/sparql/verify/%.rq,build/reports/temp/%.csv,$(EDIT_V_QUERIES))

.PRECIOUS: build/reports/edit-verify.csv
verify-edit: build/reports/edit-verify.csv
build/reports/edit-verify.csv: $(EDIT) | check_robot build/reports/temp
	@rm -f $(EDIT_V_RES)
	@$(ROBOT) verify \
	 --input $< \
	 --queries $(EDIT_V_QUERIES) \
	 --fail-on-violation false \
	 --output-dir $(word 2,$|)
	@python3 src/util/concat_csv.py \
	 --input $(EDIT_V_RES) \
	 --category TEST \
	 --output $@

# ----------------------------------------
# DIFF
# ----------------------------------------

.PHONY: diff
diff: build/reports/diff.tsv

# Get the last release of $(ONT).owl (only if newer available)
build/$(ONT)-last.version: FORCE | build
	@LATEST=$$(curl -sL "http://purl.obolibrary.org/obo/$(ONT).owl" | \
				sed -n '/owl:versionIRI/p;/owl:versionIRI/q' | \
				sed -E 's/.*"([^"]+)".*/\1/') ; \
	 if [[ -f $@ ]]; then \
		SRC_VERS=$$(sed '1q' $@) ; \
		if [[ $${SRC_VERS} != $${LATEST} ]]; then \
			echo $${LATEST} > $@ ; \
		fi ; \
	 else \
		echo $${LATEST} > $@ ; \
	 fi

build/$(ONT)-last.owl: build/$(ONT)-last.version
	@echo "Downloading latest release to $@..."
	@curl -sL http://purl.obolibrary.org/obo/$(ONT).owl -o $@

build/$(ONT)-new.owl: build/$(ONT)-edit-reasoned.owl | check_robot ci_test
#   src/sparql/build/add_en_tag.ru | check_robot ci_test
	@cp $< $@
# NEED TO CONFIRM THAT en tag is desired
# 	@$(ROBOT) query \
# 	 --input $< \
# 	 --update $(word 2,$^) \
# 	 --output $@


build/reports/diff.tsv: build/$(ONT)-last.owl build/$(ONT)-new.owl | check_robot \
  build/reports/temp
	@$(ROBOT) export \
	 --input $< \
	 --header "ID|owl:deprecated|LABEL|SYNONYMS|IAO:0000115|SubClass Of [ID NAMED]|Equivalent Class|SubClass Of [ANON]|oboInOwl:hasDbXref|skos:exactMatch|skos:closeMatch|skos:broadMatch|skos:narrowMatch|skos:relatedMatch|oboInOwl:hasAlternativeId|oboInOwl:inSubset" \
	 --export build/reports/temp/$(notdir $(basename $<)).tsv
	@$(ROBOT) export \
	 --input $(word 2,$^) \
	 --header "ID|owl:deprecated|LABEL|SYNONYMS|IAO:0000115|SubClass Of [ID NAMED]|Equivalent Class|SubClass Of [ANON]|oboInOwl:hasDbXref|skos:exactMatch|skos:closeMatch|skos:broadMatch|skos:narrowMatch|skos:relatedMatch|oboInOwl:hasAlternativeId|oboInOwl:inSubset" \
	 --export build/reports/temp/$(notdir $(basename $(word 2,$^))).tsv
	@python3 src/util/diff-re.py \
	 -1 build/reports/temp/$(notdir $(basename $<)).tsv \
	 -2 build/reports/temp/$(notdir $(basename $(word 2,$^))).tsv \
	 -o $@
	@echo "Generated diff report at $@"


##########################################
## RELEASE PRODUCTS
##########################################

PRIMARY = $(REL_DIR)/$(ONT)

.PHONY: products
products: primary base

# release vars
TS = $(shell date +'%d:%m:%Y %H:%M')
DATE := $(shell date +'%Y-%m-%d')
RELEASE_PREFIX := $(OBO)$(ONT)/releases/$(DATE)/

# standardized .obo creation;
#	args = output,input,version-iri,ontology-iri (optional, use "" to keep from input file)
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
# RELEASE PRODUCTS
# ----------------------------------------

.PHONY: primary
primary: $(PRIMARY).owl $(PRIMARY).obo $(PRIMARY).json

$(PRIMARY).owl: build/$(ONT)-new.owl | check_robot
	@$(ROBOT) annotate \
	 --input $< \
	 --version-iri "$(RELEASE_PREFIX)$(notdir $@)" \
	 --annotation oboInOwl:date "$(TS)" \
	 --annotation owl:versionInfo "$(DATE)" \
	 --output $@
	@echo "Created $@"

$(PRIMARY).obo: $(PRIMARY).owl | check_robot
	$(call build_obo,$@,$<,"$(RELEASE_PREFIX)$(notdir $@)","")
	@echo "Created $@"

$(PRIMARY).json: $(PRIMARY).owl | check_robot
	@$(ROBOT) convert --input $< --output $@
	@echo "Created $@"


.PHONY: base
base: $(PRIMARY)-base.owl

$(PRIMARY)-base.owl: $(EDIT) | check_robot
	@$(ROBOT) remove \
	 --input $< \
	 --select imports \
	 --trim false \
	annotate \
	 --ontology-iri "$(OBO)$(ONT)/$(notdir $@)" \
	 --version-iri "$(RELEASE_PREFIX)$(notdir $@)" \
	 --annotation oboInOwl:date "$(TS)" \
	 --annotation owl:versionInfo "$(DATE)" \
	 --output $@
	@echo "Created $@"


##########################################
## VERIFY build products
##########################################

.PHONY: verify
verify: verify-owl validate-obo
	@echo "Verification complete!"

# Verify symp.owl
V_QUERIES := $(wildcard src/sparql/verify/verify-*.rq)

.PHONY: verify-owl
verify-owl: $(PRIMARY).owl | check_robot build/reports
	@echo ""
	@echo "Verifying $< (see build/reports on error)"
	@$(ROBOT) reason -i $< && echo "## $< reasoning check passed!"
	@$(ROBOT) verify \
	 --input $< \
	 --queries $(V_QUERIES) \
	 --output-dir build/reports

# Using fastobo-validator
.PHONY: validate-obo
validate-obo: ${PRIMARY}.obo | check_fastobo
	@$(FASTOBO) $<


##########################################
## POST-BUILD REPORT
##########################################

# Count classes, imports, and logical defs from old and new
.PHONY: post last-reports new-reports
post: build/reports/branch-count.tsv last-reports new-reports

# all report queries
QUERIES := $(wildcard src/sparql/build/*-report.rq)

# target names for previous release reports
LAST_REPORTS := $(foreach Q,$(QUERIES), build/reports/$(basename $(notdir $(Q)))-last.tsv)
last-reports: $(LAST_REPORTS)
build/reports/%-last.tsv: src/sparql/build/%.rq build/$(ONT)-last.owl | check_robot build/reports
	@echo "Counting: $(notdir $(basename $@))"
	@$(ROBOT) query \
	 --input $(word 2,$^) \
	 --query $< $@

# target names for current release reports
NEW_REPORTS := $(foreach Q,$(QUERIES), build/reports/$(basename $(notdir $(Q)))-new.tsv)
new-reports: $(NEW_REPORTS)
build/reports/%-new.tsv: src/sparql/build/%.rq $(PRIMARY).owl | check_robot build/reports
	@echo "Counting: $(notdir $(basename $@))"
	@$(ROBOT) query \
	 --input $(word 2,$^) \
	 --query $< $@

# create a count of asserted and total (asserted + inferred) classes in each branch
branch_reports := build/reports/temp/branch-count-asserted.tsv \
  build/reports/temp/branch-count-total.tsv
.INTERMEDIATE: $(branch_reports)
build/reports/temp/branch-count-asserted.tsv: $(EDIT) src/sparql/build/branch-count.rq | \
  check_robot build/reports/temp
	@echo "Counting all branches in $<..."
	@$(ROBOT) query \
	 --input $< \
	 --query $(word 2,$^) $@

build/reports/temp/branch-count-total.tsv: $(PRIMARY).owl \
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
