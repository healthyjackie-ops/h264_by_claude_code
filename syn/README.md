# Synthesis (ASAP7, yosys + sv2v)

`make sv2v && make synth` — converts the SystemVerilog sources with
sv2v and maps `h264_core` (the per-MB decode engine, frame buffer
excluded) onto ASAP7 7.5T RVT TT through yosys+ABC at 300 MHz.

`asap7/asap7_merged_RVT_TT.lib` (44 MB, not committed): copy from
jpeg_by_claude_code/syn/asap7/ or build from OpenROAD-flow-scripts'
ASAP7 platform by merging the RVT TT NLDM groups.

Reports land in `reports/` (`syn_log.txt` carries the ABC timing line
and the yosys `stat -liberty` area table; memories are kept unmapped
and costed separately via `asap7/asap7_mem_area.py`).
