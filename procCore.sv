//Processing unit calculation core
module procCore
#(
    parameter WDATA_ROW_LEN = 16
)
(
	input clock,
	input reset,
	
	//Configs
	input [23:0] conf_i,//Kernel length
	
	//Kernel(Weight) data
	input [31:0] weights[WDATA_ROW_LEN],
	
	//Input data
	input [31:0] data_i,
	input datavalid_i,
	input stall_i,
	
	//Test outputs
	output accresvalid_o,
	output [31:0] accres_o
);

    //config decode
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

	wire stallpipeline; // Stall the pipeline, mainly triggererd by a full output buffer
	assign stallpipeline = stall_i || !conf_enable;
	
	
	//Multiplier
	
	wire [31:0] mulres;			//Multiply result
    reg mulen = 0;

    reg [7:0] datawraddr = 0;
    reg [7:0] mulbaseaddr = 0;
    reg [3:0] muloffsetaddr = 0;

    reg [0:0] mulstate = 0;
	always@(posedge clock or posedge reset) begin
		if(reset) begin
			datawraddr <= 0;
			mulbaseaddr <= 0;
            muloffsetaddr <= 0;
			mulen <= 0;
			mulstate <= 0;
		end
		else if(!stallpipeline) begin
			//data cache address calculate
			if(datavalid_i) begin
				if(!conf_incache)
					datawraddr <= datawraddr + 8'b1;
                else
                    datawraddr <= conf_cachelen;
			end

            //multiplier state machine
			case(mulstate)
			default:begin//kickstart
				if(datavalid_i) begin
					mulen <= 1;
                    if(conf_incache) begin
                        mulstate <= 1;

                    end
                    else begin
					    if(muloffsetaddr >= conf_weightlen - 1) begin
						    mulstate <= 1;
                            muloffsetaddr <= 0;
                            mulbaseaddr <= mulbaseaddr + 8'b1;
					    end
                        else begin
                            muloffsetaddr <= muloffsetaddr + 4'b1;
                        end
                    end
				end
				else begin
					mulen <= 0;
				end
			end
			1:begin//Full accumulation
                if(mulbaseaddr + muloffsetaddr != datawraddr) begin
                    mulen <= 1;
                    if(muloffsetaddr >= conf_weightlen - 1) begin
                        muloffsetaddr <= 0;
                        mulbaseaddr <= mulbaseaddr + 8'b1;
                    end
                    else 
                        muloffsetaddr <= muloffsetaddr + 4'b1;
                end
                else begin
					mulen <= 0;
				end
				
			end
			endcase
		end
	end
	
	wire [31:0] olddata;
    reg [31:0] newdata;
    reg passthrough;
    wire [31:0] data = passthrough?newdata:olddata;
    //Buffer to store data input for convolution input data reuse
	dpram_256x32 databuf(
		.clock (clock),
		.aclr(reset),
		.data (data_i),
		.enable(!stallpipeline),
		.rdaddress (mulbaseaddr + muloffsetaddr),
		.wraddress (datawraddr),
		.wren (datavalid_i & !conf_incache),//lock input while in in-cache mode
		.q (olddata)
	);

    //Pass through logic for read during write operation
    always@(posedge clock) begin
        if(datavalid_i && !conf_incache) begin//if wren is set to 1
            newdata <= data_i;
        end

        if(datavalid_i && !conf_incache && 
            (mulbaseaddr + muloffsetaddr) == datawraddr) begin//if read during write
            passthrough <= 1;
        end
        else
            passthrough <= 0;
    end


    // 1 cycle delay for sram read operation
    reg [3:0] wdrdaddr_delay;
    always@(posedge clock or posedge reset) begin
		if(reset)
			wdrdaddr_delay <= 0;
		else if(!stallpipeline)
			wdrdaddr_delay <= muloffsetaddr;
	end
	
	fpmult mult(
		.aclr(reset),					//input   aclr;
		.clk_en(!stallpipeline),	//input   clk_en;
		.clock(clock),					//input   clock;
		.dataa(data),				//input   [31:0]  dataa;
		.datab(weights[wdrdaddr_delay]),	//input   [31:0]  datab;
		.result(mulres)				//output   [31:0]  result;
	);

    //6 stage delay line to compensate for the pipeline delay
    //Multiplier cycle: 5, sram read delay: 1
	reg [4:0] mul_valid_delay;	
    reg [4:0] mul_first_delay;
    reg [4:0] mul_last_delay;
	always@(posedge clock or posedge reset) begin
		if(reset) begin
			mul_valid_delay <= 0;
            mul_first_delay <= 0;
            mul_last_delay <= 0;
        end
		else if(!stallpipeline) begin
			mul_valid_delay <= {mul_valid_delay[3:0],mulen};
            mul_first_delay <= {mul_first_delay[3:0],wdrdaddr_delay == 0 && mulen};
            mul_last_delay <= {mul_last_delay[3:0],wdrdaddr_delay == conf_weightlen - 1 && mulen};
        end
	end
	wire mulresvalid = mul_valid_delay[4];//value acquired from delay line
    wire mulresfirst = mul_first_delay[4];
    wire mulreslast = mul_last_delay[4];
	
	//Accumulator
	wire [31:0] accres;			//Accumulator result
	
	//Accumulator output delay cycle:4
	reg [3:0] acc_valid_delay;
	wire accresvalid = acc_valid_delay[3];
	always@(posedge clock or posedge reset) begin
		if(reset)
			acc_valid_delay <= 0;
		else if(!stallpipeline)
			acc_valid_delay <= {acc_valid_delay[2:0], mulreslast};
	
	end
		
	fpacc acc(
		.clk(clock),							//								input  wire        clk
		.areset(reset),						//								input  wire        areset
		.x(mulresvalid?mulres:0),	//input acc num			input  wire [31:0] x
		.n(mulresvalid && mulresfirst),	//start new acc			input  wire        n
		.r(accres),								//accumulation result	output wire [31:0] r
		.xo(),									//input overflow. 		output wire        xo
		.xu(),									//input underflow. 		output wire        xu
		.ao(),									//accumulator overflow. output wire        ao
		.en(!stallpipeline)					//enable pipeline			input  wire [0:0]  en
	);
	
	//Only for test purposes
	assign accres_o = accres;
	assign accresvalid_o = accresvalid;

endmodule



















