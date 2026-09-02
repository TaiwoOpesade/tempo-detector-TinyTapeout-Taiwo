SIM ?= icarus
TOPLEVEL_LANG ?= verilog

VERILOG_SOURCES += $(PWD)/../src/onset_detector.v
VERILOG_SOURCES += $(PWD)/../src/interval_counter.v
VERILOG_SOURCES += $(PWD)/../src/tempo_estimator.v
VERILOG_SOURCES += $(PWD)/../src/bpm_divider.v
VERILOG_SOURCES += $(PWD)/../src/result_latch.v
VERILOG_SOURCES += $(PWD)/../src/project.v

TOPLEVEL = tt_um_taiwoopesade_tempo_detector_sky26c
MODULE = test,test_edge_cases

include $(shell cocotb-config --makefiles)/Makefile.sim
