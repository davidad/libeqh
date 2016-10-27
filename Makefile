# Makefile for libeqh ( https://github.com/davidad/libeqh )
# (c) 2016 David A. Dalrymple & Eliana Lorch
# See LICENSE for your rights to this software and README.md for instructions.

#------------------------------------------------------------------------------
# Variables

# GNU Make will see all files in these directories as if they were top-level.
SHELL := /bin/bash
VPATH = download
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Default rule
.PHONY: all test bench
all: test bench
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Detect OS.
UNAME := $(shell uname)
ifeq ($(UNAME),Darwin)
    PLATFORM := macos
endif
ifeq ($(UNAME),Linux)
    PLATFORM := linux
endif
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Download fasm.
FASM_DL_VERSION := 1.71.57

ifeq ($(PLATFORM),macos)
    FASM_DL := fasm-macos-$(FASM_DL_VERSION).tgz
endif
ifeq ($(PLATFORM),linux)
    FASM_DL := fasm-linux-$(FASM_DL_VERSION).tgz
    FASM_URL := "https://flatassembler.net/fasm-$(FASM_DL_VERSION).tgz"
    FASM_DL_BIN := fasm/fasm
    FASM_STRIP_COMPONENTS := 1
    FASM_DL_HASH := cd80567beb6ab80bfb795eaba49afb56649e4c25
endif

./fasm: download/$(FASM_DL)
	tar --strip-components=$(FASM_STRIP_COMPONENTS) -xzf $< $(FASM_DL_BIN)
	touch fasm

download/fasm-linux-$(FASM_DL_VERSION).tgz:
	mkdir -p download
	curl $(FASM_URL) -o $@
	test `git hash-object $@` = $(FASM_DL_HASH)

download/fasm-macos-$(FASM_DL_VERSION).tgz:
	@echo "Error: fasm is not supported on macOS, although it is possible"\
	" to make it work. Check back later."
	@false 
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Generate object files
libeqh/syscalls.inc: libeqh/syscalls-$(PLATFORM).inc
	rm -f $@
	ln -s syscalls-$(PLATFORM).inc $@

bin/%.linux.o bin/%-test.linux.o: libeqh/%.asm libeqh/syscalls.inc ./fasm 
	mkdir -p bin
	cd libeqh \
	&& ../fasm $(shell [[ $* == *-test* ]] && echo "-d test=1") \
                   $*.asm ../$@
	rm -f libeqh/syscalls.inc

bin/%.macos.o bin/%-test.macos.o: libeqh/%.asm libeqh/syscalls.inc \
                                  ./fasm ./objconv 
	mkdir -p bin
	cd libeqh \
	&& ../fasm $(shell [[ $* == *-test* ]] && echo "-d test=1") \
                   $*.asm ../$@
	./objconv -fmacho -ar:start:_start -nu $*.o $@
	rm -f $*.o
	rm -f libeqh/syscalls.inc

bin/%.o: bin/%.$(PLATFORM).o
	ln -f $< $@

bin/bench_runner: bench_runner.c libeqh.h bin/libeqh.o
	gcc -std=c99 -o $@ $< bin/libeqh.o
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Generate binaries
bin/libeqh-bench: test/bench.c bin/libeqh.o libeqh.h
	gcc -std=c99 -I. -o $@ bin/libeqh.o $<

bin/libeqh-test: test/test.c bin/libeqh-test.o libeqh.h test/greatest.h
	gcc -std=c99 -I. -DLIBEQH_TEST -o $@ bin/libeqh-test.o $<
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Run binaries
test: bin/libeqh-test
	./$< -v | ./test/greenest
bench: bin/libeqh-bench
	./$<
#------------------------------------------------------------------------------


#------------------------------------------------------------------------------
# Cleaning up.
.PHONY: distclean cleandl clean
clean:
	rm -rf bin libeqh/syscalls.inc

cleandl:
	rm -rf download

distclean: cleandl clean
	rm -rf fasm
#------------------------------------------------------------------------------

