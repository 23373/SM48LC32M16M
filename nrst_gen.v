`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    10:12:37 02/28/2024 
// Design Name: 
// Module Name:    nrst_gen 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////


module nrst_gen #(
    parameter                       P_RST_CYCLE = 1		// 复位周期   
)(
    input                           	s_clk		,
    output                          	o_nrst         
    );
//===================================================
reg                                 	ro_nrst = 0	;
reg  [7 :0]                         	r_cnt   = 0	;
//===================================================
assign	o_nrst = ro_nrst							;
//===================================================
always@(posedge s_clk)
begin
    if(r_cnt == P_RST_CYCLE - 1 || P_RST_CYCLE == 0)
        r_cnt <= r_cnt;
    else 
        r_cnt <= r_cnt + 1;
end

always@(posedge s_clk)
begin
    if(r_cnt == P_RST_CYCLE - 1 || P_RST_CYCLE == 0)
        ro_nrst <= 'd1;
    else 
        ro_nrst <= 'd0;
end

endmodule
