# Verilator testbenches for the H.264 RTL (rtl_spec.md).
#
#   make br      -> build + run the bitreader/expgolomb differential test
#   make clean

REPO         := $(abspath ../..)
RTL_DIR      := $(REPO)/rtl/src
CMODEL_DIR   := $(REPO)/c_model
CMODEL_BUILD := $(CMODEL_DIR)/build

VERILATOR ?= verilator
VLT_FLAGS := --cc --exe --build -Wall -Wno-fatal --top-module br_eg_top \
             -CFLAGS "-I$(CMODEL_DIR)/src -O2" \
             -Mdir obj_dir_br

CMODEL_OBJS := $(CMODEL_BUILD)/bitstream.o

br: $(CMODEL_OBJS)
	$(VERILATOR) $(VLT_FLAGS) \
	  $(RTL_DIR)/br_eg_top.sv $(RTL_DIR)/bitreader.sv $(RTL_DIR)/expgolomb.sv \
	  tb_bitreader.cpp $(CMODEL_OBJS)
	./obj_dir_br/Vbr_eg_top

$(CMODEL_BUILD)/%.o:
	$(MAKE) -C $(CMODEL_DIR) all

clean:
	rm -rf obj_dir_br

.PHONY: br clean

cavlc:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module cavlc_top \
	  -CFLAGS "-O2" -Mdir obj_dir_cavlc \
	  -I$(REPO)/rtl/include \
	  $(RTL_DIR)/cavlc_top.sv $(RTL_DIR)/bitreader.sv $(RTL_DIR)/cavlc_block.sv \
	  tb_cavlc_block.cpp
	./obj_dir_cavlc/Vcavlc_top $(if $(CAVLC_LOG),$(CAVLC_LOG),/tmp/cavlc.log)

.PHONY: cavlc

MB_OBJS := $(CMODEL_BUILD)/bitstream.o $(CMODEL_BUILD)/nal.o \
           $(CMODEL_BUILD)/params.o $(CMODEL_BUILD)/slice.o \
           $(CMODEL_BUILD)/transform.o

mb: $(CMODEL_OBJS)
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module mb_top \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_mb \
	  -I$(REPO)/rtl/include \
	  $(RTL_DIR)/mb_top.sv $(RTL_DIR)/mb_dec.sv $(RTL_DIR)/bitreader.sv \
	  $(RTL_DIR)/cavlc_block.sv $(RTL_DIR)/expgolomb.sv \
	  $(RTL_DIR)/mv_pred.sv \
	  tb_mb_dec.cpp $(MB_OBJS)
	@echo "built; run: ./obj_dir_mb/Vmb_top <stream> <dump>"

