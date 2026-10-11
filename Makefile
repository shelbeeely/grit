# SPDX-License-Identifier: CC0-1.0
#
# SPDX-FileContributor: Antonio Niño Díaz, 2023-2025

# Source code paths
# -----------------

INCLUDEDIRS	:= cldib extlib libgrit libplum srcgrit

# Source files
# ------------

SOURCES_C	:= \
	libplum/libplum.c

SOURCES_CPP	:= \
	cldib/cldib_adjust.cpp \
	cldib/cldib_conv.cpp \
	cldib/cldib_core.cpp \
	cldib/cldib_tmap.cpp \
	cldib/cldib_tools.cpp \
	cldib/cldib_wu.cpp \
	libgrit/cprs.cpp \
	libgrit/cprs_huff.cpp \
	libgrit/cprs_lz.cpp \
	libgrit/cprs_rle.cpp \
	libgrit/grit_core.cpp \
	libgrit/grit_misc.cpp \
	libgrit/grit_prep.cpp \
	libgrit/grit_shared.cpp \
	libgrit/grit_xp.cpp \
	libgrit/logger.cpp \
	libgrit/pathfun.cpp \
	extlib/plum.cpp \
	srcgrit/cli.cpp \
	srcgrit/grit_main.cpp

# Version string handling
# -----------------------

# Try to generate a version string if it isn't already provided
ifeq ($(VERSION_STRING),)
    # Try an exact match with a tag (e.g. v1.12.1)
    VERSION_STRING	:= $(shell git describe --tags --exact-match --dirty 2>/dev/null)
    ifeq ($(VERSION_STRING),)
        # Try a non-exact match (e.g. v1.12.1-3-g67a811a)
        VERSION_STRING	:= $(shell git describe --tags --dirty 2>/dev/null)
        ifeq ($(VERSION_STRING),)
            # If no version is provided by the user or git, fall back to this
            VERSION_STRING	:= DEV
        endif
    endif
endif

# Defines passed to all files
# ---------------------------

DEFINES		:= -DVERSION_STRING=\"$(VERSION_STRING)\"

# Libraries
# ---------

LIBS		:=
LIBDIRS		:=

# Build artifacts
# ---------------

NAME		:= grit
BUILDDIR	:= build
ELF		:= $(NAME)

# Tools
# -----

STRIP		:= -s
BINMODE		:= 755

HOSTCC		?= gcc
HOSTCXX		?= g++
CP		:= cp
MKDIR		:= mkdir
RM		:= rm -rf
MAKE		:= make
INSTALL		:= install

# Verbose flag
# ------------

ifeq ($(VERBOSE),1)
V		:=
else
V		:= @
endif

# Compiler and linker flags
# -------------------------

WARNFLAGS_C	:= -Wall -Wextra -Wpedantic -Wstrict-prototypes

WARNFLAGS_CXX	:= -Wall -Wextra

ifeq ($(SOURCES_CPP),)
    HOSTLD	:= $(HOSTCC)
else
    HOSTLD	:= $(HOSTCXX)
endif

INCLUDEFLAGS	:= $(foreach path,$(INCLUDEDIRS),-I$(path)) \
		   $(foreach path,$(LIBDIRS),-I$(path)/include)

LIBDIRSFLAGS	:= $(foreach path,$(LIBDIRS),-L$(path)/lib)

CFLAGS		+= $(WARNFLAGS_C) $(DEFINES) $(INCLUDEFLAGS) -O3

CXXFLAGS	+= $(WARNFLAGS_CXX) $(DEFINES) $(INCLUDEFLAGS) -O3

LDFLAGS		+= $(LIBDIRSFLAGS) $(LIBS)

# Intermediate build files
# ------------------------

OBJS		:= $(addsuffix .o,$(addprefix $(BUILDDIR)/,$(SOURCES_C))) \
		   $(addsuffix .o,$(addprefix $(BUILDDIR)/,$(SOURCES_CPP)))

DEPS		:= $(OBJS:.o=.d)

# Targets
# -------

.PHONY: all clean docs install wasm wasm-node wasm-module

all: $(ELF)

$(ELF): $(OBJS)
	@echo "  HOSTLD  $@"
	$(V)$(HOSTLD) -o $@ $(OBJS) $(LDFLAGS)

