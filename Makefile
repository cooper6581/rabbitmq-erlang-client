PROJECT = amqp_client
VERSION ?= $(call get_app_version,src/$(PROJECT).app.src)
ifeq ($(VERSION),)
VERSION = 0.0.0
endif

# Release artifacts are put in $(PACKAGES_DIR).
PACKAGES_DIR ?= $(abspath PACKAGES)

TEST_DEPS += rabbit

DEP_PLUGINS = rabbit_common/mk/rabbitmq-build.mk \
	      rabbit_common/mk/rabbitmq-dist.mk \
	      rabbit_common/mk/rabbitmq-run.mk \
	      rabbit_common/mk/rabbitmq-tools.mk

# FIXME: Remove this line once Erlang.mk's ticket #502 gets fixed
# and RabbitMQ updates it.

ERLC_OPTS ?= -Werror +debug_info +warn_export_vars +warn_shadow_vars \
	+warn_obsolete_guard # +bin_opt_info +warn_export_all +warn_missing_spec

# FIXME: Use erlang.mk patched for RabbitMQ, while waiting for PRs to be
# reviewed and merged.

ERLANG_MK_REPO = https://github.com/rabbitmq/erlang.mk.git
ERLANG_MK_COMMIT = rabbitmq-tmp

include rabbitmq-components.mk
include erlang.mk

# --------------------------------------------------------------------
# Distribution.
# --------------------------------------------------------------------

.PHONY: distribution

distribution: docs source-dist package

docs:: edoc
edoc: doc/overview.edoc

doc/overview.edoc: src/overview.edoc.in
	mkdir -p doc
	sed -e 's:%%VERSION%%:$(VERSION):g' < $< > $@

.PHONY: source-dist clean-source-dist

SOURCE_DIST_BASE ?= $(PROJECT)
SOURCE_DIST_SUFFIXES ?= tar.xz zip
SOURCE_DIST ?= $(PACKAGES_DIR)/$(SOURCE_DIST_BASE)-$(VERSION)-src

# The first source distribution file is used by packages: if the archive
# type changes, you must update all packages' Makefile.
SOURCE_DIST_FILES = $(addprefix $(SOURCE_DIST).,$(SOURCE_DIST_SUFFIXES))

.PHONY: $(SOURCE_DIST_FILES)

source-dist: $(SOURCE_DIST_FILES)
	@:

RSYNC ?= rsync
RSYNC_V_0 =
RSYNC_V_1 = -v
RSYNC_V_2 = -v
RSYNC_V = $(RSYNC_V_$(V))
RSYNC_FLAGS += -a $(RSYNC_V)		\
	       --exclude '.sw?' --exclude '.*.sw?'	\
	       --exclude '*.beam'			\
	       --exclude '*.pyc'			\
	       --exclude '.git*'			\
	       --exclude '.hg*'				\
	       --exclude '.travis.yml'			\
	       --exclude '$(notdir $(ERLANG_MK_TMP))'	\
	       --exclude 'ebin'				\
	       --exclude 'erl_crash.dump'		\
	       --exclude 'deps/'			\
	       --exclude '$(notdir $(DEPS_DIR))/'	\
	       --exclude 'doc/'				\
	       --exclude 'plugins/'			\
	       --exclude '$(notdir $(DIST_DIR))/'	\
	       --exclude '/$(notdir $(PACKAGES_DIR))/'	\
	       --delete					\
	       --delete-excluded

TAR ?= tar
TAR_V_0 =
TAR_V_1 = -v
TAR_V_2 = -v
TAR_V = $(TAR_V_$(V))

GZIP ?= gzip
BZIP2 ?= bzip2
XZ ?= xz

ZIP ?= zip
ZIP_V_0 = -q
ZIP_V_1 =
ZIP_V_2 =
ZIP_V = $(ZIP_V_$(V))

.PHONY: $(SOURCE_DIST)

