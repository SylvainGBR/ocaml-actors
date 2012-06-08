SOURCES = my_queue.ml actors.ml actorssg.ml
EXEC1 = client
EXEC2 = server 
CAMLC = ocamlc
CAMLOPT = ocamlopt
CAMLDEP = ocamldep
LIBS=$(WITHUNIX) $(WITHTHREADS)
WITHUNIX =unix.cma
WITHTHREADS =-thread threads.cma

# opt : $(EXEC1).opt
# OBJS = $(SOURCES2:.ml=.cmo)
# OPTOBJS = $(SOURCES:.ml=.cmx)

CLIENT_OBJS=$(SOURCES:.ml=.cmo) client.cmo
SERVER_OBJS=$(SOURCES:.ml=.cmo) server.cmo

all: $(EXEC1) $(EXEC2)

$(EXEC1): $(CLIENT_OBJS)
	$(CAMLC) -o $(EXEC1) $(LIBS) $(CLIENT_OBJS)

$(EXEC2): $(SERVER_OBJS)
	$(CAMLC) -o $(EXEC2) $(LIBS) $(SERVER_OBJS)

# $(EXEC1).opt: $(OPTOBJS)
# 	$(CAMLOPT) -o $(EXEC1) $(LIBS:.cma=.cmxa) $(OPTOBJS)

# $(EXEC2).opt: $(OPTOBJS)
# 	$(CAMLOPT) -o $(EXEC2) $(LIBS:.cma=.cmxa) $(OPTOBJS)

.SUFFIXES:
.SUFFIXES: .ml .mli .cmo .cmi .cmx .mll .mly

.ml.cmo:
	$(CAMLC) $(LIBS) -c $< 

.mli.cmi:
	$(CAMLC) -c $<

.ml.cmx:
	$(CAMLOPT) -c $<
clean:
	rm -f *.cm[iox] *~ .*~ #*#
	rm -f $(EXEC1)
	rm -f $(EXEC1).opt
	rm -f $(EXEC2)
	rm -f $(EXEC2).opt

depend: $(SOURCE)
	$(CAMLDEP) *.mli *.ml > .depend

include .depend