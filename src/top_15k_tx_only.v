`timescale 1 ns / 1 ps

// =============================================================================
// GW15K -> GW138K cross-board 8B10B verification
// Role : 15K TX only
// Mode : RoraLink 8B10B Framing mode, 32-bit user data, 1 lane
// Note : TX payload is NOT gated by local channel_up, so a bad 15K RX will not
//        stop this board from attempting to transmit user payload.
// =============================================================================
module top
(
    input  clk,      // 50 MHz
    input  rst_n,    // low-active
    output led
);

`define LANE_WIDTH       1
`define LANE_DATA_WIDTH  32

parameter DATA_WIDTH      = `LANE_DATA_WIDTH * `LANE_WIDTH;
parameter STRB_WIDTH      = DATA_WIDTH / 8;
parameter LANE_WIDTH      = `LANE_WIDTH;
parameter LANE_DATA_WIDTH = `LANE_DATA_WIDTH;
parameter FRAME_BEATS     = 16;

localparam [31:0] TOP_VERSION = 32'h1501_0001;

// Same 4-beat pattern as your current 15K diagnostic top.
localparam [31:0] TX_PATTERN0 = 32'h12_34_56_78;
localparam [31:0] TX_PATTERN1 = 32'h9A_BC_DE_F0;
localparam [31:0] TX_PATTERN2 = 32'h55_AA_C3_3C;
localparam [31:0] TX_PATTERN3 = 32'h0F_1E_2D_3C;

// -----------------------------------------------------------------------------
// User interface
// -----------------------------------------------------------------------------
wire [DATA_WIDTH-1:0] user_tx_data  /* synthesis syn_keep=1 */;
wire [STRB_WIDTH-1:0] user_tx_strb  /* synthesis syn_keep=1 */;
wire                  user_tx_valid /* synthesis syn_keep=1 */;
wire                  user_tx_last  /* synthesis syn_keep=1 */;
wire                  user_tx_ready /* synthesis syn_keep=1 */;

wire [DATA_WIDTH-1:0] user_rx_data  /* synthesis syn_keep=1 */;
wire [STRB_WIDTH-1:0] user_rx_strb  /* synthesis syn_keep=1 */;
wire                  user_rx_valid /* synthesis syn_keep=1 */;
wire                  user_rx_last  /* synthesis syn_keep=1 */;

wire crc_pass_fail_n;
wire crc_valid;
wire hard_err;
wire soft_err;
wire frame_err;
wire channel_up                  /* synthesis syn_keep=1 */;
wire [LANE_WIDTH-1:0] lane_up    /* synthesis syn_keep=1 */;

// -----------------------------------------------------------------------------
// Clock / reset / SerDes status
// -----------------------------------------------------------------------------
wire sys_clk                     /* synthesis syn_keep=1 */;
wire sys_rst;
wire cfg_clk;
wire cfg_pll_lock;
wire sys_reset_gen;
wire gt_reset;
wire gt_pcs_tx_reset;
wire gt_pcs_rx_reset;
wire [LANE_WIDTH-1:0] gt_pcs_tx_clk;
wire [LANE_WIDTH-1:0] gt_pcs_rx_clk;
wire gt_pll_ok;
wire [LANE_WIDTH-1:0] gt_rx_align_link;
wire [LANE_WIDTH-1:0] gt_rx_pma_lock;
wire [LANE_WIDTH-1:0] gt_rx_k_lock;
wire link_reset;
wire sys_reset;

assign sys_clk = gt_pcs_tx_clk[0];

// Do not use software-controlled GT resets in this bring-up top.
assign gt_reset        = 1'b0;
assign gt_pcs_tx_reset = 1'b0;
assign gt_pcs_rx_reset = 1'b0;

assign sys_reset_gen = cfg_pll_lock & gt_pll_ok & rst_n;

// LED = this 15K design has performed at least one TX user handshake.
assign led = tx_fire_seen;

// -----------------------------------------------------------------------------
// PLL and reset generator
// Keep using the 15K PLL port list from your current project.
// reset_gen is already present as src/reset_gen.v in the 15K repository.
// -----------------------------------------------------------------------------
Gowin_PLL u_Gowin_PLL
(
    .reset   (!rst_n),
    .lock    (cfg_pll_lock),
    .clkout0 (cfg_clk),
    .mdclk   (clk),
    .clkin   (clk)
);

reset_gen u_sys_reset_gen
(
    .i_clk1 (sys_clk),
    .i_lock (sys_reset_gen),
    .o_rst1 (sys_rst)
);

// -----------------------------------------------------------------------------
// TX pattern generator
// 16 beats per frame. Payload repeats every 4 beats:
//   12345678, 9ABCDEF0, 55AAC33C, 0F1E2D3C
// user_tx_valid is intentionally NOT gated by channel_up.
// -----------------------------------------------------------------------------
reg [7:0]  tx_beat_cnt;
reg [15:0] tx_start_delay;
reg        tx_enable;
reg        tx_fire_seen;
reg        tx_ready_seen;
reg        tx_last_seen;
reg        channel_up_1d;
reg        hard_err_seen;
reg        soft_err_seen;
reg        frame_err_seen;
reg        crc_err_seen;
reg        rx_seen_valid;
reg        rx_seen_last;
reg        rx_activity_toggle;

wire tx_fire;

function [31:0] f_tx_pattern;
    input [1:0] sel;
    begin
        case (sel)
            2'd0: f_tx_pattern = TX_PATTERN0;
            2'd1: f_tx_pattern = TX_PATTERN1;
            2'd2: f_tx_pattern = TX_PATTERN2;
            2'd3: f_tx_pattern = TX_PATTERN3;
            default: f_tx_pattern = TX_PATTERN0;
        endcase
    end
endfunction

assign user_tx_data  = f_tx_pattern(tx_beat_cnt[1:0]);
assign user_tx_strb  = {STRB_WIDTH{1'b1}};
assign user_tx_valid = tx_enable;
assign user_tx_last  = tx_enable & (tx_beat_cnt == FRAME_BEATS-1);
assign tx_fire       = user_tx_valid & user_tx_ready;

always @(posedge sys_clk) begin
    if (sys_rst) begin
        tx_start_delay <= 16'd0;
        tx_enable      <= 1'b0;
        tx_beat_cnt    <= 8'd0;
        tx_fire_seen   <= 1'b0;
        tx_ready_seen  <= 1'b0;
        tx_last_seen   <= 1'b0;
    end else begin
        if (tx_start_delay != 16'hffff) begin
            tx_start_delay <= tx_start_delay + 16'd1;
            tx_enable      <= 1'b0;
        end else begin
            tx_enable      <= 1'b1;
        end

        if (user_tx_ready)
            tx_ready_seen <= 1'b1;

        if (tx_fire) begin
            tx_fire_seen <= 1'b1;
            if (user_tx_last)
                tx_last_seen <= 1'b1;

            if (tx_beat_cnt == FRAME_BEATS-1)
                tx_beat_cnt <= 8'd0;
            else
                tx_beat_cnt <= tx_beat_cnt + 8'd1;
        end
    end
end

// -----------------------------------------------------------------------------
// Local RX/status monitor only. This does not control TX.
// -----------------------------------------------------------------------------
always @(posedge sys_clk) begin
    if (sys_rst) begin
        channel_up_1d      <= 1'b0;
        hard_err_seen      <= 1'b0;
        soft_err_seen      <= 1'b0;
        frame_err_seen     <= 1'b0;
        crc_err_seen       <= 1'b0;
        rx_seen_valid      <= 1'b0;
        rx_seen_last       <= 1'b0;
        rx_activity_toggle <= 1'b0;
    end else begin
        channel_up_1d <= channel_up;

        if (hard_err) hard_err_seen <= 1'b1;
        if (soft_err) soft_err_seen <= 1'b1;
        if (frame_err) frame_err_seen <= 1'b1;
        if (crc_valid && !crc_pass_fail_n) crc_err_seen <= 1'b1;

        if (user_rx_valid) begin
            rx_seen_valid      <= 1'b1;
            rx_activity_toggle <= ~rx_activity_toggle;
            if (user_rx_last)
                rx_seen_last <= 1'b1;
        end
    end
end

// -----------------------------------------------------------------------------
// ILA signals, search prefix: ila15_
// Recommended ILA clock: sys_clk / gt_pcs_tx_clk[0]
// Recommended trigger  : ila15_tx_fire == 1, or any *_err_seen == 1
// -----------------------------------------------------------------------------
wire [31:0] ila15_top_version       /* synthesis syn_keep=1 */ = TOP_VERSION;
wire        ila15_cfg_pll_lock      /* synthesis syn_keep=1 */ = cfg_pll_lock;
wire        ila15_gt_pll_ok         /* synthesis syn_keep=1 */ = gt_pll_ok;
wire        ila15_sys_rst           /* synthesis syn_keep=1 */ = sys_rst;
wire        ila15_sys_reset         /* synthesis syn_keep=1 */ = sys_reset;
wire        ila15_link_reset        /* synthesis syn_keep=1 */ = link_reset;
wire        ila15_tx_enable         /* synthesis syn_keep=1 */ = tx_enable;
wire [15:0] ila15_tx_start_delay    /* synthesis syn_keep=1 */ = tx_start_delay;
wire [7:0]  ila15_tx_beat_cnt       /* synthesis syn_keep=1 */ = tx_beat_cnt;
wire [31:0] ila15_user_tx_data      /* synthesis syn_keep=1 */ = user_tx_data;
wire [3:0]  ila15_user_tx_strb      /* synthesis syn_keep=1 */ = user_tx_strb;
wire        ila15_user_tx_valid     /* synthesis syn_keep=1 */ = user_tx_valid;
wire        ila15_user_tx_ready     /* synthesis syn_keep=1 */ = user_tx_ready;
wire        ila15_user_tx_last      /* synthesis syn_keep=1 */ = user_tx_last;
wire        ila15_tx_fire           /* synthesis syn_keep=1 */ = tx_fire;
wire        ila15_tx_fire_seen      /* synthesis syn_keep=1 */ = tx_fire_seen;
wire        ila15_tx_ready_seen     /* synthesis syn_keep=1 */ = tx_ready_seen;
wire        ila15_tx_last_seen      /* synthesis syn_keep=1 */ = tx_last_seen;
wire        ila15_channel_up        /* synthesis syn_keep=1 */ = channel_up;
wire        ila15_channel_up_1d     /* synthesis syn_keep=1 */ = channel_up_1d;
wire [0:0]  ila15_lane_up           /* synthesis syn_keep=1 */ = lane_up;
wire [0:0]  ila15_gt_rx_pma_lock    /* synthesis syn_keep=1 */ = gt_rx_pma_lock;
wire [0:0]  ila15_gt_rx_k_lock      /* synthesis syn_keep=1 */ = gt_rx_k_lock;
wire [0:0]  ila15_gt_rx_align_link  /* synthesis syn_keep=1 */ = gt_rx_align_link;
wire [31:0] ila15_user_rx_data      /* synthesis syn_keep=1 */ = user_rx_data;
wire        ila15_user_rx_valid     /* synthesis syn_keep=1 */ = user_rx_valid;
wire        ila15_user_rx_last      /* synthesis syn_keep=1 */ = user_rx_last;
wire        ila15_crc_valid         /* synthesis syn_keep=1 */ = crc_valid;
wire        ila15_crc_pass_fail_n   /* synthesis syn_keep=1 */ = crc_pass_fail_n;
wire        ila15_hard_err          /* synthesis syn_keep=1 */ = hard_err;
wire        ila15_soft_err          /* synthesis syn_keep=1 */ = soft_err;
wire        ila15_frame_err         /* synthesis syn_keep=1 */ = frame_err;
wire        ila15_hard_err_seen     /* synthesis syn_keep=1 */ = hard_err_seen;
wire        ila15_soft_err_seen     /* synthesis syn_keep=1 */ = soft_err_seen;
wire        ila15_frame_err_seen    /* synthesis syn_keep=1 */ = frame_err_seen;
wire        ila15_crc_err_seen      /* synthesis syn_keep=1 */ = crc_err_seen;
wire        ila15_rx_seen_valid     /* synthesis syn_keep=1 */ = rx_seen_valid;
wire        ila15_rx_seen_last      /* synthesis syn_keep=1 */ = rx_seen_last;
wire        ila15_rx_activity_toggle/* synthesis syn_keep=1 */ = rx_activity_toggle;

// -----------------------------------------------------------------------------
// SerDes / RoraLink 8B10B IP
// -----------------------------------------------------------------------------
SerDes_Top u_SerDes_Top
(
    .RoraLink_8B10B_Top_reset_i           (sys_rst),
    .RoraLink_8B10B_Top_user_clk_i        (sys_clk),
    .RoraLink_8B10B_Top_init_clk_i        (cfg_clk),
    .RoraLink_8B10B_Top_user_pll_locked_i (gt_pll_ok),
    .RoraLink_8B10B_Top_link_reset_o      (link_reset),
    .RoraLink_8B10B_Top_sys_reset_o       (sys_reset),

    .RoraLink_8B10B_Top_user_tx_data_i    (user_tx_data),
    .RoraLink_8B10B_Top_user_tx_valid_i   (user_tx_valid),
    .RoraLink_8B10B_Top_user_tx_ready_o   (user_tx_ready),
    .RoraLink_8B10B_Top_user_tx_strb_i    (user_tx_strb),
    .RoraLink_8B10B_Top_user_tx_last_i    (user_tx_last),

    .RoraLink_8B10B_Top_user_rx_data_o    (user_rx_data),
    .RoraLink_8B10B_Top_user_rx_valid_o   (user_rx_valid),
    .RoraLink_8B10B_Top_user_rx_strb_o    (user_rx_strb),
    .RoraLink_8B10B_Top_user_rx_last_o    (user_rx_last),
    .RoraLink_8B10B_Top_crc_pass_fail_n_o (crc_pass_fail_n),
    .RoraLink_8B10B_Top_crc_valid_o       (crc_valid),

    .RoraLink_8B10B_Top_hard_err_o        (hard_err),
    .RoraLink_8B10B_Top_soft_err_o        (soft_err),
    .RoraLink_8B10B_Top_frame_err_o       (frame_err),
    .RoraLink_8B10B_Top_channel_up_o      (channel_up),
    .RoraLink_8B10B_Top_lane_up_o         (lane_up),

    .RoraLink_8B10B_Top_gt_pcs_tx_reset_i (gt_pcs_tx_reset),
    .RoraLink_8B10B_Top_gt_pcs_tx_clk_o   (gt_pcs_tx_clk),
    .RoraLink_8B10B_Top_gt_pcs_rx_reset_i (gt_pcs_rx_reset),
    .RoraLink_8B10B_Top_gt_rx_align_link_o(gt_rx_align_link),
    .RoraLink_8B10B_Top_gt_rx_pma_lock_o  (gt_rx_pma_lock),
    .RoraLink_8B10B_Top_gt_rx_k_lock_o    (gt_rx_k_lock),
    .RoraLink_8B10B_Top_gt_pcs_rx_clk_o   (gt_pcs_rx_clk),
    .RoraLink_8B10B_Top_gt_reset_i        (gt_reset),
    .RoraLink_8B10B_Top_gt_pll_lock_o     (gt_pll_ok)
);

endmodule
