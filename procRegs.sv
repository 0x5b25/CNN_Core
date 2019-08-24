`timescale 1ps/1ps
module procRegs(
    input clock,
    input reset,

    input [4:0] addr_i,
    input [31:0] wrdata_i,
    output reg [31:0] rddata_o,
    input wren_i,

    output [31:0] gp[16],
    output [31:0] inst,
    output [31:0] conf,
    output reg inst_val,
    input [31:0] stat
);
    //General purpose registers
    reg [31:0] gpregs[16];
    assign gp = gpregs;

    //Instruction register
    reg [31:0] ireg;
    assign inst = ireg;

    //Config register
    reg [31:0] creg;
    assign conf = creg;

    //Status, read only
    wire [31:0] stats;
    assign stats = stat;

    always begin
        #1;
        //Read data decoder
        if(addr_i[4] == 0) begin
            rddata_o <= gpregs[addr_i[3:0]];
        end else
        begin
            case(addr_i[3:0])
            0:rddata_o <= ireg;
            1:rddata_o <= creg;
            2:rddata_o <= stats;
            default:rddata_o <= 32'h1CECAFFE;
            endcase
        end
    end

    always@(posedge clock, posedge reset) begin
        if(reset) begin
            creg = 0;
            inst_val = 0;
        end
        else begin
            inst_val = 0;
            if(wren_i) begin
                //
                if(addr_i[4] == 0) begin
                    gpregs[addr_i[3:0]] = wrdata_i;
                end else
                begin
                    case(addr_i[3:0])
                    0:begin ireg  = wrdata_i; inst_val = 1;end
                    1:begin creg  = wrdata_i; end
                    //2:begin stats = wrdata_i; end
                    endcase
                end
            end
        end
    end

endmodule