# full R1c regression: every baseline-I CAVLC vector through mb_top
mb-regress: mb
	@pass=0; fail=0; \
	for V in $(REPO)/verification/vectors/phase05/*.264 \
	         $(REPO)/verification/vectors/phase06/*.264; do \
	  H264_RTL_DUMP=/tmp/mb_r.dump $(CMODEL_BUILD)/h264_decode $$V /dev/null \
	      > /dev/null 2>&1; \
	  r=$$(./obj_dir_mb/Vmb_top $$V /tmp/mb_r.dump 2>&1 | tail -1); \
	  case "$$r" in \
	    \[PASS\]*) pass=$$((pass+1));; \
	    *) fail=$$((fail+1)); echo "$$(basename $$V): $$r";; \
	  esac; \
	  rm -f /tmp/mb_r.dump; \
	done; \
	echo "=== mb-regress: $$pass pass, $$fail fail ==="; \
	test $$fail -eq 0

.PHONY: mb mb-regress

xf:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module transform_top \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_xf \
	  -I$(RTL_DIR) \
	  $(RTL_DIR)/transform_top.sv \
	  tb_transform.cpp $(CMODEL_BUILD)/transform.o
	./obj_dir_xf/Vtransform_top

.PHONY: xf

i4:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module intra4x4_pred \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_i4 \
	  $(RTL_DIR)/intra4x4_pred.sv \
	  tb_intra4.cpp $(CMODEL_BUILD)/intra.o
	./obj_dir_i4/Vintra4x4_pred

.PHONY: i4

ifull:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module intra_wrap \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_ifull \
	  $(RTL_DIR)/intra_wrap.sv $(RTL_DIR)/intra_full_pred.sv \
	  tb_intra_full.cpp $(CMODEL_BUILD)/intra.o
	./obj_dir_ifull/Vintra_wrap

.PHONY: ifull

recon:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module mb_recon \
	  -CFLAGS "-O2" -Mdir obj_dir_recon \
	  -I$(RTL_DIR) \
	  $(RTL_DIR)/mb_recon.sv $(RTL_DIR)/mc_fetch.sv $(RTL_DIR)/mc_core.sv $(RTL_DIR)/intra4x4_pred.sv \
	  $(RTL_DIR)/intra_full_pred.sv \
	  tb_mb_recon.cpp
	@echo "built; run: ./obj_dir_recon/Vmb_recon <coef> <rec> <mb_w> <cqp>"

.PHONY: recon

dbe:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module deblock_edge \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_dbe \
	  -I$(REPO)/rtl/include \
	  $(RTL_DIR)/deblock_edge.sv \
	  tb_deblock_edge.cpp $(CMODEL_BUILD)/deblock.o $(CMODEL_BUILD)/transform.o
	./obj_dir_dbe/Vdeblock_edge

.PHONY: dbe

dbf:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module deblock_frame \
	  -CFLAGS "-O2" -Mdir obj_dir_dbf \
	  -I$(REPO)/rtl/include -I$(RTL_DIR) \
	  $(RTL_DIR)/deblock_frame.sv $(RTL_DIR)/deblock_edge.sv \
	  tb_deblock_frame.cpp
	@echo "built; run with args"

.PHONY: dbf

top:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module h264_top \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_top \
	  -I$(REPO)/rtl/include -I$(RTL_DIR) \
	  $(RTL_DIR)/h264_top.sv $(RTL_DIR)/bitreader.sv $(RTL_DIR)/expgolomb.sv \
	  $(RTL_DIR)/cavlc_block.sv $(RTL_DIR)/mb_dec.sv $(RTL_DIR)/mb_recon.sv $(RTL_DIR)/mc_fetch.sv $(RTL_DIR)/mc_core.sv \
	  $(RTL_DIR)/intra4x4_pred.sv $(RTL_DIR)/intra_full_pred.sv \
	  $(RTL_DIR)/deblock_frame.sv $(RTL_DIR)/deblock_edge.sv \
	  tb_h264_top.cpp $(MB_OBJS)
	@echo "built; run: ./obj_dir_top/Vh264_top <stream> <golden.yuv>"

# full-chain frame regression: every baseline-I vector <=320 wide
top-regress: top
	@pass=0; fail=0; \
	for V in $(REPO)/verification/vectors/phase05/*.264 \
	         $(REPO)/verification/vectors/phase06/*.264; do \
	  W=$$(basename $$V | sed 's/.*_\([0-9]*\)x[0-9]*_.*/\1/'); \
	  [ $$W -gt 320 ] && continue; \
	  r=$$(./obj_dir_top/Vh264_top $$V $${V%.264}.yuv 2>&1 | tail -1); \
	  case "$$r" in \
	    \[PASS\]*) pass=$$((pass+1));; \
	    *) fail=$$((fail+1)); echo "$$(basename $$V): $$r";; \
	  esac; \
	done; \
	echo "=== top-regress: $$pass pass, $$fail fail ==="; \
	test $$fail -eq 0

.PHONY: top top-regress

# one-shot RTL regression: every unit bench + both integration sweeps
rtl-regress: br cavlc-regen i4 ifull xf dbe mb-regress top-regress \
             core-regress mc mcf cabac cmb-regress \
             p-regress prec-regress corep-regress
	@echo "=== rtl-regress: all suites passed ==="

