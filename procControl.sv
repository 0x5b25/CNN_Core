//Processing unit control module
module procControl(
	input clock,
	input reset,
	
	input [23:0] confin_i,
	input confvalid_i,
	output [23:0] confout_o
);
	//Config
	// +--------------------+
	// | Enable             | [23] 1 bit Enable this proc unit
	// +--------------------+ 
	// | Psum input         | [22] 1 bit Whether this proc unit shall accept psum from subsequent proc unit
	// +--------------------+ 
	// | Psum output        | [21] 1 bit 0:Psum to previous proc unit; 1:Psum to output mux
    // +--------------------+
    // | In-cache mode      | [20] 1 bit Whether use data inside cache or wait for new data input
	// +--------------------+ 
	// | Weight row length  | [19:16] 4 bit
	// +--------------------+ 
	// | Cache valid length | [15:8] 8 bit Used with In-cache mode together to mark valid cache length
	// +--------------------+ 
	// | PC ID              | [7:0] 8 bit
	// +--------------------+ 
	//
	
	reg enable;
	reg pinput;
	reg poutput;
    reg incache;
	reg [3:0] weightlen;
    reg [7:0] cachelen;
	reg [7:0] id;
	
	assign confout_o = {
		enable,
		pinput,
		poutput,
        incache,
		weightlen,
        cachelen,
		id
	};
	
	always@(posedge clock or posedge reset) begin
		if(reset) begin
			enable <= 0;
			pinput <= 0;
			poutput <= 0;
            incache <= 0;
			weightlen <= 0;
            cachelen <= 0;
			id <= 0;
		end
		else begin
			if(confvalid_i) begin
				{
					enable,
		            pinput,
		            poutput,
                    incache,
		            weightlen,
                    cachelen,
		            id
				} <= confin_i;
			end
		end
	end

endmodule