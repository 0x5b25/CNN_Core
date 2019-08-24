--Copyright (C) 2018  Intel Corporation. All rights reserved.
--Your use of Intel Corporation's design tools, logic functions 
--and other software and tools, and its AMPP partner logic 
--functions, and any output files from any of the foregoing 
--(including device programming or simulation files), and any 
--associated documentation or information are expressly subject 
--to the terms and conditions of the Intel Program License 
--Subscription Agreement, the Intel Quartus Prime License Agreement,
--the Intel FPGA IP License Agreement, or other applicable license
--agreement, including, without limitation, that your use is for
--the sole purpose of programming logic devices manufactured by
--Intel and sold by Intel or its authorized distributors.  Please
--refer to the applicable agreement for further details.


FUNCTION dpram_4096x32 
(
	address_a[11..0],
	address_b[11..0],
	clock_a,
	clock_b,
	data_a[31..0],
	data_b[31..0],
	rden_a,
	rden_b,
	wren_a,
	wren_b
)

RETURNS (
	q_a[31..0],
	q_b[31..0]
);
