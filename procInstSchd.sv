module procInstSchd
#(
    parameter ARRAY_COL_NUM = 4,
	parameter ARRAY_ROW_NUM = 2,
	parameter WDATA_ROW_LEN = 16
)
(
    input clock,
    input reset,

    output reg reset_req_o,

    //Instruction interface
    input [31:0] instruction_i,
    input instruction_valid_i,
    output instruction_done_o,
    output stat_idle_o,

    input [31:0] gp[16],

    //Connection between processing array
    output reg [31:0] icm_weightrow_writedata_o[WDATA_ROW_LEN],
	output reg        icm_weightrow_cs_o,

    output [39:0] icm_broadcast_writedata_o,
	output reg       icm_broadcast_cs_o,
	input         icm_broadcast_waitreq_i, //broadcast stall request

    input [39:0] ics_psum_writedata_i,//psum row output
	input        ics_psum_cs_i,

    output reg [23:0] icm_conf_writedata_o[ARRAY_COL_NUM],
    output reg        icm_conf_cs_o,

    //dma interface
    input [31:0] icm_dma_readdata_i,
    output [31:0] icm_dma_writedata_o,
    output reg [31:0] icm_dma_address_o,
    output reg icm_dma_cs_o,
    output reg icm_dma_write_o,
    input icm_dma_waitreq_i,

    //sram rw interface
    input      [31:0] sram_readdata_i,
    output reg [31:0] sram_writedata_o,
    output reg [11:0] sram_address_o,
    output reg        sram_wren_o,
    output            sram_rden_o,

    //sram write port
    output reg [11:0] sres_address_o,
    output reg [31:0] sres_writedata_o,
    output reg        sres_wren_o

);

integer schd_pc = 0;
reg schd_idle_prev;
always@(posedge clock or posedge reset) begin
    if(reset)
        schd_idle_prev = 0;
    else
        schd_idle_prev = schd_pc == 0;
end
//Extract posedge of scheduler idle state
assign instruction_done_o = (schd_idle_prev == 0) && (schd_pc == 0);
assign stat_idle_o = schd_pc == 0;

//DMA functions
reg [31:0] dma_ext_address;
reg [11:0] dma_int_address;
reg [11:0] dma_op_len;
reg [11:0] dma_curr_len;

reg dma_done = 1;
reg bro_done = 1;

assign icm_dma_writedata_o = sram_readdata_i;
assign sram_rden_o = (dma_done | !icm_dma_waitreq_i) && (bro_done | !icm_broadcast_waitreq_i);

function dma_setup;
    input [31:0] ext_addr;
    input [11:0] int_addr;
    input [11:0] length;
    input fetch;

    dma_ext_address = ext_addr;
    dma_int_address = int_addr;
    dma_op_len = length;
    dma_curr_len = 0;
    dma_done = 0;
    //sram_wren_o = 0;
    //sram_cs_o = 1;

    sram_address_o = dma_int_address;
    sram_wren_o = 0;

    icm_dma_address_o = dma_ext_address;

    if(fetch) begin
        icm_dma_cs_o = 1;
    end
    
    icm_dma_write_o = 0;    

endfunction

function dma_op;
    input fetch;
    icm_dma_cs_o = 1;
    dma_op = 0;
    if(fetch) begin

        sram_writedata_o = icm_dma_readdata_i;

        if(icm_dma_waitreq_i == 0) begin
            sram_wren_o = 1;
            //sram_cs_o = 1;

            sram_address_o = dma_int_address + dma_curr_len;
            icm_dma_address_o = dma_ext_address + dma_curr_len + 1;
            dma_curr_len = dma_curr_len + 1;

            if(dma_curr_len == dma_op_len - 1) begin
                dma_op = 1;
            end
        end
        else begin
            sram_wren_o = 0;
            //sram_cs_o = 0;
        end
    end
    else begin
        icm_dma_write_o = 1;
        //sram_wren_o = 0;
        
        icm_dma_cs_o = 1;
        

        if(icm_dma_waitreq_i == 0) begin
            //sram_cs_o = 1;
            if(dma_curr_len == dma_op_len - 1) begin
                dma_op = 1;
            end
                            
            sram_address_o = dma_int_address + dma_curr_len + 1;
            icm_dma_address_o = dma_ext_address + dma_curr_len;
            dma_curr_len = dma_curr_len + 1;
            
        end
        else begin
            //sram_cs_o = 0;
        end
    end

endfunction

function dma_cleanup;
    input fetch;

    if(icm_dma_waitreq_i == 0) begin
        dma_cleanup = 1;
        if(fetch) begin
            //save last prefetched element
            sram_writedata_o = icm_dma_readdata_i;
            sram_address_o = dma_int_address + dma_curr_len;
            sram_wren_o = 1;
        end
        else begin
            //sram interface
            sram_wren_o = 0;
            //interconn interface
            icm_dma_cs_o = 0;
            icm_dma_write_o = 0;
        end
        dma_done = 1;
    end
    else 
        dma_cleanup = 0;

