module procUnit
#(
    parameter WDATA_ROW_LEN = 16
)
(
    input clock,
    input reset,

    input  [31:0] weights[WDATA_ROW_LEN],

    //Config streaming
    input  [23:0] confin_i,
	input         confvalid_i,
	output [23:0] confout_o,

    //Route connections
    //Pipeline stall signal chain
	input         stall_omux_i,  //stall chain input, ignored when psum_output is disabled
	//input         stall_prev_i,  //stall signal from previous chain node, ignored when psum_output is enabled
	//output        stall_router_o,      //stall signal output to next chain node and calculation core
	
	//Broadcast receiver
	input  [39:0] broadcastdata_i,
	input         broadcastvalid_i,
	output        broadcaststall_o, // flag indicates core is stalled and can't receive new data
	
	//Psum data routing
	input  [39:0] psum_i,
    input         psum_valid_i,
	output [39:0] psum_o,
	output        psum_to_prev_valid_o,
	output        psum_to_omux_valid_o,

    //Psum data integrity features
    input         psum_can_send_i,      //From previous node, whether we can send psum to that node
    output        psum_can_accept_o   //To subsequent node(s), whether we can accept psum input
	
);
    wire [31:0] fifodatain;
    wire fifowrite;

    wire fifofull;
    wire fifoempty;
    wire [31:0] fifodataout;
    wire fiforead;

    assign broadcaststall_o = fifofull;

    fifo_32 accfifo(
    	.aclr(reset),
    	.clock(clock),
    	.data(fifodatain),
    	.rdreq(fiforead),
    	.wrreq(fifowrite),
    	.empty(fifoempty),
    	.full(fifofull),
    	.q(fifodataout),
    	.usedw()
    );

    procControl ctrl(
        .clock(clock),
        .reset(reset),
        .confin_i(confin_i),
        .confvalid_i(confvalid_i),
        .confout_o(confout_o)
    );

    procRouter router(
        .clock(clock),
        .reset(reset),
        //Pipeline stall signal chain
	    .stall_omux_i(stall_omux_i),  //stall chain input, ignored when psum_output is disabled
	    //.stall_prev_i(stall_prev_i),  //stall signal from previous chain node, ignored when psum_output is enabled
	    //.stall_o(stall_router_o),      //stall signal output to next chain node and calculation core
	
	//Psum data routing
	    .psum_i(psum_i),
        .psum_valid_i(psum_valid_i),
        .psum_o(psum_o),
	    .psum_to_prev_valid_o(psum_to_prev_valid_o),
	    .psum_to_omux_valid_o(psum_to_omux_valid_o),

    //Psum data integrity features
        .psum_can_send_i(psum_can_send_i),      //From previous node, whether we can send psum to that node
        .psum_can_accept_o(psum_can_accept_o),   //To subsequent node(s), whether we can accept psum input
	
	//Config input
	    .conf_i(confout_o),

	//Connection to calculation core

    //Acc result FIFO read
        .fifo_empty_i(fifoempty),
        .fifo_rdreq_o(fiforead),
        .fifo_rddata_i(fifodataout)

    );

    wire accdata_valid;
    assign fifowrite = accdata_valid && !fifofull;

    wire [31:0] data      = broadcastdata_i[39:32] == confout_o[7:0] ? broadcastdata_i[31:0] : 32'b0;
    wire        datavalid = broadcastdata_i[39:32] == confout_o[7:0] ? broadcastvalid_i      : 1'b0;

    procCore#(
        .WDATA_ROW_LEN(WDATA_ROW_LEN)
    ) core(
        .clock(clock),
        .reset(reset),
        .conf_i(confout_o),
        .weights(weights),
        .data_i(data),
        .datavalid_i(datavalid),
        .stall_i(fifofull),
        .accresvalid_o(accdata_valid),
        .accres_o(fifodatain)
    );


endmodule