# cavlc replay needs a fresh log from the current c_model
cavlc-regen:
	H264_CAVLC_LOG=/tmp/cavlc_rr.log $(CMODEL_BUILD)/h264_decode \
	  $(REPO)/verification/vectors/phase05/p05_grad_100x76_q28.264 \
	  /dev/null > /dev/null 2>&1
	$(MAKE) cavlc CAVLC_LOG=/tmp/cavlc_rr.log

.PHONY: rtl-regress cavlc-regen

dbs:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module deblock_stream \
	  -CFLAGS "-O2" -Mdir obj_dir_dbs \
	  -I$(REPO)/rtl/include -I$(RTL_DIR) \
	  $(RTL_DIR)/deblock_stream.sv $(RTL_DIR)/deblock_edge.sv \
	  tb_deblock_stream.cpp
	@echo "built"

.PHONY: dbs

core:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module h264_core \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_core \
	  -I$(REPO)/rtl/include -I$(RTL_DIR) \
	  $(RTL_DIR)/h264_core.sv $(RTL_DIR)/bitreader.sv $(RTL_DIR)/expgolomb.sv \
	  $(RTL_DIR)/cavlc_block.sv $(RTL_DIR)/mb_dec.sv $(RTL_DIR)/mb_recon.sv $(RTL_DIR)/mc_fetch.sv $(RTL_DIR)/mc_core.sv \
	  $(RTL_DIR)/intra4x4_pred.sv $(RTL_DIR)/intra_full_pred.sv \
	  $(RTL_DIR)/deblock_stream.sv $(RTL_DIR)/deblock_edge.sv \
	  $(RTL_DIR)/cabac_mb.sv $(RTL_DIR)/cabac_core.sv \
	  tb_h264_core.cpp $(MB_OBJS)
	@echo "built"

