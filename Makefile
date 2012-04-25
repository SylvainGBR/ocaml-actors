SOURCES = actorssg.ml
EXE = actorssg

all:

	ocp-ocamlc  -thread unix.cma threads.cma -o $(EXE)  $(SOURCES)