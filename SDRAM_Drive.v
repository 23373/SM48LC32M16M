`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    10:43:47 02/21/2024 
// Design Name: 
// Module Name:    SDRAM_Drive 
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


module SDRAM_Drive #(
    parameter                               P_ROW_NUM = 8192
)(
    input                                   s_clk           ,
    input                                   s_nrst          ,
    //ui interface
    input       [1 :0]                      i_op_cmd        ,   // 操作指令 1 read 2 write
    input       [23:0]                      i_op_addr       ,   // 操作地址 SDRAM中的存储地址 bank + row + col 
    input       [9 :0]                      i_op_len        ,   // 操作长度
    input                                   i_op_valid      ,   // 操作有效
    output                                  o_op_ready      ,   // 操作准备信号

    input       [31:0]                      i_wr_data       ,   // 写数据
    input                                   i_wr_last       ,   // 写数据last
    input                                   i_wr_valid      ,   // 写数据有效

    output      [31:0]                      o_rd_data       ,   // 读数据
    output                                  o_rd_valid      ,   // 读数据有效

    //sdram interface
    output                                  o_sdram_cs_n    ,   // sdram 片选
    output                                  o_sdram_ras_n   ,   // sdram 行有效
    output                                  o_sdram_cas_n   ,   // sdram 列有效
    output                                  o_sdram_we_n    ,   // sdram 写使能

    output      [12:0]                      o_sdram_addr    ,   // sdram 操作地址
    output      [1 :0]                      o_sdram_ba      ,   // sdram bank 地址
    output      [1 :0]                      o_sdram_dqm     ,   
    inout       [31:0]                      io_sdram_da         // sdram 读写数据
    );
//===========================================================
localparam                              ST_INT_WAIT   = 0   ,   // 上电等待
                                        ST_ALL_PER    = 1   ,   // 所有bank预充电
                                        ST_AREF       = 2   ,   // 自刷新
                                        ST_AR_CHECk   = 3   ,   // 自刷新检测
                                        ST_MR_SET     = 4   ,   // 设置模式寄存器
                                        ST_IDLE       = 5   ,   // 空闲
                                        ST_IDLE_AR    = 6   ,   // 空闲时自刷新
                                        ST_ROW_ACT    = 7   ,   // 行激活
                                        ST_RD_CMD     = 8   ,   // 读指令
                                        ST_RD_DATA    = 9   ,   // 读数据
                                        ST_WR_CMD     = 10  ,   // 写指令
                                        ST_WR_DATA    = 11  ,   // 写数据
                                        ST_WR_WAIT    = 12  ,   // 写同步等待周期
                                        ST_BURST_STOP = 13  ,
                                        ST_PRE_WAIT   = 14  ;   // 预充电等待

localparam      P_AP_CNT    = (6400000 / P_ROW_NUM) - 600   ;  // 自刷新等待周期
localparam                              P_INT_WAIT  = 20000 ,   // 上电静默时间 min 100us   
                                        P_TIME_TRP  = 4     ,   // 预充电周期 min 20us
                                        P_TIME_TRC  = 7     ,   //   min 66ns   
                                        P_TIME_TMRD = 2     ,   // 模式寄存器设置周期 2 clk
                                        P_TIME_TRCD = 2     ,   // 行激活等待周期 min 20ns
                                        P_TIME_TCL  = 2     ,   // 读潜伏期 3 clk       
                                        P_TIME_TWR  = 2     ,   // 写数据同步周期 min 1clk + 7.5ns
                                        P_AR_NUM    = 1     ;   // 自刷新次数 - 1 (2次)

localparam                              P_OP_READ   = 1     ,
                                        P_OP_WRITE  = 2     ;

localparam          P_SDRAM_MODE = {5'd0,1'b0,2'b00,3'b010,1'b0,3'b111};
localparam                          P_CMD_INIT  = 4'b1111   ,   // 初始化
                                    P_CMD_NOP   = 4'b0111   ,   // 空指令
                                    P_CMD_RACT  = 4'b0011   ,   // 行激活
                                    P_CMD_READ  = 4'b0101   ,   // 读 A10 = 1
                                    P_CMD_WRITE = 4'b0100   ,   // 写 A10 = 1
                                    P_CMD_PER   = 4'b0010   ,   // 预充电 A10 = 1 ALL
                                    P_CMD_AP    = 4'b0001   ,   // 自动预刷新
                                    P_CMD_MR    = 4'b0000   ,   // 模式寄存器
                                    P_CMD_BSTOP = 4'b0110   ;   // 突发终止
//===========================================================
reg     [14:0]                              ro_sdram_addr   ;

reg     [31:0]                              ro_rd_data      ;
reg                                         ro_rd_valid     ;
reg                                         ro_op_ready     ;

reg     [1 :0]                              ri_op_cmd       ;
reg     [23:0]                              ri_op_addr      ;
reg     [9 :0]                              ri_op_len       ;

reg     [31:0]                              ri_wr_data      ;
reg                                         ri_wr_last      ;
reg                                         ri_wr_valid     ;
reg     [31:0]                              ri_wr_data_1d   ;
reg                                         ri_wr_last_1d   ;
reg                                         ri_wr_valid_1d  ;
reg     [31:0]                              ri_wr_data_2d   ;
reg                                         ri_wr_last_2d   ;
reg                                         ri_wr_valid_2d  ;
reg     [31:0]                              ri_wr_data_3d   ;
reg                                         ri_wr_last_3d   ;
reg                                         ri_wr_valid_3d  ;
reg     [31:0]                              ri_wr_data_4d   ;
reg                                         ri_wr_last_4d   ;
reg                                         ri_wr_valid_4d  ;

reg                                         r_sdata_wh_rl   ;

reg     [7 :0]                              c_state,n_state ;
reg     [15:0]                              r_cnt_st        ;
reg     [2 :0]                              r_cnt_arnum     ;

reg     [3 :0]                              r_sdram_cmd     ;

reg     [15:0]                              r_cnt_ap_req    ;

reg                                         r_rd_en         ;
reg                                         r_rd_en_d       ;
reg     [15:0]                              r_cnt_rd        ;

wire                                        w_op_active     ;
wire    [31:0]                              w_sdata_r       ;
//===========================================================
assign  o_sdram_dqm   = 2'b00                               ;
assign  o_sdram_cs_n  = r_sdram_cmd[3]                      ;
assign  o_sdram_ras_n = r_sdram_cmd[2]                      ;
assign  o_sdram_cas_n = r_sdram_cmd[1]                      ;
assign  o_sdram_we_n  = r_sdram_cmd[0]                      ;
assign  o_sdram_addr  = ro_sdram_addr[12:0]                 ;
assign  o_sdram_ba    = ro_sdram_addr[14:13]                ;
assign  o_rd_data     = ro_rd_data                          ;
assign  o_rd_valid    = ro_rd_valid                         ;
assign  o_op_ready    = ro_op_ready                         ;
assign  w_op_active   = i_op_valid & o_op_ready             ;
//三态门
assign  io_sdram_da   = r_sdata_wh_rl   ? ri_wr_data_3d : {32{1'bz}};
assign  w_sdata_r     = !r_sdata_wh_rl  ? io_sdram_da   : 32'd0     ;

//===========================================================
always@(posedge s_clk)
begin
    if(!s_nrst) begin
        ri_op_cmd  <= 'd0;
        ri_op_addr <= 'd0;
        ri_op_len  <= 'd0;
    end
    else if(w_op_active) begin
        ri_op_cmd  <= i_op_cmd ;
        ri_op_addr <= i_op_addr;
        ri_op_len  <= i_op_len ;
    end
    else begin
        ri_op_cmd  <= ri_op_cmd ;
        ri_op_addr <= ri_op_addr;
        ri_op_len  <= ri_op_len ;
    end
end

always@(posedge s_clk)
begin
    if(!s_nrst) begin
        ri_wr_data  <= 'd0;
        ri_wr_last  <= 'd0;
        ri_wr_valid <= 'd0;
    end
    else begin
        ri_wr_data  <= i_wr_data  ;
        ri_wr_last  <= i_wr_last  ;
        ri_wr_valid <= i_wr_valid ;
    end
end 

always@(posedge s_clk)
begin
    if(!s_nrst) begin
        ri_wr_data_1d  <= 'd0;
        ri_wr_last_1d  <= 'd0;
        ri_wr_valid_1d <= 'd0;
        ri_wr_data_2d  <= 'd0;
        ri_wr_last_2d  <= 'd0;
        ri_wr_valid_2d <= 'd0;
        ri_wr_data_3d  <= 'd0;
        ri_wr_last_3d  <= 'd0;
        ri_wr_valid_3d <= 'd0;
        ri_wr_data_4d  <= 'd0;
        ri_wr_last_4d  <= 'd0;
        ri_wr_valid_4d <= 'd0;
    end
    else begin
        ri_wr_data_1d  <= ri_wr_data    ;
        ri_wr_last_1d  <= ri_wr_last    ;
        ri_wr_valid_1d <= ri_wr_valid   ;
        ri_wr_data_2d  <= ri_wr_data_1d ;
        ri_wr_last_2d  <= ri_wr_last_1d ;
        ri_wr_valid_2d <= ri_wr_valid_1d;
        ri_wr_data_3d  <= ri_wr_data_2d ;
        ri_wr_last_3d  <= ri_wr_last_2d ;
        ri_wr_valid_3d <= ri_wr_valid_2d;
        ri_wr_data_4d  <= ri_wr_data_3d ;
        ri_wr_last_4d  <= ri_wr_last_3d ;
        ri_wr_valid_4d <= ri_wr_valid_3d;
    end
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        c_state <= ST_INT_WAIT;
    else
        c_state <= n_state;
end

always@(*)
begin
    case(c_state)
        ST_INT_WAIT   : n_state = (r_cnt_st == P_INT_WAIT  ) ? ST_ALL_PER   : ST_INT_WAIT   ;   //上电静默200us
        ST_ALL_PER    : n_state = (r_cnt_st == P_TIME_TRP  ) ? ST_AREF      : ST_ALL_PER    ;   // 全部预充电
        ST_AREF       : n_state = (r_cnt_st == P_TIME_TRC  ) ? ST_AR_CHECk  : ST_AREF       ;   // 自刷新
        ST_AR_CHECk   : n_state = (r_cnt_arnum == P_AR_NUM ) ? ST_MR_SET    : ST_AREF       ;   // 自刷新判断
        ST_MR_SET     : n_state = (r_cnt_st == P_TIME_TMRD ) ? ST_IDLE      : ST_MR_SET     ;   // 模式配置
        ST_IDLE       : n_state = (r_cnt_ap_req == P_AP_CNT) ? ST_IDLE_AR   : (w_op_active)
                                                             ? ST_ROW_ACT   : ST_IDLE       ;      
        ST_IDLE_AR    : n_state = (r_cnt_st == P_TIME_TRC  ) ? ST_IDLE      : ST_IDLE_AR    ;
        ST_ROW_ACT    : n_state = (r_cnt_st == P_TIME_TRCD ) ? (ri_op_cmd == P_OP_READ)   
                                                    ? ST_RD_CMD : ST_WR_CMD : ST_ROW_ACT    ;   
        ST_RD_CMD     : n_state = (r_cnt_st == P_TIME_TCL-1) ? ST_RD_DATA   : ST_RD_CMD ;
        ST_RD_DATA    : n_state = (r_cnt_st == ri_op_len-1 ) ? ST_BURST_STOP: ST_RD_DATA    ; 
        ST_WR_CMD     : n_state = ST_WR_DATA    ; 
        ST_WR_DATA    : n_state = (r_cnt_st == ri_op_len-1 ) ? ST_WR_WAIT   : ST_WR_DATA    ;
        ST_WR_WAIT    : n_state = (r_cnt_st == P_TIME_TWR  ) ? ST_PRE_WAIT  : ST_WR_WAIT    ;
        ST_BURST_STOP : n_state = (r_cnt_st == P_TIME_TCL  ) ? ST_PRE_WAIT  : ST_BURST_STOP ;
        ST_PRE_WAIT   : n_state = (r_cnt_st == P_TIME_TRP  ) ? ST_IDLE      : ST_PRE_WAIT   ;
        default       : n_state = 'd0;
    endcase
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        r_cnt_st <= 'd0;
    else if(c_state != n_state)
        r_cnt_st <= 'd0;
    else
        r_cnt_st <= r_cnt_st + 'd1;
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        r_cnt_arnum <= 'd0;
    else if(c_state == ST_AR_CHECk)
        r_cnt_arnum <= r_cnt_arnum + 'd1;
    else
        r_cnt_arnum <= r_cnt_arnum;
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        r_cnt_ap_req <= 'd0;
    else if(c_state == ST_IDLE_AR)
        r_cnt_ap_req <= 'd0;
    else if(c_state > ST_MR_SET && r_cnt_ap_req < P_AP_CNT)
        r_cnt_ap_req <= r_cnt_ap_req + 'd1;
    else
        r_cnt_ap_req <= r_cnt_ap_req;
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        r_sdram_cmd <= 'd0;
    else if((c_state == ST_ALL_PER || c_state == ST_PRE_WAIT)&& r_cnt_st == 0)
        r_sdram_cmd <= P_CMD_PER;
    else if((c_state == ST_AREF || c_state == ST_IDLE_AR) && r_cnt_st == 0)
        r_sdram_cmd <= P_CMD_AP;
    else if(c_state == ST_MR_SET && r_cnt_st == 0)
        r_sdram_cmd <= P_CMD_MR;
    else if(c_state == ST_ROW_ACT && r_cnt_st == 0)
        r_sdram_cmd <= P_CMD_RACT;
    else if(c_state == ST_RD_CMD && r_cnt_st == 0)
        r_sdram_cmd <= P_CMD_READ;
    else if(c_state == ST_WR_CMD && r_cnt_st == 0)
        r_sdram_cmd <= P_CMD_WRITE;
    else if(c_state == ST_BURST_STOP && r_cnt_st == 0)
        r_sdram_cmd <= P_CMD_BSTOP;
    else
        r_sdram_cmd <= P_CMD_NOP;
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        ro_sdram_addr <= 'd0;
    else if((c_state == ST_ALL_PER || c_state == ST_AREF) && r_cnt_st == 0)
        ro_sdram_addr <= {4'd0 , 1'd1 , 10'd0}; 
    else if(c_state == ST_MR_SET && r_cnt_st == 0)
        ro_sdram_addr <= P_SDRAM_MODE;
    else if(c_state == ST_ROW_ACT && r_cnt_st == 0)
        ro_sdram_addr <= ri_op_addr[23:9];
    else if((c_state == ST_RD_CMD || c_state == ST_WR_CMD) && r_cnt_st == 0)
        ro_sdram_addr <= {ri_op_addr[23:22],2'd0,1'b1,1'b0,ri_op_addr[8:0]};
    else
        ro_sdram_addr <= 15'h7FFF;
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        r_sdata_wh_rl <= 'd0;  
    else if(c_state == ST_WR_DATA && r_cnt_st == ri_op_len - 1)
        r_sdata_wh_rl <= 'd0;
    else if(c_state == ST_WR_CMD)
        r_sdata_wh_rl <= 'd1;
    else
        r_sdata_wh_rl <= r_sdata_wh_rl;
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        ro_op_ready <= 'd0;
    else if(w_op_active || r_cnt_ap_req >= P_AP_CNT - 2)
        ro_op_ready <= 'd0;
    else if(c_state == ST_IDLE && r_cnt_ap_req != P_AP_CNT)
        ro_op_ready <= 'd1;
    else
        ro_op_ready <= 'd0;
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        ro_rd_data <= 'd0;
    else if(r_rd_en_d && !r_rd_en)
        ro_rd_data <= 'd0;
    else if(r_rd_en)
        ro_rd_data <= w_sdata_r;
    else 
        ro_rd_data <= ro_rd_data;
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        ro_rd_valid <= 'd0;
    else if(r_rd_en_d && !r_rd_en)
        ro_rd_valid <= 'd0;
    // else if(c_state == ST_RD_DATA && r_cnt_st == 0)
    else if(r_rd_en)
        ro_rd_valid <= 'd1;
    else
        ro_rd_valid <= ro_rd_valid;
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        r_rd_en <= 'd0;
    else if(r_cnt_rd == ri_op_len - 1)
        r_rd_en <= 'd0;
    else if(c_state == ST_RD_CMD && r_cnt_st == P_TIME_TCL - 1)
        r_rd_en <= 'd1;
    else
        r_rd_en <= r_rd_en;
end

always@(posedge s_clk)
begin
    if(!s_nrst)
        r_rd_en_d <= 'd0;  
    else
        r_rd_en_d <= r_rd_en;
end        

always@(posedge s_clk)
begin
    if(!s_nrst)
        r_cnt_rd <= 'd0;
    else if(r_cnt_rd == ri_op_len - 1)
        r_cnt_rd <= 'd0;
    else if(r_rd_en)
        r_cnt_rd <= r_cnt_rd + 'd1;
    else
        r_cnt_rd <= r_cnt_rd;
end

endmodule