endfunction

//config functions
reg [3:0] conf_rows;
reg [3:0] conf_curr_row;

function conf_setup;
    input foo;

    conf_curr_row = 0;
    conf_rows = gp[2][19:16];
    icm_conf_cs_o = 0;

endfunction

function conf_write;
    input foo;

    integer conf_it;
    for(conf_it = 0; conf_it < ARRAY_COL_NUM; conf_it = conf_it + 1) begin
        icm_conf_writedata_o[conf_it] = {
            conf_it <= gp[0][15:0] - gp[2][3:0],//enable
            conf_curr_row != 0,//psum input
            conf_curr_row == conf_rows - 1,//psum output
            1'b0,
            gp[2][3:0],//weight width
            8'b0,
            (conf_curr_row + conf_it[7:0])
        };
        
    end

    icm_conf_cs_o = 1;

    if(conf_curr_row == conf_rows - 1)
        conf_write = 1;
    else
        conf_write = 0;

    conf_curr_row = conf_curr_row + 1;

endfunction

function conf_cleanup;
    input foo;

    icm_conf_cs_o = 0;

endfunction

reg [3:0] kheight,kwidth;
reg [15:0] pheight,pwidth;
reg [15:0] rheight,rwidth;

//weightdata delay chain
reg [3:0] kwidth_delay = 0;
reg icm_weightrow_cs_pre = 0;
always@(posedge clock) begin
    kwidth_delay <= kwidth;
    icm_weightrow_writedata_o[kwidth_delay] <= sram_readdata_i;
    icm_weightrow_cs_o <= icm_weightrow_cs_pre;
end

//broadcast delay chain
reg [15:0] pheight_delay[2] = '{ 16'b0, 16'b0 };
reg icm_broadcast_cs_pre = 0;
always@(posedge clock) begin
    if(icm_broadcast_waitreq_i == 0) begin
        icm_broadcast_cs_o <= icm_broadcast_cs_pre;
        pheight_delay[0] <= pheight;
        pheight_delay[1] <= pheight_delay[0];
    end
end

assign icm_broadcast_writedata_o = {pheight_delay[1][7:0],sram_readdata_i};

reg rval;

// Scheduler pseudo code
always@(posedge clock or posedge reset) begin
    
    if(reset) begin
		reset_req_o = 0;
        schd_pc = 0;
        icm_weightrow_cs_pre = 0;
    end
    else begin
		reset_req_o = 0;
        case(schd_pc)

//@entry point
default:begin
//    reset all flags
    icm_dma_cs_o = 0;
    icm_weightrow_cs_pre = 0;
    icm_broadcast_cs_pre = 0;
    sram_wren_o = 0;
    sres_wren_o = 0;
	
    if(instruction_valid_i) begin
        case(instruction_i[31:24])
//    if (instruction == reset)
        default:begin
//        do system reset
            reset_req_o = 1;
        end
//    else
//        execute corresponding routine
        8'b0000_0001:begin//instruction load
            schd_pc = 1;
        end
        8'b0000_0010:begin//instruction store
            schd_pc = 4;
        end
        8'b0000_0011:begin//instruction loadweight
            schd_pc = 7;
        end
        8'b0000_0100:begin//instruction doconv
            schd_pc = 9;
        end
        endcase
    end
end

