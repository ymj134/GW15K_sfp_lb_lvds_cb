`timescale 1 ns / 1 ps

module top
(
    input           clk,          // 50M
    input           rst_n,        // low-active

    output          led
);

//==============================================================================
// 0) 参数定义
//==============================================================================
`define LANE_WIDTH      1
`define LANE_DATA_WIDTH 32

parameter DATA_WIDTH      = `LANE_DATA_WIDTH * `LANE_WIDTH;
parameter STRB_WIDTH      = DATA_WIDTH/8;
parameter LANE_WIDTH      = `LANE_WIDTH;
parameter LANE_DATA_WIDTH = `LANE_DATA_WIDTH;

// 每帧 16 个 32bit beat
parameter FRAME_BEATS     = 16;

// 版本号：V1.3.0 -> 0x01030000
localparam [31:0] TOP_VERSION = 32'h0103_0000;

// 4-beat 固定循环模式
localparam [31:0] TX_PATTERN0 = 32'h12_34_56_78;
localparam [31:0] TX_PATTERN1 = 32'h9A_BC_DE_F0;
localparam [31:0] TX_PATTERN2 = 32'h55_AA_C3_3C;
localparam [31:0] TX_PATTERN3 = 32'h0F_1E_2D_3C;

//==============================================================================
// 1) 用户接口信号
//==============================================================================
wire [DATA_WIDTH-1:0] user_tx_data  /* synthesis syn_keep=1 */;
wire [STRB_WIDTH-1:0] user_tx_strb  /* synthesis syn_keep=1 */;
wire                  user_tx_valid /* synthesis syn_keep=1 */;
wire                  user_tx_last  /* synthesis syn_keep=1 */;
wire                  user_tx_ready /* synthesis syn_keep=1 */;

wire [DATA_WIDTH-1:0] user_rx_data  /* synthesis syn_keep=1 */;
wire [STRB_WIDTH-1:0] user_rx_strb  /* synthesis syn_keep=1 */;
wire                  user_rx_valid /* synthesis syn_keep=1 */;
wire                  user_rx_last  /* synthesis syn_keep=1 */;

wire                  crc_pass_fail_n;
wire                  crc_valid;

wire                  hard_err;
wire                  soft_err;
wire                  frame_err;

wire                  channel_up /* synthesis syn_keep=1 */;
wire [LANE_WIDTH-1:0] lane_up    /* synthesis syn_keep=1 */;

//==============================================================================
// 2) 时钟 / 复位 / SerDes 状态
//==============================================================================
wire                  sys_clk     /* synthesis syn_keep=1 */;
wire                  sys_rst;
wire                  cfg_clk;
wire                  cfg_pll_lock;

wire                  sys_reset_gen;

wire                  gt_reset;
wire                  gt_pcs_tx_reset;
wire                  gt_pcs_rx_reset;

wire [LANE_WIDTH-1:0] gt_pcs_tx_clk;
wire [LANE_WIDTH-1:0] gt_pcs_rx_clk;
wire                  gt_pll_ok;

wire [LANE_WIDTH-1:0] gt_rx_align_link;
wire [LANE_WIDTH-1:0] gt_rx_pma_lock;
wire [LANE_WIDTH-1:0] gt_rx_k_lock;

wire                  link_reset;
wire                  sys_reset;

//==============================================================================
// 3) 最小 TX/RX 测试逻辑
//==============================================================================
reg  [7:0]  tx_beat_cnt;
reg  [31:0] rx_last_data;
reg  [31:0] rx_prev_data;
reg         rx_data_changed;

reg         channel_up_1d;
reg         rx_seen_valid;
reg         rx_seen_last;
reg         rx_activity_toggle;
reg         test_pass;

// 为了方便观察，保留少量“sticky”错误标志
reg         hard_err_seen;
reg         soft_err_seen;
reg         frame_err_seen;
reg         crc_err_seen;

//==============================================================================
// 4) 顶层固定连接
//==============================================================================
// assign sfp1_tx_disable_o = 1'b0;     //15k板子此接口已经固定低电平
// assign sfp2_tx_disable_o = 1'b0;

assign led               = test_pass;

// 保持与官方参考 top 一致的关键骨架
assign sys_clk           = gt_pcs_tx_clk[0];

// 这一版不再通过寄存器软件控制 GT/PCS 复位，全部固定为 0
assign gt_reset          = 1'b0;
assign gt_pcs_tx_reset   = 1'b0;
assign gt_pcs_rx_reset   = 1'b0;

assign sys_reset_gen     = cfg_pll_lock & gt_pll_ok & rst_n;

//==============================================================================
// 5) 配置时钟与复位生成
//==============================================================================
Gowin_PLL u_Gowin_PLL
(
    .reset      ( !rst_n        ),
    .lock       ( cfg_pll_lock  ),
    .clkout0    ( cfg_clk       ),
    .mdclk      ( clk           ),
    .clkin      ( clk           )
);

reset_gen u2_reset_gen
(
    .i_clk1     ( sys_clk       ),
    .i_lock     ( sys_reset_gen ),
    .o_rst1     ( sys_rst       )
);

//==============================================================================
// 6) 4-beat 固定模式 Framing 发送器
//------------------------------------------------------------------------------
// 每帧 16 个 beat，帧内数据按 4 个固定 32bit 字循环发送：
//   beat[1:0] = 0 -> TX_PATTERN0
//   beat[1:0] = 1 -> TX_PATTERN1
//   beat[1:0] = 2 -> TX_PATTERN2
//   beat[1:0] = 3 -> TX_PATTERN3
//==============================================================================
wire tx_active;
wire tx_fire;
reg  [31:0] tx_pattern_word;

assign tx_active     = channel_up_1d & (~sys_reset);
assign tx_fire       = user_tx_valid & user_tx_ready;

assign user_tx_valid = tx_active;
assign user_tx_data  = tx_pattern_word;
assign user_tx_strb  = {STRB_WIDTH{1'b1}};
assign user_tx_last  = tx_active & (tx_beat_cnt == FRAME_BEATS-1);

always @(*) begin
    case (tx_beat_cnt[1:0])
        2'd0: tx_pattern_word = TX_PATTERN0;
        2'd1: tx_pattern_word = TX_PATTERN1;
        2'd2: tx_pattern_word = TX_PATTERN2;
        2'd3: tx_pattern_word = TX_PATTERN3;
        default: tx_pattern_word = TX_PATTERN0;
    endcase
end

always @(posedge sys_clk) begin
    if (sys_reset) begin
        tx_beat_cnt <= 8'd0;
    end
    else if (!channel_up_1d) begin
        tx_beat_cnt <= 8'd0;
    end
    else if (tx_fire) begin
        if (tx_beat_cnt == FRAME_BEATS-1)
            tx_beat_cnt <= 8'd0;
        else
            tx_beat_cnt <= tx_beat_cnt + 8'd1;
    end
end

//==============================================================================
// 7) 最小 RX 观察逻辑
//------------------------------------------------------------------------------
// 不做 payload 正确性判定，只记录：
//   1. 是否收到过有效数据
//   2. 是否收到过完整帧（user_rx_last）
//   3. RX 数据是否变化、上一拍/当前拍是什么
//   4. 是否出现 hard/soft/frame/crc error
//==============================================================================
always @(posedge sys_clk) begin
    if (sys_reset) begin
        channel_up_1d      <= 1'b0;
        rx_seen_valid      <= 1'b0;
        rx_seen_last       <= 1'b0;
        rx_activity_toggle <= 1'b0;
        test_pass          <= 1'b0;

        hard_err_seen      <= 1'b0;
        soft_err_seen      <= 1'b0;
        frame_err_seen     <= 1'b0;
        crc_err_seen       <= 1'b0;

        rx_last_data       <= 32'd0;
        rx_prev_data       <= 32'd0;
        rx_data_changed    <= 1'b0;
    end
    else begin
        channel_up_1d <= channel_up;

        if (!channel_up_1d) begin
            rx_seen_valid      <= 1'b0;
            rx_seen_last       <= 1'b0;
            rx_activity_toggle <= 1'b0;
            test_pass          <= 1'b0;

            hard_err_seen      <= 1'b0;
            soft_err_seen      <= 1'b0;
            frame_err_seen     <= 1'b0;
            crc_err_seen       <= 1'b0;

            rx_last_data       <= 32'd0;
            rx_prev_data       <= 32'd0;
            rx_data_changed    <= 1'b0;
        end
        else begin
            if (user_rx_valid) begin
                rx_seen_valid      <= 1'b1;
                rx_activity_toggle <= ~rx_activity_toggle;

                rx_prev_data       <= rx_last_data;
                rx_last_data       <= user_rx_data;
                rx_data_changed    <= (user_rx_data != rx_last_data);
            end

            if (user_rx_valid && user_rx_last)
                rx_seen_last <= 1'b1;

            if (hard_err)
                hard_err_seen <= 1'b1;

            if (soft_err)
                soft_err_seen <= 1'b1;

            if (frame_err)
                frame_err_seen <= 1'b1;

            if (crc_valid && !crc_pass_fail_n)
                crc_err_seen <= 1'b1;

            if (channel_up_1d &&
                rx_seen_valid &&
                rx_seen_last &&
                !hard_err_seen &&
                !soft_err_seen &&
                !frame_err_seen &&
                !crc_err_seen) begin
                test_pass <= 1'b1;
            end
        end
    end
end

//==============================================================================
// 8) ILA 观测信号（统一 ila_ 前缀）
//==============================================================================
wire [31:0] ila_top_version       = TOP_VERSION;
wire [31:0] ila_tx_pat0           = TX_PATTERN0;
wire [31:0] ila_tx_pat1           = TX_PATTERN1;
wire [31:0] ila_tx_pat2           = TX_PATTERN2;
wire [31:0] ila_tx_pat3           = TX_PATTERN3;
wire [31:0] ila_tx_pattern_word   = tx_pattern_word;

wire        ila_sys_clk           = sys_clk;
wire        ila_sys_reset         = sys_reset;
wire        ila_link_reset        = link_reset;
wire        ila_gt_reset          = gt_reset;
wire        ila_gt_pcs_tx_reset   = gt_pcs_tx_reset;
wire        ila_gt_pcs_rx_reset   = gt_pcs_rx_reset;
wire        ila_gt_pll_ok         = gt_pll_ok;

wire [LANE_WIDTH-1:0] ila_gt_pcs_tx_clk    = gt_pcs_tx_clk;
wire [LANE_WIDTH-1:0] ila_gt_pcs_rx_clk    = gt_pcs_rx_clk;
wire [LANE_WIDTH-1:0] ila_gt_rx_pma_lock   = gt_rx_pma_lock;
wire [LANE_WIDTH-1:0] ila_gt_rx_k_lock     = gt_rx_k_lock;
wire [LANE_WIDTH-1:0] ila_gt_rx_align_link = gt_rx_align_link;

wire        ila_channel_up        = channel_up;
wire [LANE_WIDTH-1:0] ila_lane_up = lane_up;
wire        ila_channel_up_1d     = channel_up_1d;

wire [DATA_WIDTH-1:0] ila_user_tx_data  = user_tx_data;
wire [STRB_WIDTH-1:0] ila_user_tx_strb  = user_tx_strb;
wire                  ila_user_tx_valid = user_tx_valid;
wire                  ila_user_tx_last  = user_tx_last;
wire                  ila_user_tx_ready = user_tx_ready;
wire                  ila_tx_fire       = tx_fire;
wire [7:0]            ila_tx_beat_cnt   = tx_beat_cnt;

wire [DATA_WIDTH-1:0] ila_user_rx_data  = user_rx_data;
wire [STRB_WIDTH-1:0] ila_user_rx_strb  = user_rx_strb;
wire                  ila_user_rx_valid = user_rx_valid;
wire                  ila_user_rx_last  = user_rx_last;
wire [31:0]           ila_rx_last_data  = rx_last_data;
wire [31:0]           ila_rx_prev_data  = rx_prev_data;
wire                  ila_rx_data_changed = rx_data_changed;

wire                  ila_crc_valid       = crc_valid;
wire                  ila_crc_pass_fail_n = crc_pass_fail_n;
wire                  ila_hard_err        = hard_err;
wire                  ila_soft_err        = soft_err;
wire                  ila_frame_err       = frame_err;

wire                  ila_rx_seen_valid      = rx_seen_valid;
wire                  ila_rx_seen_last       = rx_seen_last;
wire                  ila_rx_activity_toggle = rx_activity_toggle;
wire                  ila_hard_err_seen      = hard_err_seen;
wire                  ila_soft_err_seen      = soft_err_seen;
wire                  ila_frame_err_seen     = frame_err_seen;
wire                  ila_crc_err_seen       = crc_err_seen;
wire                  ila_test_pass          = test_pass;

//==============================================================================
// 9) SerDes_Top 实例
//==============================================================================
SerDes_Top u_SerDes_Top
(
    // --------- Clock & Reset
    .RoraLink_8B10B_Top_reset_i               ( sys_rst            ),
    .RoraLink_8B10B_Top_user_clk_i            ( sys_clk            ),
    .RoraLink_8B10B_Top_init_clk_i            ( cfg_clk            ),
    .RoraLink_8B10B_Top_user_pll_locked_i     ( gt_pll_ok          ),

    .RoraLink_8B10B_Top_link_reset_o          ( link_reset         ),
    .RoraLink_8B10B_Top_sys_reset_o           ( sys_reset          ),

    // --------- user TX interface
    .RoraLink_8B10B_Top_user_tx_data_i        ( user_tx_data       ),
    .RoraLink_8B10B_Top_user_tx_valid_i       ( user_tx_valid      ),
    .RoraLink_8B10B_Top_user_tx_ready_o       ( user_tx_ready      ),
    .RoraLink_8B10B_Top_user_tx_strb_i        ( user_tx_strb       ),
    .RoraLink_8B10B_Top_user_tx_last_i        ( user_tx_last       ),

    // --------- user RX interface
    .RoraLink_8B10B_Top_user_rx_data_o        ( user_rx_data       ),
    .RoraLink_8B10B_Top_user_rx_valid_o       ( user_rx_valid      ),
    .RoraLink_8B10B_Top_user_rx_strb_o        ( user_rx_strb       ),
    .RoraLink_8B10B_Top_user_rx_last_o        ( user_rx_last       ),

    .RoraLink_8B10B_Top_crc_pass_fail_n_o     ( crc_pass_fail_n    ),
    .RoraLink_8B10B_Top_crc_valid_o           ( crc_valid          ),

    // --------- Status
    .RoraLink_8B10B_Top_hard_err_o            ( hard_err           ),
    .RoraLink_8B10B_Top_soft_err_o            ( soft_err           ),
    .RoraLink_8B10B_Top_frame_err_o           ( frame_err          ),

    .RoraLink_8B10B_Top_channel_up_o          ( channel_up         ),
    .RoraLink_8B10B_Top_lane_up_o             ( lane_up            ),

    // --------- SerDes
    .RoraLink_8B10B_Top_gt_pcs_tx_reset_i     ( gt_pcs_tx_reset    ),
    .RoraLink_8B10B_Top_gt_pcs_tx_clk_o       ( gt_pcs_tx_clk      ),

    .RoraLink_8B10B_Top_gt_pcs_rx_reset_i     ( gt_pcs_rx_reset    ),
    .RoraLink_8B10B_Top_gt_rx_align_link_o    ( gt_rx_align_link   ),
    .RoraLink_8B10B_Top_gt_rx_pma_lock_o      ( gt_rx_pma_lock     ),
    .RoraLink_8B10B_Top_gt_rx_k_lock_o        ( gt_rx_k_lock       ),
    .RoraLink_8B10B_Top_gt_pcs_rx_clk_o       ( gt_pcs_rx_clk      ),

    .RoraLink_8B10B_Top_gt_reset_i            ( gt_reset           ),
    .RoraLink_8B10B_Top_gt_pll_lock_o         ( gt_pll_ok          )
);

endmodule

//==============================================================================
// reset_gen
//==============================================================================
module reset_gen
(
    input           i_clk1,
    input           i_lock,
    output reg      o_rst1 = 1'b1
);

reg [11:0] r_cnt = 12'd0;

always @(posedge i_clk1) begin
    if (!i_lock) begin
        r_cnt  <= 12'd0;
        o_rst1 <= 1'b1;
    end
    else if (r_cnt < 12'hfff) begin
        r_cnt  <= r_cnt + 12'd1;
        o_rst1 <= 1'b1;
    end
    else begin
        o_rst1 <= 1'b0;
    end
end

endmodule
