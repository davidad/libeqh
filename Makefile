# Makefile for libeqh ( https://github.com/davidad/libeqh )
# (c) 2016 David A. Dalrymple & Eliana Lorch
# See LICENSE for your rights to this software and README.md for instructions.

#------------------------------------------------------------------------------
# Variables

# GNU Make will see all files in these directories as if they were top-level.
VPATH = download
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Detect OS.
UNAME := $(shell uname)
ifeq ($(UNAME),Darwin)
    PLATFORM := darwin
    # This means we are running on OSX.
endif
ifeq ($(UNAME),Linux)
    PLATFORM := linux
endif
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Download fasm.
FASM_DL_VERSION := 1.71.57

ifeq ($(PLATFORM),darwin)
    FASM_DL := fasm-osx.tgz
endif
ifeq ($(PLATFORM),linux)
    FASM_DL := fasm-linux.tgz
    FASM_URL := "https://flatassembler.net/fasm-$(FASM_DL_VERSION).tgz"
    FASM_DL_BIN := fasm/fasm
    FASM_STRIP_COMPONENTS := 1
endif

./fasm: download/$(FASM_DL)
	tar --strip-components=$(FASM_STRIP_COMPONENTS) -xzf $< $(FASM_DL_BIN)
	touch fasm

download/$(FASM_DL):
	mkdir -p download
	curl $(FASM_URL) -o $@
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Cleaning up.
.PHONY: distclean cleandl clean
clean:
	rm -rf bin

cleandl:
	rm -rf download

distclean: cleandl clean
	rm -rf fasm
#------------------------------------------------------------------------------

