# Makefile --- Mini-project: build, run and measure your matrix multiply unit.
#
# Self-contained: it needs `bsc` on your PATH and nothing else.  `make depth`
# additionally needs yowasp-yosys (see below); the rest works without it.
#
#   make          compile, run both workloads, check correctness, report cycles
#   make depth    report cell count and logic depth of mkMatMul
#   make clean    remove everything generated
#
# `make depth` needs a one-time install, no sudo and no licence:
#
#   pip install --user 'yowasp-yosys==0.68.0.0.post1208'
#
# The version is pinned so that everyone's numbers are comparable.

TOP      = mkTbMatMul
MAIN     = TbMatMul.bsv
DUT      = mkMatMul
DUTSRC   = MatMul.bsv
BUILDDIR = build_bsim
EXE      = $(TOP).bexe

BSC      ?= bsc
BSCFLAGS  = -sim -aggressive-conditions -no-warn-action-shadowing \
            -bdir $(BUILDDIR) -simdir $(BUILDDIR) -info-dir $(BUILDDIR)

.PHONY: all check run link compile depth schedule clean

all: check

$(BUILDDIR):
	@mkdir -p $(BUILDDIR)

# Type-check the BSV and elaborate it down to a Bluesim module.
compile: | $(BUILDDIR)
	$(BSC) $(BSCFLAGS) -u -g $(TOP) $(MAIN)

# Generate C++ for the elaborated design and link it into an executable.
link: compile
	$(BSC) $(BSCFLAGS) -e $(TOP) -o $(EXE)

run: link
	@./$(EXE)

# Turn the simulation's verdict into an exit code, so a wrong answer fails
# loudly instead of printing a wall of output nobody reads to the end.
check: link
	@./$(EXE) | tee $(BUILDDIR)/run.log
	@echo
	@if grep -q '^MINIPROJ OK' $(BUILDDIR)/run.log; then \
	    echo "mini-project: PASS"; \
	else \
	    echo "mini-project: FAIL -- see the output above"; exit 1; \
	fi

# Cells and logic depth: what Bluesim cannot tell you.  See spec §8.
depth:
	@./area-delay.sh $(DUT) $(DUTSRC) .

# Why two rules you expected to fire together never do.  See spec §10.
schedule: | $(BUILDDIR)
	$(BSC) $(BSCFLAGS) -show-schedule -u -g $(DUT) $(DUTSRC)
	@echo
	@echo "schedule written to $(BUILDDIR)/$(DUT).sched"

clean:
	rm -rf $(BUILDDIR) $(EXE) $(TOP).bexe.so .area-delay-$(DUT)
