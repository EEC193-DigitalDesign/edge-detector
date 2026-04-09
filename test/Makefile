# Define the simulator
SIM ?= modelsim

# Define the language
TOPLEVEL_LANG ?= verilog

# List your Verilog source files here (space separated if multiple)
# Makefile inside /test/
VERILOG_SOURCES += $(PWD)/../hdl/nms.v

# The name of the top-level module inside your Verilog file
TOPLEVEL = nms

# The name of your Python test file (without the .py extension)
MODULE = test_edge

# Include the Cocotb makefiles
include $(shell cocotb-config --makefiles)/Makefile.sim