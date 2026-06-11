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
	./obj_dir_cavlc/Vcavlc_top /tmp/cavlc.log

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
	  $(RTL_DIR)/mb_recon.sv $(RTL_DIR)/intra4x4_pred.sv \
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