//@instruction load
1:begin
//    unset flag
//    setup_dma();
    /*input [31:0] ext_addr;
    input [11:0] int_addr;
    input [11:0] length;
    input fetch;*/
    rval = dma_setup(gp[0],instruction_i[11:0],instruction_i[23:12],1'b1);
//    step();
    schd_pc = schd_pc + 1;
end
//@.
2:begin
//    if(do_dma() == finished)
    if(dma_op(1'b1) == 1'b1)
//        step();
        schd_pc = schd_pc + 1;
end
//@.
3:begin
//    set flag;
//    cleanup_dma();
    if(dma_cleanup(1'b1) == 1'b1)
//    return;
        schd_pc = 0;
end

//@instruction store
4:begin
//    unset flag
//    setup_dma();
    rval = dma_setup(gp[0],instruction_i[11:0],instruction_i[23:12],1'b0);
//    step();
    schd_pc = schd_pc + 1;
end
//@.
5:begin
//    if(do_dma() == finished)
    if(dma_op(1'b0) == 1'b1)
//        step();
        schd_pc = schd_pc + 1;
end
//@.
6:begin
//    set flag;
//    cleanup_dma();
    if(dma_cleanup(1'b0) == 1'b1)
//    return;
        schd_pc = 0;
end

//@instruction loadweight
7:begin
//    clear counters
    kheight = 0;
    kwidth = 0;
//    reset finish flag
//    set read flag
    sram_address_o = instruction_i[11:0];
    sram_wren_o = 0;
//    step();
    schd_pc = schd_pc + 1;
end
//@.
8:begin

    sram_address_o = sram_address_o + 1;
//    if(width_counter == width - 1){
    if(kwidth == instruction_i[23:20] - 1) begin
//        width_counter = 0;
        kwidth = 0;
//        set row valid flag
        icm_weightrow_cs_pre = 1;
//        if(height_counter == height - 1){
        if(kheight == instruction_i[19:16] - 1) begin
//            set finish flag
//            reset read flag 
//            return;
            schd_pc = 0;
//        }else{
        end
        else begin
//            height_counter++;
            kheight = kheight + 1;
//        }
        end
    end
//    }else{
    else begin
//        width_counter++;
        kwidth = kwidth + 1;
//        reset row valid flag
        icm_weightrow_cs_pre = 0;
//    }
    end
//
end

//@instruction doconv
9:begin
//    setup_config_write();
    rval = conf_setup(1'b1);
//    step();
    schd_pc = schd_pc + 1;
end
//@.
10:begin
//    if(do_config_write() == finished)
    if(conf_write(1'b1) == 1'b1)
//        step();
        schd_pc = schd_pc + 1;
end
//@.
11:begin
//    cleanup_config_write();
    rval = conf_cleanup(1'b1);
//    setup_data_read();
    pwidth = 0;
    pheight = 0;
    rwidth = 0;
    rheight = 0;
//    step();
    schd_pc = schd_pc + 1;
    dma_done = 0;
end
//@.
12:begin
//    send broadcast
//    # use broadcast_wait to generate read clock enable signal
//    # 1-cycle delay from read enable to broadcast valid
//    output [39:0] icm_broadcast_writedata_o,
//	output        icm_broadcast_cs_o,
//	input         icm_broadcast_waitreq_i, //broadcast stall request
//    if(broadcast_wait == 0){
    if(icm_broadcast_waitreq_i == 0) begin
//        set read flag
        icm_broadcast_cs_pre = 1;
        sram_address_o = gp[1] + (pheight)*gp[0][15:0] + pwidth;
        if(pwidth == gp[0][15:0]) begin
            icm_broadcast_cs_pre = 0;
        end
        else begin
//        if(height_counter == height - 1){
            if(pheight == gp[0][31:16] - 1) begin
//                height_counter = 0;

//                if(width_counter == width){

//                    set finish flag
                    
//                    reset read flag 
//                    halt();
//                }else{
//                    width_counter++;
                    pheight = 0;
                    pwidth = pwidth + 1;
                    //sram_address_o = gp[1] + (pheight)*gp[0][15:0] + pwidth + 1;
//                }
//            }else{
            end
            else begin
//                height_counter++;
                pheight = pheight + 1;
                //sram_address_o = gp[1] + (pheight + 1)*gp[0][15:0] + pwidth;
//            }
            end
        end
//    }
    end
    else begin

    end
//
//  output [11:0] sres_address_o,
//  output [31:0] sres_writedata_o,
//  output sres_wren_o
//  assign sres_wren_o = ics_psum_cs_i;
//  assign sres_writedata_o = ics_psum_writedata_i[31:0];
//    if(result_valid == 1){
    if(ics_psum_cs_i == 1) begin
//        set write flag
        sres_wren_o = 1;
        sres_writedata_o = ics_psum_writedata_i[31:0];
        sres_address_o = gp[5] + (rheight)*(gp[0][15:0] - gp[2][3:0] + 1) + rwidth;
//        if(height_counter == height - 1){
        if(rheight == gp[0][31:16] - gp[2][19:16]) begin
            rheight = 0;
//            if(width_counter == width - 1){
            if(rwidth == gp[0][15:0] - gp[2][3:0]) begin
//                return;
                schd_pc = 0;
                dma_done = 1;
//            }else{
            end
            else begin
//                width_counter++;
                rwidth = rwidth + 1;
                //sres_address_o = gp[5] + (rheight)*(gp[0][15:0] - gp[2][3:0] + 1) + rwidth + 1;
//            }
            end
//        }else{
        end
        else begin
//            height_counter++;
            rheight = rheight + 1;
            //sres_address_o = gp[5] + (rheight + 1)*(gp[0][15:0] - gp[2][3:0] + 1) + rwidth;
//        }
        end
//    }else{
    end
    else begin
//        reset write flag
        sres_wren_o = 0;
//    }
    end
//
end
//@.rdbuf
        endcase
    end
end

endmodule