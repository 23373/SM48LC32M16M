`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    10:43:23 02/21/2024 
// Design Name: 
// Module Name:    SDRAM_TOP 
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


module SDRAM_TOP(
    input                                   s_clk           ,
    
    output                                  o_sdram_clk     ,
    output                                  o_sdram_cs_n    ,
    output                                  o_sdram_ras_n   ,
    output                                  o_sdram_cas_n   ,
    output                                  o_sdram_we_n    ,
    output      [12:0]                      o_sdram_addr    ,
    output      [1 :0]                      o_sdram_ba      ,
    output      [1 :0]                      o_sdram_dqm     ,
    inout       [31:0]                      io_sdram_da      
    );
//===========================================================
localparam                                  ST_IDLE  = 0    ,
                                            ST_WRITE = 1    ,
                                            ST_READ  = 2    ,
                                            ST_END   = 3    ;

localparam                                  P_OP_NUM = 512  ,   // 操作数量
                                            P_OP_DAS = 65535;   // 写起始
//===========================================================
reg     [1 :0]                              ri_op_cmd       ;
reg     [23:0]                              ri_op_addr      ;
reg     [9 :0]                              ri_op_len       ;
reg                                         ri_op_valid     ;
reg     [31:0]                              ri_wr_data      ;
reg                                         ri_wr_last      ;
reg                                         ri_wr_valid     ;

reg     [2 :0]                              c_state,n_state ;
reg     [7 :0]                              r_cnt_st        ;

reg                                         r_op_ready      ;
reg     [15:0]                              r_cnt_write     ;
//===========================================================
wire                                        s_nrst          ;

wire                                        wo_op_ready     ;
wire    [31:0]                              wo_rd_data      ;
wire                                        wo_rd_valid     ;

wire                                        w_ready_pos     ;
wire                                        w_op_active     ;

wire                                        w_clk_0         ;
wire                                        w_clk_100m      ;
wire                                        w_clk_100mx180  ;
wire                                        w_locked        ;
//===========================================================
DCM_BASE #(
    .CLKDV_DIVIDE(2.0), // Divide by: 1.5,2.0,2.5,3.0,3.5,4.0,4.5,5.0,5.5,6.0,6.5
                        // 7.0,7.5,8.0,9.0,10.0,11.0,12.0,13.0,14.0,15.0 or 16.0
    .CLKFX_DIVIDE(1), // Can be any integer from 1 to 32
    .CLKFX_MULTIPLY(2), // Can be any integer from 2 to 32
    .CLKIN_DIVIDE_BY_2("FALSE"), // TRUE/FALSE to enable CLKIN divide by two feature
    .CLKIN_PERIOD(20.0), // Specify period of input clock in ns from 1.25 to 1000.00
    .CLKOUT_PHASE_SHIFT("NONE"), // Specify phase shift mode of NONE or FIXED
    .CLK_FEEDBACK("1X"), // Specify clock feedback of NONE, 1X or 2X
    .DCM_PERFORMANCE_MODE("MAX_SPEED"), // Can be MAX_SPEED or MAX_RANGE
    .DESKEW_ADJUST("SYSTEM_SYNCHRONOUS"), // SOURCE_SYNCHRONOUS, SYSTEM_SYNCHRONOUS or
                                          // an integer from 0 to 15
    .DFS_FREQUENCY_MODE("LOW"), // LOW or HIGH frequency mode for frequency synthesis
    .DLL_FREQUENCY_MODE("LOW"), // LOW, HIGH, or HIGH_SER frequency mode for DLL
    .DUTY_CYCLE_CORRECTION("TRUE"), // Duty cycle correction, TRUE or FALSE
    .FACTORY_JF(16'hf0f0), // FACTORY JF value suggested to be set to 16'hf0f0
    .PHASE_SHIFT(0), // Amount of fixed phase shift from -255 to 1023
    .STARTUP_WAIT("FALSE") // Delay configuration DONE until DCM LOCK, TRUE/FALSE
) 
DCM_BASE_inst (
    .CLK0(w_clk_0), // 0 degree DCM CLK output
    .CLK180(), // 180 degree DCM CLK output
    .CLK270(), // 270 degree DCM CLK output
    .CLK2X(w_clk_100m), // 2X DCM CLK output
    .CLK2X180(w_clk_100mx180), // 2X, 180 degree DCM CLK out
    .CLK90(), // 90 degree DCM CLK output
    .CLKDV(), // Divided DCM CLK out (CLKDV_DIVIDE)
    .CLKFX(), // DCM CLK synthesis out (M/D)
    .CLKFX180(), // 180 degree CLK synthesis out
    .LOCKED(w_locked), // DCM LOCK status output
    .CLKFB(w_clk_0), // DCM clock feedback
    .CLKIN(s_clk), // Clock input (from IBUFG, BUFG or DCM)
    .RST(0) // DCM asynchronous reset input
   );

nrst_gen #(
    .P_RST_CYCLE                            (100            )
) 
nrst_gen_u (
    .s_clk                                  (w_clk_100m     ),
    .o_nrst                                 (s_nrst         )
    );

SDRAM_Drive #(
    .P_ROW_NUM                              (8192           )
)
SDRAM_Drive_u (
    .s_clk                                  (w_clk_100m     ),
    .s_nrst                                 (s_nrst         ),
    //ui interface
    .i_op_cmd                               (ri_op_cmd      ),   // 操作指令 1 read 2 write
    .i_op_addr                              (ri_op_addr     ),   // 操作地址 SDRAM中的存储地址 bank + row + col 
    .i_op_len                               (ri_op_len      ),   // 操作长度
    .i_op_valid                             (ri_op_valid    ),   // 操作有效
    .o_op_ready                             (wo_op_ready    ),   // 操作准备信号

    .i_wr_data                              (ri_wr_data     ),   // 写数据
    .i_wr_last                              (ri_wr_last     ),   // 写数据last
    .i_wr_valid                             (ri_wr_valid    ),   // 写数据有效

    .o_rd_data                              (wo_rd_data     ),   // 读数据
    .o_rd_valid                             (wo_rd_valid    ),   // 读数据有效

    //sdram interface
    .o_sdram_cs_n                           (o_sdram_cs_n   ),   // sdram 片选
    .o_sdram_ras_n                          (o_sdram_ras_n  ),   // sdram 行有效
    .o_sdram_cas_n                          (o_sdram_cas_n  ),   // sdram 列有效
    .o_sdram_we_n                           (o_sdram_we_n   ),   // sdram 写使能
    .o_sdram_addr                           (o_sdram_addr   ),   // sdram 操作地址
    .o_sdram_ba                             (o_sdram_ba     ),   // sdram bank 地址
    .o_sdram_dqm                            (o_sdram_dqm    ),   
    .io_sdram_da                            (io_sdram_da    )    // sdram 读写数据
    );
wire        [35:0]                          w_CONTROL       ;

ICON ICON_u (
    .CONTROL0(w_CONTROL) // INOUT BUS [35:0]
    );

ILA ILA_u (
    .CONTROL(w_CONTROL), // INOUT BUS [35:0]
    .CLK(w_clk_100m), // IN
    .TRIG0(ri_wr_data), // IN BUS [31:0]
    .TRIG1(ri_wr_last), // IN BUS [0:0]
    .TRIG2(ri_wr_valid), // IN BUS [0:0]
    .TRIG3(wo_rd_data), // IN BUS [31:0]
    .TRIG4(wo_rd_valid) // IN BUS [0:0]
);
//===========================================================
assign  w_ready_pos = !r_op_ready & wo_op_ready             ;
assign  w_op_active = ri_op_valid & wo_op_ready             ; 
assign  o_sdram_clk = ~w_clk_100m                           ;
//===========================================================
always@(posedge w_clk_100m)
begin
    if(!s_nrst)
        r_op_ready <= 'd0;
    else
        r_op_ready <= wo_op_ready;
end

always@(posedge w_clk_100m)
begin
    if(!s_nrst)
        c_state <= ST_IDLE;
    else
        c_state <= n_state;
end

always@(*)
begin
    case(c_state)
        ST_IDLE  : n_state = wo_op_ready     ? ST_WRITE : ST_IDLE   ;
        ST_WRITE : n_state = w_ready_pos     ? ST_READ  : ST_WRITE  ;
        ST_READ  : n_state = w_ready_pos     ? ST_END   : ST_READ   ;
        ST_END   : n_state = r_cnt_st == 255 ? ST_IDLE  : ST_END    ;
        default  : n_state = ST_IDLE;
    endcase
end

always@(posedge w_clk_100m)
begin
    if(!s_nrst)
        r_cnt_st <= 'd0;
    else if(c_state != n_state)
        r_cnt_st <= 'd0;
    else if(r_cnt_st < 255)
        r_cnt_st <= r_cnt_st + 'd1;
    else 
        r_cnt_st <= r_cnt_st; 
end

always@(posedge w_clk_100m)
begin
    if(!s_nrst) begin
        ri_op_cmd   <= 'd0;
        ri_op_addr  <= 'd0;
        ri_op_len   <= 'd0;
        ri_op_valid <= 'd0;
    end
    else if(c_state == ST_WRITE && r_cnt_st == 0) begin
        ri_op_cmd   <= 'd2;
        ri_op_addr  <= 'd0;
        ri_op_len   <= P_OP_NUM;
        ri_op_valid <= 'd1;
    end
    else if(c_state == ST_READ && r_cnt_st == 0) begin
        ri_op_cmd   <= 'd1;
        ri_op_addr  <= 'd0;
        ri_op_len   <= P_OP_NUM;
        ri_op_valid <= 'd1;
    end
    else begin
        ri_op_cmd   <= 'd0;
        ri_op_addr  <= 'd0;
        ri_op_len   <= 'd0;
        ri_op_valid <= 'd0;
    end
end

always@(posedge w_clk_100m)
begin
    if(!s_nrst)
        ri_wr_data <= P_OP_DAS;
    else if(ri_wr_data == P_OP_DAS + P_OP_NUM - 1)
        ri_wr_data <= P_OP_DAS;
    else if(ri_wr_valid)
        ri_wr_data <= ri_wr_data + 1;
    else
        ri_wr_data <= ri_wr_data;
end

always@(posedge w_clk_100m)
begin
    if(!s_nrst)
        ri_wr_valid <= 'd0;
    else if(r_cnt_write == P_OP_NUM - 1)
        ri_wr_valid <= 'd0;
    else if(w_op_active && ri_op_cmd == 2)
        ri_wr_valid <= 'd1;
    else
        ri_wr_valid <= ri_wr_valid;
end

always@(posedge w_clk_100m)
begin
    if(!s_nrst)
        r_cnt_write <= 'd0;
    else if(r_cnt_write == P_OP_NUM - 1)
        r_cnt_write <= 'd0;
    else if(ri_wr_valid)
        r_cnt_write <= r_cnt_write + 'd1;
    else
        r_cnt_write <= r_cnt_write;
end

always@(posedge w_clk_100m)
begin
    if(!s_nrst)
        ri_wr_last <= 'd0;
    else if(r_cnt_write == P_OP_NUM - 2)
        ri_wr_last <= 'd1;
    else
        ri_wr_last <= 'd0;
end

endmodule