clean:
	@echo "  CLEAN  "
	$(V)$(RM) $(ELF) $(BUILDDIR)

# WebAssembly build (Emscripten)
# ------------------------------
#
# wasm-node:   $(WASMDIR)/grit-node.js, a CLI for Node.js that uses the real
#              filesystem: `node grit-node.js image.png -ftc`
# wasm-module: $(WASMDIR)/grit.mjs + grit.wasm, an ES6 module factory for
#              browsers, workers and Node.js that works on an in-memory
#              filesystem. See wasm/grit-wasm.mjs for a high-level wrapper
#              and wasm/index.html for a demo page.

EMCC		?= emcc
EMCXX		?= em++
WASMDIR		:= $(BUILDDIR)/wasm

WASM_OBJS	:= $(addsuffix .o,$(addprefix $(WASMDIR)/obj/,$(SOURCES_C))) \
		   $(addsuffix .o,$(addprefix $(WASMDIR)/obj/,$(SOURCES_CPP)))

WASM_LDFLAGS	:= -O3 -sALLOW_MEMORY_GROWTH=1 -sEXIT_RUNTIME=1

WASM_LDFLAGS_NODE	:= $(WASM_LDFLAGS) -sNODERAWFS=1 -sENVIRONMENT=node

WASM_LDFLAGS_MODULE	:= $(WASM_LDFLAGS) -sMODULARIZE=1 -sEXPORT_ES6=1 \
			   -sEXPORT_NAME=createGritModule -sINVOKE_RUN=0 \
			   -sFORCE_FILESYSTEM=1 \
			   -sEXPORTED_RUNTIME_METHODS=FS,callMain \
			   -sENVIRONMENT=web,worker,node

wasm: wasm-node wasm-module

wasm-node: $(WASMDIR)/grit-node.js

wasm-module: $(WASMDIR)/grit.mjs

$(WASMDIR)/grit-node.js: $(WASM_OBJS)
	@echo "  EMLD    $@"
	$(V)$(EMCXX) -o $@ $(WASM_OBJS) $(WASM_LDFLAGS_NODE)

$(WASMDIR)/grit.mjs: $(WASM_OBJS) wasm/grit-wasm.mjs wasm/index.html
	@echo "  EMLD    $@"
	$(V)$(EMCXX) -o $@ $(WASM_OBJS) $(WASM_LDFLAGS_MODULE)
	$(V)$(CP) wasm/grit-wasm.mjs wasm/index.html $(WASMDIR)/

docs:
	@echo "  DOXYGEN"
	doxygen Doxyfile

INSTALLDIR	?= /opt/blocksds/core/tools/grit
INSTALLDIR_ABS	:= $(abspath $(INSTALLDIR))

install: all
	@echo "  INSTALL $(INSTALLDIR_ABS)"
	@test $(INSTALLDIR_ABS)
	$(V)$(RM) $(INSTALLDIR_ABS)
	$(V)$(INSTALL) -d $(INSTALLDIR_ABS)
	$(V)$(INSTALL) $(STRIP) -m $(BINMODE) $(NAME) $(INSTALLDIR_ABS)
	$(V)$(CP) COPYING $(INSTALLDIR_ABS)

# Rules
# -----

$(BUILDDIR)/%.c.o : %.c
	@echo "  HOSTCC  $<"
	@$(MKDIR) -p $(@D)
	$(V)$(HOSTCC) $(CFLAGS) -MMD -MP -c -o $@ $<

$(BUILDDIR)/%.cpp.o : %.cpp
	@echo "  HOSTCXX $<"
	@$(MKDIR) -p $(@D)
	$(V)$(HOSTCXX) $(CXXFLAGS) -MMD -MP -c -o $@ $<

$(WASMDIR)/obj/%.c.o : %.c
	@echo "  EMCC    $<"
	@$(MKDIR) -p $(@D)
	$(V)$(EMCC) $(CFLAGS) -MMD -MP -c -o $@ $<

$(WASMDIR)/obj/%.cpp.o : %.cpp
	@echo "  EMCXX   $<"
	@$(MKDIR) -p $(@D)
	$(V)$(EMCXX) $(CXXFLAGS) -MMD -MP -c -o $@ $<

# Include dependency files if they exist
# --------------------------------------

-include $(DEPS) $(WASM_OBJS:.o=.d)
