# H.264 baseline-I core synthesis (ASAP7, yosys + sv2v).
#   make sv2v   -> convert rtl/src SystemVerilog to plain Verilog
#   make synth  -> run yosys ASAP7 mapping (reports/ gets stat + netlist)

REPO    := $(abspath ..)
RTL     := $(REPO)/rtl/src
INC     := $(REPO)/rtl/include

SRCS := $(RTL)/h264_core.sv $(RTL)/bitreader.sv $(RTL)/expgolomb.sv \
        $(RTL)/cavlc_block.sv $(RTL)/mb_dec.sv $(RTL)/mb_recon.sv \
        $(RTL)/intra4x4_pred.sv $(RTL)/intra_full_pred.sv \
        $(RTL)/transform_dec.sv $(RTL)/deblock_edge.sv \
        $(RTL)/deblock_stream.sv

sv2v_out.v: $(SRCS)
	sv2v -I$(INC) -I$(RTL) $(SRCS) > $@

sv2v: sv2v_out.v

synth: sv2v_out.v
	cd scripts && yosys syn_asap7.ys 2>&1 | tee ../reports/syn_log.txt | tail -40

clean:
	rm -f sv2v_out.v reports/syn_log.txt reports/h264_core_netlist.v

.PHONY: sv2v synth clean
