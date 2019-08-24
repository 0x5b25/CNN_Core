/*TODO: Reduce long combinational logic chains*/

module procRouter(
	input clock,
	input reset,
	
	//Pipeline stall signal chain
	input stall_omux_i,  //stall chain input, ignored when psum_output is disabled
	//output stall_o,      //stall signal output to next chain node and calculation core
	
	//Psum data routing
	input [39:0] psum_i,
    input psum_valid_i,
	output [39:0] psum_o,
	output psum_to_prev_valid_o,
	output psum_to_omux_valid_o,

    //Psum data integrity features
    input psum_can_send_i,      //From previous node, whether we can send psum to that node
    output psum_can_accept_o,   //To subsequent node(s), whether we can accept psum input
	
	//Config input
	input [23:0] conf_i,

	//Connection to calculation core

    //Acc result FIFO read
    input fifo_empty_i,
    output fifo_rdreq_o,
    input [31:0] fifo_rddata_i
);
    wire stall_this_router;

    //config decode
    wire conf_enable;
	wire conf_psum_input;
	wire conf_psum_output;
    wire conf_incache;
	wire [3:0] conf_weightlen;
    wire [7:0] conf_cachelen;
	wire [7:0] conf_id;

    assign {
        conf_enable,
	    conf_psum_input,
	    conf_psum_output,
        conf_incache,
	    conf_weightlen,
        conf_cachelen,
	    conf_id
    } = conf_i;

    assign psum_o[39:32] = conf_id;
    //FIFO connection
    //Delay chain compensates for 1 cycle delay between rdreq and valid data output
    reg fifo_rdvaild_delay;
    always@(posedge clock or posedge reset) begin
        if(reset == 1)
            fifo_rdvaild_delay <= 0;
        else if(!stall_this_router)
            fifo_rdvaild_delay <= fifo_rdreq_o;
    end
    //In order to deliever the same group of data from fifo and subsequent psum
    //to the chain node adder at the same time, we need to buffer input psum for 1
    //cycle again, to compensate for 1 cycle delay from fifo
    reg [31:0] psum_input_delay;
    reg psum_input_valid_delay;
    always@(posedge clock or posedge reset) begin
        if(reset == 1) begin
            psum_input_delay <= 0;
            psum_input_valid_delay <= 0;
        end
        else if(!stall_this_router) begin
            psum_input_delay <= psum_i[31:0];
            psum_input_valid_delay <= psum_valid_i;
        end
    end
    //read request management
    /*
        +---------+----------+------------------+--------------------------------------------------+
        |         |          |                  |                     Read FIFO                    |
        | Psum in | Psum out |    Condition     +----------+---------------+-----------+-----------+
        |         |          |                  | can send | Psum_in valid | not empty | not stall | 
        +---------+----------+------------------+----------+---------------+-----------+-----------+
        |    0    |    0     | Link end         |    1     |       0       |     1     |     1     |
        +---------+----------+------------------+----------+---------------+-----------+-----------+
        |    0    |    1     | Link with 1 node |    0     |       0       |     1     |     1     |
        +---------+----------+------------------+----------+---------------+-----------+-----------+
        |    1    |    0     | Normal link node |    1     |       1       |     1     |     1     |
        +---------+----------+------------------+----------+---------------+-----------+-----------+
        |    1    |    1     | Link head        |    0     |       1       |     1     |     1     |
        +---------+----------+------------------+----------+---------------+-----------+-----------+
    */
    assign fifo_rdreq_o = (!fifo_empty_i) && (!stall_this_router) &&(
        (conf_psum_output || psum_can_send_i) &&
        ((!conf_psum_input) || psum_valid_i)
    );

	//Add chain
    //enable adder when accepts psum input and is enabled
	wire addchain_ena = conf_psum_input && !stall_this_router;
    wire [31:0] addchain_res;
	//Adder cycle: 7
    reg [6:0] addchain_res_valid_delay = 0;
    always@(posedge clock or posedge reset) begin
        if(reset == 1)
            addchain_res_valid_delay <= 0;
        else if(addchain_ena)
            addchain_res_valid_delay <= {addchain_res_valid_delay[5:0],psum_input_valid_delay && fifo_rdvaild_delay};
    end
	fpadd add(
        .aclr(reset),//input	  aclr;
	    .clk_en(addchain_ena),//input	  clk_en;
	    .clock(clock),//input	  clock;
	    .dataa(fifo_rddata_i),//input	[31:0]  dataa;
	    .datab(psum_input_delay),//input	[31:0]  datab;
	    .result(addchain_res)//output	[31:0]  result;
	);
	
	//Data router
    //Psum output routing
    assign psum_o[31:0]         = conf_psum_input == 1'b1  ? addchain_res                    : fifo_rddata_i;
    wire   psum_valid           = conf_psum_input == 1'b1  ? addchain_res_valid_delay[6]     : fifo_rdvaild_delay;
    assign psum_to_prev_valid_o = conf_psum_output == 1'b1 ? 1'b0                            : psum_valid;
    assign psum_to_omux_valid_o = conf_psum_output == 1'b1 ? psum_valid                      : 1'b0;
    assign psum_can_accept_o    = conf_psum_input == 1'b1  ? !((fifo_empty_i || stall_this_router)&& psum_valid_i) : 1'b0;

    //Stall signaling
    //Not only previous node stalled but also previous node can't accept psum input
    assign stall_this_router = !conf_enable || (conf_psum_output == 1 ? stall_omux_i : !psum_can_send_i);

    //Broadcast filtering


endmodule