core-regress: core
	@pass=0; fail=0; \
	for V in $(REPO)/verification/vectors/phase05/*.264 \
	         $(REPO)/verification/vectors/phase06/*.264 \
	         $(REPO)/verification/vectors/phase08/*.264; do \
	  r=$$(./obj_dir_core/Vh264_core $$V $${V%.264}.yuv 2>&1 | tail -1); \
	  case "$$r" in \
	    \[PASS\]*) pass=$$((pass+1));; \
	    *) fail=$$((fail+1)); echo "$$(basename $$V): $$r";; \
	  esac; \
	done; \
	echo "=== core-regress: $$pass pass, $$fail fail ==="; \
	test $$fail -eq 0

.PHONY: core core-regress

mc:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module mc_wrap \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_mc \
	  $(RTL_DIR)/mc_wrap.sv $(RTL_DIR)/mc_core.sv \
	  tb_mc.cpp $(CMODEL_BUILD)/mc.o
	./obj_dir_mc/Vmc_wrap

.PHONY: mc

mcf:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module mc_fetch \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_mcf \
	  $(RTL_DIR)/mc_fetch.sv $(RTL_DIR)/mc_core.sv \
	  tb_mc_fetch.cpp $(CMODEL_BUILD)/mc.o
	./obj_dir_mcf/Vmc_fetch

.PHONY: mcf

pparse:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module mb_top \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_pparse \
	  -I$(REPO)/rtl/include \
	  $(RTL_DIR)/mb_top.sv $(RTL_DIR)/mb_dec.sv $(RTL_DIR)/bitreader.sv \
	  $(RTL_DIR)/cavlc_block.sv $(RTL_DIR)/expgolomb.sv \
	  $(RTL_DIR)/mv_pred.sv \
	  tb_p_parse.cpp $(MB_OBJS)
	@echo built

# P-syntax differential over every CAVLC baseline P stream that the
# dump gate accepts (others come back empty and are counted as skips).
p-regress: pparse
	@pass=0; skip=0; fail=0; \
	for V in $(REPO)/verification/vectors/phase1[3-9]/*.264; do \
	  rm -f /tmp/pregress.dump; \
	  H264_RTL_DUMP_P=/tmp/pregress.dump \
	    $(CMODEL_DIR)/build/h264_decode $$V /tmp/pregress.yuv \
	    >/dev/null 2>&1; \
	  if [ ! -s /tmp/pregress.dump ]; then skip=$$((skip+1)); continue; fi; \
	  r=$$(./obj_dir_pparse/Vmb_top $$V /tmp/pregress.dump 2>&1 | tail -1); \
	  case "$$r" in \
	    \[PASS\]*) pass=$$((pass+1));; \
	    \[SKIP\]*) skip=$$((skip+1));; \
	    *) fail=$$((fail+1)); echo "$$(basename $$V): $$r";; \
	  esac; \
	done; \
	rm -f /tmp/pregress.dump /tmp/pregress.yuv; \
	echo "=== p-regress: $$pass pass, $$skip skip, $$fail fail ==="; \
	test $$fail -eq 0

prec:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module p_rec_top \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_prec \
	  -I$(REPO)/rtl/include -I$(RTL_DIR) \
	  $(RTL_DIR)/p_rec_top.sv $(RTL_DIR)/mb_dec.sv $(RTL_DIR)/bitreader.sv \
	  $(RTL_DIR)/cavlc_block.sv $(RTL_DIR)/expgolomb.sv \
	  $(RTL_DIR)/mv_pred.sv $(RTL_DIR)/mb_recon.sv \
	  $(RTL_DIR)/mc_fetch.sv $(RTL_DIR)/mc_core.sv \
	  $(RTL_DIR)/intra4x4_pred.sv $(RTL_DIR)/intra_full_pred.sv \
	  tb_p_rec.cpp $(MB_OBJS)
	@echo built

# P reconstruction differential over every gated CAVLC baseline P stream
prec-regress: prec
	@pass=0; skip=0; fail=0; \
	for V in $(REPO)/verification/vectors/phase1[3-9]/*.264; do \
	  rm -f /tmp/pr_p.dump /tmp/pr_prec.dump /tmp/pr_ref.dump; \
	  H264_RTL_DUMP_P=/tmp/pr_p.dump \
	  H264_RTL_DUMP_PREC=/tmp/pr_prec.dump \
	  H264_RTL_DUMP_REF=/tmp/pr_ref.dump \
	    $(CMODEL_DIR)/build/h264_decode $$V /tmp/pr.yuv \
	    >/dev/null 2>&1; \
	  if [ ! -s /tmp/pr_prec.dump ] || [ ! -s /tmp/pr_ref.dump ]; then \
	    skip=$$((skip+1)); continue; fi; \
	  r=$$(./obj_dir_prec/Vp_rec_top $$V /tmp/pr_prec.dump \
	       /tmp/pr_ref.dump 2>&1 | tail -1); \
	  case "$$r" in \
	    \[PASS\]*) pass=$$((pass+1));; \
	    \[SKIP\]*) skip=$$((skip+1));; \
	    *) fail=$$((fail+1)); echo "$$(basename $$V): $$r";; \
	  esac; \
	done; \
	rm -f /tmp/pr_p.dump /tmp/pr_prec.dump /tmp/pr_ref.dump /tmp/pr.yuv; \
	echo "=== prec-regress: $$pass pass, $$skip skip, $$fail fail ==="; \
	test $$fail -eq 0

# full decoder objects for benches that call h264_decode() directly
DEC_OBJS := $(CMODEL_BUILD)/bitstream.o $(CMODEL_BUILD)/nal.o \
            $(CMODEL_BUILD)/params.o $(CMODEL_BUILD)/slice.o \
            $(CMODEL_BUILD)/cavlc.o $(CMODEL_BUILD)/cabac.o \
            $(CMODEL_BUILD)/intra.o $(CMODEL_BUILD)/transform.o \
            $(CMODEL_BUILD)/mc.o $(CMODEL_BUILD)/deblock.o \
            $(CMODEL_BUILD)/decoder.o

corep:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module h264_core \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_corep \
	  -I$(REPO)/rtl/include -I$(RTL_DIR) \
	  $(RTL_DIR)/h264_core.sv $(RTL_DIR)/bitreader.sv $(RTL_DIR)/expgolomb.sv \
	  $(RTL_DIR)/cavlc_block.sv $(RTL_DIR)/mb_dec.sv $(RTL_DIR)/mb_recon.sv \
	  $(RTL_DIR)/mc_fetch.sv $(RTL_DIR)/mc_core.sv $(RTL_DIR)/mv_pred.sv \
	  $(RTL_DIR)/intra4x4_pred.sv $(RTL_DIR)/intra_full_pred.sv \
	  $(RTL_DIR)/deblock_stream.sv $(RTL_DIR)/deblock_edge.sv \
	  $(RTL_DIR)/cabac_mb.sv $(RTL_DIR)/cabac_core.sv \
	  tb_h264_core_p.cpp $(DEC_OBJS)
	@echo built

# multi-frame I/P streams through the full core with writeback
corep-regress: corep
	@pass=0; skip=0; fail=0; \
	for V in $(REPO)/verification/vectors/phase13/*.264 \
	         $(REPO)/verification/vectors/phase14/*.264 \
	         $(REPO)/verification/vectors/phase1[5-9]/*.264; do \
	  r=$$(./obj_dir_corep/Vh264_core $$V 2>&1 | tail -1); \
	  case "$$r" in \
	    \[PASS\]*) pass=$$((pass+1));; \
	    \[SKIP\]*) skip=$$((skip+1));; \
	    *) fail=$$((fail+1)); echo "$$(basename $$V): $$r";; \
	  esac; \
	done; \
	echo "=== corep-regress: $$pass pass, $$skip skip, $$fail fail ==="; \
	test $$fail -eq 0

cabac:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module cabac_core \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_cabac \
	  -I$(REPO)/rtl/include \
	  $(RTL_DIR)/cabac_core.sv \
	  tb_cabac.cpp $(CMODEL_BUILD)/cabac.o
	./obj_dir_cabac/Vcabac_core

cmb:
	$(VERILATOR) --cc --exe --build -Wall -Wno-fatal --top-module cabac_top \
	  -CFLAGS "-I$(CMODEL_DIR)/src -O2" -Mdir obj_dir_cmb \
	  -I$(REPO)/rtl/include \
	  $(RTL_DIR)/cabac_top.sv $(RTL_DIR)/cabac_mb.sv \
	  $(RTL_DIR)/cabac_core.sv $(RTL_DIR)/bitreader.sv \
	  tb_cabac_mb.cpp $(MB_OBJS)
	@echo built

# CABAC I-slice MB-layer differential over phase08/09 vectors
cmb-regress: cmb
	@pass=0; skip=0; fail=0; \
	for V in $(REPO)/verification/vectors/phase08/*.264; do \
	  [ -f "$$V" ] || continue; \
	  rm -f /tmp/cmb.dump; \
	  H264_RTL_DUMP=/tmp/cmb.dump \
	    $(CMODEL_DIR)/build/h264_decode $$V /tmp/cmb.yuv >/dev/null 2>&1; \
	  if [ ! -s /tmp/cmb.dump ]; then skip=$$((skip+1)); continue; fi; \
	  r=$$(./obj_dir_cmb/Vcabac_top $$V /tmp/cmb.dump 2>&1 | tail -1); \
	  case "$$r" in \
	    \[PASS\]*) pass=$$((pass+1));; \
	    \[SKIP\]*) skip=$$((skip+1));; \
	    *) fail=$$((fail+1)); echo "$$(basename $$V): $$r";; \
	  esac; \
	done; \
	rm -f /tmp/cmb.dump /tmp/cmb.yuv; \
	echo "=== cmb-regress: $$pass pass, $$skip skip, $$fail fail ==="; \
	test $$fail -eq 0

.PHONY: pparse p-regress prec prec-regress corep corep-regress cabac \
        cmb cmb-regress
