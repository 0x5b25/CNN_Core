module proc_top
#(
    parameter ARRAY_COL_NUM = 16,
	parameter ARRAY_ROW_NUM = 4,
	parameter WDATA_ROW_LEN = 16
)
(
    input clock,
    input reset,

    //Avalon slave
    input [6:2] avs_address_i,
    input [31:0] avs_writedata_i,
    output [31:0] avs_readdata_o,
    input avs_write_i,
    output avs_irq_o,

    //Avalon dma master
    output [31:0] avm_address_o,
    output [31:0] avm_writedata_o,
    input [31:0] avm_readdata_i,
    output avm_read_o,
    output avm_write_o,
    input avm_waitreq_i

);

    wire [31:0] gp[16];
    wire [31:0] inst;
    wire [31:0] conf;//0:interrupt ena
    wire inst_val;
    wire [31:0] stat;//0:idle

    procRegs regs(
        .clock(clock),
        .reset(reset),

        .addr_i(avs_address_i),
        .wrdata_i(avs_writedata_i),
        .rddata_o(avs_readdata_o),
        .wren_i(avs_write_i),

        .gp(gp),
        .inst(inst),
        .conf(conf),
        .inst_val(inst_val),
        .stat(stat)
    );

    wire reset_req;
    wire proc_reset = reset | reset_req;
    wire inst_done;
    assign avs_irq_o = inst_done & conf[0];

    wire [31:0] ic_weightrow_writedata[WDATA_ROW_LEN];
	wire        ic_weightrow_cs;

    wire [39:0] ic_broadcast_writedata;
	wire        ic_broadcast_cs;
	wire        ic_broadcast_waitreq; //broadcast stall request

    wire [39:0] ic_psum_writedata;//psum row output
	wire        ic_psum_cs;

    wire [23:0] ic_conf_writedata[ARRAY_COL_NUM];
	wire        ic_conf_cs;

    wire dma_cs;
    wire dma_wr;
    assign avm_read_o = dma_cs & ~dma_wr;
    assign avm_write_o = dma_cs & dma_wr;

    wire [31:0] sram_readdata;
    wire [31:0] sram_writedata;
    wire [11:0] sram_address;
    wire        sram_wren;
    wire        sram_rden;

    //sram write port
    wire [11:0] sres_address;
    wire [31:0] sres_writedata;
    wire        sres_wren;

    procInstSchd 
    #(
        .ARRAY_COL_NUM(ARRAY_COL_NUM),
	    .ARRAY_ROW_NUM(ARRAY_ROW_NUM),
	    .WDATA_ROW_LEN(WDATA_ROW_LEN)
    )
    instschd(
        .clock(clock),
        .reset(reset),

        .reset_req_o(reset_req),
        .stat_idle_o(stat[0]),

    //Instruction interface
        .instruction_i(inst),
        .instruction_valid_i(inst_val),
        .instruction_done_o(inst_done),

        .gp(gp),

    //Connection between processing array
        .icm_weightrow_writedata_o(ic_weightrow_writedata),
	    .icm_weightrow_cs_o(ic_weightrow_cs),

        .icm_broadcast_writedata_o(ic_broadcast_writedata),
	    .icm_broadcast_cs_o(ic_broadcast_cs),
	    .icm_broadcast_waitreq_i(ic_broadcast_waitreq), //broadcast stall request

        .ics_psum_writedata_i(ic_psum_writedata),//psum row output
	    .ics_psum_cs_i(ic_psum_cs),

        .icm_conf_writedata_o(ic_conf_writedata),
	    .icm_conf_cs_o(ic_conf_cs),

    //dma interface
        .icm_dma_readdata_i(avm_readdata_i),
        .icm_dma_writedata_o(avm_writedata_o),
        .icm_dma_address_o(avm_address_o),
        .icm_dma_cs_o(dma_cs),
        .icm_dma_write_o(dma_wr),
        .icm_dma_waitreq_i(avm_waitreq_i),

    //sram rw interface
        .sram_readdata_i(sram_readdata),
        .sram_writedata_o(sram_writedata),
        .sram_address_o(sram_address),
        .sram_wren_o(sram_wren),
        .sram_rden_o(sram_rden),

    //sram write port
        .sres_address_o(sres_address),
        .sres_writedata_o(sres_writedata),
        .sres_wren_o(sres_wren)
    );

    procArray
    #(
        .ARRAY_COL_NUM(ARRAY_COL_NUM),
	    .ARRAY_ROW_NUM(ARRAY_ROW_NUM),
	    .WDATA_ROW_LEN(WDATA_ROW_LEN)
    )
    proc(
	    .clock(clock),
	    .reset(proc_reset),
	
	    .flush_weight_data_i(),
	
	//InterConn write-only master: row data output

        .icm_psum_writedata_o(ic_psum_writedata),//psum row output
	    .icm_psum_cs_o(ic_psum_cs),
	
	//InterConn write-only slave:broadcast data input
	    .ics_broadcast_writedata_i(ic_broadcast_writedata),
	    .ics_broadcast_cs_i(ic_broadcast_cs),
	    .ics_broadcast_waitreq_o(ic_broadcast_waitreq), //broadcast stall request
	
	//InterConn write-only slave:weight row data input
	    .ics_weightrow_writedata_i(ic_weightrow_writedata),
	    .ics_weightrow_cs_i(ic_weightrow_cs),
	
	//InterConn write-only slave:pu config data input
	    .ics_conf_writedata_i(ic_conf_writedata),
	    .ics_conf_cs_i(ic_conf_cs)
	
    );

    dpram_4096x32 dbuf(
	    .address_a(sram_address),
	    .address_b(sres_address),
	    .clock_a(clock),
	    .clock_b(clock),
	    .data_a(sram_writedata),
	    .data_b(sres_writedata),
	    .wren_a(sram_wren),
	    .wren_b(sres_wren),
        .rden_a(sram_rden),
	    .rden_b(0),
	    .q_a(sram_readdata),
	    .q_b()
    );

endmodule