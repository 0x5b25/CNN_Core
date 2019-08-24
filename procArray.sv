`timescale 1ps/1ps
module procArray
#(
    parameter ARRAY_COL_NUM = 4,
	parameter ARRAY_ROW_NUM = 4,
	parameter WDATA_ROW_LEN = 16
)
(
	input clock,
	input reset,
	
	input flush_weight_data_i,
	
	//InterConn write-only master: row data output

    output reg [39:0] icm_psum_writedata_o,//psum row output
	output reg        icm_psum_cs_o,
	
	//InterConn write-only slave:broadcast data input
	input [39:0] ics_broadcast_writedata_i,
	input        ics_broadcast_cs_i,
	output       ics_broadcast_waitreq_o, //broadcast stall request
	
	//InterConn write-only slave:weight row data input
	input [31:0] ics_weightrow_writedata_i[WDATA_ROW_LEN],
	input        ics_weightrow_cs_i,
	
	//InterConn write-only slave:pu config data input
	input [23:0] ics_conf_writedata_i[ARRAY_COL_NUM],
	input        ics_conf_cs_i
	
);
	/*Array data streaming interface
	
	                   new data input
               +                 +           +
               |                 |           |
               v                 v           v
	                          col 0       col 1       ...
	      +------------+    +-----------+-----------+
	row 0 | weight row |    | PU config | PU config | ...
         +------------+    +-----------------------+
   row 1 | weight row |    | PU config | PU config | ...
         +------------+    +-----------+-----------+
   ...     ...               ...         ...
               +                 +           +
               |                 |           |
               |                 |           |
               v                 v           v
                 old data streams downwards

	*/

	//Processing unit array
	//array clock and reset
	wire puarray_clock = clock;
	wire puarray_reset = reset;
	
   reg [39:0] row_psum_writedata_o[ARRAY_COL_NUM];//psum row output
	wire       row_psum_waitreq_i;
	reg row_psum_valid_o;
	reg [ARRAY_COL_NUM - 1:0]row_psum_wordenable_o;
	
	//array broadcast network stall signal
	wire [ARRAY_ROW_NUM - 1:0] brostall_row_collector_input; //stall signal collector for each row
	wire broadcaststall = |brostall_row_collector_input; //broadcast stall request
	
	assign ics_broadcast_waitreq_o = broadcaststall;//broadcast stall request
	
	wire [31:0] stream_to_next_weightdata[ARRAY_ROW_NUM][WDATA_ROW_LEN];
	wire [39:0] icm_psum_writedata[ARRAY_ROW_NUM][ARRAY_COL_NUM];
	
	wire [39:0] icm_psum_writedata_const_zero[ARRAY_COL_NUM];
	
	genvar y_it;
	generate
		for(y_it = 0; y_it < ARRAY_ROW_NUM; y_it++) begin:const_zero
			assign icm_psum_writedata_const_zero[y_it] = 0;
		end
	endgenerate
	
	wire [23:0] stream_to_next_conf[ARRAY_ROW_NUM][ARRAY_COL_NUM];
	
	generate
        
		for(y_it = 0; y_it < ARRAY_ROW_NUM; y_it++) begin:pu_row
        //connections between rows

            

            //outputs
            wire icm_psum_cs;
            wire [ARRAY_COL_NUM - 1:0] icm_psum_wordenable;
            wire icm_psum_waitreq;

            wire [ARRAY_COL_NUM - 1:0] stream_to_prev_psum_valid;
            wire [ARRAY_COL_NUM - 1:0] stream_to_next_psum_can_send;

            wire [ARRAY_COL_NUM - 1:0] stream_to_next_router_stall;

            //array network conns
            wire [31:0] stream_from_prev_weightdata[WDATA_ROW_LEN];
            if(y_it == 0) begin
                assign stream_from_prev_weightdata = ics_weightrow_writedata_i;
            end
            else begin
                assign stream_from_prev_weightdata = stream_to_next_weightdata[y_it - 1];
            end

            wire [ARRAY_COL_NUM - 1:0] stream_from_next_psum_valid;
            if(y_it == ARRAY_ROW_NUM - 1) begin
                assign stream_from_next_psum_valid = 0;
            end
            else begin
                assign stream_from_next_psum_valid = pu_row[y_it + 1].stream_to_prev_psum_valid;
            end

            wire [39:0] stream_from_next_psum_data[ARRAY_COL_NUM];
            if(y_it == ARRAY_ROW_NUM - 1) begin
                assign stream_from_next_psum_data = icm_psum_writedata_const_zero;
            end
            else begin
                assign stream_from_next_psum_data = icm_psum_writedata[y_it + 1];
            end

            wire [ARRAY_COL_NUM - 1:0] stream_from_prev_psum_can_send;
            if(y_it == 0) begin
                assign stream_from_prev_psum_can_send = 0;
            end
            else begin
                assign stream_from_prev_psum_can_send = pu_row[y_it - 1].stream_to_next_psum_can_send;
            end

            wire [23:0] stream_from_prev_conf[ARRAY_COL_NUM];
            if(y_it == 0) begin
                assign stream_from_prev_conf = ics_conf_writedata_i;
            end
            else begin
                assign stream_from_prev_conf = stream_to_next_conf[y_it - 1];
            end
           /*
            wire [ARRAY_COL_NUM - 1:0] stream_from_prev_router_stall;
            if(y_it == 0) begin
                assign stream_from_prev_router_stall = 0;
            end
            else begin
                assign stream_from_prev_router_stall = pu_row[y_it - 1].stream_to_next_router_stall;
            end*/
		
			//Processing unit row
			//config data streaming outputs
			procRow#(
                .PU_ROW_LEN(ARRAY_COL_NUM),
                .WDATA_ROW_LEN(WDATA_ROW_LEN)
            )pu_row_inst(
                .clock(puarray_clock),
                .reset(puarray_reset),
                .flush_weight_data_i(flush_weight_data_i),

                .stream_from_prev_weightdata_i(stream_from_prev_weightdata),
	            .stream_from_global_weightdata_valid_i(ics_weightrow_cs_i),
                .stream_to_next_weightdata_o(stream_to_next_weightdata[y_it]),
	
	//InterConn write-only slave:broadcast data input
	            .ics_broadcast_writedata_i(ics_broadcast_writedata_i),
	            .ics_broadcast_cs_i(ics_broadcast_cs_i),
	            .ics_broadcast_waitreq_o(brostall_row_collector_input[y_it]), //broadcast stall request

    //InterConn write-only master: row psum data output
	            .icm_psum_writedata_o(icm_psum_writedata[y_it]),//psum row output
	            .icm_psum_cs_o(icm_psum_cs),
	            .icm_psum_wordenable_o(icm_psum_wordenable),//Flag indicates valid pu words(40 bits) inside psum row output
	            .icm_psum_waitreq_i(icm_psum_waitreq),

    //Streaming interface: psum
                .stream_to_prev_psum_valid_o(stream_to_prev_psum_valid),
                .stream_from_next_psum_valid_i(stream_from_next_psum_valid),
                .stream_from_next_psum_data_i(stream_from_next_psum_data),
                .stream_from_prev_psum_can_send_i(stream_from_prev_psum_can_send),
                .stream_to_next_psum_can_send_o(stream_to_next_psum_can_send),

    //Streaming interface: config
                .stream_from_global_conf_valid_i(ics_conf_cs_i),
                .stream_to_next_conf_o(stream_to_next_conf[y_it]),
                .stream_from_prev_conf_i(stream_from_prev_conf)

    //streaming interface: router stall signal chain
                //.stream_from_prev_router_stall_i(stream_from_prev_router_stall),
                //.stream_to_next_router_stall_o(stream_to_next_router_stall)
            );
		end
	endgenerate
	
	//Gather all row's necessary signals
	wire [ARRAY_COL_NUM - 1:0] psum_wordenable_collect[ARRAY_ROW_NUM];
	wire [ARRAY_ROW_NUM - 1:0] psum_cs_collect;
	wire [39:0] psum_writedata_row_collect[ARRAY_ROW_NUM][ARRAY_COL_NUM];
	
	generate
		genvar ro_collect_it;
		for(ro_collect_it = 0; ro_collect_it < ARRAY_ROW_NUM; ro_collect_it = ro_collect_it + 1)begin:rovalid_collect
			assign psum_wordenable_collect    [ro_collect_it] = pu_row[ro_collect_it].icm_psum_wordenable;
			assign psum_cs_collect            [ro_collect_it] = pu_row[ro_collect_it].icm_psum_cs;
			assign psum_writedata_row_collect [ro_collect_it] = icm_psum_writedata[ro_collect_it];
		end
	endgenerate
	//wire t = pu_row[tit].output_all_valid;
	
	//Output mux
	reg [3:0] row_granted;
	//fix priority row arbitration and io selecton
	integer mux_row_it;
	integer psum_o_init_it;
	always@(*) begin
		row_granted = 0;
		for(psum_o_init_it = 0; psum_o_init_it < ARRAY_COL_NUM; psum_o_init_it = psum_o_init_it + 1) begin
			row_psum_writedata_o[psum_o_init_it] = 0;//psum row output
		end
		row_psum_valid_o = 0;
		row_psum_wordenable_o = 0;
		for(mux_row_it = 0; mux_row_it < ARRAY_ROW_NUM; mux_row_it = mux_row_it + 1) begin
			if(psum_cs_collect[mux_row_it] == 1) begin
				row_granted = mux_row_it;
				row_psum_writedata_o = psum_writedata_row_collect[mux_row_it];//psum row output
	            row_psum_valid_o = 1;
	            row_psum_wordenable_o = psum_wordenable_collect[mux_row_it];
			end
		end
	end
	
	//row output wait signal generation
	generate
		genvar stall_row_it;
		for(stall_row_it = 0; stall_row_it < ARRAY_ROW_NUM; stall_row_it = stall_row_it + 1) begin:pu_row_stall_sig
			assign pu_row[stall_row_it].icm_psum_waitreq = (stall_row_it != row_granted) || row_psum_waitreq_i;
		end
	endgenerate

    //parallel output to serial output
    //output reg [39:0] row_psum_writedata_o[ARRAY_COL_NUM],//psum row output
	//output reg        row_psum_valid_o,
	//output reg [ARRAY_COL_NUM - 1:0] row_psum_wordenable_o,//Flag indicates valid pu words(40 bits) inside psum row output
	//input             row_psum_waitreq_i,
    //output reg [39:0] icm_psum_writedata_o,//psum row output
	//output reg        icm_psum_cs_o,
    reg [ARRAY_COL_NUM - 1:0] selectedBit;
    reg [ARRAY_COL_NUM - 1:0] wordEnaBits;
    wire [ARRAY_COL_NUM - 1:0] wordEnaBits_masked = wordEnaBits & ~selectedBit;
    reg busy;

    assign row_psum_waitreq_i = row_psum_valid_o & busy;

    integer osel_it;
    reg [1:0] osel_state = 0;
    always@(posedge clock or posedge reset) begin
        if(reset) begin
            osel_state <= 0;
            wordEnaBits <= 0;
            selectedBit <= 0;
            icm_psum_cs_o <= 0;
        end
        else begin
            case(osel_state)
                default:begin//idle
                    busy <= 1;
                    icm_psum_cs_o <= 0;
                    if(row_psum_valid_o) begin
                        wordEnaBits <= row_psum_wordenable_o;
                        selectedBit <= 0;
                        osel_state <= 1;
                    end
                end
                1:begin//output selection
                    if(wordEnaBits_masked == 0) begin
                        busy <= 0;
                        osel_state <= 2;
                        icm_psum_cs_o <= 0;
                    end
                    else begin
                        busy <= 1;
                        icm_psum_cs_o <= 1;
                    end
                    wordEnaBits = wordEnaBits_masked;
                    for(osel_it = ARRAY_COL_NUM - 1; osel_it >= 0; osel_it = osel_it - 1) begin
                        if(wordEnaBits_masked[osel_it] == 1) begin
                            selectedBit = 1 << osel_it;
                        end
                    end
                end
                2:begin//release
                    busy <= 1;
                    icm_psum_cs_o <= 0;
                    osel_state <= 0;
                end
            endcase
        end
    end
    /*always@(posedge clock or posedge reset) begin
        if(reset) begin
            wordEnaBits = 0;
            selectedBit = 0;
        end
        else begin
            if(wordEnaBits == 0) begin
                selectedBit = 0;
                //Release wait request
                //Load new output if possible
                if(row_psum_valid_o) begin
                    wordEnaBits = row_psum_wordenable_o;
                    busy = 0;
                    for(osel_it = ARRAY_COL_NUM - 1; osel_it >= 0; osel_it = osel_it - 1) begin
                        if(row_psum_wordenable_o[osel_it] == 1) begin
                            busy = 1;
                            selectedBit = 1 << osel_it;
                        end
                    end
                end
                else begin
                    busy = 1;
                end
            end
            else begin
                busy = 0;
                wordEnaBits = wordEnaBits_masked;
                for(osel_it = ARRAY_COL_NUM - 1; osel_it >= 0; osel_it = osel_it - 1) begin
                    if(wordEnaBits_masked[osel_it] == 1) begin
                        busy = 1;
                        selectedBit = 1 << osel_it;
                    end
                end
            end
        end
    end*/
	
    //Output priority arbitrator
    always begin
        #1;
        icm_psum_writedata_o = 0;
        for(osel_it = ARRAY_COL_NUM - 1; osel_it >= 0; osel_it = osel_it - 1) begin
            if(wordEnaBits[osel_it] == 1) begin
                icm_psum_writedata_o = row_psum_writedata_o[osel_it];
            end
        end
    end
	
endmodule