$(SOURCE_DIST): $(ERLANG_MK_RECURSIVE_DEPS_LIST)
	$(verbose) mkdir -p $(dir $@)
	$(gen_verbose) $(RSYNC) $(RSYNC_FLAGS) ./ $@/
	$(verbose) sed -E -i.bak \
		-e 's/[{]vsn[[:blank:]]*,[^}]+}/{vsn, "$(VERSION)"}/' \
		$@/src/$(PROJECT).app.src && \
		rm $@/src/$(PROJECT).app.src.bak
	$(verbose) for dep in $$(cat $(ERLANG_MK_RECURSIVE_DEPS_LIST) | grep -v '/$(PROJECT)$$' | LC_COLLATE=C sort); do \
		$(RSYNC) $(RSYNC_FLAGS) \
		 $$dep \
		 $@/deps; \
		if test -f $@/deps/$$(basename $$dep)/erlang.mk && \
		   test "$$(wc -l $@/deps/$$(basename $$dep)/erlang.mk | awk '{print $$1;}')" = "1" && \
		   grep -qs -E "^[[:blank:]]*include[[:blank:]]+(erlang\.mk|.*/erlang\.mk)$$" $@/deps/$$(basename $$dep)/erlang.mk; then \
			echo "include ../../erlang.mk" > $@/deps/$$(basename $$dep)/erlang.mk; \
		fi; \
		sed -E -i.bak "s|^[[:blank:]]*include[[:blank:]]+\.\./.*erlang.mk$$|include ../../erlang.mk|" \
		 $@/deps/$$(basename $$dep)/Makefile && \
		rm $@/deps/$$(basename $$dep)/Makefile.bak; \
	done
	$(verbose) for file in $$(find $@ -name '*.app.src'); do \
		sed -E -i.bak -e 's/[{]vsn[[:blank:]]*,[[:blank:]]*""[[:blank:]]*}/{vsn, "$(VERSION)"}/' $$file; \
		rm $$file.bak; \
	done
	$(verbose) echo "$(PROJECT) $$(git rev-parse HEAD) $$(git describe --tags --exact-match 2>/dev/null || git symbolic-ref -q --short HEAD)" > $@/git-revisions.txt
	$(verbose) for dep in $$(cat $(ERLANG_MK_RECURSIVE_DEPS_LIST)); do \
		(cd $$dep; echo "$$(basename "$$dep") $$(git rev-parse HEAD) $$(git describe --tags --exact-match 2>/dev/null || git symbolic-ref -q --short HEAD)") >> $@/git-revisions.txt; \
	done
	$(verbose) rm $@/README.in
	$(verbose) cp README.in $@/README
	$(verbose) cat "$(BUILD_DOC)" >> $@/README

# TODO: Fix file timestamps to have reproducible source archives.
# $(verbose) find $@ -not -name 'git-revisions.txt' -print0 | xargs -0 touch -r $@/git-revisions.txt

$(SOURCE_DIST).tar.gz: $(SOURCE_DIST)
	$(gen_verbose) cd $(dir $(SOURCE_DIST)) && \
		find $(notdir $(SOURCE_DIST)) -print0 | LC_COLLATE=C sort -z | \
		xargs -0 $(TAR) $(TAR_V) --no-recursion -cf - | \
		$(GZIP) --best > $@

$(SOURCE_DIST).tar.bz2: $(SOURCE_DIST)
	$(gen_verbose) cd $(dir $(SOURCE_DIST)) && \
		find $(notdir $(SOURCE_DIST)) -print0 | LC_COLLATE=C sort -z | \
		xargs -0 $(TAR) $(TAR_V) --no-recursion -cf - | \
		$(BZIP2) > $@

$(SOURCE_DIST).tar.xz: $(SOURCE_DIST)
	$(gen_verbose) cd $(dir $(SOURCE_DIST)) && \
		find $(notdir $(SOURCE_DIST)) -print0 | LC_COLLATE=C sort -z | \
		xargs -0 $(TAR) $(TAR_V) --no-recursion -cf - | \
		$(XZ) > $@

$(SOURCE_DIST).zip: $(SOURCE_DIST)
	$(verbose) rm -f $@
	$(gen_verbose) cd $(dir $(SOURCE_DIST)) && \
		find $(notdir $(SOURCE_DIST)) -print0 | LC_COLLATE=C sort -z | \
		xargs -0 $(ZIP) $(ZIP_V) $@

clean:: clean-source-dist

clean-source-dist:
	$(gen_verbose) rm -rf -- $(SOURCE_DIST_BASE)-*

package: dist
	cp $(DIST_DIR)/*.ez $(PACKAGES_DIR)
