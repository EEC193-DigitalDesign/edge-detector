import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

@cocotb.test()
async def basic_nms_test(dut):
    """A simple test to drive the NMS module"""
    
    # 1. Start a 25 MHz clock on the 'clk' port
    clock = Clock(dut.clk, 40, units="ns") 
    cocotb.start_soon(clock.start())

    # 2. Initialize your inputs
    dut.rst_n.value = 0
    dut.de_in.value = 0
    dut.mag_in.value = 0
    dut.dir_in.value = 0

    # 3. Wait for a few clock cycles, then pull reset high
    for _ in range(5):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1

    # 4. Drive some test data!
    await RisingEdge(dut.clk)
    dut.de_in.value = 1
    dut.mag_in.value = 150 # example magnitude
    dut.dir_in.value = 2   # example direction (90 degrees)

    # Wait to let the pipeline process (e.g., filling the shift registers)
    for _ in range(10):
        await RisingEdge(dut.clk)

    # 5. Read the output
    dut._log.info(f"Final Data Enable Out: {dut.de_out.value}")
    dut._log.info(f"Final Magnitude Out: {dut.mag_out.value}")