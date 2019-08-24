module procRow
#(
	parameter PU_ROW_LEN = 16,
	parameter WDATA_ROW_LEN = 16
)
(
	input clock,
	input reset,
	
	//weight data streaming interface
	input         flush_weight_data_i,
	input  [31:0] stream_from_prev_weightdata_i[WDATA_ROW_LEN],
	input         stream_from_global_weightdata_valid_i,
	output [31:0] stream_to_next_weightdata_o[WDATA_ROW_LEN],
	
	//InterConn write-only slave:broadcast data input
	input  [39:0] ics_broadcast_writedata_i,
	input         ics_broadcast_cs_i,
	output        ics_broadcast_waitreq_o, //broadcast stall request

    //InterConn write-only master: row psum data output
	output [39:0]             icm_psum_writedata_o[PU_ROW_LEN],//psum row output
	output                    icm_psum_cs_o,
	output [PU_ROW_LEN - 1:0] icm_psum_wordenable_o,//Flag indicates valid pu words(40 bits) inside psum row output
	input                     icm_psum_waitreq_i,

    //Streaming interface: psum
    output [PU_ROW_LEN - 1:0] stream_to_prev_psum_valid_o,
    input  [PU_ROW_LEN - 1:0] stream_from_next_psum_valid_i,
    input  [39:0]             stream_from_next_psum_data_i[PU_ROW_LEN],
    input  [PU_ROW_LEN - 1:0] stream_from_prev_psum_can_send_i,
    output [PU_ROW_LEN - 1:0] stream_to_next_psum_can_send_o,

    //Streaming interface: config
    input         stream_from_global_conf_valid_i,
    output [23:0] stream_to_next_conf_o[PU_ROW_LEN],
    input  [23:0] stream_from_prev_conf_i[PU_ROW_LEN]

    //streaming interface: router stall signal chain
    //input  [PU_ROW_LEN - 1:0] stream_from_prev_router_stall_i,
    //output [PU_ROW_LEN - 1:0] stream_to_next_router_stall_o
);


	reg [31:0] weightrow[WDATA_ROW_LEN];
	assign stream_to_next_weightdata_o = weightrow;
	
	generate
		//buffer data streaming
		begin:wdata_stream_node
			always@(posedge clock or posedge flush_weight_data_i) begin
				if(flush_weight_data_i) begin
					integer flush_wl_body;
					for(flush_wl_body = 0; flush_wl_body < 16; flush_wl_body = flush_wl_body + 1)
						weightrow[flush_wl_body] <= 0;
				end
				else if(stream_from_global_weightdata_valid_i)
					weightrow <= stream_from_prev_weightdata_i;
			end
		end
	endgenerate
	
	//Broadcast signals
	wire [PU_ROW_LEN - 1:0] brostall_collector_input;//stall signal collector for each pu package in this row
	assign ics_broadcast_waitreq_o = |brostall_collector_input;
			
	//Row io signals
	wire [PU_ROW_LEN - 1:0] output_ready_collector_input;					//row collector for psum valid signal
    wire [PU_ROW_LEN - 1:0] pu_enabled_collector_input;					//row collector for psum valid signal
	assign icm_psum_cs_o = output_ready_collector_input == pu_enabled_collector_input && pu_enabled_collector_input != 0;//Every single pu inside current row's output is valid
	
	generate
        genvar x_it;
        for(x_it = 0; x_it < PU_ROW_LEN; x_it++) begin:pu_package
            wire [23:0] conf_data;
            assign stream_to_next_conf_o[x_it] = conf_data;
            //Psum output
            wire [39:0] psum;
            wire psum_to_prev_valid;
            wire psum_to_omux_valid;
            assign output_ready_collector_input[x_it] = psum_to_omux_valid;
            assign pu_enabled_collector_input[x_it] = conf_data[23]/*pu enable bit*/;
            assign icm_psum_wordenable_o[x_it] = psum_to_omux_valid;
            assign icm_psum_writedata_o[x_it] = psum;
            assign stream_to_prev_psum_valid_o[x_it] = psum_to_prev_valid;

            //Whether current node's router should stall
            wire stall_this_router = psum_to_omux_valid & (!icm_psum_cs_o/*sync all pu in the same row*/ || icm_psum_waitreq_i);
				
            //processing unit instance
            procUnit #(
                .WDATA_ROW_LEN(WDATA_ROW_LEN)
            ) pu_core(
                .clock(clock),
                .reset(reset),

                .weights(weightrow),

                //Config streaming
                .confin_i(stream_from_prev_conf_i[x_it]),
                .confvalid_i(stream_from_global_conf_valid_i),
                .confout_o(conf_data),

                //Route connections
                //Pipeline stall signal chain
                .stall_omux_i(stall_this_router),  //stall chain input, ignored when psum_output is disabled
                //.stall_prev_i(stream_from_prev_router_stall_i[x_it]),  //stall signal from previous chain node, ignored when psum_output is enabled
                //.stall_router_o(stream_to_next_router_stall_o[x_it]),      //stall signal output to next chain node and calculation core
	
                //Broadcast receiver
                .broadcastdata_i(ics_broadcast_writedata_i),
                .broadcastvalid_i(ics_broadcast_cs_i),
                .broadcaststall_o(brostall_collector_input[x_it]), // flag indicates core is stalled and can't receive new data
	
                //Psum data routing
                .psum_i(stream_from_next_psum_data_i[x_it]),
                .psum_valid_i(stream_from_next_psum_valid_i[x_it]),
                .psum_o(psum),
                .psum_to_prev_valid_o(psum_to_prev_valid),
                .psum_to_omux_valid_o(psum_to_omux_valid),

                //Psum data integrity features
                .psum_can_send_i(stream_from_prev_psum_can_send_i[x_it]),      //From previous node, whether we can send psum to that node
                .psum_can_accept_o(stream_to_next_psum_can_send_o[x_it])   //To subsequent node(s), whether we can accept psum input
	
			);
		end //pu_package
	endgenerate

endmodule