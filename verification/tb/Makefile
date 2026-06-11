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
