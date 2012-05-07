SOURCES = my_queue.ml actorssg.ml test.ml
EXE = actorssg

all:

	ocp-ocamlc  -thread unix.cma threads.cma -o $(EXE)  $(SOURCES)